require 'csv'

require_relative 'lib/utils'

TABLE_NAME = 'translation_groups'
ENTITY_NAME = 'translation_group'
KEY = :key
KEY_NAME = KEY.to_s
MODEL = PageTranslationGroup
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

      page_count: '',
    }

    language_codes.each do |code|
      subreport[:"page_#{code}"] = ''
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

      # Read old state
      if ['UPDATE', 'GET'].include?(req)
        old_pages = entity.pages.includes(:page_languages).order(:urlname)
        old_entity = {
          _todo: subreport[:_todo],
          _sort: subreport[:_sort],
          request: subreport[:request],
          id: entity.id.to_s,
          KEY => entity.key,
          page_count: old_pages.count.to_s,
        }
        language_codes.each do |code|
          page_for_lang = old_pages.detect { |p| p.page_languages.any? { |pl| pl.language_code == code } }
          old_entity[:"page_#{code}"] = page_for_lang ? "#{page_for_lang.language_code}/#{page_for_lang.urlname}" : ''
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
        entity = MODEL.create!(KEY => entity_key)
      end

      if req == 'UPDATE'
        entity.update!(KEY => entity_key) if entity_key.present? && entity_key != entity.key
      end

      # Page associations are read-only here; manage them via pages.csv translation_group column


      # Report
      Rails.logger.info("Processing #{ENTITY_NAME} '#{entity_key}': Reporting")

      updated = MODEL.find_by(id: entity.id)
      updated_pages = updated.pages.includes(:page_languages).order(:urlname)

      subreport.merge!({
        id: updated.id.to_s,
        KEY => updated.key,
        page_count: updated_pages.count.to_s,
      })
      language_codes.each do |code|
        page_for_lang = updated_pages.detect { |p| p.page_languages.any? { |pl| pl.language_code == code } }
        subreport[:"page_#{code}"] = page_for_lang ? "#{page_for_lang.language_code}/#{page_for_lang.urlname}" : ''
      end

      subreport[:status] = subreport[:error_message].present? ? 'partial success' : 'success'
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
    'partial success' => 2,
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
