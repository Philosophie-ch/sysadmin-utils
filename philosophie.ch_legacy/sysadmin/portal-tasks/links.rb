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

    source_page = page_full_path(page)
    target_pages = get_all_links(page)

    target_pages.each do |target_page|

      report << {
        source_page: source_page,
        target_page: target_page,
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
