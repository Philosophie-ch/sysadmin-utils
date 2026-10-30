require 'csv'

require_relative 'lib/utils'
require_relative 'lib/page_tools'
require_relative 'lib/export_utils'


def export_pages(ids_or_file = nil, log_level = 'info', merge_mode: false)

  ############
  # SETUP
  ############

  ExportUtils.setup_logging(log_level)

  report = []
  failed_ids = []  # records that could not be exported: in merge mode their input row is returned untouched
  processed_count = 0

  # Merge mode variables
  input_rows = nil
  preserved_columns = nil
  output_filename = nil

  # Preload attachments data once
  all_attachments_with_pages = get_all_attachments_with_pages()


  ############
  # ID PARSING AND VALIDATION
  ############

  ids = nil

  if ids_or_file.present?
    # Check if it's a file path
    if File.exist?(ids_or_file.to_s)

      # Check if merge mode is enabled and file is CSV
      if merge_mode && ids_or_file.to_s.end_with?('.csv')
        Rails.logger.info("MERGE MODE: Reading input CSV: #{ids_or_file}")

        # Read CSV data for later merging
        input_rows = ExportUtils.read_input_rows(ids_or_file)
        Rails.logger.info("Read #{input_rows.length} rows from input CSV")

        # Parse IDs from CSV
        ids = ExportUtils.parse_ids_from_csv(ids_or_file)

        # Determine preserved columns
        csv_headers = CSV.read(ids_or_file, headers: true, encoding: 'UTF-8').headers rescue CSV.read(ids_or_file, headers: true, encoding: 'UTF-16').headers
        preserved_columns = ExportUtils.get_preserved_columns('pages', csv_headers)
        Rails.logger.info("Will preserve #{preserved_columns.length} columns from input CSV")

        # Generate output filename
        output_filename = ExportUtils.generate_merge_output_filename(ids_or_file)

      else
        # Regular file with IDs (one per line)
        Rails.logger.info("Parsing IDs from file: #{ids_or_file}")
        ids = ExportUtils.parse_ids_from_file(ids_or_file)
      end

    else
      # Assume it's a comma-separated string of IDs
      Rails.logger.info("Parsing IDs from argument: #{ids_or_file}")
      ids = ExportUtils.parse_ids(ids_or_file)
    end

    # Validate and fetch in order
    Rails.logger.info("Validating and fetching pages in specified order...")
    pages = ExportUtils.validate_and_fetch_ordered(Alchemy::Page, ids)
    total_pages = pages.length

  else
    # Export ALL pages
    Rails.logger.info("No IDs specified - exporting ALL pages")
    pages = nil  # Will use find_each for all pages
    total_pages = Alchemy::Page.count
  end

  Rails.logger.info("Starting export of #{total_pages} pages...")


  ############
  # MAIN EXPORT LOOP
  ############

  # Define the page processing logic
  process_page = lambda do |page, original_id = nil|
    begin
      processed_count += 1
      ExportUtils.log_progress(processed_count, total_pages, "pages")

      # Check if page exists (nil when ID not found in DB)
      unless page
        Rails.logger.warn("Page ID not found in database - skipping (row #{processed_count})")
        error_data = build_empty_page_row(processed_count)
        error_data[:id] = original_id
        error_data[:status] = 'error'
        error_data[:error_message] = "Page ID not found in database"
        failed_ids << original_id
        report << error_data
        return
      end

      report << build_page_report_row(page, all_attachments_with_pages, processed_count)
      Rails.logger.debug("Exported page #{page.id}: #{page.urlname}")

    rescue => e
      Rails.logger.error("Error exporting page #{page&.id || 'unknown'}: #{e.message}")
      error_data = build_error_page_row(page, processed_count)
      error_data[:id] = page&.id || original_id
      error_data[:status] = 'unhandled error'
      error_data[:error_message] = "#{e.class} :: #{e.message}"
      error_data[:error_trace] = e.backtrace.join(" ::: ")
      failed_ids << error_data[:id]
      report << error_data
    end
  end

  # Execute based on whether we have specific IDs or exporting all
  if pages
    # Process specific pages in order (the id is kept for the ones that do not exist)
    ids.zip(pages).each { |original_id, page| process_page.call(page, original_id) }
  else
    # Use find_each for memory-efficient iteration through all pages
    # Eager load associations to minimize queries
    Alchemy::Page
      .includes(
        :elements,
        :taggings,
        :tags,
        :language,
        :creator,
        :authors,
        :page_body,
        :page_languages,
        elements: { contents: :essence }
      )
      .find_each(batch_size: 100, &process_page)
  end


  ############
  # REPORT GENERATION
  ############

  Rails.logger.info("Export complete. Generating report...")

  # If in merge mode, merge with input CSV data
  if merge_mode && input_rows && preserved_columns
    Rails.logger.info("Merging exported data with input CSV...")
    report = ExportUtils.merge_with_input_rows(report, input_rows, preserved_columns, failed_ids)
  end

  # Generate CSV output
  if output_filename
    # Custom filename for merge mode
    Rails.logger.info("Writing merged output to: #{output_filename}")
    headers = report.first.keys
    csv_string = CSV.generate do |csv|
      csv << headers
      report.each do |row|
        csv << headers.map { |header| row[header] }
      end
    end
    File.write(output_filename, csv_string)
    Rails.logger.info("Successfully wrote merged CSV to #{output_filename}")
  else
    # Standard report generation
    generate_csv_report(report, "pages")
  end

  Rails.logger.info("Successfully exported #{processed_count} pages")

