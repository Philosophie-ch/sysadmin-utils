require 'csv'
require 'securerandom'

ActiveRecord::Base.logger.level = Logger::WARN
ActiveSupport::Deprecation.behavior = [:silence]  # silence useless deprecation warnings
ActiveSupport::Deprecation.silenced = true

Rails.logger.level = Logger::INFO

if ARGV[0]
  # set log level
  if ARGV[0] == 'debug'
    Rails.logger.level = Logger::DEBUG
  elsif ARGV[0] == 'info'
    Rails.logger.level = Logger::INFO
  elsif ARGV[0] == 'warn'
    Rails.logger.level = Logger::WARN
  elsif ARGV[0] == 'error'
    Rails.logger.level = Logger::ERROR
  end
end


############
# FUNCTIONS
############

def generate_csv_report(report)
  return if report.empty?
  headers = report.first.keys

  csv_string = CSV.generate do |csv|
    csv << headers
    report.each do |row|
      csv << headers.map { |header| row[header] }
    end
  end

  base_folder = 'portal-tasks-reports'
  FileUtils.mkdir_p(base_folder) unless Dir.exist?(base_folder)

  file_name = "#{base_folder}/#{Time.now.strftime('%y%m%d')}_profiles_tasks_report.csv"

  begin
    File.write(file_name, csv_string)
    puts "File written successfully to #{file_name}"
  rescue Errno::EACCES => e
    puts "Permission denied: #{e.message}"
  rescue Errno::ENOSPC => e
    puts "No space left on device: #{e.message}"
  rescue StandardError => e
    puts "An error occurred: #{e.message}"
  end

  Rails.logger.info("\n\n\n============ Report generated at #{file_name} ============\n\n\n")
end


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


def get_profile_picture(user)
  profile_picture = user.profile&.avatar&.attached? ? user&.profile&.avatar&.filename.to_s : ''
  return profile_picture
end

def set_profile_picture(user, new_filename)

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

    old_filename = get_profile_picture(user)

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
      set_profile_picture_report[:error_trace] = "profiles_tasks.rb::set_profile_picture"
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
    return set_profile_picture_report
    Rails.logger.info("\t...success!")

  rescue => e
    set_profile_picture_report[:status] = "unhandled error"
    set_profile_picture_report[:error_message] = e.message
    set_profile_picture_report[:error_trace] = e.backtrace.first
    return set_profile_picture_report
  end
end



############
# MAIN
############

