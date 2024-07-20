# Hot patch the Box model to fix the users method
Box.class_eval do
  def users_custom
    Alchemy::User.where(id: user_ids)
  end
end

pages_articles = Alchemy::Page.tagged_with('article'); nil
pages_articles_picture = Alchemy::Page.tagged_with('article with picture')

pages = pages_articles + pages_articles_picture; nil

pages_report = []

pages.each do |page|
  begin

    page_info = {
      id: page.id,
      old_public_on: page.public_on,
      old_created_at: page.created_at,
      parsed_date: nil,
      new_public_on: nil,
      new_created_at: nil,
      assigned_authors_logins: [],
      old_slug: page.urlname,
      new_slug: "",
      dates_report: [],
      slug_report: [],
      general_report: []
  }

    # 1. Reset dates
    part = page.urlname.split('/').last
    if part.starts_with?('20') || part.starts_with?('19')
      begin
        date = Date.parse(part).in_time_zone.change(hour: 11)
        page_info[:parsed_date] = date
        page.update public_on: date
        page_info[:new_public_on] = page.public_on
        page.update created_at: date
        page_info[:new_created_at] = page.created_at

        page_info[:dates_report] << "Dates reset successfully"
      rescue => e
        page_info[:dates_report] << "Error while attempting to reset dates: #{e}"
      end
    else
      page_info[:dates_report] << "No date found in URL. No action taken."
    end

    # 2. Reset slugs
    box = Box.find_by(page_id: page.id)
    if box
      if box.respond_to?(:users_custom) && box.users_custom.present?
        box.users_custom.each do |user|
          page_info[:assigned_authors_logins] << user.login
        end
      elsif box.respond_to?(:user) && box.user
        page_info[:assigned_authors_logins] << box.user.login
      end
    end

    if page_info[:parsed_date]
      if page_info[:assigned_authors_logins].any?
        new_slug = ""
        new_slug += page_info[:parsed_date].strftime("%Y-%m-%d")
        new_slug += "-"
        new_slug += page_info[:assigned_authors_logins].join("-")

        page.update urlname: new_slug
        page_info[:new_slug] = new_slug
        page_info[:slug_report] << "Slug updated successfully"
      else
        page_info[:slug_report] << "No authors found. Slug not updated."
      end
    else
      page_info[:slug_report] << "No date found. Slug not updated."
    end

    # 3. Save report
    page_info[:general_report] << "Page processed successfully"

    pages_report << page_info


  rescue => e
    page_info[:general_report] << "Unexpected error: #{e}"
    pages_report << page_info
  end
end

# Save report
require 'csv'

headers = ['id', 'old_public_on', 'old_created_at', 'parsed_date', 'new_public_on', 'new_created_at', 'assigned_authors_logins', 'old_slug', 'new_slug', 'dates_report', 'slug_report', 'general_report']

CSV.open("200724_pages_report.csv", "wb", col_sep: ',', force_quotes: true) do |csv|
  csv << headers

  pages_report.each do |page|
    csv << [
      page[:id],
      page[:old_public_on],
      page[:old_created_at],
      page[:parsed_date],
      page[:new_public_on],
      page[:new_created_at],
      page[:assigned_authors_logins].join("; "),
      page[:old_slug],
      page[:new_slug],
      page[:dates_report].join("; "),
      page[:slug_report].join("; "),
      page[:general_report].join("; ")
    ]
  end
end

puts "Report saved to 200724_pages_report.csv"
