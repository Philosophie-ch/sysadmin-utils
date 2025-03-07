require 'csv'
require 'fileutils'

ActiveRecord::Base.logger.level = Logger::WARN

Rails.logger.level = Logger::INFO

if ARGV[0]
  # set log level
  if ARGV[0] == 'debug'
    Rails.logger.level = Logger::DEBUG
  elsif ARGV[0] == 'info'
    Rails.logger.level = Logger::INFO
  elsif ARGV[0] == 'warn'
    Rails.logger.level = Logger::WARN
  elsif ARGV[0] == 'error'
    Rails.logger.level = Logger::ERROR
  end
end


############
# FUNCTIONS
############

def generate_csv_report(report)
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

  file_name = "#{base_folder}/#{Time.now.strftime('%y%m%d')}_events_report.csv"

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


############
# MAIN
############

report = []
CSV.foreach("portal-tasks/events.csv", col_sep: ',', headers: true) do |row|

  subreport = {
    _request: row["_request"] || '',
    id: row["id"] || '',
    date: row["date"] || '',
    profile_slug: row["profile_slug"] || '',
    title: row["title"] || '',
    region: row["region"] || '',
    link: row["link"] || '',
    _url: row["_url"] || '',
    recurrent: row["recurrent"] || '',
    _to_do_for_us: row["_to_do_for_us"] || '',

    status: '',
    changes_made: '',
    error_message: '',
    error_trace: '',
  }


  begin

    # Control
    Rails.logger.info("Starting task for event...")

    supported_requests = ['POST', 'UPDATE', 'GET', 'DELETE']
    req = subreport[:_request].upcase.strip

    if req.nil? || req.empty? || req.strip == ''
      subreport[:status] = ''
    else
      unless supported_requests.include?(req)
        subreport[:status] = 'error'
        subreport[:error_message] = "Request not supported: #{req}. Skipping..."
        subreport[:error_trace] = "Main::Control"
        next
      end
    end

    if req == 'POST'
      same_events = Event.where(title: subreport[:title], region: subreport[:region], date: subreport[:date])
      unless same_events.empty?
        subreport[:status] = 'error'
        subreport[:error_message] = "Event with the same title, region, and date already exists. Skipping..."
        subreport[:error_trace] = "Main::Control::POST"
        next
      end
    end

    if req == 'UPDATE' || req == 'POST'
      if subreport[:title].nil? || subreport[:title].empty? || subreport[:title].strip == '' || subreport[:title].blank?
        subreport[:status] = 'error'
        subreport[:error_message] = "Title is empty, but required for '#{req}'. Skipping..."
        subreport[:error_trace] = "Main::Control::UPDATE/POST"
        next
      end

      if subreport[:region].nil? || subreport[:region].empty? || subreport[:region].strip == '' || subreport[:region].blank?
        subreport[:status] = 'error'
        subreport[:error_message] = "Region is empty, but required for '#{req}'. Skipping..."
        subreport[:error_trace] = "Main::Control::UPDATE/POST"
        next
      end

      if subreport[:date].nil? || subreport[:date].empty? || subreport[:date].strip == '' || subreport[:date].blank?
        subreport[:status] = 'error'
        subreport[:error_message] = "Date is empty, but required for '#{req}'. Skipping..."
        subreport[:error_trace] = "Main::Control::UPDATE/POST"
        next
      end

      if subreport[:profile_slug].nil? || subreport[:profile_slug].empty? || subreport[:profile_slug].strip == '' || subreport[:profile_slug].blank?
        subreport[:status] = 'error'
        subreport[:error_message] = "Profile slug is empty, but required for '#{req}'. Skipping..."
        subreport[:error_trace] = "Main::Control::UPDATE/POST"
        next
      else
        if Profile.find_by(slug: subreport[:profile_slug]).nil?
          subreport[:status] = 'error'
          subreport[:error_message] = "Profile with slug '#{subreport[:profile_slug]}' not found. Skipping..."
          subreport[:error_trace] = "Main::Control::UPDATE/POST"
          next
        end
      end

    end

    # Parsing
    Rails.logger.info("Parsing task for event...")
    id = subreport[:id]
    date = subreport[:date]
    profile_slug = subreport[:profile_slug]
    title = subreport[:title]
    region = subreport[:region]
    link = subreport[:link]
    recurrent = subreport[:recurrent].strip.downcase == 'true' ? true : false


    # Setup
    Rails.logger.info("Processing event...")

    if req == 'POST'
      event = Event.new

    elsif req == 'UPDATE' || req == 'DELETE' || req == 'GET'

      unless id.nil? || id.empty? || id.strip == '' || id.blank?
        # try to retrieve event by ID if there's one
        event = Event.find_by(id: id)

        if event.nil?
          Rails.logger.error("Event with ID #{id} not found. Skipping...")
          subreport[:status] = 'error'
          subreport[:error_message] = "Event with ID #{id} not found. Skipping..."
          subreport[:error_trace] = "Main::Setup"
          next
        end

      else
        # else try to retrieve event by title, region, and date
        event = Event.where(title: title, region: region, date: date).first

        if event.nil?
          Rails.logger.error("Event with title '#{title}', region '#{region}', and date '#{date}' not found. Skipping...")
          subreport[:status] = 'error'
          subreport[:error_message] = "Event with title '#{title}', region '#{region}', and date '#{date}' not found. Skipping..."
          subreport[:error_trace] = "Main::Setup"
          next
        end

        retrieved_profile_slug = event.profile.slug

        if subreport[:profile_slug] != retrieved_profile_slug
          subreport[:status] = 'error'
          subreport[:error_message] = "Profile slug mismatch: '#{subreport[:profile_slug]}' != '#{retrieved_profile_slug}'. Skipping..."
          subreport[:error_trace] = "Main::Setup"
          next
        end
      end


    else  # should not happen
      Rails.logger.error("Request not supported: #{req}. Skipping...")
      subreport[:status] = 'error'
      subreport[:error_message] = "Request not supported: #{req}. Skipping..."
      subreport[:error_trace] = "Main::Setup"
      next
    end

    if req == 'DELETE'
      event.delete
      if Event.find_by(id: id).present?
        subreport[:status] = 'error'
        subreport[:error_message] = "Event with ID #{id} not deleted for an unknown reason!"
        subreport[:error_trace] = "Main::Setup::DELETE"
        next
      else
        subreport[:id] = ''
        subreport[:status] = 'success'
        subreport[:changes_made] = 'EVENT WAS DELETED IN THE SERVER'
        next
      end
    end

    if req == 'UPDATE' || req == 'GET'
      old_event = {
        _request: subreport[:_request],
        id: event.id,
        date: event.date.strftime('%Y-%m-%d'),
        profile_slug: event.profile.slug,
        title: event.title,
        region: event.region,
        link: event.link,
        _url: subreport[:_url],
        recurrent: subreport[:recurrent],
        _to_do_for_us: subreport[:_to_do_for_us],

        status: subreport[:status],
        changes_made: subreport[:changes_made],
        error_message: subreport[:error_message],
        error_trace: subreport[:error_trace],
      }
    end

    # Execution
    Rails.logger.info("Executing task for event...")

    if req == 'POST' || req == 'UPDATE'
      Rails.logger.info("Processing event: setting attributes...")
      event.date = date
      event.profile = Profile.find_by(slug: profile_slug)
      event.title = title
      event.region = region
      event.link = link
      event.recurrent = recurrent

      successful_save = event.save!
      if successful_save
        subreport[:status] = 'success'
      else
        subreport[:status] = 'error'
        subreport[:error_message] = "Event not saved for an unknown reason! Skipping..."
        subreport[:error_trace] = "Main::Execution"
        next
      end
    end

    # Update report
    Rails.logger.info("Updating report...")
    subreport.merge!({
      id: event.id,
      date: event.date.strftime('%Y-%m-%d'),
      profile_slug: event.profile.slug,
      title: event.title,
      region: event.region,
      link: event.link,
      recurrent: "#{event.recurrent}".upcase,
      _url: "https://www.philosophie.ch#{event.link}",
    })

    if req == 'UPDATE' || req == 'GET'
      changes = []
      subreport.each do |key, value|
        if old_event[key] != value && key != :changes_made && key != :status && key != :error_message && key != :error_trace && key != :_request
          unless old_event[key].to_s.empty? && value.to_s.empty?
            changes << "#{key}: {{ #{old_event[key]} }} => {{ #{value} }}"
          end
        end
      end
      subreport[:changes_made] = changes.join(' ;;; ')
    end

    subreport[:status] = 'success'
    Rails.logger.info("Event processed successfully!")

  rescue StandardError => e
    subreport[:status] = 'unhandled error'
    subreport[:error_message] = e.message
    subreport[:error_trace] = e.backtrace.join(" ::: ")

  ensure
    report << subreport
  end

end

generate_csv_report(report)
