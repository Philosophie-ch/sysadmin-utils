require 'csv'

require_relative 'lib/utils'
require_relative 'lib/page_tools'
require_relative 'lib/export_utils'


def swap_webp_asset_urls(csv_file, log_level = 'info')

  ############
  # SETUP
  ############

  ExportUtils.setup_logging(log_level)

  report = []
  processed_count = 0

  # Cache: "https://assets.philosophie.ch/original.jpg" => "https://assets.philosophie.ch/original.webp"
  webp_cache = {}

  # Read input CSV data for merge
  Rails.logger.info("Reading input CSV: #{csv_file}")
  input_csv_data = ExportUtils.read_input_csv_data(csv_file)
  Rails.logger.info("Read #{input_csv_data.keys.length} rows from input CSV")

  # Parse IDs from CSV
  ids = ExportUtils.parse_ids_from_csv(csv_file)

  # Determine preserved columns
  csv_headers = CSV.read(csv_file, headers: true, encoding: 'UTF-8').headers rescue CSV.read(csv_file, headers: true, encoding: 'UTF-16').headers
  preserved_columns = ExportUtils.get_preserved_columns('pages', csv_headers)
  Rails.logger.info("Will preserve #{preserved_columns.length} columns from input CSV")

  # Generate output filename
  output_filename = ExportUtils.generate_merge_output_filename(csv_file)

  # Validate and fetch pages in order
  Rails.logger.info("Validating and fetching pages in specified order...")
  pages = ExportUtils.validate_and_fetch_ordered(Alchemy::Page, ids)
  total_pages = pages.length

  # Preload attachments data once
  all_attachments_with_pages = get_all_attachments_with_pages()

  Rails.logger.info("Starting webp swap for #{total_pages} pages...")


  ############
  # MAIN PROCESSING LOOP
  ############

  ids.zip(pages).each do |original_id, page|
    begin
      processed_count += 1
      ExportUtils.log_progress(processed_count, total_pages, "pages")

      # Handle missing pages (nil when ID not found in DB)
      unless page
        Rails.logger.warn("Page ID #{original_id} not found in database - skipping (row #{processed_count})")
        error_data = build_empty_page_row(processed_count)
        error_data[:id] = original_id
        error_data[:status] = 'error'
        error_data[:error_message] = "Page ID not found in database"
        report << error_data
        next
      end

      # Process this page's images
      error_messages = []
      changes = []
      page_modified = false

      IMAGE_ELEMENT_TYPES.each do |element_name|
        url_field_name = "picture_asset_url"

        begin
          blocks = _get_asset_blocks(page, element_name, url_field_name)
        rescue => e
          error_messages << "NO-BLOCKS: #{element_name}: failed to get blocks: #{e.message}"
          next
        end

        blocks.each do |block|
          begin
            url_content = block.contents.find { |c| c.name == url_field_name }
            current_url = url_content&.essence&.body

            # Skip blank
            if current_url.blank?
              next
            end

            # Skip if already webp
            ext = File.extname(current_url).downcase
            if ext == '.webp'
              next
            end

            # Skip if not a known non-webp image extension
            unless NON_WEBP_IMAGE_EXTENSIONS.include?(ext)
              next
            end

            # Build the expected webp URL
            webp_url = current_url.sub(/#{Regexp.escape(ext)}$/i, '.webp')
            original_relative_path = current_url.gsub('https://assets.philosophie.ch/', '')
            webp_relative_path = webp_url.gsub('https://assets.philosophie.ch/', '')

            Rails.logger.debug("Checking webp for: #{original_relative_path} -> #{webp_relative_path}")

            # (1a) Check cache
            if webp_cache.key?(current_url)
              cached_webp = webp_cache[current_url]
              Rails.logger.debug("Cache hit: #{original_relative_path} -> #{cached_webp}")
              url_content.essence.update!(body: cached_webp)
              changes << "#{element_name}[#{block.id}]: #{original_relative_path} => #{cached_webp.gsub('https://assets.philosophie.ch/', '')} (cached)"
              page_modified = true
              next
            end

            # (1b) Check asset server
            webp_check = check_asset_urls_resolve([webp_url])
            if webp_check[:status] == 'success'
              # Webp exists on server — swap and cache
              url_content.essence.update!(body: webp_url)
              webp_cache[current_url] = webp_url
              changes << "#{element_name}[#{block.id}]: #{original_relative_path} => #{webp_relative_path}"
              page_modified = true
              Rails.logger.info("Swapped: #{original_relative_path} => #{webp_relative_path}")
            else
              # No webp found
              error_messages << "NO-WEBP: #{original_relative_path}"
              Rails.logger.warn("NO-WEBP: #{original_relative_path} (page #{page.id})")
            end

          rescue => e
            error_messages << "NO-WEBP: #{element_name}[#{block.id}]: #{e.class} :: #{e.message}"
          end
        end
      end

      # Save and publish if any changes were made
      if page_modified
        begin
          page.save!
          page.publish!
        rescue => e
          error_messages << "save/publish failed: #{e.class} :: #{e.message}"
        end
      end

      # Determine status
      status = if error_messages.empty? && changes.empty?
        'skipped'
      elsif error_messages.empty?
        'success'
      elsif changes.empty? && error_messages.any?
        'error'
      else
        'partial success'
      end

      # Build report row (same structure as export_pages.rb)
      page_data = build_page_report_row(page, all_attachments_with_pages, processed_count)
      page_data[:status] = status
      page_data[:changes_made] = changes.join(' ;; ')
      page_data[:error_message] = error_messages.join(' --- ')
      page_data[:error_trace] = status == 'error' || status == 'partial success' ? 'swap_webp_asset_urls.rb' : ''

      report << page_data

    rescue => e
      Rails.logger.error("Unhandled error for page #{page&.id || 'unknown'}: #{e.message}")
      error_data = build_error_page_row(page, processed_count)
      error_data[:status] = 'unhandled error'
      error_data[:error_message] = "#{e.class} :: #{e.message}"
      error_data[:error_trace] = e.backtrace.join(" ::: ")
      report << error_data
    end
  end


  ############
  # REPORT GENERATION
  ############

  Rails.logger.info("Processing complete. Generating report...")

  # Merge with input CSV data
  Rails.logger.info("Merging exported data with input CSV...")
  report = ExportUtils.merge_with_input_csv(report, input_csv_data, preserved_columns)

  # Write output
  Rails.logger.info("Writing output to: #{output_filename}")
  headers = report.first.keys
  csv_string = CSV.generate do |csv|
    csv << headers
    report.each do |row|
      csv << headers.map { |header| row[header] }
    end
  end
  File.write(output_filename, csv_string)

  Rails.logger.info("Successfully processed #{processed_count} pages")
  Rails.logger.info("Cache stats: #{webp_cache.size} unique webp mappings cached")
  Rails.logger.info("\n\n\n============ Report generated at #{output_filename} ============\n\n\n")
end


############
# CLI ENTRY POINT
############

if __FILE__ == $0
  if ARGV.length < 1
    puts "Usage:"
    puts "  ruby swap_webp_asset_urls.rb <csv_file> [log_level]"
    puts ""
    puts "Arguments:"
    puts "  csv_file    : CSV file with 'id' column (page IDs)"
    puts "  log_level   : debug, info, warn, or error (default: info)"
    puts ""
    puts "Description:"
    puts "  For each page, checks all image elements (intro, picture_block,"
    puts "  text_and_picture, box). If an image URL points to a non-webp file,"
    puts "  checks if a .webp version exists on the asset server. If yes, swaps"
    puts "  the reference. If no, reports NO-WEBP error."
    puts ""
    puts "Examples:"
    puts "  ruby swap_webp_asset_urls.rb pages.csv"
    puts "  ruby swap_webp_asset_urls.rb pages.csv debug"
    exit 1
  end

  csv_file = ARGV[0]
  log_level = ARGV[1] || 'info'

  swap_webp_asset_urls(csv_file, log_level)
end
