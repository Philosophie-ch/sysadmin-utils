require_relative 'utils'
require_relative 'tag_tools'

# Tag handling functions (tag_columns_to_array, tag_array_to_columns)
# are now in lib/tag_tools.rb for sharing between pages and publications

def forced_intro_element(page)
  intro_element = page.intro_element

  if intro_element.blank?
    forced_intro_element = page.elements.filter { |element| element.name.include?('intro') }

    if forced_intro_element.blank?
      return nil
    end

    return forced_intro_element.first

  else
    return intro_element
  end

end



############
# Assets related functions
############

ELEMENT_NAME_AND_URL_FIELD_MAP = {
  "intro": "picture_asset_url",
  "audio_block": "audio_asset_url",
  "video_block": "video_asset_url",
  "pdf_block": "pdf_asset_url",
  "picture_block": "picture_asset_url",
  "text_and_picture": "picture_asset_url",
  "box": "picture_asset_url",
}

ELEMENTS_NOT_IN_ASIDE_COLUMN = ['intro', 'note_intro']

UNIQUE_ELEMENTS = ['intro', 'note_intro']

ELEMENTS_TO_SKIP_ON_SET = ['box']

class ElementNameNotRegistered < StandardError; end
class ElementNameUrlFieldCombinationError < StandardError; end

def validate_element_name_and_url_field_combination(element_name, url_field)

  unless ELEMENT_NAME_AND_URL_FIELD_MAP.keys.include?(element_name.to_sym)
    raise ElementNameNotRegistered, "Element name '#{element_name}' is not registered"
  end

  unless ELEMENT_NAME_AND_URL_FIELD_MAP[element_name.to_sym] == url_field
    raise ElementNameUrlFieldCombinationError, "'#{url_field}' is not the registered URL field for element '#{element_name}'"
  end

end


def _get_asset_blocks(page, element_name, url_field_name)
    asset_blocks_main_body = []
    asset_blocks_aside_column = []

    if element_name != 'box'

      if element_name == 'intro'

        intro_element = forced_intro_element(page)
        asset_blocks_main_body = intro_element ? [intro_element] : []

      else
        asset_blocks_main_body = page&.elements&.filter { |element| element.name == "#{element_name}" }

      end


      unless ELEMENTS_NOT_IN_ASIDE_COLUMN.include?(element_name)
        aside_column = Alchemy::Element.where(parent_element_id: nil, page_id: page.id, name: "aside_column").first

        unless aside_column.blank?
          asset_blocks_aside_column = aside_column.nested_elements&.filter { |element| element.name == "#{element_name}" }
        end
      end

    else
      # There's a 'boxes' element which has nested 'box', 'large_box', and 'xlarge_box' elements
      # Fortunately, we cannot have boxes in the aside column

      boxes_element = page&.elements&.find { |element| element.name == 'boxes' }

      unless boxes_element.blank?
        asset_blocks_main_body = boxes_element.nested_elements&.filter { |element| element.name == "box" || element.name == "large_box" || element.name == "xlarge_box" }
      end

    end

    asset_blocks = asset_blocks_main_body + asset_blocks_aside_column

    return asset_blocks
end


def get_asset_names(page, element_name, url_field_name)

  validate_element_name_and_url_field_combination(element_name, url_field_name)

  asset_blocks = _get_asset_blocks(page, element_name, url_field_name)

  asset_asset_urls = asset_blocks&.flat_map do |asset_block|
    essence = asset_block&.contents&.filter { |content| content.name == "#{url_field_name}" }&.first&.essence

    if essence
      if essence.body.blank?
        "empty"
      else
        essence.body
      end
    else
      "empty"
    end
  end

  unprocessed_urls = unprocess_asset_urls(asset_asset_urls)

  return unprocessed_urls

end

class AssetBlocksAndUrlsMismatch < StandardError; end

