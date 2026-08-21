require 'csv'

require_relative 'lib/utils'

TABLE_NAME = 'site_sections'
ENTITY_NAME = 'site_section'
KEY = :key
KEY_NAME = KEY.to_s
MODEL = SiteSection
MODEL_NAME = "#{MODEL.name}"
FILE_NAME = "#{__FILE__}"


def read_csv_file(file_path)
  bytes = File.binread(file_path, 3)
  content = if bytes[0..1].b == "\xFF\xFE".b || bytes[0..1].b == "\xFE\xFF".b
    File.read(file_path, encoding: 'utf-16')
  elsif bytes[0..2].b == "\xEF\xBB\xBF".b
    File.read(file_path, encoding: 'bom|utf-8')
  else
    File.binread(file_path).force_encoding('utf-8').scrub { |b| b.encode('utf-8', 'iso-8859-1') }
  end
  CSV.parse(content, col_sep: ',', headers: true)
end


def main(csv_file, log_level = 'info')

  ############
  # SETUP
  ############

  ActiveRecord::Base.logger.level = Logger::WARN
  ActiveSupport::Deprecation.behavior = :silence
  ActiveSupport::Deprecation.silenced = true
  ActiveSupport::Deprecation.debug = false

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

  language_codes = Language.public_languages.ordered.pluck(:code)

  report = []
  processed_lines = 0

  csv_data = read_csv_file(csv_file)
  total_lines = csv_data.size


  ############
  # MAIN
  ############

  csv_data.each do |row|
    Rails.logger.info("Processing row #{processed_lines + 1} of #{total_lines}")

    subreport = {
      _todo: row['_todo'] || '',
      _sort: row['_sort'] || '',

      request: row['request'] || '',
      id: row['id'] || '',
      KEY => row[KEY_NAME] || '',

      context: row['context'] || '',
      parent: row['parent'] || '',
      level: '',
      position: row['position'] || '',
      translation_group: row['translation_group'] || '',
      url_override: row['url_override'] || '',
      hidden: row['hidden'] || '',
    }

    language_codes.each do |code|
      subreport[:"title_#{code}"] = row["title_#{code}"] || ''
    end
    language_codes.each do |code|
      subreport[:"description_#{code}"] = row["description_#{code}"] || ''
    end

    subreport.merge!({
      status: '',
      changes_made: '',
      error_message: '',
      error_trace: '',
      original_order: '',
      result_order: '',
    })


    begin

      # Control
      Rails.logger.info("Processing #{ENTITY_NAME}: Control")
      supported_requests = ['POST', 'UPDATE', 'GET', 'DELETE']

      req = subreport[:request].strip.upcase
      req_err = "Z_ERROR -- #{req}"

      if req.blank?
        subreport[:status] = ""
        next
      else
        unless supported_requests.include?(req)
          subreport[:request] = req_err
          subreport[:status] = "error"
          subreport[:error_message] = "Unsupported request '#{req}'. Skipping"
          subreport[:error_trace] = "#{FILE_NAME}::main::Control"
          next
        end
      end

      id = subreport[:id].strip
      entity_key = subreport[KEY].strip

      if req == 'POST'
        if entity_key.blank?
          subreport[:request] = req_err
          subreport[:status] = "error"
          subreport[:error_message] = "Need key for POST. Skipping"
          subreport[:error_trace] = "#{FILE_NAME}::main::Control::POST"
          next
        end
        if MODEL.exists?(KEY => entity_key)
          subreport[:request] = req_err
          subreport[:status] = "error"
          subreport[:error_message] = "#{MODEL_NAME} with key '#{entity_key}' already exists. Skipping"
          subreport[:error_trace] = "#{FILE_NAME}::main::Control::POST"
          next
        end
      end

      if ['UPDATE', 'GET', 'DELETE'].include?(req)
        if id.blank? && entity_key.blank?
          subreport[:request] = req_err
          subreport[:status] = "error"
          subreport[:error_message] = "Need ID or key for '#{req}'. Skipping"
          subreport[:error_trace] = "#{FILE_NAME}::main::Control::UPDATE-GET-DELETE"
          next
        end
      end

      # Parsing
      Rails.logger.info("Processing #{ENTITY_NAME} '#{entity_key}': Parsing")

      context = subreport[:context].strip
      parent = subreport[:parent].strip
      parent = nil if parent.blank?
      position = subreport[:position].strip
      position = position.blank? ? 0 : position.to_i
      ptg_key = subreport[:translation_group].strip
      ptg_key = nil if ptg_key.blank?
      url_override = subreport[:url_override].strip
      url_override = nil if url_override.blank?
      hidden_raw = subreport[:hidden].strip.downcase
      hidden = ['true', 'yes', '1'].include?(hidden_raw)

      # Resolve parent
      if parent
        parent_key_str = parent
        parent = MODEL.find_by(KEY => parent)
        if parent.nil?
          subreport[:request] = req_err
          subreport[:status] = "error"
          subreport[:error_message] = "Parent with key '#{parent_key_str}' not found. Skipping"
          subreport[:error_trace] = "#{FILE_NAME}::main::Parsing"
          next
        end
      end

      # Setup
      Rails.logger.info("Processing #{ENTITY_NAME} '#{entity_key}': Setup")

      entity = nil
      if ['UPDATE', 'GET', 'DELETE'].include?(req)
        entity = id.present? ? MODEL.find_by(id: id) : MODEL.find_by(KEY => entity_key)

        if entity.nil?
          subreport[:request] = req_err
          subreport[:status] = "error"
          subreport[:error_message] = "#{MODEL_NAME} with ID '#{id}' or key '#{entity_key}' not found. Skipping"
          subreport[:error_trace] = "#{FILE_NAME}::main::Setup"
          next
        end
      end

      # Read old state for GET/UPDATE
      if ['UPDATE', 'GET'].include?(req)
        old_entity = {
          _todo: subreport[:_todo],
          _sort: subreport[:_sort],
          request: subreport[:request],
          id: entity.id.to_s,
          KEY => entity.key,
          context: entity.context,
          parent: entity.parent&.key || '',
          level: (entity.depth + 1).to_s,
          position: entity.position.to_s,
          translation_group: entity.page_translation_group_key || '',
          url_override: entity.url_override || '',
          hidden: entity.hidden? ? 'TRUE' : 'FALSE',
        }
        language_codes.each do |code|
          old_entity[:"title_#{code}"] = entity.title_for(code) || ''
        end
        language_codes.each do |code|
          trans = entity.translations.find_by(language_code: code)
          old_entity[:"description_#{code}"] = trans&.try(:description) || ''
        end
        old_entity.merge!({
          status: '',
          changes_made: '',
          error_message: '',
          error_trace: '',
          original_order: '',
          result_order: '',
        })
      end


      # Execution
      Rails.logger.info("Processing #{ENTITY_NAME} '#{entity_key}': Execution")

      if req == 'DELETE'
        entity.destroy!
        subreport[:id] = ''
        subreport[:status] = "success"
        subreport[:changes_made] = "#{MODEL_NAME.upcase} WAS DELETED"
        subreport[:request] = "Z_SUCCESS -- #{req}"
        next
      end

      if req == 'POST'
        entity = MODEL.new(KEY => entity_key)
      end

      if ['POST', 'UPDATE'].include?(req)
        if req == 'UPDATE' && entity_key.present? && entity_key != entity.key
          old_key = entity.key
          # Collect referencing IDs, nullify, rename key, restore references
          page_ids = Alchemy::Page.where(site_section_key: old_key).pluck(:id)
          pub_ids = defined?(Publication) && Publication.column_names.include?('site_section_key') ? Publication.where(site_section_key: old_key).pluck(:id) : []
          jour_ids = defined?(Journal) && Journal.column_names.include?('site_section_key') ? Journal.where(site_section_key: old_key).pluck(:id) : []
          publ_ids = defined?(Publisher) && Publisher.column_names.include?('site_section_key') ? Publisher.where(site_section_key: old_key).pluck(:id) : []

          Alchemy::Page.where(id: page_ids).update_all(site_section_key: nil)
          Publication.where(id: pub_ids).update_all(site_section_key: nil) if pub_ids.any?
          Journal.where(id: jour_ids).update_all(site_section_key: nil) if jour_ids.any?
          Publisher.where(id: publ_ids).update_all(site_section_key: nil) if publ_ids.any?

          entity.update_column(:key, entity_key)

          Alchemy::Page.where(id: page_ids).update_all(site_section_key: entity_key) if page_ids.any?
          Publication.where(id: pub_ids).update_all(site_section_key: entity_key) if pub_ids.any?
          Journal.where(id: jour_ids).update_all(site_section_key: entity_key) if jour_ids.any?
          Publisher.where(id: publ_ids).update_all(site_section_key: entity_key) if publ_ids.any?
        end
        entity.context = context if context.present?
        entity.parent = parent
        entity.position = position
        entity.page_translation_group_key = ptg_key
        entity.url_override = url_override
        entity.hidden = hidden

        entity.save!

        # Handle translations
        language_codes.each do |code|
          title_value = subreport[:"title_#{code}"].to_s.strip
          description_value = subreport[:"description_#{code}"].to_s.strip
          existing = entity.translations.find_by(language_code: code)

          if title_value.present?
            attrs = { title: title_value }
            attrs[:description] = description_value.presence if existing&.respond_to?(:description)
            if existing
              existing.update!(attrs)
            else
              create_attrs = { site_section: entity, language_code: code, title: title_value }
              create_attrs[:description] = description_value.presence if SiteSectionTranslation.column_names.include?('description')
              SiteSectionTranslation.create!(create_attrs)
            end
          elsif existing && title_value.blank?
            existing.destroy!
          end
        end
      end


      # Report
      Rails.logger.info("Processing #{ENTITY_NAME} '#{entity_key}': Reporting")

      updated = MODEL.find_by(id: entity.id)

      subreport.merge!({
        id: updated.id.to_s,
        KEY => updated.key,
        context: updated.context,
        parent: updated.parent&.key || '',
        level: (updated.depth + 1).to_s,
        position: updated.position.to_s,
        translation_group: updated.page_translation_group_key || '',
        url_override: updated.url_override || '',
        hidden: updated.hidden? ? 'TRUE' : 'FALSE',
      })
      language_codes.each do |code|
        subreport[:"title_#{code}"] = updated.title_for(code) || ''
      end
      language_codes.each do |code|
        trans = updated.translations.find_by(language_code: code)
        subreport[:"description_#{code}"] = trans&.try(:description) || ''
      end

      subreport[:status] = 'success'
      subreport[:request] = "Z_SUCCESS -- #{req}"


      # Changes made
      if ['UPDATE', 'GET'].include?(req)
        changes = []
        subreport.each do |key, value|
          next if [:changes_made, :status, :error_message, :error_trace, :request, :result_order, :original_order].include?(key)
          if old_entity[key] != value
            unless old_entity[key].to_s.empty? && value.to_s.empty?
              changes << "#{key}: {{ #{old_entity[key]} }} => {{ #{value} }}"
            end
          end
        end
        subreport[:changes_made] = changes.join(' ;;; ')
      end


    rescue => e
      error_message = "#{e.class} :: #{e.message}"
      Rails.logger.error("Processing #{ENTITY_NAME}: Unhandled error!: #{error_message}")
      subreport[:request] = "Z_ERROR -- #{req}"
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
