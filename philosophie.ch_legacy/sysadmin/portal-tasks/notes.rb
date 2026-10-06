require 'csv'

require_relative 'lib/utils'
require_relative 'lib/publication_tools'  # get_entity_link
require_relative 'lib/note_tools'

TABLE_NAME = 'notes'
ENTITY_NAME = 'note'
KEY = :slug  # indexed unique key to identify an entity
KEY_NAME = KEY.to_s
MODEL = Note
MODEL_NAME = "#{MODEL.name}"
FILE_NAME = "#{__FILE__}"


def main(csv_file, log_level = 'info')

  ############
  # SETUP
  ############

  ActiveRecord::Base.logger.level = Logger::WARN
  ActiveSupport::Deprecation.behavior = :silence  # silence useless deprecation warnings
  ActiveSupport::Deprecation.silenced = true
  ActiveSupport::Deprecation.debug = false  # Disable debug mode for deprecations


  Rails.logger.level = Logger::INFO

  case log_level.downcase
  when 'debug'
    Rails.logger.level = Logger::DEBUG
  when 'info'
    Rails.logger.level = Logger::INFO
  when 'warn'
    Rails.logger.level = Logger::WARN
  when 'error'
    Rails.logger.level = Logger::ERROR
  else
    Rails.logger.level = Logger::INFO
  end


  report = []
  processed_lines = 0

  csv_data = CSV.read(csv_file, col_sep: ',', headers: true, encoding: 'utf-16')
  total_lines = csv_data.size


  ############
  # MAIN
  ############

  csv_data.each do |row|
    Rails.logger.info("Processing row #{processed_lines + 1} of #{total_lines}")
    # Read data
    subreport = {
      _to_do: row['_to_do'] || '',
      _sort: row['_sort'] || '',
      id: row['id'] || '',
      title: row['title'] || '',
      summary: row['summary'] || '',
      body: row['body'] || '',
      author: row['author'] || '',
      content_languages: row['content_languages'] || '',
      KEY => row[KEY_NAME] || '',
      link: row['link'] || '',
      _request: row['_request'] || '',
      created_at: row['created_at'] || '',  # read-only
      last_updated_date: row['last_updated_date'] || '',  # read-only
      anonymous: row['anonymous'] || '',
      published: row['published'] || '',
      published_at: row['published_at'] || '',
      interest_count: row['interest_count'] || '',  # read-only
      comment_count: row['comment_count'] || '',  # read-only

      status: '',
      changes_made: '',
      error_message: '',
      error_trace: '',
      warning_messages: '',
      original_order: '',
      result_order: '',
    }


    begin

      # Control
      Rails.logger.info("Processing #{ENTITY_NAME}: Control")
      supported_requests = ['POST', 'UPDATE', 'GET', 'DELETE']

      req = subreport[:_request].strip.upcase
      req_err = "Z_ERROR -- #{req}"

      if req.blank?
        subreport[:status] = ""
        subreport[:warning_messages] += " ::: Request is blank. Skipping."
        next
      else
        unless supported_requests.include?(req)
          set_row_error(subreport, req_err, "Unsupported request '#{req}'. Skipping", "#{FILE_NAME}::main::Control::Main")
          next
        end
      end

      id = subreport[:id].strip
      entity_key = subreport[KEY].strip

      title = subreport[:title].strip
      author_slug = subreport[:author].strip

      if req == 'POST'
        if title.blank? || author_slug.blank?
          set_row_error(subreport, req_err, "Need title and author for POST. Skipping", "#{FILE_NAME}::main::Control::POST")
          next
        end

        # A blank slug is fine on POST: the portal generates one
        if entity_key.present? && MODEL.where(KEY => entity_key).present?
          set_row_error(subreport, req_err, "#{MODEL_NAME} with #{KEY_NAME} '#{entity_key}' already exists. Skipping", "#{FILE_NAME}::main::Control::POST")
          next
        end
      end

      if ['UPDATE', 'GET', 'DELETE'].include?(req)
        if id.blank? && entity_key.blank?
          set_row_error(subreport, req_err, "Need ID or #{KEY_NAME} for '#{req}'. Skipping", "#{FILE_NAME}::main::Control::UPDATE-GET-DELETE")
          next
        end
      end

      if req == 'UPDATE' && title.blank?
        set_row_error(subreport, req_err, "Need title for UPDATE. Skipping", "#{FILE_NAME}::main::Control::UPDATE")
        next
      end

      entity_display_name = title.blank? ? (entity_key.blank? ? id : entity_key) : title

      # Parsing
      Rails.logger.info("Processing #{ENTITY_NAME} '#{entity_display_name}': Parsing")

      # Blank means "leave unchanged" for these (nil)
      published = parse_published_flag(subreport[:published])
      anonymous = parse_boolean_flag(subreport[:anonymous])

      published_at, published_at_error = parse_published_at(subreport[:published_at])
      if published_at_error
        set_row_error(subreport, req_err, published_at_error, "#{FILE_NAME}::main::Parsing::published_at")
        next
      end

      content_languages, content_languages_error = parse_content_languages(subreport[:content_languages])
      if content_languages_error
        set_row_error(subreport, req_err, content_languages_error, "#{FILE_NAME}::main::Parsing::content_languages")
        next
      end

      author = nil
      if ['POST', 'UPDATE'].include?(req) && author_slug.present?
        author = Profile.find_by(slug: author_slug)
        if author.nil?
          set_row_error(subreport, req_err, "Author profile with slug '#{author_slug}' not found. Skipping", "#{FILE_NAME}::main::Parsing::author")
          next
        end
      end


      # Setup
      Rails.logger.info("Processing #{ENTITY_NAME} '#{entity_display_name}': Setup")

      entity = nil
      if ['UPDATE', 'GET', 'DELETE'].include?(req)
        entity_by_id = MODEL.find_by(id: id)
        entity_by_key = MODEL.find_by(KEY => entity_key)

        if entity_by_id.nil? && entity_by_key.nil?
          Rails.logger.error("#{MODEL_NAME} with ID '#{id}' or #{KEY_NAME} '#{entity_key}' not found. Skipping")
          set_row_error(subreport, req_err, "#{MODEL_NAME} with ID '#{id}' or #{KEY_NAME} '#{entity_key}' not found. Skipping", "#{FILE_NAME}::main::Setup::UPDATE-GET-DELETE")
          next
        end

        if entity_by_id && entity_by_key && entity_by_id.id != entity_by_key.id
          Rails.logger.error("Both #{MODEL_NAME} with ID '#{id}' and #{KEY_NAME} '#{entity_key}' found, but they are not the same. Skipping")
          set_row_error(subreport, req_err, "Both #{MODEL_NAME} with ID '#{id}' and #{KEY_NAME} '#{entity_key}' found, but they are not the same: found by_id: [[ #{entity_by_id.id}, #{entity_by_id[KEY]} ]], found by_key: [[ #{entity_by_key.id}, #{entity_by_key[KEY]} ]]. Skipping", "#{FILE_NAME}::main::Setup::UPDATE-GET-DELETE")
          next
        end

        entity = entity_by_id || entity_by_key
      end


      # Execution
      Rails.logger.info("Processing #{ENTITY_NAME} '#{entity_display_name}': Execution")

      if req == 'DELETE'
        entity_id = entity.id
        entity.destroy!  # destroy (not delete) so languages, interests and comments are removed too

        if MODEL.find_by(id: entity_id).present?
          set_row_error(subreport, req_err, "#{MODEL_NAME} with ID '#{entity_id}' was not deleted for an unknown reason. Skipping", "#{FILE_NAME}::main::Execution::DELETE")
          next
        else
          subreport[:id] = ''
          subreport[KEY] = ''
          subreport[:link] = ''
          subreport[:status] = "success"
          subreport[:changes_made] = "#{MODEL_NAME.upcase} WAS DELETED IN THE SERVER"
          subreport[:_request] = "Z_SUCCESS -- #{req}"
          next
        end
      end

      entity = MODEL.new if req == "POST"

      old_row = note_to_row(entity) if ['UPDATE', 'GET'].include?(req)

      if req == "UPDATE" || req == "POST"

        ActiveRecord::Base.transaction do
          # A blank slug keeps the current one (UPDATE) or lets the portal generate one (POST)
          entity.slug = entity_key if entity_key.present?
          entity.title = title
          entity.summary = subreport[:summary].to_s.strip.presence
          entity.body = subreport[:body].to_s.strip.presence

          # Blank author / anonymous / published / published_at leave the current value unchanged
          entity.author = author unless author.nil?
          entity.anonymous = anonymous unless anonymous.nil?
          entity.published = published unless published.nil?
          entity.published_at = published_at unless published_at.nil?
          # Same as Note#publish!: the first publication sets the date
          entity.published_at ||= Time.current if entity.published?

          entity.save!

          # Replace the set of languages
          entity.note_languages.where.not(language_code: content_languages).destroy_all
          existing_codes = entity.note_languages.reload.pluck(:language_code)
          (content_languages - existing_codes).each { |code| entity.note_languages.create!(language_code: code) }
        end

      end


      ############
      # REPORT
      ############
      Rails.logger.info("Processing #{ENTITY_NAME} '#{entity_display_name}': Updating report")

      updated_entity = MODEL.find_by(id: entity.id)
      new_row = note_to_row(updated_entity)

      subreport.merge!(new_row)
      subreport[:status] = 'success'


      ############
      # CHANGES MADE
      ############

      if ['UPDATE', 'GET'].include?(req)
        # last_updated_date changes on every save, so it is not reported as a change
        changed_keys = new_row.keys.reject { |key| key == :last_updated_date }.select { |key| old_row[key] != new_row[key] }
        subreport[:changes_made] = changed_keys.map { |key| "#{key}: {{ #{old_row[key]} }} => {{ #{new_row[key]} }}" }.join(' ;;; ')
      end

      Rails.logger.info("Processing #{ENTITY_NAME} '#{subreport[KEY]}': Success!")
      subreport[:_request] = "Z_SUCCESS -- #{req}"


    rescue => e
      error_message = "#{e.class} :: #{e.message}"
      Rails.logger.error("Processing #{ENTITY_NAME}: Unhandled error!: #{error_message}")
      subreport[:_request] = req_err
      subreport[:status] = 'unhandled error'
      subreport[:error_message] = error_message
      subreport[:error_trace] = e.backtrace.join(" ::: ")

    ensure
      report << subreport
      Rails.logger.info("Processing #{ENTITY_NAME}: Done!. Processed lines so far: #{processed_lines + 1} of #{total_lines}")
      processed_lines += 1
    end

  end


  ############
  # REPORT
  ############

  report.each_with_index do |subreport, index|
    subreport[:original_order] = index + 1
  end

  status_ordering = {
    'success' => 1,
    'partial error' => 2,
    'error' => 3,
    'unhandled error' => 4,
    'not started' => 5,
  }

  report.sort_by! { |subreport| status_ordering[subreport[:status]] || 9999 }
  report.each_with_index do |subreport, index|
    subreport[:result_order] = index + 1
  end

  report.sort_by! { |subreport| subreport[:original_order] }

  generate_csv_report(report, TABLE_NAME)

end



if ARGV[0].blank?
  log_level = ""

else
  log_level = ARGV[0]
end

main("portal-tasks/#{TABLE_NAME}.csv", log_level)
