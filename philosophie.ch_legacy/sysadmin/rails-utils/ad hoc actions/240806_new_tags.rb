require 'csv'


general_report = []

CSV.foreach('240806_new_tags.csv', col_sep: ',', headers: true) do |row|

  page_report = {
    id: "",
    old_tags: "",
    new_tags: "",
    tagging_status: "",
    unexpected_error: "",
  }

  begin

    if row["id"].nil? || row["new_tags"].nil?
      next
    end

    id = row["id"]
    page_report[:id] = id

    page_report[:new_tags] = row["new_tags"]

    page = Alchemy::Page.find_by(id: id)
    page_report[:old_tags] = page.tag_names.join(";")

    begin
      new_tags = row["new_tags"].split(";").map(&:strip)
      page.tag_names = new_tags
      page.save
    rescue => e
      page_report[:tagging_error] = e.message
    end

    page_report[:tagging_status] = "success"
    general_report << page_report

  rescue => e
    page_report[:unexpected_error] = e.message
    general_report << page_report
  end

end


CSV.open("240806_new_tags_report.csv", "wb", col_sep: ',', force_quotes: true) do |csv|
  csv << general_report.first.keys

  general_report.each do |page|
    csv << page.values
  end
end
