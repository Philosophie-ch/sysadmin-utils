require 'csv'

SUPPORTED_ASSET_TYPES = ["audio_block", "video_block", "picture_block", "pdf_block"]

module Utils

  def generate_csv_report(report, models_affected)
    return if report.empty?
    headers = report.first.keys

    csv_string = CSV.generate do |csv|
      csv << headers
      report.each do |row|
        csv << headers.map { |header| row[header] }
      end
    end

    base_folder = 'portal-tasks-reports'
    FileUtils.mkdir_p(base_folder) unless Dir.exist?(base_folder)

    file_name = "#{base_folder}/#{Time.now.strftime('%y%m%d')}_#{models_affected}_tasks_report.csv"

    begin
      File.write(file_name, csv_string)
      puts "File written successfully to #{file_name}"
    rescue Errno::EACCES => e
      puts "Permission denied: #{e.message}"
    rescue Errno::ENOSPC => e
      puts "No space left on device: #{e.message}"
    rescue StandardError => e
      puts "An error occurred: #{e.message}"
    end

    Rails.logger.info("\n\n\n============ Report generated at #{file_name} ============\n\n\n")
  end

  module_function :generate_csv_report

  def download_asset(base_dir, filename, asset_path, asset_type)

    report = {
      status: "not started",
      error_message: "",
      error_trace: ""
    }

    unless SUPPORTED_ASSET_TYPES.include?(asset_type)
      report[:status] = "failed"
      report[:error_message] = "Unsupported asset type: #{asset_type}"
      return report
    end

    begin
      destination_path = "#{base_dir}/#{filename}"
      FileUtils.mkdir_p(base_dir) unless Dir.exist?(base_dir)

      if File.exist?(destination_path)
        report[:status] = "skipped"
        report[:error_message] = "File #{destination_path} already exists"
        return report
      end

      open(destination_path, 'wb') do |file|
        file << open(asset_path).read
      end

      report[:status] = "success"
      return report

    rescue StandardError => e
      report[:status] = "unhandled exception"
      report[:error_message] = "#{e.message}"
      report[:error_trace] = e.backtrace.join(" ::: ")
      return report
    end
  end

  module_function :download_asset
end
