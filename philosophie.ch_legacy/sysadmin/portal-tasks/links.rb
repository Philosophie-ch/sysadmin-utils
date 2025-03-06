require_relative 'lib/utils'
require_relative 'lib/link_tools'


def main(log_level = 'info')

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

  ############
  # MAIN
  ############

  Alchemy::Page.all.each do |page|
    Rails.logger.info("Processing page '#{page.urlname}'")

    page_id = page.id
    page_language_code = page.language_code
    page_urlname = page.urlname
    page_full_path = page_full_path(page)

    link_reports = get_all_links(page)

    link_reports.each do |link_report|

      report << {
        page_id: page_id,
        page_language_code: page_language_code,
        page_urlname: page_urlname,
        page_full_path: page_full_path,

        link: link_report[:link],
        link_status: link_report[:status],
        link_status_message: link_report[:message]
      }

    end

  end

  ############
  # REPORT
  ############

  generate_csv_report(report, "links")

end


if ARGV[0].blank?
  log_level = ""

else
  log_level = ARGV[0]
end

main(log_level)
