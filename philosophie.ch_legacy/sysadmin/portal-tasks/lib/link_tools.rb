def retrieve_page_slug(page)
  Alchemy::Engine.routes.url_helpers.show_page_path({
    locale: !page.language.default ? page.language_code : nil, urlname: page.urlname
  })
end

def page_full_path(page)
  "https://www.philosophie.ch#{retrieve_page_slug(page)}"
end


def _extract_links_from_text(text)
  href_links = text.scan(/href="([^"]*)"/).flatten
  src_links = text.scan(/src="([^"]*)"/).flatten
  action_links = text.scan(/action="([^"]*)"/).flatten
  cite_links = text.scan(/cite="([^"]*)"/).flatten
  data_links = text.scan(/data="([^"]*)"/).flatten
  poster_links = text.scan(/poster="([^"]*)"/).flatten

  return href_links + src_links + action_links + cite_links + data_links + poster_links
end

def get_all_links(page)
  result = []

  original_verbose = $VERBOSE
  $VERBOSE = nil
  page.elements.each do |element|
    element.contents.each do |content|
      case content.essence
      when Alchemy::EssenceRichtext
        text = content.essence.body
        unless text.blank?
          result << _extract_links_from_text(text)
        end
      when Alchemy::EssenceHtml
        text = content.essence.source
        unless text.blank?
          result << _extract_links_from_text(text)
        end
      when Alchemy::EssenceLink
        link_s = content.essence.link
        unless link_s.blank?
          result << content.essence.link
        end
      else
        next []
      end
    end
  end

  $VERBOSE = original_verbose
  return result.filter(&:present?).flatten

end
