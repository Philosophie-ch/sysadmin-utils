require 'csv'

require_relative 'lib/utils'
require_relative 'lib/side_column_block_tools'

TABLE_NAME = 'side_column_blocks'
ENTITY_NAME = 'side_column_block'
KEY = :key
KEY_NAME = KEY.to_s
MODEL = SideColumnBlock
MODEL_NAME = "#{MODEL.name}"
FILE_NAME = "#{__FILE__}"

# Content syntax per block_type (for spreadsheet documentation):
#
#   text                  → raw HTML
#                           e.g. <p>Hello <em>world</em></p>
#
#   picture               → asset URL
#                           e.g. intro/my-pic.webp
#
#   embed                 → html
#                         → html || caption
#                         → html || caption || true   (wrap = true)
#
#   download_asset_button → url
#                         → url || button label
#
#   links                 → Section Title || Label: url; Label2: url2
#                           e.g. Related || Page A: /page-a; Page B: /page-b


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

  report = []
  processed_lines = 0

  csv_data = CSV.read(csv_file, col_sep: ',', headers: true, encoding: 'utf-16')
  total_lines = csv_data.size


  ############
  # MAIN
  ############

  csv_data.each do |row|
    Rails.logger.info("Processing row #{processed_lines + 1} of #{total_lines}")

    subreport = {
      _sort: row['_sort'] || '',
      KEY => row[KEY_NAME] || '',
      id: row['id'] || '',
      link: row['link'] || '',
      _request: row['_request'] || '',
      block_type: row['block_type'] || '',
      content: row['content'] || '',
      pages: row['pages'] || '',

      status: '',
      changes_made: '',
      error_message: '',
      error_trace: '',
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
        next
      else
        unless supported_requests.include?(req)
          subreport[:_request] = req_err
          subreport[:status] = "error"
          subreport[:error_message] = "Unsupported request '#{req}'. Skipping"
          subreport[:error_trace] = "#{FILE_NAME}::main::Control::Main"
          next
        end
      end

      id = subreport[:id].strip
      entity_key = subreport[KEY].strip

      if req == 'POST'
        block_type = subreport[:block_type].strip
        if entity_key.blank? || block_type.blank?
          subreport[:_request] = req_err
          subreport[:status] = "error"
          subreport[:error_message] = "Need key and block_type for POST. Skipping"
          subreport[:error_trace] = "#{FILE_NAME}::main::Control::POST"
          next
        end

        unless MODEL::BLOCK_TYPES.include?(block_type)
          subreport[:_request] = req_err
          subreport[:status] = "error"
          subreport[:error_message] = "Invalid block_type '#{block_type}'. Allowed: #{MODEL::BLOCK_TYPES.join(', ')}. Skipping"
          subreport[:error_trace] = "#{FILE_NAME}::main::Control::POST"
          next
        end

        existing = MODEL.find_by(KEY => entity_key)
        if existing
          subreport[:_request] = req_err
          subreport[:status] = "error"
          subreport[:error_message] = "#{MODEL_NAME} with key '#{entity_key}' already exists (id=#{existing.id}). Skipping"
          subreport[:error_trace] = "#{FILE_NAME}::main::Control::POST"
          next
        end
      end

      if ['UPDATE', 'GET', 'DELETE'].include?(req)
        if id.blank? && entity_key.blank?
          subreport[:_request] = req_err
          subreport[:status] = "error"
          subreport[:error_message] = "Need ID or key for '#{req}'. Skipping"
          subreport[:error_trace] = "#{FILE_NAME}::main::Control::UPDATE-GET-DELETE"
          next
        end
      end

      entity_display_name = entity_key.blank? ? id : entity_key

      # Parsing
      Rails.logger.info("Processing #{ENTITY_NAME} '#{entity_display_name}': Parsing")

      raw_content = subreport[:content].to_s

      # Setup — find or build entity
      Rails.logger.info("Processing #{ENTITY_NAME} '#{entity_display_name}': Setup")

      entity = nil
      if ['UPDATE', 'GET', 'DELETE'].include?(req)
        entity_by_id = id.present? ? MODEL.find_by(id: id) : nil
        entity_by_key = entity_key.present? ? MODEL.find_by(KEY => entity_key) : nil

        if entity_by_id.nil? && entity_by_key.nil?
          subreport[:_request] = req_err
          subreport[:status] = "error"
          subreport[:error_message] = "#{MODEL_NAME} with ID '#{id}' or key '#{entity_key}' not found. Skipping"
          subreport[:error_trace] = "#{FILE_NAME}::main::Setup"
          next
        end

        if entity_by_id && entity_by_key && entity_by_id.id != entity_by_key.id
          subreport[:_request] = req_err
          subreport[:status] = "error"
          subreport[:error_message] = "ID '#{id}' and key '#{entity_key}' resolve to different records. Skipping"
          subreport[:error_trace] = "#{FILE_NAME}::main::Setup"
          next
        end

        entity = entity_by_id || entity_by_key
      end


      # Snapshot old state for change detection
      if ['UPDATE', 'GET'].include?(req)
        old_entity = {
          _sort: subreport[:_sort],
          KEY => entity.key,
          id: entity.id.to_s,
          link: get_block_admin_link(entity),
          _request: subreport[:_request],
          block_type: entity.block_type,
          content: serialize_content(entity),
          pages: get_block_pages_display(entity),

          status: '',
          changes_made: '',
          error_message: '',
          error_trace: '',
        }
      end


      # Execution
      Rails.logger.info("Processing #{ENTITY_NAME} '#{entity_display_name}': Execution")

      if req == 'DELETE'
        entity.destroy!

        if MODEL.find_by(id: entity.id).present?
          subreport[:_request] = req_err
          subreport[:status] = "error"
          subreport[:error_message] = "#{MODEL_NAME} was not deleted for an unknown reason. Skipping"
          subreport[:error_trace] = "#{FILE_NAME}::main::Execution::DELETE"
          next
        else
          subreport[:id] = ''
          subreport[KEY] = ''
          subreport[:status] = "success"
          subreport[:changes_made] = "#{MODEL_NAME.upcase} WAS DELETED"
          next
        end
      end

      if req == 'POST'
        block_type = subreport[:block_type].strip
        content_hash = parse_content(block_type, raw_content)

        entity = MODEL.create!(
          key: entity_key,
          block_type: block_type,
          content: content_hash,
        )
      end

      if req == 'UPDATE'
        if raw_content.present?
          bt = entity.block_type
          content_hash = parse_content(bt, raw_content)
          entity.content = content_hash
        end

        entity.key = entity_key if entity_key.present?
        entity.save!
      end


      ############
      # REPORT
      ############

      Rails.logger.info("Processing #{ENTITY_NAME} '#{entity_display_name}': Updating report")

      updated = MODEL.find(entity.id)

      subreport.merge!({
        KEY => updated.key,
        id: updated.id.to_s,
        link: get_block_admin_link(updated),
        block_type: updated.block_type,
        content: serialize_content(updated),
        pages: get_block_pages_display(updated),
      })

      subreport[:status] = 'success'
      subreport[:_request] = "Z_SUCCESS -- #{req}"


      ############
      # CHANGES MADE
      ############

      if ['UPDATE', 'GET'].include?(req)
        changes = []
        subreport.each do |field, value|
          next if [:changes_made, :status, :error_message, :error_trace, :_request, :original_order, :result_order].include?(field)
          old_val = old_entity[field]
          next if old_val.to_s == value.to_s
          unless old_val.to_s.empty? && value.to_s.empty?
            changes << "#{field}: {{ #{old_val} }} => {{ #{value} }}"
          end
        end
        subreport[:changes_made] = changes.join(' ;;; ')
      end

      Rails.logger.info("Processing #{ENTITY_NAME} '#{entity_display_name}': Success!")


    rescue => e
      error_message = "#{e.class} :: #{e.message}"
      Rails.logger.error("Processing #{ENTITY_NAME}: Unhandled error!: #{error_message}")
      subreport[:_request] = "Z_ERROR -- #{subreport[:_request]}"
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
