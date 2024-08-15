require 'csv'
require 'digest'

ActiveRecord::Base.logger.level = Logger::WARN

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


def generate_csv_report(report)
  return if report.empty?
  headers = report.first.keys

  csv_string = CSV.generate do |csv|
    csv << headers
    report.each do |row|
      csv << headers.map { |header| row[header] }
    end
  end

  file_name = "#{Time.now.strftime('%y%m%d')}_profiles_tasks_report.csv"
  File.write(file_name, csv_string)

  Rails.logger.info("\n\n\n============ Report generated at #{file_name} ============\n\n\n")
end


report = []
counter = 0
CSV.foreach("profiles_tasks.csv", col_sep: ',', headers: true) do |row|

  user_report = {
    _correspondence: row["_correspondence"],
    _todo_person: row["_todo_person"],
    _todo_profile: row["_todo_profile"],
    alchemy_roles: row["alchemy_roles"].split(', '),
    _member_subcategory: row["_member_subcategory"],
    _status_wrt_association: row["_status_wrt_association"],
    id: row["id"],
    _role_wrt_portal: row["_role_wrt_portal"],
    _biblio_name: row["_biblio_name"],
    _new_login: row["_new_login"],
    _biblio_full_name: row["_biblio_full_name"],
    profile_name: row["profile_name"],
    firstname: row["firstname"],
    lastname: row["lastname"],
    email: row["email"],
    _NL: row["_NL"],
    academic_page: row["academic_page"],
    abbreviation: row["abbreviation"],
    _function: row["_function"],
    login: row["login"],
    _link: row["_link"],
    password: row["password"],
    language: row["language"],
    gender: row["gender"],
    _contact_person: row["_contact_person"],
    _contact_person_email: row["_contact_person_email"],
    _articles_assigned_to_profile: row["_articles_assigned_to_profile"],
    _biblio_keys: row["_biblio_keys"],
    _comments: row["_comments"],
    _employment: row["_employment"],
    _title: row["_title"],
    _function_title: row["_function_title"],
    _function_standardised: row["_function_standardised"],
    country: row["country"],
    area_NEW_TO_IMPLEMENT: row["area_NEW_TO_IMPLEMENT"],
    _canton: row["_canton"],
    description: row["description"],
    website: row["website"],
    teacher_at_institution: row["teacher_at_institution"],
    societies: row["societies"],
    show_email: '',  # read only
    cms_public_email_toggle: row["cms_public_email_toggle"],
    profile_picture: row["profile_picture"],
    facebook_profile: row["facebook_profile"],
    status: '',
    changes_made: '',
    error_message: ''
  }


  begin


    # Control
    Rails.logger.info("Processing user '#{row['login']}'")
    login = row['login'] || ''

    if login.blank? || login == ''
      user_report[:status] = "Login is missing. Skipping."
      next
    end

    todo_profile = row['_todo_profile'] || ''
    unless ['CREATE PROFILE', 'MAKE CHANGES', 'GET'].include?(todo_profile)
      user_report[:status] = "Row type is not one of ['CREATE PROFILE', 'MAKE CHANGES', 'GET'] for user '#{row['login']}'. Skipping"
      next
    end

    if todo_profile == "CREATE PROFILE"
      user = Alchemy::User.find_by(login: login)
      if user
        user_report[:status] = "User '#{login}' already exists. Skipping."
        next
      end
    end


    # Parsing
    Rails.logger.info("Processing user '#{login}': Parsing")
    alchemy_roles = row['alchemy_roles'] || ''  # user
    id = row['id'] || ''  # user
    profile_name = row['profile_name'] || ''  # profile
    firstname = row['firstnames'] || '' # user
    lastname = row['lastname'] || '' # user
    email = row['email'] || ''  # user
    academic_page = row['academic_page'] || ''  # profile
    abbreviation = row['abbreviation'] || ''  # profile
    password = row['password'] || ''  # user
    language = row['language'] || ''  # user
    gender = row['gender'] || ''  # user
    country = row['country'] || ''  # profile
    # To be implemented:    area = row['area'] || ''  # profile
    description = row['description'] || '' # profile
    website = row['website'] || '' # profile
    teacher_at_institution = row['teacher_at_institution'] || '' # profile
    societies = row['societies'] || '' # profile
    cms_public_email_toggle_s = "#{row['cms_public_email_toggle']}" || "false"
    cms_public_email_toggle = cms_public_email_toggle_s.downcase() == 'true' ? true : false  # profile
    profile_picture = row['profile_picture'] || '' # profile
    facebook_profile = row['facebook_profile'] || '' # profile

    if email.blank? || email == ''
      short_hash = Digest::SHA256.hexdigest(Time.now.to_s)[-8, 8]
      unique_hash = "#{short_hash}#{counter}"
      email = "info-#{unique_hash}@philosophie.ch"
      counter += 1
    end


    # Setup
    Rails.logger.info("Processing user '#{login}': Setup")
    if todo_profile == "CREATE PROFILE"
        user = Alchemy::User.new()

    elsif todo_profile == "MAKE CHANGES" || todo_profile == "GET"
        user = Alchemy::User.find_by(id: id)

        if user.nil?
          Rails.logger.error("User '#{login}' with id '#{id}' not found but requested 'MAKE CHANGES' or 'GET'. Skipping.")
          user_report[:status] = "User '#{login}' with id '#{id}' not found but requested 'MAKE CHANGES' or 'GET'. Skipping."
          next
        end
        if user.profile.nil?
          Rails.logger.error("User '#{login}' with id '#{id}' does not have a profile but requested 'MAKE CHANGES' or 'GET'. Skipping.")
          user_report[:status] = "User '#{login}' with id '#{id}' does not have a profile but requested 'MAKE CHANGES' or 'GET'. Skipping."
          next
        end

    else # Should not happen
        Rails.logger.error("Error: _todo_profile not supported")
        user_report[:status] = "Error: _todo_profile not supported"
        next
    end

    if todo_profile == "MAKE CHANGES"
      old_user = {
        alchemy_roles: user.alchemy_roles.join(', '),
        id: user.id,
        profile_name: user.profile.name,
        firstname: user.firstname,
        lastname: user.lastname,
        email: user.email,
        academic_page: user.profile.academic_page,
        abbreviation: user.profile.abbreviation,
        login: user.login,
        language: user.language,
        gender: user.gender,
        country: user.profile.country,
        #area_NEW_TO_IMPLEMENT: user.profile.area,
        description: user.profile.description,
        website: user.profile.website,
        teacher_at_institution: user.profile.teacher_at_institution,
        societies: user.profile.societies.map(&:name).join(', '),
        cms_public_email_toggle: user.profile.cms_public_email_toggle,
        facebook_profile: user.profile.facebook_profile
      }
    end


    # Execution
    Rails.logger.info("Processing user '#{login}': Execution")
    if todo_profile == "CREATE PROFILE" || todo_profile == "MAKE CHANGES"
        Rails.logger.info("Processing user '#{login}': MUTATION FOLLOWING!")
        user.login = login
        user.email = email
        user.alchemy_roles = [alchemy_roles]
        user.language = language
        user.gender = gender

        if alchemy_roles.include?("institution")
          user.firstname = profile_name
        else
          user.firstname = firstname
        end

        user.lastname = lastname

        if todo_profile == "CREATE PROFILE"
          user.password = password
          user.password_confirmation = password
          user.profile = Profile.new(
            slug: user.login,
          )
        end

        user.profile.slug = login
        user.profile.name = profile_name
        user.profile.abbreviation = abbreviation
        user.profile.academic_page = academic_page
        user.profile.country = country
        user.profile.description = description
        user.profile.website = website
        user.profile.teacher_at_institution = teacher_at_institution
        #user.profile.societies = societies  # not implemented yet
        user.profile.cms_public_email_toggle = cms_public_email_toggle
        user.profile.facebook_profile = facebook_profile

        # Saving
        Rails.logger.info("User '#{login}': MUTATION! Will save now.")
        successful_user_save = user.save!
        successful_profile_save = user.profile.save!
        successful_save = successful_user_save && successful_profile_save

        if successful_save
          Rails.logger.info("User '#{login}': saved successfully!")
        else
          Rails.logger.info("User '#{login}': NOT saved!")
          user_report[:status] = "User '#{login}' not saved!"
          user_report[:error_message] = "User '#{login}' not saved!"
          if !successful_user_save
            Rails.logger.error("User '#{login}': user not saved!")
          end
          if !successful_profile_save
            Rails.logger.error("User '#{login}': profile not saved!")
          end
          next
        end
    end

    # Update report
    Rails.logger.info("Processing user '#{login}': Updating report")
    user_report.merge!({
      id: user.id,
      login: user.login,
      profile_name: user.profile.name,
      email: user.email,
      academic_page: user.profile.academic_page,
      abbreviation: user.profile.abbreviation,
      language: user.language,
      country: user.profile.country,
      # area: user.profile.area,  # not implemented yet
      alchemy_roles: user.alchemy_roles.join(', '),
      gender: user.gender,
      firstname: user.firstname,
      lastname: user.lastname,
      description: user.profile.description,
      website: user.profile.website,
      teacher_at_institution: user.profile.teacher_at_institution,
      societies: user.profile.societies.map(&:name).join(', '),
      show_email: user.profile.show_email,
      cms_public_email_toggle: user.profile.cms_public_email_toggle,
      profile_picture: user.profile&.avatar&.attached? ? user&.profile&.avatar&.filename.to_s : '',
      facebook_profile: user.profile.facebook_profile,
    })

    if todo_profile == "MAKE CHANGES"
      changes = []
      user_report.each do |key, value|
        if old_user[key] != value
          changes << "#{key}: ''#{old_user[key]}'' → ''#{value}''"
        end
      end

      user_report[:changes_made] = changes.join(' ;;; ')
    end

    user_report[:status] = "User '#{login}' processed successfully"
    Rails.logger.info("Processing user '#{login}': Done")



  rescue => e
    Rails.logger.error("Error while processing '#{login}': #{e.message}")
    user_report[:error_message] = e.message
    user_report[:status] = 'unexpected error'

  ensure
    report << user_report
  end

end


generate_csv_report(report)
