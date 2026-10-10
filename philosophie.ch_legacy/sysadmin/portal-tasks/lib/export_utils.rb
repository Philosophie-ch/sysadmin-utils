require 'csv'

module ExportUtils

  def self.setup_logging(log_level)
    ActiveRecord::Base.logger.level = Logger::WARN
    ActiveSupport::Deprecation.behavior = :silence
    ActiveSupport::Deprecation.silenced = true
    ActiveSupport::Deprecation.debug = false

    Rails.logger.level = parse_log_level(log_level)
  end

  def self.parse_log_level(level)
    case level.to_s.downcase
    when 'debug' then Logger::DEBUG
    when 'info' then Logger::INFO
    when 'warn' then Logger::WARN
    when 'error' then Logger::ERROR
    else Logger::INFO
    end
  end

  def self.generate_export_filename(entity_name)
    timestamp = Time.now.strftime("%y%m%d_%H%M%S")
    "portal-tasks-reports/#{timestamp}_#{entity_name}_export.csv"
  end

  # Progress tracking for large exports
  def self.log_progress(current, total, entity_name)
    if current % 100 == 0
      percent = (current.to_f / total * 100).round(2)
      Rails.logger.info("Exported #{current}/#{total} #{entity_name} (#{percent}%)")
    end
  end

  # Parse IDs from file - one ID per line
  def self.parse_ids_from_file(file_path)
    unless File.exist?(file_path)
      raise "ID file not found: #{file_path}"
    end

    ids = []
    File.readlines(file_path).each_with_index do |line, idx|
      cleaned = line.strip
      next if cleaned.empty?  # Skip empty lines

      id = cleaned.to_i
      if id == 0 && cleaned != "0"
        # Check if this looks like a CSV file
        if cleaned.include?(',') || cleaned.downcase.include?('id')
          raise "Invalid ID on line #{idx + 1}: File appears to be a CSV. Did you forget to use the -m (merge mode) flag? For CSV files, use: ruby script.rb -m file.csv"
        else
          raise "Invalid ID on line #{idx + 1}: '#{cleaned}' is not a valid integer"
        end
      end

      ids << id
    end

    if ids.empty?
      raise "No valid IDs found in file: #{file_path}"
    end

    Rails.logger.info("Parsed #{ids.length} IDs from file")
    ids
  end

  # Parse IDs from comma-separated string or array
  def self.parse_ids(ids_input)
    return [] if ids_input.nil? || ids_input.empty?

    if ids_input.is_a?(Array)
      return ids_input.map(&:to_i)
    elsif ids_input.is_a?(String)
      return ids_input.split(',').map(&:strip).map(&:to_i)
    else
      raise "IDs must be an array or comma-separated string"
    end
  end

  # Validate that all IDs exist in the database
  # Returns the ordered records or raises an error
  def self.validate_and_fetch_ordered(model_class, ids)
    return nil if ids.nil? || ids.empty?

    Rails.logger.info("Validating #{ids.length} IDs...")

    # Fetch all records at once
    records = model_class.where(id: ids).index_by(&:id)

    # Warn about missing IDs (don't abort — callers handle nil gracefully)
    missing_ids = ids - records.keys
    unless missing_ids.empty?
      Rails.logger.warn("The following IDs were not found in the database (will appear as error rows): #{missing_ids.join(', ')}")
    end

    # Return records in the original order (nil for missing IDs)
    ordered_records = ids.map { |id| records[id] }

    Rails.logger.info("Validated #{ids.length} IDs (#{missing_ids.size} missing)")
    ordered_records
  end


  ############
  # MERGE MODE UTILITIES
  ############

  # Parse IDs from CSV file by reading the specified column (default: 'id')
  def self.parse_ids_from_csv(csv_file, id_column_name = 'id')
    ids = []

    # Try UTF-8 first, then UTF-16 if that fails
    csv_data = nil
    begin
      csv_data = CSV.read(csv_file, headers: true, encoding: 'UTF-8')
    rescue ArgumentError, Encoding::InvalidByteSequenceError, CSV::MalformedCSVError
      Rails.logger.info("UTF-8 parsing failed, trying UTF-16...")
      csv_data = CSV.read(csv_file, headers: true, encoding: 'UTF-16')
    end

    unless csv_data.headers.include?(id_column_name)
      raise "CSV file does not contain '#{id_column_name}' column. Available columns: #{csv_data.headers.join(', ')}"
    end

    csv_data.each do |row|
      id_value = row[id_column_name]
      next if id_value.blank?

      id_int = id_value.to_i
      if id_int.to_s != id_value.strip
        Rails.logger.warn("Invalid ID format in CSV: '#{id_value}' - skipping")
        next
      end

      ids << id_int
    end

    Rails.logger.info("Parsed #{ids.length} IDs from CSV file")
    ids
  end


  # Read input CSV data into hash keyed by ID
  def self.read_input_csv_data(csv_file)
    input_data = {}

    # Try UTF-8 first, then UTF-16 if that fails
    csv_data = nil
    begin
      csv_data = CSV.read(csv_file, headers: true, encoding: 'UTF-8')
    rescue ArgumentError, Encoding::InvalidByteSequenceError, CSV::MalformedCSVError
      Rails.logger.info("UTF-8 parsing failed, trying UTF-16...")
      csv_data = CSV.read(csv_file, headers: true, encoding: 'UTF-16')
    end

    csv_data.each do |row|
      id_value = row['id']
      next if id_value.blank?

      id_int = id_value.to_i
      input_data[id_int] = row.to_h
    end

    input_data
  end


  # Get list of columns to preserve based on entity type and input headers
  # Uses hybrid approach: all "_" prefixed columns + known exceptions
  def self.get_preserved_columns(entity_type, input_headers)
    # Define known exceptions per entity type
    exceptions = {
      'pages' => ['embedded_html_base_name'],
      'profiles' => ['password', 'biblio_keys', 'biblio_keys_further_references', 'biblio_dependencies_keys', 'mentioned_on']
    }

    preserved = []

    # Add all columns starting with "_" (skip nil/blank headers)
    preserved += input_headers.select { |h| h && h.is_a?(String) && h.start_with?('_') }

    # Add known exceptions for this entity type
    if exceptions.key?(entity_type)
      preserved += exceptions[entity_type]
    end

    preserved.uniq
  end


  # Columns that describe what happened in this run; they always come from the report row
  REPORT_COLUMNS = %i[status changes_made error_message error_trace update_links_report original_order result_order].freeze

  # Merge DB data with preserved columns from input CSV
  # failed_ids: records that could not be exported. Their row is the input row exactly as it was, only the
  # report columns (status, error_message...) say what happened, so pasting the output back changes nothing there.
  # Returns merged report ready for CSV output
  def self.merge_with_input_csv(db_rows, input_csv_data, preserved_columns, failed_ids = [])
    Rails.logger.info("Merging #{db_rows.length} rows with input CSV data...")
    Rails.logger.info("Preserving columns: #{preserved_columns.join(', ')}")

    merged_rows = db_rows.map do |db_row|
      id = db_row[:id]
      input_row = input_csv_data[id]

      if input_row.nil?
        Rails.logger.warn("No input CSV row found for ID #{id} - using DB data only")
        next db_row
      end

      # Start with DB data
      merged = db_row.dup

      if failed_ids.include?(id)
        merged.each_key do |column|
          next if REPORT_COLUMNS.include?(column)

          merged[column] = input_row[column.to_s] if input_row.key?(column.to_s)
        end
      end

      # Override with preserved columns from input CSV
      preserved_columns.each do |col|
        if input_row.key?(col)
          merged[col.to_sym] = input_row[col]
        end
      end

      merged
    end

    Rails.logger.info("Merge complete")
    merged_rows
  end


  # The id of an input row (same rules as parse_ids_from_csv). nil when blank or not a plain integer.
  def self.parse_row_id(value)
    return nil if value.blank?

    id_int = value.to_i
    id_int.to_s == value.strip ? id_int : nil
  end


  # The input CSV as an ordered list of rows (hash header => value), one per data row,
  # including the rows without a valid id.
  def self.read_input_rows(csv_file)
    csv_data = nil
    begin
      csv_data = CSV.read(csv_file, headers: true, encoding: 'UTF-8')
    rescue ArgumentError, Encoding::InvalidByteSequenceError, CSV::MalformedCSVError
      Rails.logger.info("UTF-8 parsing failed, trying UTF-16...")
      csv_data = CSV.read(csv_file, headers: true, encoding: 'UTF-16')
    end

    csv_data.map(&:to_h)
  end


  # A row in the report layout whose cells are the ones of the input row, exactly as they were.
  # The report columns (status, error_message...) are blank, or the given values.
  def self.untouched_input_row(layout, input_row, report_values = {})
    row = layout.to_h { |column| [column, REPORT_COLUMNS.include?(column) ? '' : input_row.fetch(column.to_s, '')] }
    row.merge(report_values)
  end


  # Merge mode output: exactly one row per input row, in the same order, so it can be pasted back over the sheet.
  # - the record was exported: the DB data plus the preserved columns of THIS input row (also when an id repeats)
  # - the record could not be exported (failed_ids): the input row as it was, only the report columns say what happened
  # - the row has no valid id: the input row as it was, with status 'error'
  # db_rows are the report rows of the rows that have a valid id, in the order of the input.
  def self.merge_with_input_rows(db_rows, input_rows, preserved_columns, failed_ids = [])
    with_id = input_rows.count { |row| parse_row_id(row['id']) }
    unless with_id == db_rows.length
      raise "The report has #{db_rows.length} rows but the input CSV has #{with_id} rows with a valid id"
    end

    layout = db_rows.first ? db_rows.first.keys : input_rows.first.keys.compact.map(&:to_sym)
    exported = db_rows.each

    input_rows.map do |input_row|
      id = parse_row_id(input_row['id'])

      if id.nil?
        next untouched_input_row(layout, input_row, status: 'error', error_message: "The row has no valid id in the 'id' column")
      end

      db_row = exported.next

      if failed_ids.include?(id)
        next untouched_input_row(layout, input_row, db_row.slice(*REPORT_COLUMNS))
      end

      merged = db_row.dup
      preserved_columns.each do |col|
        merged[col.to_sym] = input_row[col] if input_row.key?(col)
      end
      merged
    end
  end


  # Generate merge mode output filename
  # Always outputs to portal-tasks-reports/ directory with _updated suffix
  def self.generate_merge_output_filename(input_csv_path)
    base_name = File.basename(input_csv_path, '.csv')
    output_filename = "portal-tasks-reports/#{base_name}_updated.csv"

    # Ensure the reports directory exists
    FileUtils.mkdir_p('portal-tasks-reports')

    output_filename
  end

end
