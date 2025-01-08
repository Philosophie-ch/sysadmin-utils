require_relative 'lib/utils'


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

  page_ids = Alchemy::Page.pluck(:id)
  user_ids = Alchemy::User.pluck(:id)
  event_ids = Event.pluck(:id)
  topic_ids = Topic.pluck(:id)

  max_length = [page_ids.length, user_ids.length, event_ids.length, topic_ids.length].max

  page_ids.fill("", page_ids.length...max_length)
  user_ids.fill("", user_ids.length...max_length)
  event_ids.fill("", event_ids.length...max_length)
  topic_ids.fill("", topic_ids.length...max_length)

  page_ids.each_with_index do |page_id, index|
    report << {
      page_id: page_id,
      event_id: event_ids[index],
      profile_id: user_ids[index],
      themetag_id: topic_ids[index],
  }
  end

  ############
  # REPORT
  ############

  generate_csv_report(report, "news")

end


if ARGV[0].blank?
  log_level = ""

else
  log_level = ARGV[0]
end

main(log_level)
