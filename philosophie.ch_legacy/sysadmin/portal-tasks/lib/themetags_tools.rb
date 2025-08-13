
## Get these two from topic.rb in the portal code
# enum group: [:logic, :language, :ethic, :history, :aesthetic, :administrative]
SUPPORTED_GROUPS = ["logic", "language", "ethic", "history", "aesthetic", "administrative", "badge_group"]
# enum interest_type: [:structural, :discipline, :focus]
SUPPORTED_INTEREST_TYPES = ["structural", "discipline", "focus", "badge"]

def _retrieve_page_slug(page)
  Alchemy::Engine.routes.url_helpers.show_page_path({
    locale: !page.language.default ? page.language_code : nil, urlname: page.urlname
  })
end

def get_themetag_url(themetag)
  page = themetag.find_alchemy_page()

  if page.nil?
    return ""
  else
    slug = _retrieve_page_slug(page)
    return "https://www.philosophie.ch#{slug}"
  end
end
