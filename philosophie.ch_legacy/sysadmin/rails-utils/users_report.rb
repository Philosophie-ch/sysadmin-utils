require 'csv'


begin

  report = []

  users = Alchemy::User.all

  users.each do |user|

    user_report = {
      id: "",
      firstname: "",
      lastname: "",
      login: "",
      profile_name: "",
      role: "",
      status: "",
      unexpected_error: "",
    }

    begin

      user_report[:id] = user&.id || ""
      user_report[:firstname] = user&.firstname || ""
      user_report[:lastname] = user&.lastname || ""
      user_report[:login] = user&.login || ""
      user_report[:profile_name] = user&.profile&.name || ""
      user_report[:role] = user&.role || ""

      user_report[:status] = "processed successfully"

    rescue => e
      user_report[:unexpected_error] = e.message
      user_report[:status] = "unexpected error"
    ensure
      report << user_report
    end
  end

  timestamp = Time.now.strftime("%y%m%d")

  CSV.open("#{timestamp}_users_report.csv", "wb", col_sep: ',', force_quotes: true) do |csv|
    csv << report.first.keys
    report.each do |row|
      csv << row.values
    end
  end

rescue => e
  puts "\n\n\t============ Error ============\n\n#{e.message}\n\n"
end
