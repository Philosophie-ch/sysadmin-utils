# find the images in the intro elements of all pages

pages = Alchemy::Page.all

pages_report = []

pages.each do |page|
  page_report = {
    id: page.id,
    slug: page.urlname,
    intro_essences_dump: [],
    intro_image_essences_dump: [],
    intro_image_id: nil,
    intro_image_file_name: nil,
    intro_image_name: nil,
    general_report: []
  }

  begin

    elements = page.elements
    intro_elements = elements.select { |element| element.name == 'intro' || element.name == 'event_intro' || element.name == 'job_intro' || element.name == 'call_for_papers_intro' }

    if intro_elements.empty?
      page_report[:general_report] << "No intro element found"
      pages_report << page_report
      next

    elsif intro_elements.size > 1
      page_report[:general_report] << "Error: Multiple intro elements found. Skipping."
      pages_report << page_report
      next

    else

      intro_element = intro_elements.first

      all_essences = intro_element.contents.flat_map(&:essence)

      all_essences.each do |essence|
        case essence
        when Alchemy::EssencePicture
          page_report[:intro_image_essences_dump] << {
            id: essence.id,
            type: essence.class.name,
          }
        else
          page_report[:intro_essences_dump] << {
            id: essence.id,
            type: essence.class.name,
          }
        end
      end

      if page_report[:intro_image_essences_dump].empty?
        page_report[:general_report] << "No image essences found in intro element"
        pages_report << page_report
        next
      elsif page_report[:intro_image_essences_dump].size > 1
        page_report[:general_report] << "Error: Multiple image essences found in intro element"
        pages_report << page_report
        next
      end

      all_essences.each do |essence|
        case essence
        when Alchemy::EssencePicture
          page_report[:intro_image_id] = essence.id
          page_report[:intro_image_file_name] = essence.picture.image_file_name
          page_report[:intro_image_name] = essence.picture.name
        end
      end

      page_report[:general_report] << "Successfully processed page and found image essence"
      pages_report << page_report

    end

  rescue => e
    page_report[:general_report] << "Unexpected error: #{e.message}"
    pages_report << page_report
    next
  end

end

require 'csv'

headers = ['id', 'slug', 'intro_essences_dump', 'intro_image_essences_dump', 'intro_image_id', 'intro_image_file_name', 'intro_image_name', 'general_report']

CSV.open("200724_intro_images_analysis.csv", "wb", col_sep: ',', force_quotes: true) do |csv|
  csv << headers

  pages_report.each do |page|
    csv << [
      page[:id],
      page[:slug],
      page[:intro_essences_dump].map(&:to_s).join('; '),
      page[:intro_image_essences_dump].map(&:to_s).join('; '),
      page[:intro_image_id],
      page[:intro_image_file_name],
      page[:intro_image_name],
      page[:general_report].join('; ')
    ]
  end
end

puts "Done. Check intro_images_analysis.csv for the report."
