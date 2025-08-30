require 'csv'

require_relative 'lib/utils'
require_relative 'lib/journal_publisher_tools'

TABLE_NAME = 'publishers'
ENTITY_NAME = 'publisher'
KEY = :publisher_key  # indexed unique key to identify an entity
KEY_NAME = KEY.to_s
MODEL = Publisher
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
      _temp: row['_temp'] || '',
      _sort: row['_sort'] || '',
      _todo: row['_todo'] || '',

      request: row['request'] || '',
      id: row['id'] || '',
      KEY => row[KEY_NAME] || '',

      _biblio_full_name: row['_biblio_full_name'] || '',
      name: row['name'] || '',
      link: row['link'] || '',

      presentation_page_language_code: row['presentation_page_language_code'] || '',
      presentation_page_urlname: row['presentation_page_urlname'] || '',

      _contact_person: row['_contact_person'] || '',
      _contact_person_email: row['_contact_person_email'] || '',

      _references_keys: row['_references_keys'] || '',
      references_asset: row['references_asset'] || '',
      _further_references_keys: row['_further_references_keys'] || '',
      further_references_asset: row['further_references_asset'] || '',
      _references_dependencies_keys: row['_references_dependencies_keys'] || '',

      description: row['description'] || '',
      website: row['website'] || '',
      cover_picture_asset: row['cover_picture_asset'] || '',

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
      supported_requests = ['POST', 'UPDATE', 'GET', 'DELETE', 'AD HOC']

      req = subreport[:request].strip.upcase
      req_err = "Z_ERROR -- #{req}"

      if req.blank?
        subreport[:status] = ""
        subreport[:warning_messages] += " ::: Request is blank. Skipping."
        next
      else
        unless supported_requests.include?(req)
          subreport[:request] = req_err
          subreport[:status] = "error"
          subreport[:error_message] = "Unsupported request '#{req}'. Skipping"
          subreport[:error_trace] = "#{FILE_NAME}.rb::main::Control::Main"
        end
      end

      id = subreport[:id].strip
      entity_key = subreport[KEY].strip

      name = subreport[:name].strip

      if req == 'POST'
        if name.blank? || entity_key.blank?
          subreport[:request] = req_err
          subreport[:status] = "error"
          subreport[:error_message] = "Need name and entity_key for POST. Skipping"
          subreport[:error_trace] = "#{FILE_NAME}::main::Control::POST"

          next
        end
        retrieved = MODEL.where(KEY => entity_key)

        if retrieved.present?
          subreport[:request] = req_err
          subreport[:status] = "error"
          subreport[:error_message] = "#{MODEL_NAME} with key '#{entity_key}' already exists. Skipping"
          subreport[:error_trace] = "#{FILE_NAME}::main::Control::POST"

          next
        end
      end

      if ['UPDATE', 'GET', 'DELETE', 'AD HOC'].include?(req)
        if id.blank? && entity_key.blank?
          subreport[:request] = req_err
          subreport[:status] = "error"
          subreport[:error_message] = "Need ID or #{KEY_NAME} for '#{req}'. Skipping"
          subreport[:error_trace] = "#{FILE_NAME}::main::Control::UPDATE-GET-DELETE"

          next
        end
      end

      entity_display_name = name.blank? ? id : name

      # Parsing
      Rails.logger.info("Processing #{ENTITY_NAME} '#{entity_display_name}': Parsing")

      presentation_page_language_code = subreport[:presentation_page_language_code].strip
      presentation_page_urlname = subreport[:presentation_page_urlname].strip
      presentation_page = nil

      if ['UPDATE', 'POST', 'AD HOC'].include?(req)

        if !presentation_page_language_code.blank? && !presentation_page_urlname.blank?

          unless SUPPORTED_LANGUAGE_CODES.include?(presentation_page_language_code)
            subreport[:request] = req_err
            subreport[:status] = "error"
            subreport[:error_message] = "Unsupported language code '#{presentation_page_language_code}'. Skipping. Supported language codes are: #{SUPPORTED_LANGUAGE_CODES.join(', ')}"
            subreport[:error_trace] = "#{FILE_NAME}::main::Parsing"
            next
          end

          presentation_page = Alchemy::Page.find_by(urlname: presentation_page_urlname, language_code: presentation_page_language_code)  # this combination is unique

          if not presentation_page_language_code.blank? and not presentation_page_urlname.blank? and presentation_page.nil?
            subreport[:request] = req_err
            subreport[:status] = "error"
            subreport[:error_message] = "Page with URL name '#{presentation_page_urlname}' and language code '#{presentation_page_language_code}' not found. Skipping"
            subreport[:error_trace] = "#{FILE_NAME}::main::Parsing"
            next

          end

        end
      end


      # Setup
      Rails.logger.info("Processing #{ENTITY_NAME} '#{entity_display_name}': Setup")

      raw_cover_picture_asset = subreport[:cover_picture_asset].strip
      cover_picture_asset = raw_cover_picture_asset.blank? ? 'empty' : raw_cover_picture_asset

      raw_references_asset = subreport[:references_asset].strip
      references_asset = raw_references_asset.blank? ? 'empty' : raw_references_asset

      raw_further_references_asset = subreport[:further_references_asset].strip
      further_references_asset = raw_further_references_asset.blank? ? 'empty' : raw_further_references_asset

      unprocessed_assets = [
        cover_picture_asset,
        references_asset,
        further_references_asset
      ].join(',').strip

      if ['POST', 'UPDATE', 'AD HOC'].include?(req)

        processed_assets = process_asset_urls(unprocessed_assets)
        urls_check = check_asset_urls_resolve(processed_assets)

        if urls_check[:status] != 'success'
          subreport[:request] = req_err
          subreport[:status] = urls_check[:status]
          subreport[:error_message] = urls_check[:error_message]
          subreport[:error_urls] = urls_check[:error_urls]
          subreport[:error_trace] = urls_check[:error_trace]
          next
        end

      end

      processed_cover_picture_asset = process_asset_urls(cover_picture_asset).first.to_s.strip
      processed_references_asset = process_asset_urls(references_asset).first.to_s.strip
      processed_further_references_asset = process_asset_urls(further_references_asset).first.to_s.strip


      entity = nil
      if ['UPDATE', 'GET', 'DELETE', 'AD HOC'].include?(req)
        entity_by_id = MODEL.find_by(id: id)
        entity_by_key = MODEL.find_by(KEY => entity_key)

        if entity_by_id.nil? && entity_by_key.nil?
          Rails.logger.error("#{MODEL_NAME} with ID '#{id}' or #{KEY_NAME} '#{entity_key} not found. Skipping")
          subreport[:request] = req_err
          subreport[:status] = "error"
          subreport[:error_message] = "#{MODEL_NAME} with ID '#{id}' or #{KEY_NAME} '#{entity_key} not found. Skipping"
          subreport[:error_trace] = "#{FILE_NAME}::main::Setup::UPDATE-GET-DELETE"
          next
        end

        if entity_by_id && entity_by_key && entity_by_id.id != entity_by_key.id
          Rails.logger.error("Both #{MODEL_NAME} with ID '#{id}' and #{KEY_NAME} '#{entity_key}' found, but they are not the same. Skipping")
          subreport[:request] = req_err
          subreport[:status] = "error"
          subreport[:error_message] = "Both #{MODEL_NAME} with ID '#{id}' and #{KEY_NAME} '#{entity_key}' found, but they are not the same: found by_id: [[ #{entity_by_id.id}, #{entity_by_id[KEY]} ]], found by_key: [[ #{entity_by_key.id}, #{entity_by_key[KEY]} ]]. Skipping"
          subreport[:error_trace] = "#{FILE_NAME}::main::Setup::UPDATE-GET-DELETE"
          next
        end

        if entity_by_id
          entity = entity_by_id
        else
          entity = entity_by_key
        end

      end


      # Execution
      Rails.logger.info("Processing #{ENTITY_NAME} '#{entity_display_name}': Execution")

      if req == 'DELETE'
        entity.delete

        entity_present = MODEL.find_by(id: id).present?

        if entity_present
          subreport[:request] = req_err
          subreport[:status] = "error"
          subreport[:error_message] = "#{MODEL_NAME} with ID '#{id}' was not deleted for an unknown reason. Skipping"
          subreport[:error_trace] = "#{FILE_NAME}::main::Execution::DELETE"
          next
        else
          subreport[:id] = ''
          subreport[:slug] = ''
          subreport[:link] = ''
          subreport[:status] = "success"
          subreport[:changes_made] = "#{MODEL_NAME.upcase} WAS DELETED IN THE SERVER"
          next
        end
      end

      if req == "POST"

        entity = MODEL.new(
          KEY => entity_key,
        )

      end

      if ['UPDATE', 'GET'].include?(req)

        old_entity_key = entity[KEY]
        old_page = get_entity_presentation_page(entity, ENTITY_NAME)
        old_page_urlname = old_page&.urlname || ''
        old_page_language_code = old_page&.language_code || ''

        old_entity = {
          _temp: subreport[:_temp],
          _sort: subreport[:_sort],
          _todo: subreport[:_todo],

          request: subreport[:request],
          id: subreport[:id],
          KEY => old_entity_key,

          _biblio_full_name: subreport[:_biblio_full_name],
          name: entity.name || '',
          link: get_entity_link(old_entity_key, ENTITY_NAME),

          presentation_page_language_code: old_page_language_code,
          presentation_page_urlname: old_page_urlname,

          _contact_person: subreport[:_contact_person],
          _contact_person_email: subreport[:_contact_person_email],

          _references_keys: subreport[:_references_keys],
          references_asset: entity.references_url || '',
          _further_references_keys: subreport[:_further_references_keys],
          further_references_asset: entity.further_references_url || '',
          _references_dependencies_keys: subreport[:_references_dependencies_keys],

          description: entity.description || '',
          website: entity.website || '',
          cover_picture_asset: entity.picture_url || '',

          status: '',
          changes_made: '',
          error_message: '',
          error_trace: '',
          warning_messages: '',
          original_order: '',
          result_order: '',

        }

      end

      if req == "UPDATE" || req == "POST"

        entity[KEY] = entity_key
        entity.name = name

        entity.presentation_page_id = presentation_page&.id

        entity.references_url = processed_references_asset
        entity.further_references_url = processed_further_references_asset

        entity.description = subreport[:description].to_s.strip || ''
        entity.website = subreport[:website].to_s.strip || ''
        entity.picture_url = processed_cover_picture_asset

        entity.save!
      end

      # Update report
      Rails.logger.info("Processing #{ENTITY_NAME} '#{entity_display_name}': Updating report")


      #######
      # AD HOC
      # Special request not to be commited
      #######

      if req == 'AD HOC'

      end


      ############
      # REPORT
      ############
      updated_entity = MODEL.find_by(id: entity.id)
      queried_page = Alchemy::Page.find_by(id: entity.presentation_page_id)

      queried_page_language_code = queried_page&.language_code || ""
      queried_page_urlname = queried_page&.urlname || ""

      new_link = get_entity_link(updated_entity[KEY], ENTITY_NAME)

      unprocessed_references_asset = updated_entity.references_url.blank? ? 'empty' : updated_entity.references_url
      unprocessed_further_references_asset = updated_entity.further_references_url.blank? ? 'empty' : updated_entity.further_references_url

      cover_pic_url = updated_entity.picture_url.to_s.strip || ''
      unprocessed_cover_picture_asset = cover_pic_url.blank? ? 'empty' : unprocess_asset_urls([cover_pic_url]).strip

      subreport.merge!({
        id: "#{updated_entity.id}".strip,
        KEY => updated_entity[KEY].strip,

        name: updated_entity.name,
        link: new_link,

        presentation_page_language_code: queried_page_language_code,
        presentation_page_urlname: queried_page_urlname,

        references_asset: unprocessed_references_asset,
        further_references_asset: unprocessed_further_references_asset,

        description: updated_entity.description.to_s.strip || '',
        website: updated_entity.website.to_s.strip || '',
        cover_picture_asset: unprocessed_cover_picture_asset,

      })

      subreport[:status] = 'success'


      ############
      # COMPLEX TASKS ON UPDATE AND POST
      ############

      if req == "UPDATE" || req == "POST"
        ## If some complext task is added and it fails, the status should be "partial error" and the request "... PARTIAL"

        ## Saving
        #entity.save!
        #entity.publish!
      end


      ############
      # CHANGES MADE
      ############

      if ['UPDATE', 'GET', 'AD HOC'].include?(req)
        changes = []
        subreport.each do |key, value|
          if old_entity[key] != value && key != :changes_made && key != :status && key != :error_message && key != :error_trace && key != :request && key != :warning_messages && key != :result_order && key != :original_order
            # Skip if both old and new values are empty
            unless old_entity[key].to_s.empty? && value.to_s.empty?
              changes << "#{key}: {{ #{old_entity[key]} }} => {{ #{value} }}"
            end
          end
        end
        subreport[:changes_made] = changes.join(' ;;; ')
      end

      Rails.logger.info("Processing #{ENTITY_NAME} '#{subreport[:urlname]}': Success!")
      subreport[:request] = "Z_SUCCESS -- #{req}"


    rescue => e
      error_message = "#{e.class} :: #{e.message}"
      Rails.logger.error("Processing #{ENTITY_NAME}: Unhandled error!: #{error_message}")
      subreport[:request] = req_err
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
    'url error' => 6,
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
