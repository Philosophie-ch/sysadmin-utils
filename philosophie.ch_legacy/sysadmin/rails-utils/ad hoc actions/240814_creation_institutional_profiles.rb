require 'csv'
require 'digest'


#ReportEntry = T.type_alias { T::Hash[Symbol, T.any(Integer, String, T.nilable(String))] }

#sig { params(report: T::Array[ReportEntry]).void }
def generate_csv_report(report)
  # Return early if the report is empty
  return if report.empty?

  # Get the headers from the first element, since we've checked report is not empty
  headers = report.first.keys

  # Generate the CSV
  csv_string = CSV.generate do |csv|
    csv << headers
    report.each do |row|
      csv << headers.map { |header| row[header] }
    end
  end

  # Write the CSV to a file
  file_name = "#{Time.now.strftime('%y%m%d')}_profile_creation_report.csv"

  File.write(file_name, csv_string)

  puts "\n\n\n============ Report generated at #{file_name} ============\n\n\n"

end


report = []
counter = 0
CSV.foreach("#{Time.now.strftime('%y%m%d')}_new_users.csv", col_sep: ',', headers: true) do |row|

  new_user_report = {
    id: '',
    login: '',
    email: '',
    password: '',
    role: '',
    language: '',
    slug: '',
    profile_name: '',
    abbreviation: '',
    academic_page: '',
    status: '',
    error_message: '',
  }

  begin

    if row[2] == "CREATE PROFILE"

      login = row[15]
      existing_user = Alchemy::User.find_by(login: login)

      if !existing_user

        profile_name = row[10]
        email = row[12]
        abbreviation = row[14]
        language = row['language']
        academic_page = row['academic_page']
        password = row['password']

        if email.blank?
          short_hash = Digest::SHA256.hexdigest(Time.now.to_s)[-8, 8]
          unique_hash = "#{short_hash}#{counter}"
          email = "info-#{unique_hash}@philosophie.ch"
          counter += 1
        end

        new_user = Alchemy::User.new()

        new_user.login = login
        new_user_report[:login] = new_user.login
        new_user.email = email
        new_user_report[:email] = new_user.email
        new_user.password = password
        new_user_report[:password] = new_user.password
        new_user.password_confirmation = password
        new_user.alchemy_roles = ['institution']
        new_user_report[:role] = new_user.role
        new_user.language = language
        new_user_report[:language] = new_user.language

        new_user.profile = Profile.new(
          slug: new_user.login,
        )
        new_user_report[:slug] = new_user.profile.slug

        new_user.profile.name = profile_name
        new_user_report[:profile_name] = new_user.profile.name
        new_user.profile.abbreviation = abbreviation
        new_user_report[:abbreviation] = new_user.profile.abbreviation
        new_user.profile.academic_page = academic_page
        new_user_report[:academic_page] = new_user.profile.academic_page

        new_user.save!
        new_user_report[:id] = new_user.id
        new_user_report[:status] = "User '#{login} created successfully"

      else
        new_user_report[:status] = "User '#{login}' already exists. Skipping."
      end

    else
      new_user_report[:status] = "Row type is not CREATE PROFILE for user '#{row[15]}'. Skipping"
    end

  rescue => e
    new_user_report[:error_message] = e.message
    new_user_report[:status] = 'unexpected error'

  ensure
    report << new_user_report
  end

end


generate_csv_report(report)
