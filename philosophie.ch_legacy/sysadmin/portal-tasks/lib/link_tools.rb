require_relative 'utils'


def retrieve_page_slug(page)
  Alchemy::Engine.routes.url_helpers.show_page_path({
    locale: !page.language.default ? page.language_code : nil, urlname: page.urlname
  })
end

def page_full_path(page)
  "https://www.philosophie.ch#{retrieve_page_slug(page)}"
end

def relative_to_full_path(relative_path)
  "https://www.philosophie.ch#{relative_path}"
end

HTML_TAGS = ["href", "src", "action", "cite", "data", "poster", "a"]

def _process_link(link)
  truncate = link.length > 500 ? "#{data_process[0..500]}[TRUNCATED...]" : link
  return truncate
end

def _extract_links_from_text(text)
  result = []

  HTML_TAGS.each do |tag|
    result += text.scan(/#{tag}="([^"]*)"/).flatten.map { |link| {link: _process_link(link), tag: tag} }
  end

  return result

end


def _check_url_resolution(raw_url)
  begin

    url = ""
    unless raw_url.blank?
      if raw_url.start_with?("/")
        url = relative_to_full_path(raw_url)
      elsif raw_url.start_with?("http")
        url = raw_url
      else
        return {link: raw_url, status: "invalid", message: "URL '#{raw_url}' is not a valid URL"}
      end
    end

    if url.blank?
      return {link: url, status: "blank", message: 'URL is blank'}
    end

    response = fetch_with_redirect(url)

    unless response.is_a?(Net::HTTPSuccess)
      return {link: raw_url, status: "broken", message: "URL '#{url}' returned status code '#{response.code}'"}
    end

    return {link: raw_url, status: "functioning", message: ""}

  rescue => e
    return {link: raw_url, status: "broken", message: "URL '#{url}' could not be resolved: #{e.class}; #{e.message}; BACKTRACE: #{e.backtrace.join(" ::: ")}"}

  end

end

def get_all_links(page)

  result = []
  elements = Alchemy::Element.where(page_id: page.id)

  elements.each do |element|
    Alchemy::Content.where(element_id: element.id).each do |content|

      case content.essence

      when Alchemy::EssenceRichtext
        text = content.essence.body
        unless text.blank?
          extracted_links = _extract_links_from_text(text).filter(&:present?).flatten

          extracted_links.each do |extracted_link|
            link_report = {
              link: extracted_link[:link],
              tag: extracted_link[:tag],
              element_id: element.id,
              element_type: content&.essence_type
            }
            result << link_report
          end
        end

      when Alchemy::EssenceHtml
        text = content.essence.source
        unless text.blank?
          extracted_links = _extract_links_from_text(text).filter(&:present?).flatten

          extracted_links.each do |extracted_link|
            link_report = {
              link: extracted_link[:link],
              tag: extracted_link[:tag],
              element_id: element.id,
              element_type: content&.essence_type

            }
            result << link_report
          end
        end

      when Alchemy::EssenceLink
        link_s = content.essence.link
        unless link_s.blank?
          extracted_link = relative_to_full_path(link_s)
          result << {
            link: extracted_link,
            tag: "link",
            element_id: element.id,
            element_type: content&.essence_type
          }
        end
      else
        next []
      end
    end
  end

  return result

end


def get_all_links_with_report(page)
  result = []

  original_verbose = $VERBOSE
  $VERBOSE = nil

  elements = Alchemy::Element.where(page_id: page.id)

  elements.each do |element|
    Alchemy::Content.where(element_id: element.id).each do |content|

      case content.essence

      when Alchemy::EssenceRichtext
        text = content.essence.body
        unless text.blank?
          extracted_links = _extract_links_from_text(text).filter(&:present?).flatten

          extracted_links.each do |extracted_link|
            link_report = _check_url_resolution(extracted_link)
            result << link_report
          end
        end

      when Alchemy::EssenceHtml
        text = content.essence.source
        unless text.blank?
          extracted_links = _extract_links_from_text(text).filter(&:present?).flatten

          extracted_links.each do |extracted_link|
            link_report = _check_url_resolution(extracted_link)
            result << link_report
          end
        end

      when Alchemy::EssenceLink
        link_s = content.essence.link
        unless link_s.blank?
          extracted_link = relative_to_full_path(link_s)
          link_report_raw = _check_url_resolution(extracted_link)
          result << {
            link: extracted_link,
            status: link_report_raw[:status],
            message: link_report_raw[:message]
          }
        end
      else
        next []
      end
    end
  end


  $VERBOSE = original_verbose
  return result

end
