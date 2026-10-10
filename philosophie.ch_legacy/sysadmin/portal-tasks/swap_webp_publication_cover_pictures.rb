require 'csv'

require_relative 'lib/utils'
require_relative 'lib/publication_tools'
require_relative 'lib/export_utils'


NON_WEBP_IMAGE_EXTENSIONS = %w[.jpg .jpeg .png .gif .bmp .tiff .tif].freeze


def swap_webp_publication_cover_pictures(csv_file, log_level = 'info')

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
  preserved_columns = ExportUtils.get_preserved_columns('publications', csv_headers)
  Rails.logger.info("Will preserve #{preserved_columns.length} columns from input CSV")

  # Generate output filename
  output_filename = ExportUtils.generate_merge_output_filename(csv_file)

  # Validate and fetch publications in order
  Rails.logger.info("Validating and fetching publications in specified order...")
  publications = ExportUtils.validate_and_fetch_ordered(Publication, ids)
  total_publications = publications.length

  Rails.logger.info("Starting webp swap for #{total_publications} publications...")


  ############
  # MAIN PROCESSING LOOP
  ############

  ids.zip(publications).each do |original_id, publication|
    begin
      processed_count += 1
      ExportUtils.log_progress(processed_count, total_publications, "publications")

      # Handle missing publications (nil when ID not found in DB)
      unless publication
        Rails.logger.warn("Publication ID #{original_id} not found in database - skipping (row #{processed_count})")
        error_data = build_error_publication_data(nil, "Publication ID not found in database")
        error_data[:id] = original_id
        error_data[:result_order] = processed_count
        error_data[:status] = 'error'
        report << error_data
        next
      end

      # Process this publication's cover picture
      error_messages = []
      changes = []

      current_url = publication.cover_picture_asset

      # Skip if blank
      if current_url.blank?
        Rails.logger.debug("Publication #{publication.id} (#{publication.publication_key}) has no cover_picture_asset - skipping")
      else
        ext = File.extname(current_url).downcase

        if ext == '.webp'
          # Already webp, nothing to do
          Rails.logger.debug("Publication #{publication.id} (#{publication.publication_key}) already has webp cover picture - skipping")
        elsif !NON_WEBP_IMAGE_EXTENSIONS.include?(ext)
          # Not a known image extension, skip
          Rails.logger.debug("Publication #{publication.id} (#{publication.publication_key}) has unknown image extension (#{ext}) - skipping")
        else
          # Build the expected webp URL
          webp_url = current_url.sub(/#{Regexp.escape(ext)}$/i, '.webp')
          original_relative_path = current_url.gsub('https://assets.philosophie.ch/', '')
          webp_relative_path = webp_url.gsub('https://assets.philosophie.ch/', '')

          Rails.logger.debug("Checking webp for: #{original_relative_path} -> #{webp_relative_path}")

          # (1a) Check cache
          if webp_cache.key?(current_url)
            cached_webp = webp_cache[current_url]
            Rails.logger.debug("Cache hit: #{original_relative_path} -> #{cached_webp}")
            publication.cover_picture_asset = cached_webp
            publication.save!
            changes << "cover_picture_asset: #{original_relative_path} => #{cached_webp.gsub('https://assets.philosophie.ch/', '')} (cached)"
          else
            # (1b) Check asset server
            webp_check = check_asset_urls_resolve([webp_url])
            if webp_check[:status] == 'success'
              # Webp exists on server — swap and cache
              publication.cover_picture_asset = webp_url
              publication.save!
              webp_cache[current_url] = webp_url
              changes << "cover_picture_asset: #{original_relative_path} => #{webp_relative_path}"
              Rails.logger.info("Swapped: #{original_relative_path} => #{webp_relative_path}")
            else
              # No webp found
              error_messages << "NO-WEBP: #{original_relative_path}"
              Rails.logger.warn("NO-WEBP: #{original_relative_path} (publication #{publication.id}, #{publication.publication_key})")
            end
          end
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

      # Build report row (same structure as publications.rb GET)
      pub_data = build_publication_report_row(publication, processed_count)
      pub_data[:status] = status
      pub_data[:changes_made] = changes.join(' ;; ')
      pub_data[:error_message] = error_messages.join(' --- ')
      pub_data[:error_trace] = status == 'error' || status == 'partial success' ? 'swap_webp_publication_cover_pictures.rb' : ''

      report << pub_data

    rescue => e
      Rails.logger.error("Unhandled error for publication #{publication&.id || 'unknown'} (#{publication&.publication_key || 'unknown'}): #{e.message}")
      error_data = build_error_publication_data(publication, "#{e.class} :: #{e.message}", e.backtrace.join(" ::: "))
      error_data[:result_order] = processed_count
      error_data[:status] = 'unhandled error'
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

  Rails.logger.info("Successfully processed #{processed_count} publications")
  Rails.logger.info("Cache stats: #{webp_cache.size} unique webp mappings cached")
  Rails.logger.info("\n\n\n============ Report generated at #{output_filename} ============\n\n\n")
end


############
# CLI ENTRY POINT
############

if __FILE__ == $0
  if ARGV.length < 1
    puts "Usage:"
    puts "  ruby swap_webp_publication_cover_pictures.rb <csv_file> [log_level]"
    puts ""
    puts "Arguments:"
    puts "  csv_file    : CSV file with 'id' column (publication IDs)"
    puts "  log_level   : debug, info, warn, or error (default: info)"
    puts ""
    puts "Description:"
    puts "  For each publication, checks if cover_picture_asset points to a"
    puts "  non-webp file. If a .webp version exists on the asset server, swaps"
    puts "  the reference. If no webp found, reports NO-WEBP error."
    puts ""
    puts "Examples:"
    puts "  ruby swap_webp_publication_cover_pictures.rb publications.csv"
    puts "  ruby swap_webp_publication_cover_pictures.rb publications.csv debug"
    exit 1
  end

  csv_file = ARGV[0]
  log_level = ARGV[1] || 'info'

  swap_webp_publication_cover_pictures(csv_file, log_level)
end
