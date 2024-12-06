
def tag_columns_to_array(row)
  col_tag_page_type = row.fetch(:tag_page_type, '')
  tag_page_type = col_tag_page_type.empty? ? [] : ["page type: #{col_tag_page_type}"]

  col_tag_media_1 = row.fetch(:tag_media_1, '')
  tag_media_1 = col_tag_media_1.empty? ? [] : ["media 1: #{col_tag_media_1}"]

  col_tag_media_2 = row.fetch(:tag_media_2, '')
  tag_media_2 = col_tag_media_2.empty? ? [] : ["media 2: #{col_tag_media_2}"]

  col_tag_language = row.fetch(:tag_language, '')
  tag_language = col_tag_language.empty? ? [] : ["language: #{col_tag_language}"]

  col_tag_university = row.fetch(:tag_university, '')
  tag_university = col_tag_university.empty? ? [] : ["university: #{col_tag_university}"]

  col_tag_canton = row.fetch(:tag_canton, '')
  tag_canton = col_tag_canton.empty? ? [] : ["canton: #{col_tag_canton}"]

  col_tag_special_content_1 = row.fetch(:tag_special_content_1, '')
  tag_special_content_1 = col_tag_special_content_1.empty? ? [] : ["special content 1: #{col_tag_special_content_1}"]

  col_tag_special_content_2 = row.fetch(:tag_special_content_2, '')
  tag_special_content_2 = col_tag_special_content_2.empty? ? [] : ["special content 2: #{col_tag_special_content_2}"]

  col_tag_references = row.fetch(:tag_references, '')
  tag_references = col_tag_references.empty? ? [] : ["references?: #{col_tag_references}"]

  col_tag_footnotes = row.fetch(:tag_footnotes, '')
  tag_footnotes = col_tag_footnotes.empty? ? [] : ["footnotes?: #{col_tag_footnotes}"]

  col_tag_others = row.fetch(:tag_others, '')
  tag_others = col_tag_others.empty? ? [] : col_tag_others.split(',').map(&:strip)

  return tag_page_type + tag_media_1 + tag_media_2 + tag_language + tag_university + tag_canton + tag_special_content_1 + tag_special_content_2 + tag_references + tag_footnotes + tag_others
end


def tag_array_to_columns(tag_names)
  tag_page_type = tag_names.find { |tag| tag.start_with?('page type: ') }&.gsub('page type: ', '') || ''
  tag_media_1 = tag_names.find { |tag| tag.start_with?('media 1: ') }&.gsub('media 1: ', '') || ''
  tag_media_2 = tag_names.find { |tag| tag.start_with?('media 2: ') }&.gsub('media 2: ', '') || ''
  tag_language = tag_names.find { |tag| tag.start_with?('language: ') }&.gsub('language: ', '') || ''
  tag_university = tag_names.find { |tag| tag.start_with?('university: ') }&.gsub('university: ', '') || ''
  tag_canton = tag_names.find { |tag| tag.start_with?('canton: ') }&.gsub('canton: ', '') || ''
  tag_special_content_1 = tag_names.find { |tag| tag.start_with?('special content 1: ') }&.gsub('special content 1: ', '') || ''
  tag_special_content_2 = tag_names.find { |tag| tag.start_with?('special content 2: ') }&.gsub('special content 2: ', '') || ''
  tag_references = tag_names.find { |tag| tag.start_with?('references?: ') }&.gsub('references? ', '') || ''
  tag_footnotes = tag_names.find { |tag| tag.start_with?('footnotes?:') }&.gsub('footnotes? ', '') || ''
  tag_others_arr = tag_names.select { |tag| !tag.start_with?('page type: ', 'media 1: ', 'media 2: ', 'language: ', 'university: ', 'canton: ', 'special content 1: ', 'special content 2: ', 'references? ', 'footnotes? ') }
  tag_others = tag_others_arr.blank? ? '' : tag_others_arr.join(', ')


  return {
    tag_page_type: tag_page_type,
    tag_media_1: tag_media_1,
    tag_media_2: tag_media_2,
    tag_language: tag_language,
    tag_university: tag_university,
    tag_canton: tag_canton,
    tag_special_content_1: tag_special_content_1,
    tag_special_content_2: tag_special_content_2,
    tag_references: tag_references,
    tag_footnotes: tag_footnotes,
    tag_others: tag_others
  }
