require 'csv'

#ActiveRecord::Base.logger.level = Logger::WARN

#Rails.logger.level = Logger::INFO

#if ARGV[0]
  ## set log level
  #if ARGV[0] == 'debug'
    #Rails.logger.level = Logger::DEBUG
  #elsif ARGV[0] == 'info'
    #Rails.logger.level = Logger::INFO
  #elsif ARGV[0] == 'warn'
    #Rails.logger.level = Logger::WARN
  #elsif ARGV[0] == 'error'
    #Rails.logger.level = Logger::ERROR
  #end
#end


############
# FUNCTIONS
############

def generate_csv_report(report, file_name)
  return if report.empty?
  headers = report.first.keys

  csv_string = CSV.generate do |csv|
    csv << headers
    report.each do |row|
      csv << headers.map { |header| row[header] }
    end
  end

  begin
    File.write(file_name, csv_string)
    puts "File written successfully to #{file_name}"
  rescue Errno::EACCES => e
    puts "Permission denied: #{e.message}"
  rescue Errno::ENOSPC => e
    puts "No space left on device: #{e.message}"
  rescue StandardError => e
    puts "An error occurred: #{e.message}"
  end

  Rails.logger.info("\n\n\n============ Report generated at #{file_name} ============\n\n\n")
end

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
      result << "Attachment with ID '#{id}' not found"
    end

    result << file_name
  end

  return result.join(", ")

end


############
# MAIN
############

report = []
processed_lines = 0

