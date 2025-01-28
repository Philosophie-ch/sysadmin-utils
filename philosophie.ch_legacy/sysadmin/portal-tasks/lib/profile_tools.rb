require 'securerandom'
require_relative 'utils'


def generate_randomized_password
  SecureRandom.uuid.gsub('-', '')[0, 16]
end


def generate_hashed_email_address
  hash = SecureRandom.uuid.gsub('-', '')[-16, 16]
  "info-#{hash}@philosophie.ch"
end


def get_assigned_articles(user)
  all_articles = Alchemy::Page.where(page_layout: 'article')
  all_intro_elements = all_articles.map do |article|
    article.elements.where(name: 'intro').first
  end; nil
  creator_essences = all_intro_elements.map do |intro_element|
    intro_element&.content_by_name(:creator)&.essence
  end; nil
  creator_essences.compact!
  user_creator_essences = creator_essences.select do |creator_essence|
    creator_essence.alchemy_users.map(&:login).include?(user.login)
  end; nil

  user_creator_essences.map(&:page)
end


def get_page_link(page)
    retrieved_slug = Alchemy::Engine.routes.url_helpers.show_page_path({
      locale: !page.language.default ? page.language_code : nil, urlname: page.urlname
    })
    "https://www.philosophie.ch#{retrieved_slug}"
end


def update_links(new_login, old_login)
  ActiveSupport::Deprecation.behavior = [:silence]  # silence useless deprecation warnings
  Rails.logger.info("Updating links from '#{old_login}' to '#{new_login}'...")
  update_links_report = {
    status: "not started",
    old_login: old_login,
    new_login: new_login,
    error_message: "",
    error_trace: "",
    changed_essences: [],
    failed_essences: []
  }

  begin
    if old_login.blank? || new_login.blank?
      update_links_report[:status] = "error"
      update_links_report[:error_message] = "Old login or new login is blank. Skipping update_links."
      return update_links_report
    end

    if old_login == new_login
      update_links_report[:status] = "success"
      update_links_report[:error_message] = "Old login is the same as new login, no need to update links."
      return update_links_report
    end

    Rails.logger.info("\t...setup...")
    old_link_double_quotes = sprintf('/profil/%s"', old_login)
    new_link_double_quotes = sprintf('/profil/%s"', new_login)
    old_link_single_quotes = sprintf("/profil/%s'", old_login)
    new_link_single_quotes = sprintf("/profil/%s'", new_login)

    all_essences_text = Alchemy::EssenceText.all
    all_essences_richtext = Alchemy::EssenceRichtext.all

    Rails.logger.info("\t...retrieved essences, now processing...")
    # Text
    all_essences_text.each do |essence|
      begin
        body = essence.body.to_s

        if body.include?(old_link_double_quotes) || body.include?(old_link_single_quotes)

          if body.include?(old_link_double_quotes)
          new_body = body.gsub(old_link_double_quotes, new_link_double_quotes)
          elsif body.include?(old_link_single_quotes)
          new_body = body.gsub(old_link_single_quotes, new_link_single_quotes)
          end

          essence.body = new_body
          essence.save!
          essence.page.save!
          essence.page.publish!
          changed_essence = {
            e_id: essence.id,
            p_id: essence&.page&.id,
            p_urlname: essence&.page&.urlname
          }
          update_links_report[:changed_essences] << changed_essence
        end
      rescue => e
        failed_essence = {
          essence_id: essence.id,
          error_message: e.message,
          error_trace: e.backtrace.first
        }
        update_links_report[:failed_essences] << failed_essence
      end
    end
    # Richtext
    all_essences_richtext.each do |essence|
      begin
        body = essence.body.to_s

        if body.include?(old_link_double_quotes) || body.include?(old_link_single_quotes)

          if body.include?(old_link_double_quotes)
            new_body = body.gsub(old_link_double_quotes, new_link_double_quotes)
          elsif body.include?(old_link_single_quotes)
            new_body = body.gsub(old_link_single_quotes, new_link_single_quotes)
          end

          essence.body = new_body
          essence.save!
          if essence.page.nil?
            changed_essence = {
              e_id: essence.id,
              p_id: nil,
              p_urlname: "essence is not attached to a page!",
          }
          else
            essence.page.save!
            essence.page.publish!
            changed_essence = {
              e_id: essence.id,
              p_id: essence&.page&.id,
              p_urlname: essence&.page&.urlname
            }
          end
          update_links_report[:changed_essences] << changed_essence
        end
      rescue => e
        failed_essence = {
          essence_id: essence.id,
          error_message: e.message,
          error_trace: e.backtrace.first
        }
        update_links_report[:failed_essences] << failed_essence
      end
    end

    # Update report
    if update_links_report[:failed_essences].empty?
      update_links_report[:status] = "success"
      Rails.logger.info("\t...success!")
    else
      update_links_report[:status] = "partial success"
      Rails.logger.info("\t...partial success!")
    end

    return update_links_report

  rescue => e
    update_links_report[:status] = "unhandled error"
    update_links_report[:error_message] = e.message
    update_links_report[:error_trace] = e.backtrace.first
    return update_links_report
  end
end


# Server asset
def get_profile_picture_asset_name(user)
  url = user&.profile&.profile_picture_url

  if url.nil?
    return ''
  end

  unprocessed_url = unprocess_asset_urls([url])

  return unprocessed_url

end

