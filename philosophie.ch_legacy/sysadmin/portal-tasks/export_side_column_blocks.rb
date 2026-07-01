require 'csv'

require_relative 'lib/utils'
require_relative 'lib/side_column_block_tools'
require_relative 'lib/export_utils'


def export_side_column_blocks(ids_or_file = nil, log_level = 'info', merge_mode: false)

  ############
  # SETUP
  ############

  ExportUtils.setup_logging(log_level)

  report = []
  processed_count = 0

  # Merge mode variables
  input_csv_data = nil
  preserved_columns = nil
  output_filename = nil


  ############
  # ID PARSING AND VALIDATION
  ############

  ids = nil

  if ids_or_file.present?
    if File.exist?(ids_or_file.to_s)

      if merge_mode && ids_or_file.to_s.end_with?('.csv')
        Rails.logger.info("MERGE MODE: Reading input CSV: #{ids_or_file}")

        input_csv_data = ExportUtils.read_input_csv_data(ids_or_file)
        Rails.logger.info("Read #{input_csv_data.keys.length} rows from input CSV")

        ids = ExportUtils.parse_ids_from_csv(ids_or_file)

        csv_headers = CSV.read(ids_or_file, headers: true, encoding: 'UTF-8').headers rescue CSV.read(ids_or_file, headers: true, encoding: 'UTF-16').headers
        preserved_columns = ExportUtils.get_preserved_columns('side_column_blocks', csv_headers)
        Rails.logger.info("Will preserve #{preserved_columns.length} columns from input CSV")

        output_filename = ExportUtils.generate_merge_output_filename(ids_or_file)
      else
        Rails.logger.info("Parsing IDs from file: #{ids_or_file}")
        ids = ExportUtils.parse_ids_from_file(ids_or_file)
      end

    else
      Rails.logger.info("Parsing IDs from argument: #{ids_or_file}")
      ids = ExportUtils.parse_ids(ids_or_file)
    end

    Rails.logger.info("Validating and fetching side_column_blocks in specified order...")
    blocks = ExportUtils.validate_and_fetch_ordered(SideColumnBlock, ids)
    total_blocks = blocks.length

  else
    Rails.logger.info("No IDs specified - exporting ALL side_column_blocks")
    blocks = nil
    total_blocks = SideColumnBlock.count
  end

  Rails.logger.info("Starting export of #{total_blocks} side_column_blocks...")


  ############
  # MAIN EXPORT LOOP
  ############

  process_block = lambda do |block|
    begin
      processed_count += 1
      ExportUtils.log_progress(processed_count, total_blocks, "side_column_blocks")

      unless block
        Rails.logger.warn("SideColumnBlock ID not found in database - skipping (row #{processed_count})")
        error_data = {
          _sort: "", key: "", id: "", link: "", _request: "", block_type: "", content: "", pages: "",
          status: 'error', changes_made: '',
          error_message: "SideColumnBlock ID not found in database",
          error_trace: '',
          original_order: '', result_order: '',
        }
        report << error_data
        return
      end

      block_data = {
        _sort: "",
        key: block.key,
        id: block.id.to_s,
        link: get_block_admin_link(block),
        _request: "",
        block_type: block.block_type,
        content: serialize_content(block),
        pages: get_block_pages_display(block),

        status: 'success',
        changes_made: '',
        error_message: '',
        error_trace: '',
        original_order: '', result_order: '',
      }

      report << block_data
      Rails.logger.debug("Exported side_column_block #{block.id}: #{block.key}")

    rescue => e
      Rails.logger.error("Error exporting side_column_block #{block&.id || 'unknown'}: #{e.message}")
      error_data = {
        _sort: "",
        key: block&.key || "",
        id: block&.id&.to_s || "",
        link: "",
        _request: "",
        block_type: block&.block_type || "",
        content: "",
        pages: "",

        status: 'unhandled error',
        changes_made: '',
        error_message: "#{e.class} :: #{e.message}",
        error_trace: e.backtrace.join(" ::: "),
        original_order: '', result_order: '',
      }
      report << error_data
    end
  end

  if blocks
    blocks.each(&process_block)
  else
    SideColumnBlock
      .includes(:alchemy_page_side_column_blocks)
      .find_each(batch_size: 100, &process_block)
  end


  ############
  # ORDERING
  ############

  report.each_with_index do |subreport, index|
    subreport[:original_order] = index + 1
  end

  status_ordering = {
    'success' => 1,
    'partial success' => 2,
    'error' => 3,
    'unhandled error' => 4,
  }

  report.sort_by! { |subreport| status_ordering[subreport[:status]] || 9999 }
  report.each_with_index do |subreport, index|
    subreport[:result_order] = index + 1
  end

  report.sort_by! { |subreport| subreport[:original_order] }


  ############
  # REPORT GENERATION
  ############

  Rails.logger.info("Export complete. Generating report...")

  if merge_mode && input_csv_data && preserved_columns
    Rails.logger.info("Merging exported data with input CSV...")
    report = ExportUtils.merge_with_input_csv(report, input_csv_data, preserved_columns)
  end

  if output_filename
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
    generate_csv_report(report, "side_column_blocks")
  end

  Rails.logger.info("Successfully exported #{processed_count} side_column_blocks")

end


############
# CLI ENTRY POINT
############

if __FILE__ == $0
  merge_mode = false
  ids_or_file = nil
  log_level = 'info'

  if ARGV.include?('-m') || ARGV.include?('--merge')
    merge_mode = true
    ARGV.delete('-m')
    ARGV.delete('--merge')
  end

  if ARGV.length == 0
    export_side_column_blocks(nil, 'info', merge_mode: merge_mode)

  elsif ARGV.length == 1
    arg = ARGV[0]
    if ['debug', 'info', 'warn', 'error'].include?(arg.downcase)
      export_side_column_blocks(nil, arg, merge_mode: merge_mode)
    else
      export_side_column_blocks(arg, 'info', merge_mode: merge_mode)
    end

  elsif ARGV.length == 2
    export_side_column_blocks(ARGV[0], ARGV[1], merge_mode: merge_mode)

  else
    puts "Usage:"
    puts "  ruby export_side_column_blocks.rb [log_level]                       # Export all"
    puts "  ruby export_side_column_blocks.rb [ids_or_file] [log_level]         # Export specific IDs"
    puts "  ruby export_side_column_blocks.rb -m [csv_file] [log_level]         # Merge mode with CSV"
    exit 1
  end
end
