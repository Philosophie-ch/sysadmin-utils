require 'csv'

SUPPORTED_ASSET_TYPES = ["audio_block", "video_block", "picture_block", "pdf_block"]


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


def process_asset_urls(unprocessed_asset_urls)
  split = unprocessed_asset_urls.split(',').map(&:strip).filter(&:present?)

  result = split.map do |url|
    if url.start_with?('http://', 'https://')
      url
    elsif url == 'empty'
      ""
    else
      "https://assets.philosophie.ch/#{url}"
    end
  end

  return result
end


def unprocess_asset_urls(processed_urls)
  unprocessed = processed_urls.map do |url|
    url.gsub('https://assets.philosophie.ch/', '')
  end

  return unprocessed.join(', ')
end


class UrlResolutionError < StandardError; end

def fetch_with_redirect(url, limit = 20)
  raise UrlResolutionError, 'too many HTTP redirects' if limit == 0

  uri = URI(url)
  response = Net::HTTP.get_response(uri)

  case response
  when Net::HTTPSuccess then
    response
  when Net::HTTPRedirection then
    location = response['location']
    new_uri = URI(location)

    unless new_uri.host
      new_uri = uri + location
    end

    Rails.logger.warn("URL '#{url}' redirected to '#{new_uri}'. Iteration: #{limit}")
    fetch_with_redirect(new_uri, limit - 1)
  else
    response.value
  end
end


def check_asset_urls_resolve(processed_urls)
  report = {
    status: 'not started',
    error_message: '',
    error_urls: "",
    error_trace: '',
  }

  error_urls = []

  begin

    processed_urls.each do |url|
      begin
        response = fetch_with_redirect(url)

        unless response.is_a?(Net::HTTPSuccess)
          error_urls << url
        end

      rescue => e
        error_urls << url
        report[:error_message] += " --- #{e.class} :: #{e.message}"
      end
    end

    if error_urls.blank?

      report[:status] = 'success'
      return report

    else
      report[:status] = 'url error'
      report[:error_message] = "The following URLs could not be resolved: #{error_urls.join(', ')}"
      report[:error_urls] = error_urls.join(', ')
      return report
    end

  rescue => e
    report[:status] = 'unhandled error'
    report[:error_message] = "#{e.class} :: #{e.message}"
    report[:error_trace] = e.backtrace.join(" ::: ")
    return report
  end
end
