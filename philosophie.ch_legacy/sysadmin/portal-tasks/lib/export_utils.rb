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

    # Check for missing IDs
    missing_ids = ids - records.keys
    unless missing_ids.empty?
      raise "The following IDs were not found in the database: #{missing_ids.join(', ')}"
    end

    # Return records in the original order
    ordered_records = ids.map { |id| records[id] }

    Rails.logger.info("All #{ids.length} IDs validated successfully")
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
    rescue ArgumentError, Encoding::InvalidByteSequenceError
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
    rescue ArgumentError, Encoding::InvalidByteSequenceError
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


  # Merge DB data with preserved columns from input CSV
  # Returns merged report ready for CSV output
  def self.merge_with_input_csv(db_rows, input_csv_data, preserved_columns)
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
