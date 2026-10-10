require 'csv'
require 'date'
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


# 'dates' cell: comma-separated ISO dates, e.g. "2026-11-05, 2026-11-06".
# Returns [sorted_dates, error_message]
def parse_event_dates(dates_str)
  parts = dates_str.to_s.split(',').map(&:strip).reject(&:blank?)
  return [[], "No dates found"] if parts.empty?

  parsed = []
  parts.each do |part|
    begin
      parsed << Date.iso8601(part)
    rescue ArgumentError
      return [[], "Invalid date '#{part}'. Use YYYY-MM-DD, several dates separated by commas"]
    end
  end

  duplicates = parsed.select { |d| parsed.count(d) > 1 }.uniq
  return [[], "Duplicate dates: #{duplicates.map(&:iso8601).join(', ')}"] unless duplicates.empty?

  [parsed.sort, nil]
end


# 'speakers' cell: semicolon-separated, each "@profile-slug | affiliation" or "Plain Name | affiliation".
# The affiliation part is optional. Order in the cell becomes the speaker position.
# Returns [array of {profile:, name:, affiliation:}, error_message]
def parse_event_speakers(speakers_str)
  items = speakers_str.to_s.split(';').map(&:strip).reject(&:blank?)
  speakers = []

  items.each do |item|
    who, affiliation = item.split('|', 2).map(&:strip)

    if who.blank?
      return [[], "Speaker without a name or profile slug in '#{item}'"]
    end

    if who.start_with?('@')
      slug = who[1..-1].strip
      profile = Profile.find_by(slug: slug)
      return [[], "Speaker profile with slug '#{slug}' not found"] if profile.nil?

      speakers << { profile: profile, name: nil, affiliation: affiliation.presence }
    else
      speakers << { profile: nil, name: who, affiliation: affiliation.presence }
    end
  end

  [speakers, nil]
end


def event_dates_to_string(event)
  event.ordered_dates.map { |event_date| event_date.date.iso8601 }.join(', ')
end


def event_speakers_to_string(event)
  event.speakers.order(:position).map do |speaker|
    who = speaker.profile.present? ? "@#{speaker.profile.slug}" : speaker.name.to_s
    speaker.affiliation.present? ? "#{who} | #{speaker.affiliation}" : who
  end.join('; ')
end


# Saves the event. Old events can have a title longer than the limit the model has today. When that is the only
# problem and the title is not being changed, the validation is skipped so the rest of the update still goes through.
def save_event!(event)
  return event.save! if event.valid?

  only_old_long_title = event.errors.keys == [:title] &&
                        event.errors.details[:title].all? { |detail| detail[:error] == :too_long } &&
                        !event.title_changed?

  only_old_long_title ? event.save!(validate: false) : event.save!
end


############
# MAIN
############

report = []
CSV.foreach("portal-tasks/events.csv", col_sep: ',', headers: true) do |row|

  subreport = {
    _request: row["_request"] || '',
    id: row["id"] || '',
    dates: row["dates"] || '',
    profile_slug: row["profile_slug"] || '',
    speakers: row["speakers"] || '',
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

    # Dates are required to create/update, and used for the fallback lookup (no id) otherwise
    dates = []
    if req == 'POST' || req == 'UPDATE' || subreport[:dates].present?
      dates, dates_error = parse_event_dates(subreport[:dates])
      if dates_error
        subreport[:status] = 'error'
        subreport[:error_message] = "#{dates_error}. Skipping..."
        subreport[:error_trace] = "Main::Control::dates"
        next
      end
    end

    if req == 'POST'
      same_events = Event.where(title: subreport[:title], region: subreport[:region], date: dates.min)
      unless same_events.empty?
        subreport[:status] = 'error'
        subreport[:error_message] = "Event with the same title, region, and earliest date already exists. Skipping..."
        subreport[:error_trace] = "Main::Control::POST"
        next
      end
    end

    speakers = []
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

      speakers, speakers_error = parse_event_speakers(subreport[:speakers])
      if speakers_error
        subreport[:status] = 'error'
        subreport[:error_message] = "#{speakers_error}. Skipping..."
        subreport[:error_trace] = "Main::Control::speakers"
        next
      end

    end

    # Parsing
    Rails.logger.info("Parsing task for event...")
    id = subreport[:id]
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
        # else try to retrieve event by title, region, and earliest date
        if dates.empty?
          subreport[:status] = 'error'
          subreport[:error_message] = "Neither id nor dates given, cannot look up the event. Skipping..."
          subreport[:error_trace] = "Main::Setup"
          next
        end

        event = Event.where(title: title, region: region, date: dates.min).first

        if event.nil?
          Rails.logger.error("Event with title '#{title}', region '#{region}', and earliest date '#{dates.min}' not found. Skipping...")
          subreport[:status] = 'error'
          subreport[:error_message] = "Event with title '#{title}', region '#{region}', and earliest date '#{dates.min}' not found. Skipping..."
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
      event_id = event.id
      event.destroy!  # also destroys event_dates and speakers
      if Event.find_by(id: event_id).present?
        subreport[:status] = 'error'
        subreport[:error_message] = "Event with ID #{event_id} not deleted for an unknown reason!"
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
        dates: event_dates_to_string(event),
        profile_slug: event.profile.slug,
        title: event.title,
        region: event.region,
        speakers: event_speakers_to_string(event),
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

      ActiveRecord::Base.transaction do
        # Event#date caches the earliest of event_dates (and is validated before the callback runs)
        event.date = dates.min
        event.profile = Profile.find_by(slug: profile_slug)
        event.title = title
        event.region = region
        # page-anchored events get their link computed by the portal from page_id and node_id
        event.link = link unless event.page_id.present? && event.node_id.present?
        event.recurrent = recurrent

        save_event!(event)

        # Replace the set of dates
        event.event_dates.where.not(date: dates).destroy_all
        existing_dates = event.event_dates.reload.map(&:date)
        (dates - existing_dates).each { |date| event.event_dates.create!(date: date) }

        # Save again so the before_save callback re-syncs Event#date from the new set of dates
        save_event!(event.reload)

        # Replace the speakers; position follows the order in the cell
        event.speakers.destroy_all
        speakers.each_with_index do |speaker, index|
          event.speakers.create!(position: index, profile: speaker[:profile], name: speaker[:name], affiliation: speaker[:affiliation])
        end
      end

      event.reload
      subreport[:status] = 'success'
    end

    # Update report
    Rails.logger.info("Updating report...")
    subreport.merge!({
      id: event.id,
      dates: event_dates_to_string(event),
      profile_slug: event.profile.slug,
      title: event.title,
      region: event.region,
      speakers: event_speakers_to_string(event),
      link: event.link,
      _url: "https://www.philosophie.ch#{event.link}",
      recurrent: "#{event.recurrent}".upcase,
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