def _set_asset_blocks(page, asset_urls, element_name, url_field_name)
    # Checks both in the main body and in the aside column, in order
    # Main body's elements first, top to bottom, then aside column's elements, top to bottom
    asset_blocks = _get_asset_blocks(page, element_name, url_field_name)

    if asset_urls.length != asset_blocks.length
      raise AssetBlocksAndUrlsMismatch, "Number of #{element_name}s and number of URLs do not match. Found #{asset_blocks.length} #{element_name} blocks but #{asset_urls.length} URLs/asset names."
    end

    if asset_blocks == []
      return 'success'
    end

    asset_blocks.zip(asset_urls).each do |asset_block, asset_url|
      essence = asset_block&.contents&.filter { |content| content.name == "#{url_field_name}" }&.first&.essence
      if essence
        essence.update(body: asset_url)

      else
        if asset_block

          Rails.logger.warn("#{element_name} block: '#{url_field_name}' field not found for #{element_name} block. Creating...")
          new_essence_text = Alchemy::EssenceText.create(body: asset_url)
          asset_block.contents.create(
            name: url_field_name,
            essence: new_essence_text
          )
          asset_block.save!
        else
          Rails.logger.error("Asset block is nil while setting asset blocks for element '#{element_name}'. This should never happen.")
          return 'error'
        end
      end
    end

    page.save!
    page.publish!

    return 'success'
end


def set_asset_blocks(page, unprocessed_asset_urls, element_name, url_field_name)
  report = {
    status: 'not started',
    error_message: '',
    error_trace: '',
  }
  begin

    validate_element_name_and_url_field_combination(element_name, url_field_name)

    if UNIQUE_ELEMENTS.include?(element_name) && ["", nil].include?(unprocessed_asset_urls)
      asset_processed_urls = [""]
    else
      asset_processed_urls = process_asset_urls(unprocessed_asset_urls)
    end

    asset_urls_check = check_asset_urls_resolve(asset_processed_urls)

    if asset_urls_check[:status] != 'success'
      report[:status] = 'url error'
      report[:error_message] = asset_urls_check[:error_message]
      report[:error_trace] = asset_urls_check[:error_trace]
      return report
    end

    set_asset_blocks_response = _set_asset_blocks(page, asset_processed_urls, element_name, url_field_name)

    if set_asset_blocks_response == 'success'
      report[:status] = 'success'
      return report
    else
      report[:status] = 'error'
      report[:error_message] = "Unknown error while setting asset blocks. Check logs for more details."
      report[:error_trace] = "pages_tasks.rb::set_asset_blocks"
      return report
    end

  rescue => e
    report[:status] = 'unhandled error'
    report[:error_message] = "#{e.class} :: #{e.message}"
    report[:error_trace] = e.backtrace.join(" ::: ")
    return report
  end

end



############
# Intro pictures
############

class ImageFileUrlNotProvided < StandardError; end
def generate_picture_show_url(image_file_url)

  if image_file_url.blank? || image_file_url.nil?
    return nil
  end

  return "https://philosophie.ch#{image_file_url}"
end


def get_intro_image_show_url(page)
  intro_elements = ['intro', 'event_intro', 'call_for_papers_intro', 'job_intro']

  page.elements.each do |element|
    next unless intro_elements.include?(element.name)

    has_intro_picture = element.contents&.any? { |content| content.essence.is_a?(Alchemy::EssencePicture) }

    if has_intro_picture
      picture_image_file_url = element.contents&.find { |content| content.essence.is_a?(Alchemy::EssencePicture) }&.essence&.picture&.image_file&.url
      return picture_image_file_url.blank? ? '' : generate_picture_show_url(picture_image_file_url)
    end
  end

  ""

end

#deprecated
def get_intro_image_portal(page)
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

def get_intro_image_portal_raw_filename(page)
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

# deprecated
def update_intro_image_portal(page, image_file_name)
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

    intro_elements = ['intro', 'event_intro', 'call_for_papers_intro', 'job_intro', 'note_intro']

    # Find the picture with the given image_file_name
    new_picture = Alchemy::Picture.find_by(image_file_name: image_file_name)

    if new_picture.nil?
      Rails.logger.error("Picture with image_file_name '#{image_file_name}' not found. Skipping...")
      result[:status] = 'error'
      result[:error_message] = "Picture with image_file_name '#{image_file_name}' not found"
      result[:error_trace] = "pages_tasks.rb::update_intro_image_portal"
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
    result[:error_trace] = "pages_tasks.rb::update_intro_image_portal"
    return result

  rescue => e
    result[:status] = 'unhandled error'
    result[:error_message] = "#{e.class} :: #{e.message}"
    result[:error_trace] = e.backtrace.join(" ::: ")
    return result
  end