end


def get_intro_block_image(page)
  intro_elements = ['intro', 'event_intro', 'call_for_papers_intro', 'job_intro']

  page.elements.each do |element|
    next unless intro_elements.include?(element.name)

    has_intro_picture = element.contents&.any? { |content| content.essence.is_a?(Alchemy::EssencePicture) }

    if has_intro_picture
      picture = element.contents&.find { |content| content.essence.is_a?(Alchemy::EssencePicture) }&.essence&.picture&.image_file_name
      return picture.blank? ? '' : picture
    end
  end

  ""
end


def get_intro_block_image_raw_filename(page)
  intro_elements = ['intro', 'event_intro', 'call_for_papers_intro', 'job_intro']

  page.elements.each do |element|
    next unless intro_elements.include?(element.name)

    has_intro_picture = element.contents&.any? { |content| content.essence.is_a?(Alchemy::EssencePicture) }

    if has_intro_picture
      picture = element.contents&.find { |content| content.essence.is_a?(Alchemy::EssencePicture) }&.essence&.picture&.image_file_uid
      return picture.blank? ? '' : picture
    end
  end

  ""
end


def update_intro_block_image(page, image_file_name)
  result = {
    status: 'not started',
    error_message: '',
    error_trace: '',
  }
  begin

    if image_file_name.blank? || image_file_name.nil? || image_file_name.empty? || image_file_name.strip == ''
      Rails.logger.info("Image file name is empty. Skipping...")
      # Just ignore if image_file_name is empty
      result[:status] = 'success'
      return result
    end

    intro_elements = ['intro', 'event_intro', 'call_for_papers_intro', 'job_intro']

    # Find the picture with the given image_file_name
    new_picture = Alchemy::Picture.find_by(image_file_name: image_file_name)

    if new_picture.nil?
      Rails.logger.error("Picture with image_file_name '#{image_file_name}' not found. Skipping...")
      result[:status] = 'error'
      result[:error_message] = "Picture with image_file_name '#{image_file_name}' not found"
      result[:error_trace] = "pages_tasks.rb::update_intro_block_image"
      return result
    end

    page.elements.each do |element|
      next unless intro_elements.include?(element.name)

      has_intro_picture = element.contents&.any? { |content| content.essence.is_a?(Alchemy::EssencePicture) }

      if has_intro_picture
        Rails.logger.info("Updating intro block image...")
        content = element.contents.find { |content| content.essence.is_a?(Alchemy::EssencePicture) }
        content.essence.update(picture: new_picture)
        page.publish!
        result[:status] = 'success'
        Rails.logger.info("Intro block image updated successfully")
        return result
      end
    end

    result[:status] = 'error'
    result[:error_message] = "No intro picture found"
    result[:error_trace] = "pages_tasks.rb::update_intro_block_image"
    return result

  rescue => e
    result[:status] = 'unhandled error'
    result[:error_message] = "#{e.class} :: #{e.message}"
    result[:error_trace] = e.backtrace.join("\n")
    return result
  end
end


def get_audio_blocks_file_names(page)
  audio_blocks = page&.elements&.select { |element| element.name == 'audio_block' }

  audio_files = audio_blocks&.flat_map do |audio_block|
    audio_block.contents&.map do |content|
      essence = content.essence
      essence.respond_to?(:attachment) ? essence.attachment&.file_name : nil
    end
  end

  return audio_files&.compact&.blank? ? "" : audio_files.compact.join(', ')
end


def get_video_blocks_file_names(page)
  video_blocks = page&.elements&.select { |element| element.name == 'video_block' }

  video_files = video_blocks&.flat_map do |video_block|
    video_block.contents&.map do |content|
      essence = content.essence
      essence.respond_to?(:attachment) ? essence.attachment&.file_name : nil
    end
  end

  return video_files&.compact&.blank? ? "" : video_files.compact.join(', ')
end