report = []
processed_lines = 0
CSV.foreach("portal-tasks/profiles_tasks.csv", col_sep: ',', headers: true, encoding: 'utf-16') do |row|
  puts "\n"
  Rails.logger.info("Processing row #{processed_lines + 1}...")
  subreport = {
    _correspondence: row["_correspondence"] || "",
    _todo_person: row["_todo_person"] || "",
    _request: row["_request"] || "",
    alchemy_roles: row["alchemy_roles"] || "",
    _member_subcategory: row["_member_subcategory"] || "",
    _status_wrt_association: row["_status_wrt_association"] || "",
    id: row["id"] || "",
    _role_wrt_portal: row["_role_wrt_portal"] || "",
    _biblio_name: row["_biblio_name"] || "",
    _biblio_full_name: row["_biblio_full_name"] || "",
    profile_name: row["profile_name"] || "",
    firstname: row["firstname"] || "",
    lastname: row["lastname"] || "",
    email_addresses: row["email_addresses"] || "",
    _NL: row["_NL"] || "",
    academic_page: row["academic_page"] || "",
    abbreviation: row["abbreviation"] || "",
    _function: row["_function"] || "",
    login: row["login"] || "",
    _old_login: row["_old_login"] || "",
    _link: row["_link"] || "",
    password: row["password"] || "",
    language: row["language"] || "",
    gender: row["gender"] || "",

    _contact_person: row["_contact_person"] || "",
    _contact_person_email: row["_contact_person_email"] || "",
    _articles_assigned_to_profile: row["_articles_assigned_to_profile"] || "",
    _articles_assigned_to_profile_links: row["_articles_assigned_to_profile_links"] || "",
    _biblio_keys: row["_biblio_keys"] || "",
    _comments: row["_comments"] || "",
    _employment: row["_employment"] || "",
    _title: row["_title"] || "",
    _function_title: row["_function_title"] || "",
    _function_standardised: row["_function_standardised"] || "",

    country: row["country"] || "",
    area: row["area"] || "",
    _canton: row["_canton"] || "",
    description: row["description"] || "",
    website: row["website"] || "",
    teacher_at_institution: row["teacher_at_institution"] || "",
    societies: row["societies"] || "",
    cms_public_email_toggle: row["cms_public_email_toggle"] || "",
    profile_picture: row["profile_picture"] || "",
    facebook_profile: row["facebook_profile"] || "",

    # report
    status: '',
    changes_made: '',
    error_message: '',
    error_trace: '',
    update_links_report: '',

    # dump
    birth_date: row["birth_date"] || "",
    public: row["public"] || "",
    level: row["level"] || "",
    other_personal_information: row["other_personal_information"] || "",
    institutional_affiliation: row["institutional_affiliation"] || "",
    type_of_affiliation: row["type_of_affiliation"] || "",
    teach_as_well: row["teach_as_well"] || "",
    receive_leaflets: row["receive_leaflets"] || "",
    share_material: row["share_material"] || "",
    interested_in_education: row["interested_in_education"] || "",
    first_favorites: row["first_favorites"] || "",
    second_favorites: row["second_favorites"] || "",
    other_institutional_affiliation: row["other_institutional_affiliation"] || "",
    activities: row["activities"] || "",
    number_of_professorships: row["number_of_professorships"] || "",
    address: row["address"] || "",
    number_of_postgraduates: row["number_of_postgraduates"] || "",
    number_of_students: row["number_of_students"] || "",
    characteristics: row["characteristics"] || "",
    other_type_of_affiliation: row["other_type_of_affiliation"] || "",
    filter: row["filter"] || "",
  }


  begin

    # Control
    login = subreport[:login].strip
    id = subreport[:id].strip
    req = subreport[:_request].strip

    if login.blank? && id.blank?
      Rails.logger.error("Login and ID are missing. Skipping.")
      subreport[:_request] = req + " ERROR"
      subreport[:status] = "error"
      subreport[:error_message] = "Either login or ID are missing, but need at least one to uniquely identify a profile. Skipping."
      subreport[:error_trace] = "Main::Control"
      next
    end

    Rails.logger.info("Processing user '#{login}'")
    supported_requests = ['POST', 'UPDATE', 'GET', 'DELETE', 'UPDATE LINKS', 'UPDATE PASSWORD']
    unless supported_requests.include?(req)
      if req.blank?
        subreport[:_request] = req + " ERROR"
        subreport[:status] = "success"
        subreport[:error_message] = "Request is blank. Skipping."
        subreport[:error_trace] = "Main::Control"
        next
      end

      subreport[:_request] = req + " ERROR"
      subreport[:status] = "error"
      subreport[:error_message] = "Request is not one of #{supported_requests.join(", ")}. Skipping."
      subreport[:error_trace] = "Main::Control"
      next

    end

    if req == "POST"
      user = Alchemy::User.find_by(login: login)
      if user
        subreport[:_request] = req + " ERROR"
        subreport[:status] = "error"
        subreport[:error_message] = "User '#{login}' already exists. Skipping."
        subreport[:error_trace] = "Main::Control::POST"
        next
      end
    end


    # Parsing
    Rails.logger.info("Processing user '#{login}': Parsing")

    alchemy_roles_str = subreport[:alchemy_roles].strip  # user
    id = subreport[:id].strip  # user
    profile_name = subreport[:profile_name].strip  # profile
    firstname = subreport[:firstname].strip # user
    lastname = subreport[:lastname].strip # user
    email_addresses_raw = subreport[:email_addresses].strip  # profile
    academic_page = subreport[:academic_page].strip  # profile
    abbreviation = subreport[:abbreviation].strip  # profile
    password = subreport[:password].strip  # user
    language = subreport[:language].strip  # user
    gender = subreport[:gender].strip  # user
    country = subreport[:country].strip  # profile
    area = subreport[:area].strip  # profile
    description = subreport[:description].strip # profile
    website = subreport[:website].strip # profile
    teacher_at_institution = subreport[:teacher_at_institution].strip # profile
    societies = subreport[:societies].strip # profile
    cms_public_email_toggle_s = "#{row['cms_public_email_toggle']}" || "false"
    cms_public_email_toggle = cms_public_email_toggle_s.downcase() == 'true' ? true : false  # profile
    profile_picture = subreport[:profile_picture].strip # profile
    facebook_profile = subreport[:facebook_profile].strip # profile

    # profile dump
    birth_date = subreport[:birth_date].strip
    public_field = subreport[:public].strip
    level = subreport[:level].strip
    other_personal_information = subreport[:other_personal_information].strip
    institutional_affiliation = subreport[:institutional_affiliation].strip
    type_of_affiliation = subreport[:type_of_affiliation].strip
    teach_as_well = subreport[:teach_as_well].strip
    receive_leaflets = subreport[:receive_leaflets].strip
    share_material = subreport[:share_material].strip
    interested_in_education = subreport[:interested_in_education].strip
    first_favorites = subreport[:first_favorites].strip
    second_favorites = subreport[:second_favorites].strip
    other_institutional_affiliation = subreport[:other_institutional_affiliation].strip
    activities = subreport[:activities].strip
    number_of_professorships = subreport[:number_of_professorships].strip
    address = subreport[:address].strip
    number_of_postgraduates = subreport[:number_of_postgraduates].strip
    number_of_students = subreport[:number_of_students].strip
    characteristics = subreport[:characteristics].strip
    other_type_of_affiliation = subreport[:other_type_of_affiliation].strip
    filter = subreport[:filter].strip

    # emails
    email_addresses = email_addresses_raw.split(',').map(&:strip).join(', ')  # profile


    # Setup
    Rails.logger.info("Processing user '#{login}': Setup")
    if req == "POST"
        user = Alchemy::User.new()

    elsif req == "UPDATE" || req == "GET" || req == "DELETE" || req == "UPDATE LINKS" || req == "UPDATE PASSWORD"

      unless id.blank?
        user = Alchemy::User.find(id)
      else
        unless login.blank?
        user = Alchemy::User.find_by(login: login)
        else
          Rails.logger.error("Error: login and id are both blank. Skipping.")
          subreport[:_request] = req + " ERROR"
          subreport[:status] = "error"
          subreport[:error_message] = "Login and id are both blank. Skipping."
          subreport[:error_trace] = "Main::Setup"
          next
        end
      end

      if user.nil?
        Rails.logger.error("User '#{login}' not found in the server, but requested 'UPDATE' or 'GET'. Skipping.")
        subreport[:_request] = req + " ERROR"
        subreport[:status] = "error"
        subreport[:error_message] = "User '#{login}' with id '#{id}' not found but requested 'UPDATE' or 'GET'. Skipping."
        subreport[:error_trace] = "Main::Setup"
        next
      end

      if user.profile.nil?
        Rails.logger.error("User '#{login}' with id '#{id}' does not have a profile attached to it. How is this even possible? Verify manually. Skipping.")
        subreport[:_request] = req + " ERROR"
        subreport[:status] = "error"
        subreport[:error_message] = "User '#{login}' with id '#{id}' does not have a profile but requested 'UPDATE' or 'GET'. Skipping."
        subreport[:error_trace] = "Main::Setup"
        next
      end

    else # Should not happen
        Rails.logger.error("Error: _request not supported")
        subreport[:_request] = req + " ERROR"
        subreport[:status] = "error"
        subreport[:error_message] = "_request not supported"
        subreport[:error_trace] = "Main::Setup"
        next
    end


    # Execution
    Rails.logger.info("Processing user '#{login}': Execution")

    if req == "DELETE"
      profile = user.profile
      profile_id = profile.id
      user.delete
      profile.delete

      if Alchemy::User.find_by(login: login).present? || Profile.find_by(id: profile_id).present?
        Rails.logger.error("User '#{login}' not deleted for an unknown reason!")
        subreport[:_request] = req + " ERROR"
        subreport[:status] = "error"
        subreport[:error_message] = "User '#{login}' not deleted for an unknown reason!"
        subreport[:error_trace] = "Main::Execution::DELETE"
      else
        subreport[:id] = ""
        subreport[:login] = ""
        subreport[:_link] = ""
        subreport[:status] = "success"
        subreport[:changes_made] = "USER WAS DELETED IN THE SERVER"
      end
      next
    end

    if req == "UPDATE" || req == "GET"
      old_user = {
        alchemy_roles: user.alchemy_roles.join(', '),
        id: user.id,
        profile_name: user.profile.name,
        firstname: user.firstname,
        lastname: user.lastname,
        email_addresses: user.profile.email_addresses,
        _NL: subreport[:_NL],
        academic_page: user.profile.academic_page,
        abbreviation: user.profile.abbreviation,
        login: user.login,
        language: user.language,
        gender: user.gender,
        country: user.profile.country,
        area: user.profile.area,
        description: user.profile.description,
        website: user.profile.website,
        teacher_at_institution: user.profile.teacher_at_institution,
        societies: user.profile.societies.map(&:name).join(', '),
        cms_public_email_toggle: user.profile.cms_public_email_toggle,
        profile_picture: get_profile_picture(user),
        facebook_profile: user.profile.facebook_profile,

        status: '',
        changes_made: '',
        error_message: '',
        error_trace: '',
        update_links_report: '',

        birth_date: user.profile.birth_date,
        public: user.profile.public,
        level: user.profile.level,
        other_personal_information: user.profile.other_personal_information,
        institutional_affiliation: user.profile.institutional_affiliation,
        type_of_affiliation: user.profile.type_of_affiliation,
        teach_as_well: user.profile.teach_as_well,
        receive_leaflets: user.profile.receive_leaflets,
        share_material: user.profile.share_material,
        interested_in_education: user.profile.interested_in_education,
        first_favorites: user.profile.first_favorites,
        second_favorites: user.profile.second_favorites,
        other_institutional_affiliation: user.profile.other_institutional_affiliation,
        activities: user.profile.activities,
        number_of_professorships: user.profile.number_of_professorships,
        address: user.profile.address,
        number_of_postgraduates: user.profile.number_of_postgraduates,
        number_of_students: user.profile.number_of_students,
        characteristics: user.profile.characteristics,
        other_type_of_affiliation: user.profile.other_type_of_affiliation,
        confirmation_token: user.profile.confirmation_token,
        confirmed_at: user.profile.confirmed_at,
        confirmation_sent_at: user.profile.confirmation_sent_at,
        filter: user.profile.filter
      }
    end

    if req == "POST" || req == "UPDATE"
        Rails.logger.info("Processing user '#{login}': MUTATION FOLLOWING!")
        alchemy_roles = alchemy_roles_str.split(',').map(&:strip)
        user.alchemy_roles = alchemy_roles
        user.language = language
        user.gender = gender
        user.firstname = firstname
        user.lastname = lastname

        if req == "POST"
          # Randomize password on POST
          password = generate_randomized_password
          email = generate_hashed_email_address
          user.email = email
          user.password = password
          user.password_confirmation = password
          user.profile = Profile.new(
            slug: user.login,
          )
          subreport[:password] = password
        end

        user.login = login
        user.profile.slug = login

        user.profile.name = profile_name
        user.profile.abbreviation = abbreviation
        user.profile.email_addresses = email_addresses
        user.profile.academic_page = academic_page
        user.profile.country = country
        user.profile.area = area
        user.profile.description = description
        user.profile.website = website
        user.profile.teacher_at_institution = teacher_at_institution

        societies_names = societies.split(',').map(&:strip)
        societies_names.map do |name|
          society = Society.find_by(name: name)
          if society.nil?
            raise "Society '#{name}' not found in the database. Skipping."
          end
          user.profile.societies << society
        end

        user.profile.cms_public_email_toggle = cms_public_email_toggle
        user.profile.facebook_profile = facebook_profile

        user.profile.birth_date = birth_date
        user.profile.public = public_field
        user.profile.level = level
        user.profile.other_personal_information = other_personal_information
        user.profile.institutional_affiliation = institutional_affiliation
        user.profile.type_of_affiliation = type_of_affiliation
        user.profile.teach_as_well = teach_as_well
        user.profile.receive_leaflets = receive_leaflets
        user.profile.share_material = share_material
        user.profile.interested_in_education = interested_in_education
        user.profile.first_favorites = first_favorites
        user.profile.second_favorites = second_favorites
        user.profile.other_institutional_affiliation = other_institutional_affiliation
        user.profile.activities = activities
        user.profile.number_of_professorships = number_of_professorships
        user.profile.address = address
        user.profile.number_of_postgraduates = number_of_postgraduates
        user.profile.number_of_students = number_of_students
        user.profile.characteristics = characteristics
        user.profile.other_type_of_affiliation = other_type_of_affiliation
        user.profile.filter = filter

        # Saving
        Rails.logger.info("User '#{login}': MUTATION! Will save now.")
        successful_user_save = user.save!
        successful_profile_save = user.profile.save!
        successful_save = successful_user_save && successful_profile_save

        if successful_save
          Rails.logger.info("User '#{login}': saved successfully!")
        else
          if req == "POST"
            # On POST, try to save the user with a different email address
            post_counter = 0
            while !successful_save && post_counter < 3
              post_counter += 1
              email = generate_hashed_email_address
              user.email = email
              user.password = password
              user.password_confirmation = password
              successful_user_save = user.save!
              successful_profile_save = user.profile.save!
              successful_save = successful_user_save && successful_profile_save
            end
          end
        end

        if req == "UPDATE"
          retrieved_user = Alchemy::User.find_by(login: login)
          if retrieved_user.nil?
            Rails.logger.error("User '#{login}': user not saved!")
            subreport[:_request] = req + " ERROR"
            subreport[:status] = "error"
            subreport[:error_message] = "User not saved!"
            subreport[:error_trace] = "Main::Execution::Save"
            subreport[:update_links_report] = "User not saved, no need to update links."
            next
          end
          if retrieved_user.login != old_user[:login]
            # Update links
            old_login = old_user[:login]
            update_links_report = update_links(login, old_login)
            subreport[:update_links_report] = update_links_report
          else
            subreport[:update_links_report] = "Old login is the same as new login, no need to update links."
          end
        end

        if !successful_save
          subreport[:_request] = req + " ERROR"
          subreport[:status] = "error"
          err_msg = ""
          err_trace = ""
          if !successful_user_save
            Rails.logger.error("User '#{login}': user not saved!")
            err_msg += "User not saved!"
            err_trace += "Main::Execution::Save"
          end
          if !successful_profile_save
            Rails.logger.error("User '#{login}': profile not saved!")
            err_msg = err_msg.blank? ? "Profile not saved!" : err_msg + " ;;; Profile not saved!"
            err_trace = "Main::Execution::Save"
          end
          subreport[:error_message] = err_msg
          subreport[:error_trace] = err_trace
          next
        end

    end

    if req == "UPDATE LINKS"
      old_login = subreport[:_old_login].strip
      update_links_report = update_links(login, old_login)
      subreport[:update_links_report] = update_links_report
    end

    if req == "UPDATE PASSWORD"
      password = generate_randomized_password
      user.password = password
      user.password_confirmation = password
      user.save!
      subreport[:password] = password
    end

    # Complex actions
    if req == "UPDATE"

      # Set profile picture
      if profile_picture.present?
        set_profile_picture_report = set_profile_picture(user, profile_picture)
        if set_profile_picture_report[:status] != "success"
          subreport[:error_message] = set_profile_picture_report[:error_message]
          subreport[:error_trace] = set_profile_picture_report[:error_trace]
        end
      end

    end


    # Update report
    Rails.logger.info("Processing user '#{login}': Updating report")
    subreport.merge!({
      id: user.id,
      login: user.login,
      _link: "https://www.philosophie.ch/profil/#{user.login}",
      profile_name: user.profile.name,
      email_addresses: user.profile.email_addresses,
      academic_page: user.profile.academic_page,
      abbreviation: user.profile.abbreviation,
      language: user.language,
      country: user.profile.country,
      area: user.profile.area,
      alchemy_roles: user.alchemy_roles.join(', '),
      gender: user.gender,
      firstname: user.firstname,
      lastname: user.lastname,
      description: user.profile.description,
      website: user.profile.website,
      teacher_at_institution: user.profile.teacher_at_institution,
      societies: user.profile.societies.map(&:name).join(', '),
      cms_public_email_toggle: user.profile.cms_public_email_toggle,
      profile_picture: get_profile_picture(user),
      facebook_profile: user.profile.facebook_profile,

      birth_date: user.profile.birth_date,
      public: user.profile.public,
      level: user.profile.level,
      other_personal_information: user.profile.other_personal_information,
      institutional_affiliation: user.profile.institutional_affiliation,
      type_of_affiliation: user.profile.type_of_affiliation,
      teach_as_well: user.profile.teach_as_well,
      receive_leaflets: user.profile.receive_leaflets,
      share_material: user.profile.share_material,
      interested_in_education: user.profile.interested_in_education,
      first_favorites: user.profile.first_favorites,
      second_favorites: user.profile.second_favorites,
      other_institutional_affiliation: user.profile.other_institutional_affiliation,
      activities: user.profile.activities,
      number_of_professorships: user.profile.number_of_professorships,
      address: user.profile.address,
      number_of_postgraduates: user.profile.number_of_postgraduates,
      number_of_students: user.profile.number_of_students,
      characteristics: user.profile.characteristics,
      other_type_of_affiliation: user.profile.other_type_of_affiliation,
      filter: user.profile.filter

    })

    if req == "GET"
      # Get assigned articles and links
      articles = get_assigned_articles(user)
      subreport[:_articles_assigned_to_profile] = articles.map(&:urlname).join(', ')

      article_links = articles.map { |article| get_page_link(article) }
      subreport[:_articles_assigned_to_profile_links] = article_links.join(', ')
    end

    if req == "UPDATE" || req == "GET"
      changes = []
      subreport.each do |key, value|
        if old_user[key] != value && key != :changes_made && key != :status && key != :error_message && key != :error_trace && key != :update_links_report && key != :_request
          # Skip if both old and new values are empty
          unless old_user[key].to_s.empty? && value.to_s.empty?
            changes << "#{key}: {{ #{old_user[key]} }} => {{ #{value} }}"
          end
        end
      end

      subreport[:changes_made] = changes.join(' ;;; ')
    end

    subreport[:status] = "success"
    Rails.logger.info("Processing user '#{login}': Done")


  rescue => e
    Rails.logger.error("Error while processing '#{login}': #{e.message}")
    subreport[:_request] = req + " ERROR"
    subreport[:status] = 'unhandled error'
    subreport[:error_message] = e.message
    subreport[:error_trace] = e.backtrace.join("\n")

  ensure
    report << subreport
    Rails.logger.info("Processed user '#{login.blank? ? id : login}'. Processed lines so far: #{processed_lines + 1}")
    processed_lines += 1
  end

end


generate_csv_report(report)
