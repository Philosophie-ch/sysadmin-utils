require 'csv'

def generate_csv_report(headers, report, base_folder, models_affected)
  return if report.empty?

  csv_string = CSV.generate do |csv|
    csv << headers
    report.each do |row|
      csv << headers.map { |header| row[header] }
    end
  end

  FileUtils.mkdir_p(base_folder) unless Dir.exist?(base_folder)

  file_name = "#{base_folder}/#{Time.now.strftime('%y%m%d')}_#{models_affected}_report.csv"

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


def download_submission_pdf(submission, base_folder)
  report = {
    status: "not started",
    error_message: "",
    error_trace: ""
  }

  begin
    unless submission.is_a?(Submission)
      report[:status] = "failed"
      report[:error_message] = "Invalid submission object"
      return report
    end
    unless submission&.file
      report[:status] = "failed"
      report[:error_message] = "Submission does not have a PDF"
      return report
    end

    file_name = "#{base_folder}/#{submission.dialectica_id}.pdf"
    FileUtils.mkdir_p(base_folder) unless Dir.exist?(base_folder)

    if File.exist?(file_name)
      report[:status] = "skipped"
      report[:error_message] = "File #{file_name} already exists."
      return report
    end

    open(file_name, 'wb') do |file|
      file.write(submission.file.download)
    end

    report[:status] = "success"

  rescue => e
    error_message = "utils ::: download_submission_pdf ::: #{e.class} ::: #{e.message}"
    report[:status] = "unhandled exception"
    report[:error_message] = error_message
    report[:error_trace] = e.backtrace.join(" :::")
  end

  report
end