CSV.foreach("portal-tasks/pages_tasks.csv", col_sep: ',', headers: true) do |row|
  Rails.logger.info("Processing row #{processed_lines + 1}")
  subreport = {
    _sort: row['_sort'] || "",
    id: row['id'] || "",  # page
    name: row['name'] || "",  # page
    title: row['title'] || "",  # page
    language_code: row['language_code'] || "",  # page
    urlname: row['urlname'] || "",  # page
    slug: row['slug'] || "", # page
    link: row['link'] || "",  # crafted
    _request: row['_request'] || "",
    _article_bib_key: row['_article_bib_key'] || "",  # article
    _doi: row['_doi'] || "",  # article
    created_at: row['created_at'] || "",  # page
    page_layout: row['page_layout'] || "",  # page

    tag_page_type: row['tag_page_type'] || "",  # tag
    tag_media_1: row['tag_media_1'] || "",  # tag
    tag_media_2: row['tag_media_2'] || "",  # tag
    tag_language: row['tag_language'] || "",  # tag
    tag_university: row['tag_university'] || "",  # tag
    tag_canton: row['tag_canton'] || "",  # tag
    tag_special_content_1: row['tag_special_content_1'] || "",  # tag
    tag_special_content_2: row['tag_special_content_2'] || "",  # tag
    tag_references: row['tag_references'] || "",  # tag
    tag_footnotes: row['tag_footnotes'] || "",  # tag
    tag_others: row['tag_others'] || "",  # tag

    ref_bib_keys: row['ref_bib_keys'] || "",  # box

    _assets: row['_assets'] || "",
    _to_do_on_the_portal: row['_to_do_on_the_portal'] || "",

    assigned_authors: row['assigned_authors'] || "",  # box

    intro_block_image: row['intro_block_image'] || "",  # element
    audio_block_files: row['audio_block_files'] || "",  # element
    video_block_files: row['video_block_files'] || "",  # element
    pdf_block_files: row['pdf_block_files'] || "",  # element
    picture_block_files: row['picture_block_files'] || "",  # element

    has_picture_with_text: row['has_picture_with_text'] || "",  # element
    attachment_links: row['attachment_links'] || "",  # element
    _other_assets: row['_other_assets'] || "",
    has_html_header_tags: row['has_html_header_tags'] || "",  # element

    themetags: row['themetags'] || "",  # themetags

    status: '',
    changes_made: '',
    error_message: '',
    error_trace: '',
  }


  begin

    # Control
    Rails.logger.info("Processing page: Control")
    supported_requests = ['POST', 'UPDATE', 'GET', 'DELETE', 'GET RAW FILENAMES']
    req = subreport[:_request].strip

    if req.blank?
      subreport[:status] = ""
    else
      unless supported_requests.include?(req)
        subreport[:_request] += " ERROR"
        subreport[:status] = "error"
        subreport[:error_message] = "Unsupported request '#{req}'. Skipping"
        subreport[:error_trace] = "pages_tasks.rb::main::Control::Main"
      end
    end

    id = subreport[:id].strip
    urlname = subreport[:urlname].strip
    language_code = subreport[:language_code].strip

    if req == 'POST'
      if urlname.blank? || language_code.blank?
        subreport[:_request] += " ERROR"
        subreport[:status] = "error"
        subreport[:error_message] = "Need urlname and language code for 'POST'. Skipping"
        subreport[:error_trace] = "pages_tasks.rb::main::Control::POST"
        next
      end
      retreived_pages = Alchemy::Page.where(urlname: urlname)
      exact_page_match = retreived_pages.find { |p| p.language_code == language_code }
      if exact_page_match
        subreport[:_request] += " ERROR"
        subreport[:status] = "error"
        subreport[:error_message] = "Page already exists. Skipping"
        subreport[:error_trace] = "pages_tasks.rb::main::Control::POST"
        next
      end
    end

    if req == 'UPDATE' || req == 'GET' || req == 'DELETE' || req == 'GET RAW FILENAMES'
      if id.blank? && (language_code.blank? || urlname.blank?)
        subreport[:_request] += " ERROR"
        subreport[:status] = "error"
        subreport[:error_message] = "Need ID, or urlname + language code for '#{req}'. Skipping"
        subreport[:error_trace] = "pages_tasks.rb::main::Control::UPDATE/GET/DELETE"
        next
      end
    end

    page_identifier = urlname.blank? ? id : urlname

    # Parsing
    Rails.logger.info("Processing page '#{page_identifier}': Parsing")
    id = subreport[:id].strip
    name = subreport[:name].strip
    title = subreport[:title].strip
    slug = subreport[:slug].strip
    link = subreport[:link].strip
    created_at = subreport[:created_at].strip
    page_layout = subreport[:page_layout].strip

    tag_page_type = subreport[:tag_page_type].strip
    tag_media_1 = subreport[:tag_media_1].strip
    tag_media_2 = subreport[:tag_media_2].strip
    tag_language = subreport[:tag_language].strip
    tag_university = subreport[:tag_university].strip
    tag_canton = subreport[:tag_canton].strip
    tag_special_content_1 = subreport[:tag_special_content_1].strip
    tag_special_content_2 = subreport[:tag_special_content_2].strip
    tag_references = subreport[:tag_references].strip
    tag_footnotes = subreport[:tag_footnotes].strip
    tag_others = subreport[:tag_others].strip

    assigned_authors = subreport[:assigned_authors].strip

    intro_block_image = subreport[:intro_block_image].strip

    audio_block_files = subreport[:audio_block_files].strip
    video_block_files = subreport[:video_block_files].strip
    pdf_block_files = subreport[:pdf_block_files].strip
    picture_block_files = subreport[:picture_block_files].strip

    has_picture_with_text = subreport[:has_picture_with_text].strip
    has_html_header_tags = subreport[:has_html_header_tags].strip

    themetags = subreport[:themetags].strip


    # Setup
    Rails.logger.info("Processing page '#{page_identifier}': Setup")

    if req == 'POST'
      page = Alchemy::Page.new

      alchemy_language_code = ''
      alchemy_country_code = ''
      if language_code.include?('-')
        alchemy_language_code = language_code.split('-').first
        alchemy_country_code = language_code.split('-').last
      else
        alchemy_language_code = language_code
      end

      language = Alchemy::Language.find_by(language_code: alchemy_language_code, country_code: alchemy_country_code)

      if language.nil?
        Rails.logger.error("Language with code '#{alchemy_language_code}' and country code '#{alchemy_country_code}' not found. Skipping")
        subreport[:_request] += " ERROR"
        subreport[:status] = "error"
        subreport[:error_message] = "Language with code '#{alchemy_language_code}' and country code '#{alchemy_country_code}' not found. Skipping"
        subreport[:error_trace] = "pages_tasks.rb::main::Setup::POST"
        next

      else
        root_page = Alchemy::Page.language_root_for(language.id)

        if root_page.nil?
          Rails.logger.error("Root page for language with code '#{alchemy_language_code}' and country code '#{alchemy_country_code}' not found. Skipping")
          subreport[:_request] += " ERROR"
          subreport[:status] = "error"
          subreport[:error_message] = "Root page for language with code '#{alchemy_language_code}' and country code '#{alchemy_country_code}' not found. Skipping"
          subreport[:error_trace] = "pages_tasks.rb::main::Setup::POST"
          next
        else
          page.parent_id = root_page.id
          page.language_id = root_page.language_id
          page.language_code = root_page.language_code
        end
      end

    elsif req == 'UPDATE' || req == 'GET' || req == 'DELETE'|| req == 'GET RAW FILENAMES'
      unless id.blank?
        page = Alchemy::Page.find(id)
      else
        unless urlname.blank? || language_code.blank?
          page = Alchemy::Page.find_by(urlname: urlname, language_code: language_code)  # this combination is unique
        else
          Rails.logger.error("Need ID, or urlname + language code for '#{req}'. Skipping")
          subreport[:_request] += " ERROR"
          subreport[:status] = "error"
          subreport[:error_message] = "Need ID, or urlname + language code for '#{req}'. Skipping"
          subreport[:error_trace] = "pages_tasks.rb::main::Setup::UPDATE-GET-DELETE"
          next
        end
      end

      if page.nil?
        Rails.logger.error("Page with ID '#{id}' or urlname '#{urlname}' and language code '#{language_code}' not found. Skipping")
        subreport[:_request] += " ERROR"
        subreport[:status] = "error"
        subreport[:error_message] = "Page with ID '#{id}' or urlname '#{urlname}' and language code '#{language_code}' not found, but needed for #{req}. Skipping"
        subreport[:error_trace] = "pages_tasks.rb::main::Setup::UPDATE-GET-DELETE"
        next
      end

    else  # Should not happen
      Rails.logger.error("How did we get here? Unsupported request '#{req}'. Skipping")
      subreport[:_request] += " ERROR"
      subreport[:status] = "error"
      subreport[:error_message] = "How did we get here? Unsupported request '#{req}'. Skipping"
      subreport[:error_trace] = "pages_tasks.rb::main::Setup::Main"
      next
    end

    if req == 'DELETE'
      page.delete
      if !id.blank?
        page_present = Alchemy::Page.find_by(id: id).present?
      elsif !urlname.blank? && !language_code.blank?
        page_present = Alchemy::Page.find_by(urlname: urlname, language_code: language_code).present?
      else
        page_present = false
      end

      if page_present
        subreport[:_request] += " ERROR"
        subreport[:status] = "error"
        subreport[:error_message] = "Page not deleted by an unknown reason!. Skipping"
        subreport[:error_trace] = "pages_tasks.rb::main::Setup::DELETE"
        next
      else
        subreport[:id] = ''
        subreport[:slug] = ''
        subreport[:link] = ''
        subreport[:status] = "success"
        subreport[:changes_made] = "PAGE WAS DELETED IN THE SERVER"
        next
      end
    end

    if req == 'UPDATE' || req == 'GET' || req == 'GET RAW FILENAMES'
      old_page_tag_names = page.tag_names
      old_page_tag_columns = tag_array_to_columns(old_page_tag_names)
      old_page_assigned_authors = get_assigned_authors(page)

      if req == 'GET RAW FILENAMES'
        retrieved_intro_block_image = get_intro_block_image_raw_filename(page)
      elsif req == 'GET'
        retrieved_intro_block_image = get_intro_block_image(page)
      else
        retrieved_intro_block_image = get_intro_block_image(page)
      end

      old_page = {
        _sort: subreport[:_sort],
        id: page.id,
        name: page.name,
        title: page.title,
        language_code: page.language_code,
        urlname: page.urlname,
        slug: subreport[:slug],
        link: subreport[:link],
        _request: subreport[:_request],
        _article_bib_key: subreport[:_article_bib_key],
        _doi: subreport[:_doi],
        created_at: get_created_at(page),
        page_layout: page.page_layout,

        tag_page_type: old_page_tag_columns[:tag_page_type],
        tag_media_1: old_page_tag_columns[:tag_media_1],
        tag_media_2: old_page_tag_columns[:tag_media_2],
        tag_language: old_page_tag_columns[:tag_language],
        tag_university: old_page_tag_columns[:tag_university],
        tag_canton: old_page_tag_columns[:tag_canton],
        tag_special_content_1: old_page_tag_columns[:tag_special_content_1],
        tag_special_content_2: old_page_tag_columns[:tag_special_content_2],
        tag_references: old_page_tag_columns[:tag_references],
        tag_footnotes: old_page_tag_columns[:tag_footnotes],
        tag_others: old_page_tag_columns[:tag_others] || '',

        ref_bib_keys: get_references_bib_keys(page),

        _assets: subreport[:_assets],
        _to_do_on_the_portal: subreport[:_to_do_on_the_portal],

        assigned_authors: old_page_assigned_authors,

        intro_block_image: retrieved_intro_block_image,
        audio_block_files: get_audio_blocks_file_names(page),
        video_block_files: get_video_blocks_file_names(page),
        pdf_block_files: get_pdf_blocks_file_names(page),
        picture_block_files: get_picture_blocks_file_names(page),

        has_picture_with_text: page.elements.any? { |element| element.name == 'text_and_picture' } ? "yes" : "",
        attachment_links: get_attachment_links(page),
        _other_assets: subreport[:_other_assets],
        has_html_header_tags: has_html_header_tags(page),

        themetags: get_themetags(page),

        status: '',
        changes_made: '',
        error_message: '',
        error_trace: '',
      }
    end

    # Execution
    Rails.logger.info("Processing page '#{page_identifier}': Execution")

    if req == "POST" || req == "UPDATE"
      Rails.logger.info("\t...POST or UPDATE: '#{page_identifier}': Setting attributes")
      page.name = name
      page.title = title
      page.language_code = language_code
      page.urlname = urlname
      page.page_layout = page_layout
      page.created_at = created_at

      tag_columns = {
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

      page.tag_names = tag_columns_to_array(tag_columns)

      page.save!
      page.publish!

     end

    # Update report
    Rails.logger.info("Processing page '#{page_identifier}': Updating report")
    tags_to_cols = tag_array_to_columns(page.tag_names)
    retrieved_slug = retrieve_page_slug(page)

    if req == 'GET RAW FILENAMES'
      retrieved_intro_block_image = get_intro_block_image_raw_filename(page)
    elsif req == 'GET'
      retrieved_intro_block_image = get_intro_block_image(page)
    else
      retrieved_intro_block_image = get_intro_block_image(page)
    end

    subreport.merge!({
      id: page.id,
      name: page.name,
      title: page.title,
      language_code: page.language_code,
      urlname: page.urlname,
      slug: retrieved_slug,
      link: "https://www.philosophie.ch#{retrieved_slug}",
      created_at: get_created_at(page),
      page_layout: page.page_layout,
      tag_page_type: tags_to_cols[:tag_page_type],
      tag_media_1: tags_to_cols[:tag_media_1],
      tag_media_2: tags_to_cols[:tag_media_2],
      tag_language: tags_to_cols[:tag_language],
      tag_university: tags_to_cols[:tag_university],
      tag_canton: tags_to_cols[:tag_canton],
      tag_special_content_1: tags_to_cols[:tag_special_content_1],
      tag_special_content_2: tags_to_cols[:tag_special_content_2],
      tag_references: tags_to_cols[:tag_references],
      tag_footnotes: tags_to_cols[:tag_footnotes],
      tag_others: tags_to_cols[:tag_others],
      ref_bib_keys: get_references_bib_keys(page),
      assigned_authors: get_assigned_authors(page),
      intro_block_image: retrieved_intro_block_image,
      audio_block_files: get_audio_blocks_file_names(page),
      video_block_files: get_video_blocks_file_names(page),
      pdf_block_files: get_pdf_blocks_file_names(page),
      picture_block_files: get_picture_blocks_file_names(page),
      has_picture_with_text: page.elements.any? { |element| element.name == 'text_and_picture' } ? "yes" : "",
      attachment_links: get_attachment_links(page),
      has_html_header_tags: has_html_header_tags(page),
      themetags: get_themetags(page),
    })

    # Complex tasks
    if req == "UPDATE" || req == "POST"
      Rails.logger.info("Processing page '#{page_identifier}': Complex tasks")

      update_authors_report = update_assigned_authors(page, assigned_authors)
      if update_authors_report[:status] != 'success'
        subreport[:_request] += " PARTIAL"
        subreport[:status] = 'partial success'
        subreport[:error_message] = update_authors_report[:error_message]
        subreport[:error_message] += ". Page saved, but update_assigned_authors failed! Stopping...\n"
        subreport[:error_trace] = update_authors_report[:error_trace] + "\n"
        next
      end
      subreport[:assigned_authors] = get_assigned_authors(page)

      update_intro_block_image_report = update_intro_block_image(page, intro_block_image)
      if update_intro_block_image_report[:status] != 'success'
        subreport[:_request] += " PARTIAL"
        subreport[:status] = 'error'
        subreport[:error_message] = update_intro_block_image_report[:error_message]
        subreport[:error_message] += ". Page saved, but update_intro_block_image failed! Stopping...\n"
        subreport[:error_trace] = update_intro_block_image_report[:error_trace] + "\n"
        next
      end
      subreport[:intro_block_image] = get_intro_block_image(page)

      update_references_report = set_references_bib_keys(page, subreport[:ref_bib_keys])

      if update_references_report[:status] != 'success'
        subreport[:_request] += " PARTIAL"
        subreport[:status] = 'partial success'
        subreport[:error_message] = update_references_report[:error_message]
        subreport[:error_message] += ". Page saved, but set_references_bib_keys failed! Stopping...\n"
        subreport[:error_trace] = update_references_report[:error_trace] + "\n"
      end

      # TODO: update_themetags

      # Saving
      page.save!
      page.publish!
      Rails.logger.info("Processing page '#{page_identifier}': Complex tasks: Success!")
    end


    if req == "UPDATE" || req == "GET" || req == "GET RAW FILENAMES"
      changes = []
      subreport.each do |key, value|
        if old_page[key] != value && key != :changes_made && key != :status && key != :error_message && key != :error_trace && key != :_request
          # Skip if both old and new values are empty
          unless old_page[key].to_s.empty? && value.to_s.empty?
            changes << "#{key}: {{ #{old_page[key]} }} => {{ #{value} }}"
          end
        end
      end
      subreport[:changes_made] = changes.join(' ;;; ')
    end

    subreport[:status] = 'success'
    Rails.logger.info("Processing page '#{subreport[:urlname]}': Success!")


  rescue => e
    Rails.logger.error("Error while processing page '#{subreport[:urlname].blank? ? subreport[:id] : subreport[:urlname]}': #{e.message}")
    subreport[:status] = 'unhandled error'
    subreport[:error_message] = e.message
    subreport[:error_trace] = e.backtrace.join("\n")

  ensure
    report << subreport
    Rails.logger.info("Processing page: Done!. Processed lines so far: #{processed_lines + 1}")
    processed_lines += 1
  end

end


base_folder = 'portal-tasks-reports'
FileUtils.mkdir_p(base_folder) unless Dir.exist?(base_folder)

file_name = "#{base_folder}/#{Time.now.strftime('%y%m%d')}_pages_tasks_report.csv"

generate_csv_report(report, file_name)
