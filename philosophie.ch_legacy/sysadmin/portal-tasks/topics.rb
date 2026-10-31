require 'csv'

require_relative 'lib/utils'
require_relative 'lib/topics_tools'


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

  csv_data = CSV.read(csv_file, col_sep: ',', headers: true)
  total_lines = csv_data.size


  ############
  # MAIN
  ############

  csv_data.each do |row|
    Rails.logger.info("Processing row #{processed_lines + 1} of #{total_lines}")
    # Read data
    subreport = {
      _sort: row['_sort'] || '',
      request: row['request'] || '',
      id: row['id'] || '',
      topic_key: row['topic_key'] || '',
      group: row['group'] || '',
      interest_type: row['interest_type'] || '',
      color_theme: row['color_theme'] || '',
      translated: row['translated'] || '',
      translation_group: row['translation_group'] || '',
      name_de: row['name_de'] || '',
      name_fr: row['name_fr'] || '',
      name_it: row['name_it'] || '',
      name_en: row['name_en'] || '',
      name: row['name'] || '',
      page_language_code: row['page_language_code'] || '',
      page_urlname: row['page_urlname'] || '',
      url: row['url'] || '',

      status: '',
      changes_made: '',
      error_message: '',
      error_trace: '',
      original_order: '',
      result_order: '',
    }


    begin

      # Control
      Rails.logger.info("Processing topic: Control")
      supported_requests = ['POST', 'UPDATE', 'GET', 'DELETE', 'PURGE', 'PURGE DRY RUN', 'AD HOC']

      req = subreport[:request].strip

      if req.blank?
        subreport[:status] = ""
        next
      end

      unless supported_requests.include?(req)
        subreport[:request] = "ERROR"
        subreport[:status] = "error"
        subreport[:error_message] = "Unsupported request '#{req}'. Skipping"
        subreport[:error_trace] = "topics.rb::main::Control::Main"
        next
      end

      id = subreport[:id].strip
      fields = row_fields(row)

      if req == 'POST'
        if fields[:group].blank? || fields[:interest_type].blank?
          subreport[:request] += " ERROR"
          subreport[:status] = "error"
          subreport[:error_message] = "Need group and interest_type for POST. Skipping"
          subreport[:error_trace] = "topics.rb::main::Control::POST"
          next
        end

        if !parse_translated_flag(fields[:translated]) && Topic.where(name: fields[:name], group: fields[:group], interest_type: fields[:interest_type]).exists?
          subreport[:request] += " ERROR"
          subreport[:status] = "error"
          subreport[:error_message] = "Topic with name '#{fields[:name]}', group '#{fields[:group]}', and interest_type '#{fields[:interest_type]}' already exists. Skipping"
          subreport[:error_trace] = "topics.rb::main::Control::POST"
          next
        end
      end

      if ['UPDATE', 'GET', 'DELETE', 'PURGE', 'PURGE DRY RUN', 'AD HOC'].include?(req)
        if id.blank?
          subreport[:request] += " ERROR"
          subreport[:status] = "error"
          subreport[:error_message] = "Need ID for '#{req}'. Skipping"
          subreport[:error_trace] = "topics.rb::main::Control::UPDATE-GET-DELETE"
          next
        end
      end

      topic_identifier = fields[:name].blank? ? id : fields[:name]

      # Setup
      Rails.logger.info("Processing topic '#{topic_identifier}': Setup")

      if ['POST', 'UPDATE', 'AD HOC'].include?(req)
        problems = []
        problems << "Unsupported group '#{fields[:group]}'" unless SUPPORTED_GROUPS.include?(fields[:group])
        problems << "Unsupported interest_type '#{fields[:interest_type]}'" unless SUPPORTED_INTEREST_TYPES.include?(fields[:interest_type])

        if fields[:interest_type] == "badge" && !Topic::COLOR_THEMES.include?(fields[:color_theme])
          problems << "Unsupported color theme '#{fields[:color_theme]}'. Supported color themes are: #{Topic::COLOR_THEMES.join(', ')}"
        end

        unless problems.empty?
          subreport[:request] += " ERROR"
          subreport[:status] = "error"
          subreport[:error_message] = "Validation failed: #{problems.join(' --- ')}. Skipping"
          subreport[:error_trace] = "topics.rb::main::Setup"
          next
        end
      end

      topic = nil
      if ['UPDATE', 'GET', 'DELETE', 'PURGE', 'PURGE DRY RUN', 'AD HOC'].include?(req)
        topic = Topic.find_by(id: id)

        if topic.nil?
          Rails.logger.error("Topic with ID '#{id}' not found. Skipping")
          subreport[:request] += " ERROR"
          subreport[:status] = "error"
          subreport[:error_message] = "Topic with ID '#{id}' not found. Skipping"
          subreport[:error_trace] = "topics.rb::main::Setup::UPDATE-GET-DELETE"
          next
        end
      end


      # Execution
      Rails.logger.info("Processing topic '#{topic_identifier}': Execution")

      if req == 'DELETE'
        pages = topic_page_count(topic.id)

        if pages > 0
          subreport[:request] += " ERROR"
          subreport[:status] = "error"
          subreport[:error_message] = "Topic with ID '#{id}' is on #{pages} pages. It can only be removed by merging it into another topic. Skipping"
          subreport[:error_trace] = "topics.rb::main::Execution::DELETE"
          next
        end

        topic.destroy!

        if Topic.find_by(id: id).present?
          subreport[:request] += " ERROR"
          subreport[:status] = "error"
          subreport[:error_message] = "Topic with ID '#{id}' was not deleted for an unknown reason. Skipping"
          subreport[:error_trace] = "topics.rb::main::Execution::DELETE"
          next
        end

        subreport[:id] = ''
        subreport[:url] = ''
        subreport[:status] = "success"
        subreport[:changes_made] = "TOPIC WAS DELETED IN THE SERVER"
        subreport[:request] = "#{req} SUCCESS"
        next
      end

      if ['PURGE', 'PURGE DRY RUN'].include?(req)
        dry_run = req == 'PURGE DRY RUN'

        if topic.editors_pick
          subreport[:request] += " ERROR"
          subreport[:status] = "error"
          subreport[:error_message] = "Topic with ID '#{id}' is the editor's pick. Skipping"
          subreport[:error_trace] = "topics.rb::main::Execution::PURGE"
          next
        end

        pages = topic_page_count(topic.id)
        filters_changed = 0

        ActiveRecord::Base.transaction do
          AlchemyEssenceTopicsTopic.where(topic_id: topic.id).delete_all
          filters_changed = replace_topic_in_saved_filters([topic.id], nil)
          topic.destroy!
          raise ActiveRecord::Rollback if dry_run  # everything ran, nothing is saved
        end

        if dry_run
          subreport[:status] = "success"
          subreport[:changes_made] = "DRY RUN (nothing saved): TOPIC WOULD BE REMOVED FROM #{pages} PAGES, FROM #{filters_changed} SAVED FILTERS AND DELETED"
        else
          subreport[:id] = ''
          subreport[:url] = ''
          subreport[:status] = "success"
          subreport[:changes_made] = "TOPIC WAS REMOVED FROM #{pages} PAGES, FROM #{filters_changed} SAVED FILTERS AND DELETED IN THE SERVER"
        end
        subreport[:request] = "#{req} SUCCESS"
        next
      end

      if ['UPDATE', 'POST'].include?(req)
        check_translation_columns(fields)
        page = find_topic_page(fields[:page_language_code], fields[:page_urlname])  # this combination is unique
        translated = parse_translated_flag(fields[:translated])

        ActiveRecord::Base.transaction do
          if translated && page
            unless PageTranslationGroup.exists?(key: fields[:translation_group])
              raise "Translation group '#{fields[:translation_group]}' does not exist."
            end

            put_page_in_translation_group(page, fields[:translation_group])
          end

          topic = Topic.new if req == 'POST'
          apply_topic_fields(topic, fields, page)
        end
      end


      ############
      # REPORT
      ############
      Rails.logger.info("Processing topic '#{topic_identifier}': Updating report")

      updated_topic = Topic.find_by(id: topic.id)
      new_values = topic_report_values(updated_topic)

      old_values = {
        id: subreport[:id], topic_key: fields[:topic_key], group: fields[:group], interest_type: fields[:interest_type],
        color_theme: fields[:color_theme], translated: parse_translated_flag(fields[:translated]) ? "TRUE" : "FALSE",
        translation_group: fields[:translation_group], name_de: fields[:name_de], name_fr: fields[:name_fr],
        name_it: fields[:name_it], name_en: fields[:name_en], name: fields[:name],
        page_language_code: fields[:page_language_code], page_urlname: fields[:page_urlname], url: subreport[:url].strip,
      }

      subreport.merge!(new_values)
      subreport[:status] = 'success'


      ############
      # CHANGES MADE
      ############

      if ['UPDATE', 'GET', 'AD HOC'].include?(req)
        changes = []
        new_values.each do |key, value|
          next if old_values[key].to_s.empty? && value.to_s.empty?

          changes << "#{key}: {{ #{old_values[key]} }} => {{ #{value} }}" if old_values[key].to_s != value.to_s
        end
        subreport[:changes_made] = changes.join(' ;;; ')
      end

      Rails.logger.info("Processing topic '#{topic_identifier}': Success!")
      subreport[:request] = "#{req} SUCCESS"


    rescue => e
      error_message = "#{e.class} :: #{e.message}"
      Rails.logger.error("Processing topic: Unhandled error!: #{error_message}")
      subreport[:request] += " ERROR"
      subreport[:status] = 'unhandled error'
      subreport[:error_message] = error_message
      subreport[:error_trace] = e.backtrace.join(" ::: ")

    ensure
      report << subreport
      Rails.logger.info("Processing topic: Done!. Processed lines so far: #{processed_lines + 1} of #{total_lines}")
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
    'error' => 2,
    'unhandled error' => 3,
  }

  report.sort_by! { |subreport| status_ordering[subreport[:status]] || 9999 }
  report.each_with_index do |subreport, index|
    subreport[:result_order] = index + 1
  end

  report.sort_by! { |subreport| subreport[:original_order] }

  generate_csv_report(report, "topics")

end



if ARGV[0].blank?
  log_level = ""

else
  log_level = ARGV[0]
end

main("portal-tasks/topics.csv", log_level)