def get_pdf_blocks_file_names(page)
  pdf_blocks = page&.elements&.select { |element| element.name == 'pdf_block' }

  pdf_files = pdf_blocks&.flat_map do |pdf_block|
    pdf_block.contents&.map do |content|
      essence = content.essence
      essence.respond_to?(:attachment) ? essence.attachment&.file_name : nil
    end
  end

  return pdf_files&.compact&.blank? ? "" : pdf_files.compact.join(', ')
end


def get_picture_blocks_file_names(page)
  picture_block_elements = page&.elements&.select { |element| element.name == 'picture_block' }

  picture_files = picture_block_elements&.flat_map do |picture_block|
    picture_block.contents&.map do |content|
      essence = content.essence
      essence.respond_to?(:picture) ? essence.picture&.image_file_name : nil
    end
  end

  return picture_files&.compact&.blank? ? "" : picture_files.compact.join(', ')
end


def get_assigned_authors(page)
  page_is_article = page.page_layout == "article" ? true : false
  page_is_event = page.page_layout == "event" ? true : false

  unless page_is_article || page_is_event
    return ""
  end

  intro_element = page.elements.find { |element| element.name.include?('intro') }; nil
  creator_content = intro_element&.content_by_name(:creator); nil
  creator_essence = creator_content&.essence

  unless creator_essence
    return ""
  end

  return creator_essence.alchemy_users.map(&:login).join(', ')

end


def update_assigned_authors(page, authors_str)

  Rails.logger.info("Updating assigned authors...")
  page_is_article = page.page_layout == "article" ? true : false
  page_is_event = page.page_layout == "event" ? true : false

  unless page_is_article || page_is_event
    Rails.logger.debug("\tPage is not an article or event. Skipping...")
    return {
      status: 'success',
      error_message: '',
      error_trace: '',
    }
  end

  result = {
    status: 'not started',
    error_message: '',
    error_trace: '',
  }

  begin
    Rails.logger.debug("\tPage is an article or event. Proceeding...")

    intro_element = page.elements.find { |element| element.name.include?('intro') }
    creator_essence = intro_element&.content_by_name(:creator)&.essence

    unless creator_essence
      Rails.logger.error("\tCreator essence not found. Skipping...")
      result[:status] = 'error'
      result[:error_message] = "Creator essence not found"
      result[:error_trace] = "pages_tasks.rb::update_assigned_authors"
      return result
    end

    author_list = authors_str.to_s.split(',').map(&:strip)
    users = []

    flag = true
    user_error_message = "Users with the following logins not found: "
    for author in author_list
      user = Alchemy::User.find_by(login: author)

      if user.nil?
        user_error_message += "'#{author}', "
        flag = false
      else
        users << user
      end
    end

    if !flag
      Rails.logger.error("\tUsers with the following logins not found: #{user_error_message}")
      result[:status] = 'error'
      user_error_message = user_error_message[0..-3] unless user_error_message.nil? || user_error_message.empty?
      result[:error_message] = user_error_message unless user_error_message.nil? || user_error_message.empty?
      result[:error_trace] = "pages_tasks.rb::update_assigned_authors"
      return result
    end

    creator_essence.alchemy_users = users.uniq.compact
    creator_essence.save!

    Rails.logger.debug("\tAssigned authors updated successfully")
    result[:status] = 'success'
    return result

  rescue => e
    Rails.logger.error("\tError while updating assigned authors: #{e.message}")
    result[:status] = 'unhandled error'
    result[:error_message] = "#{e.class} :: #{e.message}"
    result[:error_trace] = e.backtrace.join("\n")
    return result
  end
end


def has_html_header_tags(page)
  has_html_header_tags = false

  page.elements.each do |element|

    case element.name
    when 'intro', 'text_block', 'text_and_picture'
      richtext_contents = element.contents.where(name: ['pre_headline', 'lead_text', 'text'])
      richtext_contents.each do |content|
        essence = content.essence

        body = essence.body? ? essence.body : ""

        # Regex to match any header tag from h1 to h6, even if multi-line
        has_html_header_tags = body.match?(/<h[1-6][^>]*>.*?<\/h[1-6]>/m)

        if has_html_header_tags
          return "yes"
        end
      end

    when 'aside_column'
      # This one has nested elements
      element.elements.each do |nested_element|
        nested_element.contents.each do |content|
          essence = content.essence

          body = essence.body? ? essence.body : ""

          # Regex to match any header tag from h1 to h6, even if multi-line
          has_html_header_tags = body.match?(/<h[1-6][^>]*>.*?<\/h[1-6]>/m)

          if has_html_header_tags
            return "yes"
          end
        end
      end
    end
  end

  return has_html_header_tags ? "yes" : ""