end


# Transfer portal-managed intro image to assets server
def transfer_intro_image(page)
  report = { status: 'not started', error_message: '', error_trace: '' }
  begin
    intro_elements = ['intro', 'event_intro', 'call_for_papers_intro', 'job_intro', 'note_intro']
    picture = nil
    essence_picture_content = nil

    page.elements.each do |element|
      next unless intro_elements.include?(element.name)
      content = element.contents&.find { |c| c.essence.is_a?(Alchemy::EssencePicture) }
      if content&.essence&.picture.present?
        picture = content.essence.picture
        essence_picture_content = content
        break
      end
    end

    unless picture
      report[:status] = 'error'
      report[:error_message] = "Page '#{page.urlname}' has no intro picture to transfer"
      report[:error_trace] = "page_tools.rb::transfer_intro_image"
      return report
    end

    source_path = picture.image_file.path

    result = ImageCompressor.compress(source_path, candidate_threshold: "1KB")
    begin
      remote_path = "#{page.urlname}.webp"
      uploaded_path = FilebrowserClient.upload(result.webp_path, remote_path)

      intro_element = forced_intro_element(page)
      url_content = intro_element.contents.find { |c| c.name == "picture_asset_url" }
      if url_content&.essence
        url_content.essence.update!(body: uploaded_path)
      else
        new_essence = Alchemy::EssenceText.create!(body: uploaded_path)
        intro_element.contents.create!(name: "picture_asset_url", essence: new_essence)
      end

      picture_id = picture.id
      Alchemy::EssencePicture.where(picture_id: picture_id).update_all(picture_id: nil)
      picture.destroy!

      page.publish!

      report[:status] = 'success'
    ensure
      result.cleanup!
    end

    report
  rescue => e
    report[:status] = 'error'
    report[:error_message] = "#{e.class} :: #{e.message}"
    report[:error_trace] = e.backtrace.join(" ::: ")
    report
  end
end


############
# Portal assets
############

class AttachmentIDNotProvided < StandardError; end
def generate_attachment_download_url(attachment_id)

  if attachment_id.blank? || attachment_id.nil?
    raise AttachmentIDNotProvided, "Attachment ID not provided"
  end

  return "https://philosophie.ch/attachment/#{attachment_id}/download"
end


VALID_ASSET_TYPES = ['audio', 'video', 'pdf']
class InvalidAssetType < StandardError; end
class InvalidPage < StandardError; end
def get_media_blocks_download_urls(page, asset_type)

  unless VALID_ASSET_TYPES.include?(asset_type)
    raise InvalidAssetType, "Invalid asset type: '#{asset_type}'. Expected one of: #{VALID_ASSET_TYPES.map { |at| "'#{at}'" }.join(', ')}"
  end

  unless page
    raise InvalidPage, "Page not found"
  end

  block_name = "#{asset_type}_block"

  blocks = page&.elements&.filter { |element| element.name == block_name }

  files = blocks&.flat_map do |block|
    essences_with_attachment = block.contents&.filter { |content| content.essence.respond_to?(:attachment) }.map(&:essence)

    essences_with_attachment&.map do |essence|
      essence.attachment&.id ? generate_attachment_download_url(essence.attachment.id) : nil
    end

  end

  return files&.compact&.blank? ? "" : files.compact.join(', ')
end


VALID_ELEMENT_NAMES = ['picture_block', 'text_and_picture']
class InvalidElementName < StandardError; end
def get_picture_blocks_show_links(page, element_name)

  unless page
    raise InvalidPage, "Page not found"
  end

  unless VALID_ELEMENT_NAMES.include?(element_name)
    raise InvalidElementName, "Invalid element name: '#{element_name}'. Expected one of: #{VALID_ELEMENT_NAMES.map { |en| "'#{en}'" }.join(', ')}"
  end

  elements = page&.elements&.filter { |element| element.name == element_name }

  files = elements&.flat_map do |element|
    element.contents&.map do |content|
      essence = content.essence
      essence.respond_to?(:picture) ? generate_picture_show_url(essence.picture&.image_file&.url) : nil
    end
  end

  return files&.compact&.blank? ? "" : files.compact.join(', ')

