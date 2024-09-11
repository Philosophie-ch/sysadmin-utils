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

def generate_csv_report(report)
  return if report.empty?
  headers = report.first.keys

  csv_string = CSV.generate do |csv|
    csv << headers
    report.each do |row|
      csv << headers.map { |header| row[header] }
    end
  end

  file_name = "#{Time.now.strftime('%y%m%d')}_pages_tasks_report.csv"
  File.write(file_name, csv_string)

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
    result[:status] = 'unexpected error'
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

  page_is_article = page.page_layout == "article" ? true : false
  page_is_event = page.page_layout == "event" ? true : false

  unless page_is_article || page_is_event
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

    intro_element = page.elements.find { |element| element.name.include?('intro') }
    creator_essence = intro_element&.content_by_name(:creator)&.essence

    unless creator_essence
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
      result[:status] = 'error'
      user_error_message = user_error_message[0..-3] unless user_error_message.nil? || user_error_message.empty?
      result[:error_message] = user_error_message unless user_error_message.nil? || user_error_message.empty?
      result[:error_trace] = "pages_tasks.rb::update_assigned_authors"
      return result
    end

    creator_essence.alchemy_users = users.uniq.compact
    creator_essence.save!

    result[:status] = 'success'
    return result

  rescue => e
    result[:status] = 'unexpected error'
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



############
# MAIN
############

report = []
counter = 0

