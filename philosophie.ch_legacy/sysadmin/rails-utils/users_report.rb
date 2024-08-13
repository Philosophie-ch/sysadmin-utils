require 'csv'

begin
  report = []

  users = Alchemy::User.all

  users.each do |user|
    user_report = {
      id: '', # user
      login: '', # user
      role: '', # user
      gender: '', # user
      firstname: '', # user
      lastname: '', # user
      profile_name: '',  # profile
      abbreviation: '',  # profile
      description: '', # profile
      website: '', # profile
      academic_page: '', # profile
      country: '', # profile
      area: '', # profile
      teacher_at_institution: '', # profile
      societies: '', # profile
      language: '', # user
      show_email: '', # profile
      cms_public_email_toggle: '', # profile
      profile_picture: '', # ...profile.avatar.attached? ? ...profile.avatar.filename.to_s : ""
      facebook_profile: '', # profile
      status: '',
      error_message: ''
    }

    begin
      user_report[:id] = user.id || ''
      user_report[:login] = user.login || ''
      user_report[:role] = user.role || ''
      user_report[:gender] = user.gender || ''
      user_report[:firstname] = user.firstname || ''
      user_report[:lastname] = user.lastname || ''
      user_report[:profile_name] = user&.profile&.name || ''
      user_report[:abbreviation] = user&.profile&.abbreviation || ''
      user_report[:description] = user&.profile&.description || ''
      user_report[:website] = user&.profile&.website || ''
      user_report[:academic_page] = user&.profile&.academic_page || ''
      user_report[:country] = user&.profile&.country || ''
      user_report[:area] = user&.profile&.area || ''
      user_report[:teacher_at_institution] = user&.profile&.teacher_at_institution || ''
      user_report[:societies] = user&.profile&.societies&.map(&:name)&.join(', ') || ''
      user_report[:language] = user.language || ''
      user_report[:show_email] = user&.profile.show_email || ''
      user_report[:cms_public_email_toggle] = user&.profile&.cms_public_email_toggle.to_s || ''
      user_report[:profile_picture] = user&.profile&.avatar&.attached? ? user&.profile&.avatar&.filename.to_s : ''
      user_report[:facebook_profile] = user&.profile&.facebook_profile || ''

      user_report[:status] = 'processed successfully'

    rescue => e
      user_report[:error_message] = e.message
      user_report[:status] = 'unexpected error'

    ensure
      report << user_report
    end

  end

  timestamp = Time.now.strftime('%y%m%d')

  CSV.open("#{timestamp}_users_report.csv", 'wb', col_sep: ',', force_quotes: true) do |csv|
    csv << report.first.keys
    report.each do |row|
      csv << row.values
    end
  end

rescue => e
  puts "\n\n\t============ Error ============\n\n#{e.message}\n\n"
end
