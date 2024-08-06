require 'csv'
tag_cleanup_report = []

def clean_others(tag)
  tag.gsub("other: ", "")
end

begin
  parent_page = Alchemy::Page.find(5098)


  parent_page.children.each do |child|

    begin
      page_report = {
        id: child.id,
        old_tags: [],
        new_tags: [],
        tagging_status: "",
        unexpected_error: "",
      }

      old_tags = child.tag_names
      page_report[:old_tags] = old_tags

      new_tags = old_tags.map { |tag| clean_others(tag) }
      page_report[:new_tags] = new_tags

      child.tag_names = new_tags
      child.save!

      page_report[:tagging_status] = "success"

    rescue => e
      page_report[:unexpected_error] = e.message
    ensure
      tag_cleanup_report << page_report
    end
  end

rescue => e
  puts "An error occurred: #{e.message}"
end


CSV.open("240806_multilingual_pages_tag_other_cleanup_report.csv", "wb", col_sep: ',', force_quotes: true) do |csv|

  csv << tag_cleanup_report.first.keys

  tag_cleanup_report.each do |page|
    csv << page.values
  end
end