end



#deprecated
def get_audio_blocks_file_names(page)
  audio_blocks = page&.elements&.filter { |element| element.name == 'audio_block' }

  audio_files = audio_blocks&.flat_map do |audio_block|
    audio_block.contents&.map do |content|
      essence = content.essence
      essence.respond_to?(:attachment) ? essence.attachment&.file_name : nil
    end
  end

  return audio_files&.compact&.blank? ? "" : audio_files.compact.join(', ')
end

#deprecated
def get_video_blocks_file_names(page)
  video_blocks = page&.elements&.filter { |element| element.name == 'video_block' }

  video_files = video_blocks&.flat_map do |video_block|
    video_block.contents&.map do |content|
      essence = content.essence
      essence.respond_to?(:attachment) ? essence.attachment&.file_name : nil
    end
  end

  return video_files&.compact&.blank? ? "" : video_files.compact.join(', ')
end

#deprecated
def get_pdf_blocks_file_names(page)
  pdf_blocks = page&.elements&.filter { |element| element.name == 'pdf_block' }

  pdf_files = pdf_blocks&.flat_map do |pdf_block|
    pdf_block.contents&.map do |content|
      essence = content.essence
      essence.respond_to?(:attachment) ? essence.attachment&.file_name : nil
    end
  end

  return pdf_files&.compact&.blank? ? "" : pdf_files.compact.join(', ')
end


#deprecated
def get_picture_blocks_file_names(page)
  picture_block_elements = page&.elements&.filter { |element| element.name == 'picture_block' }

  picture_files = picture_block_elements&.flat_map do |picture_block|
    picture_block.contents&.map do |content|
      essence = content.essence
      essence.respond_to?(:picture) ? essence.picture&.image_file_name : nil
    end
  end

  return picture_files&.compact&.blank? ? "" : picture_files.compact.join(', ')
end

#deprecated
def get_text_and_picture_blocks_file_names(page)
  text_and_picture_block_elements = page&.elements&.filter { |element| element.name == 'text_and_picture' }

  text_and_picture_files = text_and_picture_block_elements&.flat_map do |text_and_picture_block|
    text_and_picture_block.contents&.map do |content|
      essence = content.essence
      essence.respond_to?(:picture) ? essence.picture&.image_file_name : nil
    end
  end

  return text_and_picture_files&.compact&.blank? ? "" : text_and_picture_files.compact.join(', ')
end


############
# Other functions
############

def get_assigned_authors(page)
  page_is_article = page.page_layout == "article" ? true : false
  page_is_event = page.page_layout == "event" ? true : false
  page_is_info = page.page_layout == "info" ? true : false
  page_is_note = page.page_layout == "note" ? true : false

  unless page_is_article || page_is_event || page_is_info || page_is_note
    return ""
  end

  # Use new AlchemyPageAuthor system for all page types
  page.authors.map(&:slug).join(', ')
end


def update_assigned_authors(page, authors_str)

  Rails.logger.info("Updating assigned authors...")
  page_is_article = page.page_layout == "article" ? true : false
  page_is_event = page.page_layout == "event" ? true : false
  page_is_info = page.page_layout == "info" ? true : false
  page_is_note = page.page_layout == "note" ? true : false

  unless page_is_article || page_is_event || page_is_info || page_is_note
    Rails.logger.debug("\tPage is not an article or event or info or note. Skipping...")
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
    Rails.logger.debug("\tPage is an article or event or info or note. Proceeding...")

    author_list = authors_str.to_s.split(',').map(&:strip).reject(&:blank?)
    profiles = []

    flag = true
    user_error_message = "Users not found or missing profiles: "
    for author in author_list
      user = Alchemy::User.find_by(login: author)

      if user.nil?
        user_error_message += "'#{author}', "
        flag = false
      elsif user.profile.nil?
        user_error_message += "'#{author}' (no profile), "
        flag = false
      else
        profiles << user.profile
      end
    end

    if !flag
      Rails.logger.error("\t#{user_error_message}")
      result[:status] = 'error'
      user_error_message = user_error_message[0..-3] unless user_error_message.nil? || user_error_message.empty?
      result[:error_message] = user_error_message unless user_error_message.nil? || user_error_message.empty?
      result[:error_trace] = "pages_tasks.rb::update_assigned_authors"
      return result
    end

    # Use new AlchemyPageAuthor system for all page types
    page.authors = profiles.uniq.compact
    page.save!

    Rails.logger.debug("\tAssigned authors updated successfully")
    result[:status] = 'success'
    return result

  rescue => e
    Rails.logger.error("\tError while updating assigned authors: #{e.message}")
    result[:status] = 'unhandled error'
    result[:error_message] = "#{e.class} :: #{e.message}"
    result[:error_trace] = e.backtrace.join(" ::: ")
    return result
  end