end


############
# CLI ENTRY POINT
############

if __FILE__ == $0
  # Parse command line arguments
  # Usage:
  #   ruby export_pages.rb [log_level]                        # Export all pages
  #   ruby export_pages.rb [ids_or_file] [log_level]          # Export specific IDs
  #   ruby export_pages.rb -m [csv_file] [log_level]          # Merge mode with CSV

  merge_mode = false
  ids_or_file = nil
  log_level = 'info'

  # Check for merge mode flag
  if ARGV.include?('-m') || ARGV.include?('--merge')
    merge_mode = true
    ARGV.delete('-m')
    ARGV.delete('--merge')
  end

  if ARGV.length == 0
    # No arguments - export all with default log level
    export_pages(nil, 'info', merge_mode: merge_mode)

  elsif ARGV.length == 1
    # One argument - could be log level OR ids/file
    arg = ARGV[0]

    # Check if it's a log level
    if ['debug', 'info', 'warn', 'error'].include?(arg.downcase)
      export_pages(nil, arg, merge_mode: merge_mode)
    else
      # Assume it's IDs or a file
      export_pages(arg, 'info', merge_mode: merge_mode)
    end

  elsif ARGV.length == 2
    # Two arguments - ids/file and log level
    export_pages(ARGV[0], ARGV[1], merge_mode: merge_mode)

  else
    puts "Usage:"
    puts "  ruby export_pages.rb [log_level]                       # Export all pages"
    puts "  ruby export_pages.rb [ids_or_file] [log_level]         # Export specific IDs"
    puts "  ruby export_pages.rb -m [csv_file] [log_level]         # Merge mode with CSV"
    puts ""
    puts "Arguments:"
    puts "  -m, --merge   : Enable merge mode (preserve manual columns from input CSV)"
    puts "  ids_or_file   : File path (with one ID per line) OR comma-separated IDs"
    puts "  csv_file      : CSV file with 'id' column (for merge mode)"
    puts "  log_level     : debug, info, warn, or error (default: info)"
    puts ""
    puts "Examples:"
    puts "  ruby export_pages.rb                                   # Export all pages, info logging"
    puts "  ruby export_pages.rb debug                             # Export all pages, debug logging"
    puts "  ruby export_pages.rb ids.txt                           # Export IDs from file"
    puts "  ruby export_pages.rb '123,456,789'                     # Export specific IDs"
    puts "  ruby export_pages.rb ids.txt debug                     # Export IDs from file with debug"
    puts "  ruby export_pages.rb -m articles.csv                   # Merge mode: updates articles_updated.csv"
    puts "  ruby export_pages.rb -m articles.csv debug             # Merge mode with debug logging"
    puts ""
    puts "Merge Mode:"
    puts "  - Reads IDs from 'id' column in input CSV"
    puts "  - Fetches fresh DB data for those IDs"
    puts "  - Preserves manual/metadata columns from input CSV"
    puts "  - Outputs to {input_name}_updated.csv"
    exit 1
  end
end