CSV.foreach("pages_tasks.csv", col_sep: ',', headers: true) do |row|

  subreport = {
    _sort: row['_sort'],
    id: row['id'],  # page
    name: row['name'],  # page
    title: row['title'],  # page
    language_code: row['language_code'],  # page
    urlname: row['urlname'],  # page
    slug: row['slug'],  # "#{page.language_code}/#{page.urlname}" or just page.urlname if language_code == "en_UK"
    link: row['link'],  # "https://www.philosophie.ch/#{slug}"
    _request: row['_request'],
    _additional_info: row['_additional_info'],
    page_layout: row['page_layout'],  # page

    tag_page_type: row['tag_page_type'],  # tag
    tag_media_1: row['tag_media_1'],  # tag
    tag_media_2: row['tag_media_2'],  # tag
    tag_language: row['tag_language'],  # tag
    tag_university: row['tag_university'],  # tag
    tag_canton: row['tag_canton'],  # tag
    tag_special_content_1: row['tag_special_content_1'],  # tag
    tag_special_content_2: row['tag_special_content_2'],  # tag
    tag_references: row['tag_references'],  # tag
    tag_footnotes: row['tag_footnotes'],  # tag
    tag_others: row['tag_others'],  # tag

    _to_do_on_the_portal: row['_to_do_on_the_portal'],

    assigned_authors: row['assigned_authors'],  # box

    intro_block_image: row['intro_block_image'],  # element
    audio_block_files: row['audio_block_files'],  # element
    video_block_files: row['video_block_files'],  # element
    pdf_block_files: row['pdf_block_files'],  # element
    picture_block_files: row['picture_block_files'],  # element

    has_picture_with_text: row['has_picture_with_text'],  # element
    _other_assets: row['_other_assets'],
    has_html_header_tags: row['has_html_header_tags'],  # element

    themetags: row['themetags'],  # themetags

    status: '',
    changes_made: '',
    error_message: '',
    error_trace: '',
  }


  begin

    Rails.logger.info("Processing page '#{subreport[:urlname]}'...")

    # Control
    supported_requests = ['POST', 'UPDATE', 'GET', 'DELETE']
    req = subreport[:_request]

    if req.nil? || req.strip.empty? || req.strip == ''
      subreport[:status] = ""
    else
      unless supported_requests.include?(req)
        subreport[:status] = "error"
        subreport[:error_message] = "Unsupported request '#{req}'. Skipping"
        subreport[:error_trace] = "pages_tasks.rb::main::Control::Main"
      end
    end

    if req == 'POST'
      retreived_pages = Alchemy::Page.where(urlname: subreport[:urlname])
      exact_page_match = retreived_pages.find { |p| p.language_code == subreport[:language_code] }
      if exact_page_match
        subreport[:status] = "error"
        subreport[:error_message] = "Page already exists. Skipping"
        subreport[:error_trace] = "pages_tasks.rb::main::Control::POST"
        next
      end
    end

    if req == 'UPDATE'
      language_code = subreport[:language_code]
      urlname = subreport[:urlname]

      if language_code.blank? || language_code == '' || language_code.nil? || urlname.blank? || urlname == '' || urlname.nil?
        subreport[:status] = "error"
        subreport[:error_message] = "language_code or urlname is empty. Skipping!"
        subreport[:error_trace] = "pages_tasks.rb::main::Control::UPDATE"
        next
      end

    end


    # Parsing
    Rails.logger.info("Processing page '#{subreport[:urlname]}': Parsing")
    id = subreport[:id] || ''
    name = subreport[:name] || ''
    title = subreport[:title] || ''
    language_code = subreport[:language_code] || ''
    urlname = subreport[:urlname] || ''
    slug = subreport[:slug] || ''
    link = subreport[:link] || ''
    page_layout = subreport[:page_layout] || ''

    tag_page_type = subreport[:tag_page_type] || ''
    tag_media_1 = subreport[:tag_media_1] || ''
    tag_media_2 = subreport[:tag_media_2] || ''
    tag_language = subreport[:tag_language] || ''
    tag_university = subreport[:tag_university] || ''
    tag_canton = subreport[:tag_canton] || ''
    tag_special_content_1 = subreport[:tag_special_content_1] || ''
    tag_special_content_2 = subreport[:tag_special_content_2] || ''
    tag_references = subreport[:tag_references] || ''
    tag_footnotes = subreport[:tag_footnotes] || ''
    tag_others = subreport[:tag_others] || ''

    assigned_authors = subreport[:assigned_authors] || ''

    intro_block_image = subreport[:intro_block_image] || ''

    audio_block_files = subreport[:audio_block_files] || ''
    video_block_files = subreport[:video_block_files] || ''
    pdf_block_files = subreport[:pdf_block_files] || ''
    picture_block_files = subreport[:picture_block_files] || ''

    has_picture_with_text = subreport[:has_picture_with_text] || ''
    has_html_header_tags = subreport[:has_html_header_tags] || ''

    themetags = subreport[:themetags] || ''


    # Setup
    Rails.logger.info("Processing page '#{subreport[:urlname]}': Setup")

    if req == 'POST'
      page = Alchemy::Page.new

      alchemy_language_code = ''
      alchemy_country_code = ''
      if subreport[:language_code].include?('-')
        alchemy_language_code = subreport[:language_code].split('-').first
        alchemy_country_code= subreport[:language_code].split('-').last
      else
        alchemy_language_code = subreport[:language_code]
      end

      language = Alchemy::Language.find_by(language_code: alchemy_language_code, country_code: alchemy_country_code)

      if language.nil?
        Rails.logger.error("Language with code '#{alchemy_language_code}' and country code '#{alchemy_country_code}' not found. Skipping")
        subreport[:status] = "error"
        subreport[:error_message] = "Language with code '#{alchemy_language_code}' and country code '#{alchemy_country_code}' not found. Skipping"
        subreport[:error_trace] = "pages_tasks.rb::main::Setup::POST"
        next

      else
        root_page = Alchemy::Page.language_root_for(language.id)

        if root_page.nil?
          Rails.logger.error("Root page for language with code '#{alchemy_language_code}' and country code '#{alchemy_country_code}' not found. Skipping")
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

    elsif req == 'UPDATE' || req == 'GET' || req == 'DELETE'
      unless id.nil? || id.empty? || id.strip == '' || id.blank?
        page = Alchemy::Page.find(id)
      else
        unless urlname.nil? || urlname.empty? || urlname.strip == '' || urlname.blank? || language_code.nil? || language_code.empty? || language_code.strip == '' || language_code.blank?
          page = Alchemy::Page.find_by(urlname: urlname, language_code: language_code)  # this combination is unique

        else
          Rails.logger.error("Need ID, or urlname + language code for '#{req}'. Skipping")
          subreport[:status] = "error"
          subreport[:error_message] = "Need ID, or urlname + language code for '#{req}'. Skipping"
          subreport[:error_trace] = "pages_tasks.rb::main::Setup::UPDATE-GET-DELETE"
          next
        end
      end

      if page.nil?
        Rails.logger.error("Page with ID '#{id}' or urlname '#{urlname}' and language code '#{language_code}' not found. Skipping")
        subreport[:status] = "error"
        subreport[:error_message] = "Page with ID '#{id}' or urlname '#{urlname}' and language code '#{language_code}' not found. Skipping"
        subreport[:error_trace] = "pages_tasks.rb::main::Setup::UPDATE-GET-DELETE"
        next
      end

    else  # Should not happen
      Rails.logger.error("Unsupported request '#{req}'. Skipping")
      subreport[:status] = "error"
      subreport[:error_message] = "How did we get here? Unsupported request '#{req}'. Skipping"
      subreport[:error_trace] = "pages_tasks.rb::main::Setup::Main"
      next
    end

    if req == 'DELETE'
      page.delete
      if Alchemy::Page.find_by(id: id).present?
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

    if req == 'UPDATE' || req == 'GET'
      old_page_tag_names = page.tag_names
      old_page_tag_columns = tag_array_to_columns(old_page_tag_names)
      old_page_assigned_authors = get_assigned_authors(page)

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
        _additional_info: subreport[:_additional_info],
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

        _to_do_on_the_portal: subreport[:_to_do_on_the_portal],

        assigned_authors: old_page_assigned_authors,

        intro_block_image: get_intro_block_image(page),
        audio_block_files: get_audio_blocks_file_names(page),
        video_block_files: get_video_blocks_file_names(page),
        pdf_block_files: get_pdf_blocks_file_names(page),
        picture_block_files: get_picture_blocks_file_names(page),

        has_picture_with_text: page.elements.any? { |element| element.name == 'text_and_picture' } ? "yes" : "",
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
    Rails.logger.info("Processing page '#{subreport[:urlname]}': Execution")

    if req == "POST" || req == "UPDATE"
      Rails.logger.info("Processing page '#{subreport[:urlname]}': Setting attributes")
      page.name = name
      page.title = title
      page.language_code = language_code
      page.urlname = urlname
      page.page_layout = page_layout


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

      update_authors_report = update_assigned_authors(page, subreport[:assigned_authors])

      if update_authors_report[:status] != 'success'
        subreport = old_page  # Revert to old page
        subreport[:status] = 'error'
        subreport[:error_message] = update_authors_report[:error_message]
        subreport[:error_message] += ". Not saved!\n"
        subreport[:error_trace] = update_authors_report[:error_trace] + "\n"
        next
      end

      update_intro_block_image_report = update_intro_block_image(page, intro_block_image)

      if update_intro_block_image_report[:status] != 'success'
        subreport = old_page  # Revert to old page
        subreport[:status] = 'error'
        subreport[:error_message] = update_intro_block_image_report[:error_message]
        subreport[:error_message] += ". Not saved!\n"
        subreport[:error_trace] = update_intro_block_image_report[:error_trace] + "\n"
        next
      end

      # TODO: update_themetags

      # Saving
      successful_page_save = page.save!
      succcessful_page_publish = page.publish!
      successful_save = successful_page_save && succcessful_page_publish

      if successful_save
        subreport[:status] = 'success'
        subreport[:changes_made] = 'created'
      else
        subreport[:status] = 'error'
        subreport[:error_message] += 'Error while saving or publishing page'
        subreport[:error_trace] += 'pages_tasks.rb::main::Saving'
        next
      end
    end

    # Update report
    Rails.logger.info("Processing page '#{subreport[:urlname]}': Updating report")
    tags_to_cols = tag_array_to_columns(page.tag_names)
    retrieved_slug = Alchemy::Engine.routes.url_helpers.show_page_path({
      locale: !page.language.default ? page.language_code : nil, urlname: page.urlname
    })

    subreport.merge!({
      id: page.id,
      name: page.name,
      title: page.title,
      language_code: page.language_code,
      urlname: page.urlname,
      slug: retrieved_slug,
      link: "https://www.philosophie.ch#{retrieved_slug}",
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
      assigned_authors: get_assigned_authors(page),
      intro_block_image: get_intro_block_image(page),
      audio_block_files: get_audio_blocks_file_names(page),
      video_block_files: get_video_blocks_file_names(page),
      pdf_block_files: get_pdf_blocks_file_names(page),
      picture_block_files: get_picture_blocks_file_names(page),
      has_picture_with_text: page.elements.any? { |element| element.name == 'text_and_picture' } ? "yes" : "",
      has_html_header_tags: has_html_header_tags(page),
      themetags: get_themetags(page),
    })


    if req == "UPDATE" || req == "GET"
      changes = []
      subreport.each do |key, value|
        if old_page[key] != value && key != :changes_made && key != :status && key != :error_message && key != :error_trace
          # Skip if both old and new values are empty
          unless old_page[key].to_s.empty? && value.to_s.empty?
            changes << "#{key}: #{old_page[key]} => #{value}"
          end
        end
      end
      subreport[:changes_made] = changes.join(' ;;; ')
    end

    subreport[:status] = 'success'
    Rails.logger.info("Processing page '#{subreport[:urlname]}': Done")


  rescue => e
    Rails.logger.error("Error while processing page '#{subreport[:urlname]}': #{e.message}")
    subreport[:status] = 'unexpected error'
    subreport[:error_message] = e.message
    subreport[:error_trace] = e.backtrace.join("\n")

  ensure
    report << subreport
  end

end


generate_csv_report(report)