def set_profile_picture_asset(user, new_asset_name)
  report = {
    status: 'not started',
    error_message: '',
    error_trace: ''
  }

  begin
    processed_url_array = process_asset_urls(new_asset_name)

    if processed_url_array.empty? || processed_url_array.first == ''
      user.profile.profile_picture_url = ''
      user.profile.save!
      user.save!
      report[:status] = 'success'
      return report
    end

    asset_url_check = check_asset_urls_resolve(processed_url_array)

    if asset_url_check[:status] != 'success'
      report[:status] = 'error'
      report[:error_message] = asset_url_check[:error_message]
      report[:error_trace] = asset_url_check[:error_trace]
      return report
    end

    user.profile.profile_picture_url = processed_url_array.first
    user.profile.save!
    user.save!

    report[:status] = 'success'
    return report

  rescue => e
    error_message = "Error setting profile picture for '#{user.login}': #{e.class} :: #{e.message}"
    Rails.logger.error(error_message)
    report[:status] = 'error'
    report[:error_message] = error_message
    report[:error_trace] = e.backtrace.join(" ::: ")
    return report
  end

end


# Portal asset
def get_profile_picture_file_name(user)
  profile_picture = user.profile&.avatar&.attached? ? user&.profile&.avatar&.filename.to_s : ''
  return profile_picture
end


def get_last_updater(user)
  last_updater_id = user.updater_id
  last_updater = Alchemy::User.find_by(id: last_updater_id)
  return last_updater.blank? ? '' : last_updater.login
end

def get_last_updated_date(user)
  # In YYYY-MM-DD format
  return user.updated_at.strftime('%Y-%m-%d')
end


# Deprecated
def _set_profile_picture(user, new_filename)

  set_profile_picture_report = {
    new_filename: new_filename,
    status: "not started",
    error_message: "",
    error_trace: "",
  }
  begin
    Rails.logger.info("Updating profile picture for '#{user.login}'...")

    if new_filename.blank?
      Rails.logger.info("\tnew filename is blank. Skipping...")
      set_profile_picture_report[:status] = "success"
      return set_profile_picture_report
    end

    old_filename = get_profile_picture_file_name(user)

    if old_filename == new_filename
      Rails.logger.info("\tnew filename is the same as the old one. Skipping...")
      set_profile_picture_report[:status] = "success"
      return set_profile_picture_report
    end

    picture = Alchemy::Picture.find_by(image_file_name: new_filename)

    if picture.nil?
      Rails.logger.error("Picture with image_file_name '#{new_filename}' not found. Skipping...")
      set_profile_picture_report[:status] = 'error'
      set_profile_picture_report[:error_message] = "Picture with image_file_name '#{new_filename}' not found"
      set_profile_picture_report[:error_trace] = "profiles.rb::set_profile_picture"
      return set_profile_picture_report
    end

    Rails.logger.info("\t #{new_filename} found, attaching to user...")
    user.profile.avatar.attach(
      io: File.open(picture.image_file.path),
      filename: picture.image_file_name,
      content_type: picture.image_file.mime_type
    )

    user.profile.avatar.save!
    user.profile.save!
    user.save!
    Rails.logger.info("\t...success!")
    return set_profile_picture_report

  rescue => e
    set_profile_picture_report[:status] = "unhandled error"
    set_profile_picture_report[:error_message] = e.message
    set_profile_picture_report[:error_trace] = e.backtrace.first
    return set_profile_picture_report
  end
end


# Institutional affiliation tools

INSTITUTIONAL_AFFILIATION_MAP = {
  "UniBS" => "UniBS",
  "UniBE" => "UniBE",
  "UniFR" => "UniFR",
  "UniGE" => "UniGE",
  "UniL" => "UniL",
  "EPFL" => "EPFL",
  "USI" => "USI",
  "UniLU" => "UniLU",
  "UniNE" => "UniNE",
  "UniSG" => "UniSG",
  "UZH" => "UZH",
  "ETHZ" => "ETHZ",
  "FHNW" => "FHNW",
  "HEP_Fribourg" => "HEP Fribourg / PH Freiburg",
  "HEP_Valais" => "HEP Valais / PH Wallis",
  "HEP_Vaud" => "HEP Vaud",
  "HEP_BeJuNe" => "HEP BeJuNe",
  "PH_Bern" => "PH Bern",
  "PH_Luzern" => "PH Luzern",
  "PH_Schaffhausen" => "PH Schaffhausen",
  "PH_St_Gallen" => "PH St. Gallen",
  "PH_Thurgau" => "PH Thurgau",
  "PH_Zug" => "PH Zug",
  "PH_Zuerich" => "PH Zürich",
}

class InstitutionalAffiliationNotFoundError < StandardError; end

def institutional_affiliation_to_string(institutional_affiliation)

  unless INSTITUTIONAL_AFFILIATION_MAP.key.include?(institutional_affiliation)
    raise InstitutionalAffiliationNotFoundError, "Institutional affiliation '#{institutional_affiliation}' not found."
  end

  INSTITUTIONAL_AFFILIATION_MAP[institutional_affiliation]
end

def string_to_institutional_affiliation(string)
  unless INSTITUTIONAL_AFFILIATION_MAP.value.include?(string)
    raise InstitutionalAffiliationNotFoundError, "Institutional affiliation '#{string}' not found."
  end
  INSTITUTIONAL_AFFILIATION_MAP.key(string)
end