end


def has_html_header_tags(page)
  has_html_header_tags = false

  page.elements.each do |element|

    case element.name
    when 'intro', 'text_block', 'text_and_picture', 'note_intro'
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
    badge: "",
    structural: "",
  }

  if page.page_layout == ''
    return themetags_hashmap
  end

  intro_element = forced_intro_element(page)
  if intro_element
    topic_content = intro_element.contents.find { |content| content.name == 'topics' }
    topics = topic_content&.essence&.topics&.uniq || []

    themetags_hashmap[:discipline] = themetag_names_by_interest_type(topics, "discipline")
    themetags_hashmap[:focus] = themetag_names_by_interest_type(topics, "focus")
    themetags_hashmap[:badge] = themetag_names_by_interest_type(topics, "badge")
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

    if page.page_layout == '' || page.page_layout == 'index'
      report[:status] = 'success'
      return report
    end

    intro_element = forced_intro_element(page)
    if intro_element.nil?
      report[:status] = 'error'
      report[:error_message] = "Intro element not found for page layout '#{page.page_layout}'"
      report[:error_trace] = "pages_tools.rb::set_themetags"
      return report
    end

    topic_content = intro_element.contents.find { |content| content.name == 'topics' }
    themetags = themetag_names.map { |name| get_themetag_by_name(name) }.compact.uniq
    update_response = topic_content.essence.update(topics: themetags)

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
    report[:error_trace] = e.backtrace.join(" ::: ")

  ensure
    return report
  end

end


# Utils
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
  references = page.elements.named(:references).first
  unless references and page.page_layout == "article"
    Rails.logger.debug("get_references_bib_keys: No references element found")
    return ""
  end

  bibkeys = references.ingredient(:bibkeys)

  Rails.logger.debug("get_references_bib_keys: Found bibkeys = '#{bibkeys}'")

  return bibkeys.to_s.strip
end


def set_references_bib_keys(page, bibkeys)
  result = {
    status: 'not started',
    error_message: '',
    error_trace: '',
  }
  begin
    references = page.elements.named(:references).first

    unless references
      Rails.logger.warn("References element not found. Creating...")
      # Create the references element
      page.elements.create!(name: "references", page_id: page.id, parent_element_id: nil, public: true)
      page.reload
      references = page.elements.named(:references).first

      unless references
        raise "References element could not be created"
      end
    end

    # Update the bibkeys content using the proper Alchemy API
    bibkeys_content = references.content_by_name(:bibkeys)
    bibkeys_content.update_essence(ingredient: bibkeys)

    result[:status] = 'success'
    return result

  rescue => e
    result[:status] = 'unhandled error'
    result[:error_message] = "#{e.class} :: #{e.message}"
    result[:error_trace] = e.backtrace.join(" ::: ")
    return result
  end
end


def get_all_attachments_with_pages()
  return Alchemy::Attachment.all.filter { |attachment| attachment.pages != [] }
end


