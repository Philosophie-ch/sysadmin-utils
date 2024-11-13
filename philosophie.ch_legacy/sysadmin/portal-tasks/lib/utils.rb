require 'csv'

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

end
