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

def _extract_links_from_text(text)
  href_links = text.scan(/href="([^"]*)"/).flatten
  src_links = text.scan(/src="([^"]*)"/).flatten
  action_links = text.scan(/action="([^"]*)"/).flatten
  cite_links = text.scan(/cite="([^"]*)"/).flatten
  data_links = text.scan(/data="([^"]*)"/).flatten
  poster_links = text.scan(/poster="([^"]*)"/).flatten

  return href_links + src_links + action_links + cite_links + data_links + poster_links
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

  original_verbose = $VERBOSE
  $VERBOSE = nil

  page.elements.each do |element|
    element.contents.each do |content|

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