def get_attachment_links_portal(page, all_attachments_with_pages)
  result = []

  # 1. Look in the Richtext essences
  attachment_links_portal = page.elements.flat_map do |element|
    element.contents.flat_map do |content|
      next [] unless content.essence.is_a?(Alchemy::EssenceRichtext) && content.essence.body

      content.essence.body.scan(/href="([^"]*attachment[^"]*)"/).flatten
    end
  end

  attachment_links_portal.each do |link|
    # Remove everything from the link except the number after 'attachment/'
    # This is the attachment ID
    # Example: href="/attachment/1234/show" -> 1234
    # Example 2: href="/attachment/1234/download" -> 1234
    id = link.match(/\/attachment\/(\d+)\//)&.captures&.first

    attachment = Alchemy::Attachment.find_by(id: id)

    unless attachment
      result << "Attachment with ID '#{id}' in link '#{link}' not found"
      next
    end

    # Generate downloadable link instead of filename
    result << generate_attachment_download_url(id)
  end

  # 2. Look in the Embed elements of the page
  html_embed_elements = page.elements.flat_map do |element|
    element.contents.flat_map do |content|
      next [] unless content.essence.is_a?(Alchemy::EssenceHtml) && content.essence.source

      content.essence.source.scan(/src="([^"]*attachment[^"]*)"/).flatten
    end
  end

  html_embed_elements.each do |link|
    # Remove everything from the link except the number after 'attachment/'
    # This is the attachment ID
    # Example: src="/attachment/1234/show" -> 1234
    # Example 2: src="/attachment/1234/download" -> 1234
    id = link.match(/\/attachment\/(\d+)\//)&.captures&.first

    attachment = Alchemy::Attachment.find_by(id: id)

    unless attachment
      result << "Attachment with ID '#{id}' in link '#{link}' not found"
      next
    end

    # Generate downloadable link instead of filename
    result << generate_attachment_download_url(id)
  end

  # 3. Look for all attachments, and return those whose 'pages' include the current page
  page_attachments = all_attachments_with_pages.filter { |attachment| attachment.pages.map(&:id).include?(page.id) }.map { |attachment| generate_attachment_download_url(attachment.id) }

  result << page_attachments


  return result.flatten.reject { |element| element.nil? || element.strip.empty? }.uniq.join(", ")

end


def get_pre_headline(page)
  intro_element = forced_intro_element(page)
  return "" if intro_element.nil?
  intro_element.content_by_name(:pre_headline)&.essence&.body || ""
end


def set_pre_headline(page, pre_headline)
  intro_element = forced_intro_element(page)
  return if intro_element.nil?
  intro_element.content_by_name(:pre_headline)&.essence&.update({body: pre_headline})
end


def get_lead_text(page)
  intro_element = forced_intro_element(page)
  return "" if intro_element.nil?
  intro_element.content_by_name(:lead_text)&.essence&.body || ""
end


def set_lead_text(page, lead_text)
  intro_element = forced_intro_element(page)
  return if intro_element.nil?
  intro_element.content_by_name(:lead_text)&.essence&.update({body: lead_text})
end


def get_embed_blocks(page)
  page.elements.map { |element| element if element.name == "embed" }.compact
end

def has_embed_blocks(page)
  get_embed_blocks(page).any? ? "yes" : ""
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

  references_block.content_by_name("references_asset_url").essence.update!({body: references_url})

  references_block.content_by_name("further_references_asset_url").essence.update!({body: further_references_url})

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
    references_url = references_block.content_by_name("references_asset_url")&.essence&.link
    further_references_url = references_block.content_by_name("further_references_asset_url")&.essence&.link

    urls[:references_url] = references_url.blank? ? "" : references_url
    urls[:further_references_url] = further_references_url.blank? ? "" : further_references_url
  end

  return urls

end

def soft_get_aside_columns(page)
  aside_columns = Alchemy::Element.where(parent_element_id: nil, page_id: page.id, name: "aside_column")

  return aside_columns
end

class MoreThanOneAsideColumnError < StandardError; end

def get_aside_column(page)
  aside_columns = Alchemy::Element.where(parent_element_id: nil, page_id: page.id, name: "aside_column")

  amount = aside_columns.length
  if amount > 1
    raise MoreThanOneAsideColumnError, "There are more than one aside column for page '#{page.id}'. Please clean this up and try again."
  end

  return aside_columns.first
end

def get_article_metadata_element(aside_column)
  # This is a nested element inside the aside_column element
  if aside_column.blank?
    return nil
  else
    article_metadata = aside_column.nested_elements.filter { |nested_element| nested_element.name == "article_metadata" }.first
    if article_metadata.blank?
      return nil
    else
      return article_metadata
    end
  end
end


def set_article_metadata(page, how_to_cite, pure_html_asset_full_url, pure_pdf_asset_full_url, doi)
  # pure_html_asset_full_url and pure_pdf_asset_full_url are meant to be full URLs
  # doi is EssenceText
  # how_to_cite is EssenceRichtext

  report = {
    status: 'not started',
    error_message: '',
    error_trace: '',
  }

  begin
    aside_column = get_aside_column(page)

    if aside_column.blank?
      # create it
      page.elements.create!(name: "aside_column", page_id: page.id, parent_element_id: nil, public: true)
      aside_column = get_aside_column(page)

      if aside_column.blank?
        raise "Aside column could not be created"
      end

    end

    try_article_metadata = get_article_metadata_element(aside_column)

    if try_article_metadata.blank?
      # create it
      aside_column.nested_elements.create!(name: "article_metadata", page_id: page.id, parent_element_id: aside_column.id, public: true)
      aside_column.save!
    else
      # destroy it and create a new one
      try_article_metadata.destroy!
      aside_column.nested_elements.create!(name: "article_metadata", page_id: page.id, parent_element_id: aside_column.id, public: true)
      aside_column.save!
    end

    page.reload
    aside_column = get_aside_column(page)

    if aside_column.blank?
      raise "Aside column could not be created"
    end

    aside_column.update!(public: true)

    article_metadata = get_article_metadata_element(aside_column)

    if article_metadata.blank?
      raise "Article metadata could not be created"
    end

    article_metadata.update!(public: true)

    article_metadata.contents.find_by(name: "doi").essence.update!({body: doi})

    article_metadata.contents.find_by(name: "how_to_cite").essence.update!({body: how_to_cite})

    article_metadata.contents.find_by(name: "pure_html_url").essence.update!({body: pure_html_asset_full_url})

    article_metadata.contents.find_by(name: "pure_pdf_url").essence.update!({body: pure_pdf_asset_full_url})

    # Put the article metadata at the top of the aside column
    article_metadata.update!(position: 1)

    article_metadata.save!
    aside_column.nested_elements = aside_column.nested_elements.reorder('position ASC')
    aside_column.save!

    # Save everything
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
  return  full_url&.start_with?(pure_links_base_url) ? full_url.gsub(pure_links_base_url, "") : full_url
end

def get_pure_pdf_asset(article_metadata_element, pure_links_base_url)
  full_url = article_metadata_element.contents.find_by(name: "pure_pdf_url").essence.body
  return  full_url&.start_with?(pure_links_base_url) ? full_url.gsub(pure_links_base_url, "") : full_url
end

def get_metadata_json(article_metadata_element)
  metadata_content = article_metadata_element.contents.find_by(name: "metadata")
  return metadata_content.present? ? metadata_content.essence.body.to_s : ''
end


def get_academic_metadata_json(page)
  academic_metadata = page.elements.named(:academic_metadata).first
  unless academic_metadata and page.page_layout == "article"
    Rails.logger.debug("get_academic_metadata_json: No academic_metadata element found")
    return ""
  end

  metadata_json = academic_metadata.ingredient(:metadata_json)
  return metadata_json.to_s.strip
end


def set_academic_metadata_json(page, metadata_json_str)
  result = {
    status: 'not started',
    error_message: '',
    error_trace: '',
  }
  begin
    # Find or create academic_metadata element
    academic_metadata = page.elements.named(:academic_metadata).first

    unless academic_metadata
      Rails.logger.warn("Academic metadata element not found. Creating...")
      # Create the academic_metadata element
      page.elements.create!(name: "academic_metadata", page_id: page.id, parent_element_id: nil, public: true)
      page.reload
      academic_metadata = page.elements.named(:academic_metadata).first

      unless academic_metadata
        raise "Academic metadata element could not be created"
      end
    end

    # Update the metadata_json content using the proper Alchemy API
    metadata_json_content = academic_metadata.content_by_name(:metadata_json)
    metadata_json_content.update_essence(ingredient: metadata_json_str)

    result[:status] = 'success'
    return result

  rescue => e
    result[:status] = 'unhandled error'
    result[:error_message] = "#{e.class} :: #{e.message}"
    result[:error_trace] = e.backtrace.join(" ::: ")
    return result
  end
end


def unpublish_page(page)
  report = {
    status: 'not started',
    error_message: '',
    error_trace: '',
  }

  begin
    page.update(public_on: nil, public_until: nil, published_at: nil)
    page.save!
    report[:status] = 'success'
    return report

  rescue => e
    report[:status] = 'error'
    report[:error_message] = "#{e.class} :: #{e.message}"
    report[:error_trace] = e.backtrace.join(" ::: ")
    return report
  end

end


def get_published(page)
  if not page.public_on
    return "UNPUBLISHED"
  else
    return "PUBLISHED"
  end
end

def get_creator(page)
  creator_id = page.creator_id
  creator = Alchemy::User.find_by(id: creator_id)
  return creator.blank? ? "" : creator.login
end

def get_last_updater(page)
  last_updater_id = page.updater_id
  last_updater = Alchemy::User.find_by(id: last_updater_id)
  return last_updater.blank? ? "" : last_updater.login
end

def get_last_updated_date(page)
  # In YYYY-MM-DD format
  return page.updated_at.strftime('%Y-%m-%d')
end


def generate_asset_filename(page, media_name, extension)
  sanitized_urlname = page.urlname.gsub('/', '-')
  filename = "#{sanitized_urlname}-#{media_name}#{n}.#{extension}"
  return filename
end


# Comments
def get_comments(page)
  Comment.find_comments_for_commentable('Alchemy::Page', page.id).distinct.order('created_at DESC')
end

def get_latest_comment_login_and_date(page)
  latest_comment = get_comments(page).first

  login = Alchemy::User.find_by(id: latest_comment&.user_id)&.login
  date = latest_comment.blank? ? "" : latest_comment.created_at.strftime('%Y-%m-%d')

  return {login: login, date: date}
end


# Threads
def get_reply_target_urlname(page)
  result = Alchemy::Page.find_by(id: page.reply_target_id)
  return result.blank? ? "" : result.id
end

class SetReplyTargetError < StandardError; end
def set_reply_target_by_id(page, id_s)
  begin
    id_i = id_s.to_i
    reply_target = Alchemy::Page.find_by(id: id_i)

    if reply_target.blank?
      return ""

    else
      page.update!(reply_target_id: reply_target.id)
      return ""
    end
  rescue => e
    return "Could not set reply target via 'id'. Details :: #{e.class} :: #{e.message}"
  end
end

def get_replied_by(page)
  Alchemy::Page.where(reply_target_id: page.id).order('created_at DESC').pluck(:urlname).join(", ")
end



# Anonymous pages

def get_anon(page)

  anon_value = page.anonymous

  if anon_value.nil?
    return ""
  end

  return anon_value.to_s.strip.upcase
end


def set_anon(page, raw_value)

  page_layout = page.page_layout

  case page_layout

  when 'note'
    if raw_value.nil? || raw_value == ""
      raise ArgumentError, "'anon' value must be a string that represents a boolean, or a boolean itself. Got no value"
    end

    value_s = raw_value.to_s.strip.downcase
    value = value_s == "true" ? true : false

    if value != true && value != false
      raise ArgumentError, "'anon' value must be a string that represents a boolean, or a boolean itself. Got: [[ #{raw_value} ]]"
    end

    intro_element = forced_intro_element(page)
    return if intro_element.nil?
    intro_element.content_by_name(:anonymous)&.essence&.update!({value: value})

  end

end




def create_pdf_block(page)
  report = {
    status: 'not started',
    error_message: '',
    error_trace: '',
  }

  begin
    # Validate input
    if page.nil? || page.blank?
      raise InvalidPage, "Page is required and cannot be nil"
    end

    # Create the pdf_block element
    pdf_block = page.elements.create!(name: "pdf_block")

    # Create the pdf_asset_url content with empty essence
    new_essence_text = Alchemy::EssenceText.create!(body: "")
    pdf_block.contents.create!(
      name: "pdf_asset_url",
      essence: new_essence_text
    )

    # Save and publish
    pdf_block.save!
    page.save!
    page.publish!

    # Return success
    report[:status] = 'success'
    return report

  rescue InvalidPage => e
    report[:status] = 'error'
    report[:error_message] = e.message
    report[:error_trace] = "page_tools.rb::create_pdf_block::validation"
    return report

  rescue => e
    report[:status] = 'unhandled error'
    report[:error_message] = "#{e.class} :: #{e.message}"
    report[:error_trace] = e.backtrace.join(" ::: ")
    return report
  end
end
