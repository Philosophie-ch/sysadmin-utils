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
        raise "Invalid ID on line #{idx + 1}: '#{cleaned}' is not a valid integer"
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

end