end

def themetag_names_by_interest_type(topics, interest_type)
  return topics.filter { |topic| topic.interest_type == interest_type }.map(&:name).join(", ")
end

def get_themetags(page)

  themetags_hashmap = {
    discipline: "",
    focus: "",
    structural: "",
  }

  intro_element = page.elements.find { |element| element.name.include?('intro') }
  if intro_element
    topic_content = intro_element.contents.find { |content| content.name == 'topics' }
    topics = topic_content&.essence&.topics&.uniq || []

    themetags_hashmap[:discipline] = themetag_names_by_interest_type(topics, "discipline")
    themetags_hashmap[:focus] = themetag_names_by_interest_type(topics, "focus")
    themetags_hashmap[:structural] = themetag_names_by_interest_type(topics, "structural")
  end

  return themetags_hashmap

end

class ThemetagNotFoundError < StandardError; end

def get_themetag_by_name(name)
  # nil name allows us to effectively delete the themetag in the set function
  if name.blank? || name.nil? || name.empty?
    return nil
  end

  found = Topic.find_by('LOWER(name) = ?', name.downcase.strip)

  # if we do pass a name however, we expect to find the themetag
  if found.nil? || found.blank?
    raise ThemetagNotFoundError, "Themetag/Topic with name '#{name}' not found."
  end

  return found
end

def set_themetags(page, themetag_names)
  report = {
    status: 'not started',
    error_message: '',
    error_trace: '',
  }

  begin
    intro_element = page.elements.find { |element| element.name.include?('intro') }
    if intro_element
      topic_content = intro_element.contents.find { |content| content.name == 'topics' }
      themetags = themetag_names.map { |name| get_themetag_by_name(name) }.compact.uniq
      update_response = topic_content.essence.update(topics: themetags)
    end

    if !update_response
      report[:status] = 'error'
      report[:error_message] = "Unknown error while updating themetags, 'update' method returned `false`. Check logs for more details."
      report[:error_trace] = "pages_tools.rb::set_themetags"
    else
      report[:status] = 'success'
    end

  rescue => e
    report[:status] = 'error'
    report[:error_message] = "#{e.class} :: #{e.message}"
    report[:error_trace] = e.backtrace.join("\n")

  ensure
    return report
  end

end


def retrieve_page_slug(page)
  Alchemy::Engine.routes.url_helpers.show_page_path({
    locale: !page.language.default ? page.language_code : nil, urlname: page.urlname
  })
end


def get_created_at(page)
  page.created_at.strftime('%Y-%m-%d')
end

def parse_created_at(date)
  Date.parse(date.to_s)
end

def get_references_bib_keys(page)
  references = page.find_elements.find_by(name: "references")
  return "" unless references

  result = references.contents.each_with_object([]) do |c, arr|
    arr << c.essence.body if c.name == "bibkeys"
  end

  result.join(", ").strip.split(", ").uniq.join(", ")
end


def set_references_bib_keys(page, bibkeys)
  result = {
    status: 'not started',
    error_message: '',
    error_trace: '',
  }
  begin
    references = page.find_elements.find_by(name: "references")

    unless references
      Rails.logger.warn("References element not found. Skipping...")
      result[:status] = 'success'
      return result
    end

    bibkeys_content = references.contents.find_by(name: "bibkeys")

    unless bibkeys_content
      Rails.logger.error("Bibkeys content not found in the references element! How is this possible?. Skipping...")
      result[:status] = 'error'
      result[:error_message] = "Bibkeys content not found in the references element! How is this possible?"
      result[:error_trace] = "pages_tasks.rb::set_references_bib_keys"
      return result
    end

    bibkeys_content.essence.update(body: bibkeys)

    Rails.logger.info("References bibkeys updated successfully")

    result[:status] = 'success'
    return result

  rescue => e
    result[:status] = 'unhandled error'
    result[:error_message] = "#{e.class} :: #{e.message}"
    result[:error_trace] = e.backtrace.join("\n")
    return result
  end
