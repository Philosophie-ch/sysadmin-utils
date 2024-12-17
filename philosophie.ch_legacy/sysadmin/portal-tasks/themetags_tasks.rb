require 'csv'

require_relative 'lib/utils'
require_relative 'lib/themetags_tools'


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
      name: row['name'] || '',
      group: row['group'] || '',
      interest_type: row['interest_type'] || '',
      page_language_code: row['page_language_code'] || '',
      page_urlname: row['page_urlname'] || '',
      url: row['url'] || '',

      status: '',
      changes_made: '',
      error_message: '',
      error_trace: '',
    }


    begin

      # Control
      Rails.logger.info("Processing themetag: Control")
      supported_requests = ['POST', 'UPDATE', 'GET', 'DELETE', 'AD HOC']

      req = subreport[:request].strip

      if req.blank?
        subreport[:status] = ""
        next
      else
        unless supported_requests.include?(req)
          subreport[:request] = "ERROR"
          subreport[:status] = "error"
          subreport[:error_message] = "Unsupported request '#{req}'. Skipping"
          subreport[:error_trace] = "themetags_tasks.rb::main::Control::Main"
        end
      end

      id = subreport[:id].strip
      name = subreport[:name].strip
      group = subreport[:group].strip
      interest_type = subreport[:interest_type].strip

      if req == 'POST'
        if name.blank? || group.blank? || interest_type.blank?
          subreport[:request] += " ERROR"
          subreport[:status] = "error"
          subreport[:error_message] = "Need name, group, and interest_type for POST. Skipping"
          subreport[:error_trace] = "themetags_tasks.rb::main::Control::POST"
          next
        end
        retreived_themetags = Topic.where(name: name, group: group, interest_type: interest_type)

        if retreived_themetags.present?
          subreport[:request] += " ERROR"
          subreport[:status] = "error"
          subreport[:error_message] = "Themetag with name '#{name}', group '#{group}', and interest_type '#{interest_type}' already exists. Skipping"
          subreport[:error_trace] = "themetags_tasks.rb::main::Control::POST"
          next
        end
      end

      if ['UPDATE', 'GET', 'DELETE', 'AD HOC'].include?(req)
        if id.blank?
          subreport[:request] += " ERROR"
          subreport[:status] = "error"
          subreport[:error_message] = "Need ID for '#{req}'. Skipping"
          subreport[:error_trace] = "themetags_tasks.rb::main::Control::UPDATE-GET-DELETE"
          next
        end
      end

      themetag_identifier = name.blank? ? id : name

      # Parsing
      Rails.logger.info("Processing themetag '#{themetag_identifier}': Parsing")

      page_language_code = subreport[:page_language_code].strip

      unless SUPPORTED_LANGUAGE_CODES.include?(page_language_code)
        subreport[:request] += " ERROR"
        subreport[:status] = "error"
        subreport[:error_message] = "Unsupported language code '#{page_language_code}'. Skipping. Supported language codes are: #{SUPPORTED_LANGUAGE_CODES.join(', ')}"
        subreport[:error_trace] = "themetags_tasks.rb::main::Parsing"
        next
      end

      page_urlname = subreport[:page_urlname].strip

      page = Alchemy::Page.find_by(urlname: page_urlname, language_code: page_language_code)  # this combination is unique

      if not page_language_code.blank? and not page_urlname.blank? and page.nil?
        subreport[:request] += " ERROR"
        subreport[:status] = "error"
        subreport[:error_message] = "Page with URL name '#{page_urlname}' and language code '#{page_language_code}' not found. Skipping"
        subreport[:error_trace] = "themetags_tasks.rb::main::Parsing"
        next
      end

      url = subreport[:url].strip

      # Setup
      Rails.logger.info("Processing themetag '#{themetag_identifier}': Setup")

      if ['POST', 'UPDATE', 'AD HOC'].include?(req)

        validation_flag = true
        validation_error_message = nil

        unless SUPPORTED_GROUPS.include?(group)
          validation_flag = false
          validation_error_message += " --- Unsupported group '#{group}'"
        end

        unless SUPPORTED_INTEREST_TYPES.include?(interest_type)
          validation_flag = false
          validation_error_message += " --- Unsupported interest interest_type '#{interest_type}'"
        end

        if validation_flag == false
          subreport[:request] += " ERROR"
          subreport[:status] = "error"
          subreport[:error_message] = "Validation failed: #{validation_error_message}. Skipping"
          subreport[:error_trace] = "themetags_tasks.rb::main::Execution::POST"
          next
        end

      end

      if ['UPDATE', 'GET', 'DELETE', 'AD HOC'].include?(req)
        themetag = Topic.find_by(id: id)

        if themetag.nil?
          Rails.logger.error("Themetag with ID '#{id}' not found. Skipping")
          subreport[:request] += " ERROR"
          subreport[:status] = "error"
          subreport[:error_message] = "Themetag with ID '#{id}' not found. Skipping"
          subreport[:error_trace] = "themetags_tasks.rb::main::Setup::UPDATE-GET-DELETE"
          next
        end
      end


      # Execution
      Rails.logger.info("Processing themetag '#{themetag_identifier}': Execution")

      if req == 'DELETE'
        themetag.delete

        themetag_present = Topic.find_by(id: id).present?

        if themetag_present
          subreport[:request] += " ERROR"
          subreport[:status] = "error"
          subreport[:error_message] = "Themetag with ID '#{id}' was not deleted for an unknown reason. Skipping"
          subreport[:error_trace] = "themetags_tasks.rb::main::Execution::DELETE"
          next
        else
          subreport[:id] = ''
          subreport[:slug] = ''
          subreport[:link] = ''
          subreport[:status] = "success"
          subreport[:changes_made] = "THEMETAG WAS DELETED IN THE SERVER"
          next
        end
      end

      if req == "POST"

        themetag = Topic.new(
          name: name,
          group: group,
          interest_type: interest_type,
        )

        if page.present?
          themetag.page_id = page.id
        end

        themetag.save!
      end

      if ['UPDATE', 'GET'].include?(req)
        old_themetag = {
          _sort: subreport[:_sort],
          id: subreport[:id],
          name: name,
          group: group,
          interest_type: interest_type,
          page_language_code: page_language_code,
          page_urlname: page_urlname,
          url: url,

          status: '',
          changes_made: '',
          error_message: '',
          error_trace: '',
        }
      end

      if req == "UPDATE"
        themetag.name = name
        themetag.group = group
        themetag.interest_type = interest_type

        if page.present?
          themetag.page_id = page.id
          new_page = Alchemy::Page.find_by(id: themetag.page_id)
          subreport[:page_language_code] = new_page.language_code
          subreport[:page_urlname] = new_page.urlname
        else
          themetag.page_id = nil
          subreport[:page_language_code] = ""
          subreport[:page_urlname] = ""
        end

        themetag.save!
      end

      # Update report
      Rails.logger.info("Processing themetag '#{themetag_identifier}': Updating report")


      #######
      # AD HOC
      # Special request not to be commited
      #######

      if req == 'AD HOC'

      end


      ############
      # REPORT
      ############
      updated_themetag = Topic.find_by(id: themetag.id)
      queried_page = Alchemy::Page.find_by(id: themetag.page_id)

      if queried_page.present?
        queried_page_language_code = queried_page.language_code
        queried_page_urlname = queried_page.urlname
      else
        queried_page_language_code = ""
        queried_page_urlname = ""
      end

      new_url = get_themetag_url(updated_themetag)

      subreport.merge!({
        id: "#{updated_themetag.id}".strip,
        name: updated_themetag.name,
        group: updated_themetag.group,
        interest_type: updated_themetag.interest_type,
        page_language_code: queried_page_language_code,
        page_urlname: queried_page_urlname,
        url: new_url,
      })

      subreport[:status] = 'success'


      ############
      # COMPLEX TASKS ON UPDATE AND POST
      ############

      if req == "UPDATE" || req == "POST"
        #Rails.logger.info("Processing themetag '#{themetag_identifier}': Complex tasks")

        ## If some complext task is added and it fails, the status should be "partial error" and the request "... PARTIAL"

        ## Saving
        #themetag.save!
        #themetag.publish!
        #Rails.logger.info("Processing themetag '#{themetag_identifier}': Complex tasks: Success!")
      end


      ############
      # CHANGES MADE
      ############

      if ['UPDATE', 'GET', 'AD HOC'].include?(req)
        changes = []
        subreport.each do |key, value|
          if old_themetag[key] != value && key != :changes_made && key != :status && key != :error_message && key != :error_trace && key != :request
            # Skip if both old and new values are empty
            unless old_themetag[key].to_s.empty? && value.to_s.empty?
              changes << "#{key}: {{ #{old_themetag[key]} }} => {{ #{value} }}"
            end
          end
        end
        subreport[:changes_made] = changes.join(' ;;; ')
      end

      Rails.logger.info("Processing themetag '#{subreport[:urlname]}': Success!")
      subreport[:request] = "#{req} SUCCESS"


    rescue => e
      error_message = "#{e.class} :: #{e.message}"
      Rails.logger.error("Processing themetag: Unhandled error!: #{error_message}")
      subreport[:request] += " ERROR"
      subreport[:status] = 'unhandled error'
      subreport[:error_message] = error_message
      subreport[:error_trace] = e.backtrace.join(" ::: ")

    ensure
      report << subreport
      Rails.logger.info("Processing themetag: Done!. Processed lines so far: #{processed_lines + 1} of #{total_lines}")
      processed_lines += 1
    end

  end


  ############
  # REPORT
  ############

  generate_csv_report(report, "themetags")

end



if ARGV[0].blank?
  log_level = ""

else
  log_level = ARGV[0]
end

main("portal-tasks/themetags_tasks.csv", log_level)
