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

  # Fetch non-biblio profile data with last_updated info using SQL joins
  # Only for non-biblio profiles (fast and efficient!)
  profile_only_data = Alchemy::User
    .where("alchemy_users.alchemy_roles NOT LIKE ?", "%biblio%")
    .joins("LEFT JOIN alchemy_users AS updaters ON alchemy_users.updater_id = updaters.id")
    .select("alchemy_users.id, updaters.login AS updater_login, alchemy_users.updated_at")
    .map do |user|
      {
        id: user.id,
        updater_login: user.updater_login || '',
        updated_at: user.updated_at&.strftime('%Y-%m-%d') || ''
      }
    end

  max_length = [page_ids.length, user_ids.length, event_ids.length, topic_ids.length, profile_only_data.length].max

  page_ids.fill("", page_ids.length...max_length)
  user_ids.fill("", user_ids.length...max_length)
  event_ids.fill("", event_ids.length...max_length)
  topic_ids.fill("", topic_ids.length...max_length)
  profile_only_data.fill({id: '', updater_login: '', updated_at: ''}, profile_only_data.length...max_length)

  page_ids.each_with_index do |page_id, index|
    report << {
      page_id: page_id,
      event_id: event_ids[index],
      profile_id: user_ids[index],
      themetag_id: topic_ids[index],
      profile_only_id: profile_only_data[index][:id],
      profile_only_last_updated_by: profile_only_data[index][:updater_login],
      profile_only_last_updated_date: profile_only_data[index][:updated_at],
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
