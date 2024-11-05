
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
    result[:error_message] = e.message
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

  intro_element = page.elements.find { |element| element.name.include?('intro') }
  creator_essence = intro_element&.content_by_name(:creator)&.essence

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
    result[:error_message] = e.message
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


def get_themetags(page)
  intro_element = page.elements.find { |element| element.name.include?('intro') }
  if intro_element
    topic_content = intro_element.contents.find { |content| content.name == 'topics' }
    topics = topic_content&.essence&.topics&.map(&:name).uniq.join(', ')
    return topics.blank? ? "" : topics
  end
  return ""
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
      Rails.logger.error("References element not found. Skipping...")
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
    result[:error_message] = e.message
    result[:error_trace] = e.backtrace.join("\n")
    return result
  end
end


def get_attachment_links(page)
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


  return result.join(", ")

end
