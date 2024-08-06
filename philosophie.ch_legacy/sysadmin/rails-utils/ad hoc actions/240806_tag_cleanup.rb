# Not executed yet

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
def map_tag(tag, tag_map)
  tag_map.fetch(tag, "other: #{tag}")
end
