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

  pages = Alchemy::Page.all
  pages_total = pages.count
  count = 1

  base_folder = 'portal-tasks-reports'
  FileUtils.mkdir_p(base_folder) unless Dir.exist?(base_folder)
  file_name = "#{base_folder}/#{Time.now.strftime('%y%m%d')}_links_report.csv"

  CSV.open(file_name, "wb") do |csv|
    csv << [
      "page_id",
      "page_language_code",
      "page_urlname",
      "element_id",
      "essence_type",
      "link",
      "link_html_tag",
      "status",
      "message",
      "error_trace"
    ]

    pages.each do |page|
      Rails.logger.info("Processing page '#{page.urlname}'")

      begin
        page_id = page.id
        page_language_code = page.language_code
        page_urlname = page.urlname

        link_reports = get_all_links(page)

        link_reports.each do |link_report|
          csv << [
            page_id,
            page_language_code,
            page_urlname,
            link_report[:element_id],
            link_report[:element_type],
            link_report[:link],
            link_report[:tag],
            "success",
            "",
            ""
          ]
        end

        Rails.logger.info("Processed page '#{page.urlname}', #{count} of #{pages_total}")
        count += 1

      rescue => e
        Rails.logger.error("Error processing page '#{page.urlname}': #{e.class}; #{e.message}; BACKTRACE: #{e.backtrace.join(" ::: ")}")
        csv << [
          page_id,
          page_language_code,
          page_urlname,
          "",
          "",
          "",
          "",
          "error",
          "#{e.class}: #{e.message}",
          e.backtrace.join(" ::: ")
        ]
        Rails.logger.info("Processed page '#{page.urlname}', #{count} of #{pages_total}")
        count += 1
      end

    end
  end

end


if ARGV[0].blank?
  log_level = ""

else
  log_level = ARGV[0]
end

main(log_level)