end


def get_all_attachments_with_pages()
  return Alchemy::Attachment.all.filter { |attachment| attachment.pages != [] }
end


def get_attachment_links(page, all_attachments_with_pages)
  result = []

  # 1. Look in the Richtext essences
  attachment_links = page.elements.flat_map do |element|
    element.contents.flat_map do |content|
      next [] unless content.essence.is_a?(Alchemy::EssenceRichtext) && content.essence.body

      content.essence.body.scan(/href="([^"]*attachments[^"]*)"/).flatten
    end
  end

  attachment_links.each do |link|
    # Remove everything from the link except the number after 'attachments/'
    # This is the attachment ID
    # Example: href="/attachments/1234/show" -> 1234
    # Example 2: href="/attachments/1234/download" -> 1234
    id = link.match(/\/attachment\/(\d+)\//)&.captures&.first

    file_name = Alchemy::Attachment.find_by(id: id)&.file_name

    unless file_name
      result << "Attachment with ID '#{id}' in link '#{link}' not found"
    end

    result << file_name
  end

  # 2. Look in the Embed elements of the page
  html_embed_elements = page.elements.flat_map do |element|
    element.contents.flat_map do |content|
      next [] unless content.essence.is_a?(Alchemy::EssenceHtml) && content.essence.source

      content.essence.source.scan(/src="([^"]*attachments[^"]*)"/).flatten
    end
  end

  html_embed_elements.each do |link|
    # Remove everything from the link except the number after 'attachments/'
    # This is the attachment ID
    # Example: src="/attachments/1234/show" -> 1234
    # Example 2: src="/attachments/1234/download" -> 1234
    id = link.match(/\/attachment\/(\d+)\//)&.captures&.first

    file_name = Alchemy::Attachment.find_by(id: id)&.file_name

    unless file_name
      result << "Attachment with ID '#{id}' in link '#{link}' not found"
    end

    result << file_name
  end

  # 3. Look for all attachments, and return those whose 'pages' include the current page
  page_attachments = all_attachments_with_pages.filter { |attachment| attachment.pages.map(&:id).include?(page.id) }.map(&:file_name)

  result << page_attachments


  return result.join(", ")

end


def get_pre_headline(page)
  page.elements.find_by(name: "intro")&.content_by_name(:pre_headline)&.essence&.body || ""
end


def set_pre_headline(page, pre_headline)
  page.elements.find_by(name: "intro")&.content_by_name(:pre_headline)&.essence&.update({body: pre_headline})
end


def get_lead_text(page)
  page.elements.find_by(name: "intro")&.content_by_name(:lead_text)&.essence&.body || ""
end


def set_lead_text(page, lead_text)
  page.elements.find_by(name: "intro")&.content_by_name(:lead_text)&.essence&.update({body: lead_text})
end


def get_embed_blocks(page)
  page.elements.map { |element| element if element.name == "embed" }.compact
end


def read_raw_html(filename)
  File.read(filename)
end


def dltc_set_embed_block(page, content)

  embed_blocks = get_embed_blocks(page)

  unless embed_blocks.blank? || embed_blocks.size == 0
    embed_blocks.each do |embed_block|
      embed_block.destroy!
    end
  end

  # WARNING! page reloads! any uncommited changes are flushed
  # Better to execute this function independently of the others
  page.reload

  page.elements.create(name: "embed")

  embed_block = get_embed_blocks(page).first

  embed_block.contents.first.essence.update({source: content})

  page.save!
  page.publish!

end


def get_references_blocks(page)
  page.elements.map { |element| element if element.name == "references" }.compact
end

def set_references_block(page, references_url, further_references_url)
  # Same as with the embed block, we delete all references blocks and create a new one

  references_blocks = get_references_blocks(page)

  unless references_blocks.blank? || references_blocks.size == 0
    references_blocks.each do |references_block|
      references_block.destroy!
    end
  end

  # WARNING! page reloads! any uncommited changes are flushed
  # Better to execute this function independently of the others
  page.reload

  page.elements.create(name: "references")

  references_block = get_references_blocks(page).first

  references_block.content_by_name("references_asset_url").essence.update({link: references_url})

  references_block.content_by_name("further_references_asset_url").essence.update({link: further_references_url})

  page.save!
  page.publish!

end

def get_references_urls(page)
  urls = {
    references_url: "",
    further_references_url: ""
  }
  references_blocks = get_references_blocks(page)

  unless references_blocks.blank? || references_blocks.size == 0
    references_block = references_blocks.first
    references_url = references_block.content_by_name("references_asset_url").essence.link
    further_references_url = references_block.content_by_name("further_references_asset_url").essence.link

    urls[:references_url] = references_url
    urls[:further_references_url] = further_references_url
  end

  return urls

end


def get_article_metadata_element(page)
  # This is a nested element inside the aside_column element
  aside_column = Alchemy::Element.where(parent_element_id: nil, page_id: page.id, name: "aside_column").first

  unless aside_column.blank?
    article_metadata = aside_column.nested_elements.select { |nested_element| nested_element.name == "article_metadata" }.first; nil
    unless article_metadata.blank?
      return article_metadata
    end
  end
  return nil
end

def get_authors_orcids(page)
    # Find the authors
    authors = page.elements.find_by(name: "intro")&.content_by_name(:creator)&.essence&.alchemy_users&.uniq&.compact || []

    if authors.blank? || authors.size == 0
      orcids_string = ""
    else
      # Extract the ORCIDs from the users
      orcids_list = authors.map { |user| user.profile.other_personal_information }.compact.map(&:strip).reject(&:empty?)
      orcids_string = orcids_list.join(", ")
    end

    return orcids_string
end

def set_article_metadata(page, how_to_cite, pure_html_asset_full_url, pure_pdf_asset_full_url, doi, orcids)
  # pure_html_asset_full_url and pure_pdf_asset_full_url are meant to be full URLs
  # doi is EssenceText
  # how_to_cite is EssenceRichtext
  # orcids is EssenceText, meant to be comma-separated, coming from the authors of the page, which we need to extract

  report = {
    status: 'not started',
    error_message: '',
    error_trace: '',
  }

  begin
    try_article_metadata = get_article_metadata_element(page)

    if try_article_metadata.blank?
      # create it
      aside_column = Alchemy::Element.where(parent_element_id: nil, page_id: page.id, name: "aside_column").first

      unless aside_column.blank?
        aside_column.nested_elements.create(name: "article_metadata", page_id: page.id)
      else
        # return error
        report[:status] = 'error'
        report[:error_message] = "Aside column element not found"
        report[:error_trace] = "pages_tasks.rb::set_article_metadata"
      end
    end

    article_metadata = get_article_metadata_element(page)

    article_metadata.contents.find_by(name: "doi").essence.update({body: doi})

    article_metadata.contents.find_by(name: "how_to_cite").essence.update({body: how_to_cite})

    article_metadata.contents.find_by(name: "pure_html_url").essence.update({body: pure_html_asset_full_url})

    article_metadata.contents.find_by(name: "pure_pdf_url").essence.update({body: pure_pdf_asset_full_url})

    article_metadata.contents.find_by(name: "orcids").essence.update({body: orcids})

    page.reload
    page.save!
    page.publish!

    report[:status] = 'success'

    return report

  rescue => e
    Rails.logger.error("Error while setting article metadata: #{e.message}")
    report[:status] = 'error'
    report[:error_message] = "#{e.class} :: #{e.message}"
    report[:error_trace] = e.backtrace.join(" ::: ")

    return report
  end
end

def get_doi(article_metadata_element)
  article_metadata_element.contents.find_by(name: "doi").essence.body
end

def get_how_to_cite(article_metadata_element)
  article_metadata_element.contents.find_by(name: "how_to_cite").essence.body
end

def get_pure_html_asset(article_metadata_element, pure_links_base_url)
  full_url = article_metadata_element.contents.find_by(name: "pure_html_url").essence.body
  return full_url.gsub(pure_links_base_url, "") if full_url.start_with?(pure_links_base_url)
end

def get_pure_pdf_asset(article_metadata_element, pure_links_base_url)
  full_url = article_metadata_element.contents.find_by(name: "pure_pdf_url").essence.body
  return full_url.gsub(pure_links_base_url, "") if full_url.start_with?(pure_links_base_url)
end
