tag_map = {

  # Page Type
  "article" => "page type: article",
  "article about event" => "page type: article about event",
  "article without DOI" => "page type: article without DOI",
  "information page" => "page type: information page",
  "media article" => "page type: media article",
  "portal page" => "page type: portal page",
  "presentation page" => "page type: presentation page",
  "topics" => "page type: topics",
  "event" => "page type: event",  # Deprecated but included for completeness

  # Media Type
  "audio" => "media type 1: audio",
  "video" => "media type 1: video",
  "pdf" => "media type 1: pdf",
  "gallery" => "media type 1: gallery",
  "picture" => "media type 2: picture",

  # Language
  "English" => "language: English",
  "French" => "language: French",
  "German" => "language: German",
  "Italian" => "language: Italian",
  "multilingual" => "language: multilingual",

  # University
  "EPFL" => "university: EPFL",
  "ETH" => "university: ETH",
  "UZH" => "university: UZH",
  "UniBE" => "university: UniBE",
  "UniGE" => "university: UniGE",
  "UniFR" => "university: UniFR",
  "UniNE" => "university: UniNE",
  "USI" => "university: USI",
  "UniL" => "university: UniL",
  "UniBS" => "university: UniBS",
  "UniSG" => "university: UniSG",
  "UniLU" => "university: UniLU",
  "Uni" => "university: Uni",
  "PH" => "university: PH",
  "VH" => "university: VH",

  # Other institutions
  "Soc" => "university: Soc",
  "Café" => "university: Café",

  # Region
  "ZH" => "region: ZH",
  "BE" => "region: BE",
  "BS" => "region: BS",
  "GE" => "region: GE",
  "VD" => "region: VD",
  "TI" => "region: TI",
  "NE" => "region: NE",
  "FR" => "region: FR",
  "LU" => "region: LU",
  "SG" => "region: SG",
  "Germany" => "region: Germany",
  "France" => "region: France",
  "Italy" => "region: Italy",
  "Belgium" => "region: Belgium",

  # References and footnotes
  "references" => "references: has references",
  "footnotes" => "footnotes: has footnotes",

  # Special content
  "metaphi" => "special content: metaphi",
  "testimonial" => "special content: testimonial",
  "job" => "special content: job",
  "our publication" => "special content: our publication",
  "Fluchtgeschichten" => "special content: Fluchtgeschichten",
  "book review" => "special content: book review",
  "book note" => "special content: book note",
  "Dialectica" => "special content: Dialectica",
  "student project" => "special content: student project",
  "essay competition" => "special content: essay competition",
  "article series" => "special content: article series",
  "discipline" => "special content: discipline",
  "press" => "special content: press",
  "journal" => "special content: journal",
  "course" => "special content: course",
  "high-schools" => "special content: high-schools",
  "PhD" => "special content: PhD",
  "our event" => "special content: our event",
  "Agora" => "special content: Agora",
  "philExpo22" => "special content: philExpo22",
  "research" => "special content: research",
  "OA" => "special content: OA",
  "philosophy olympiad" => "special content: philosophy olympiad"

}

# Helper method to map a tag to a new tag
# Add "other: " to the tag if it's not in the map
# E.g. 1, map_tag("article", tag_map) => "page type: article"
# E.g. 2, map_tag("foo", tag_map) => "other: foo"
def map_tag(tag, tag_map)
  # ignore if tag is nil or empty
  return tag if tag.nil? || tag.empty?

  # ignore if tag is in the values of the map
  return tag if tag_map.values.include?(tag)

  tag_map.fetch(tag, "other: #{tag}")

end


require 'csv'
tag_cleanup_report = []

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

      new_tags = old_tags.map { |tag| map_tag(tag, tag_map) }
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


CSV.open("240806_multilingual_pages_tag_cleanup_report.csv", "wb", col_sep: ',', force_quotes: true) do |csv|
  csv << tag_cleanup_report.first.keys

  tag_cleanup_report.each do |page|
    csv << page.values
  end
end
