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

def get_intro_box_image(page)
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

def update_intro_box_image(page, image_file_name)
  result = {
    status: 'not started',
    error_message: ''
  }
  begin
    intro_elements = ['intro', 'event_intro', 'call_for_papers_intro', 'job_intro']

    # Find the picture with the given image_file_name
    new_picture = Alchemy::Picture.find_by(image_file_name: image_file_name)

    if new_picture.nil?
      result[:status] = 'error'
      result[:error_message] = "Picture with image_file_name '#{image_file_name}' not found"
      return result
    end

    page.elements.each do |element|
      next unless intro_elements.include?(element.name)

      has_intro_picture = element.contents&.any? { |content| content.essence.is_a?(Alchemy::EssencePicture) }

      if has_intro_picture
        content = element.contents.find { |content| content.essence.is_a?(Alchemy::EssencePicture) }
        content.essence.update(picture: new_picture)
        page.publish!
        result[:status] = 'success'
        return result
      end
    end

    result[:status] = 'error'
    result[:error_message] = "No intro picture found"

  rescue => e
    result[:status] = 'error'
    result[:error_message] = e.message

  ensure
    result
  end
end

def get_audio_boxes_file_names(page)
  audio_boxes = page&.elements&.select { |element| element.name == 'audio_box' }

  audio_files = audio_boxes&.flat_map do |audio_box|
    audio_box.contents&.map do |content|
      essence = content.essence
      essence.respond_to?(:attachment) ? essence.attachment&.file_name : nil
    end
  end

  return audio_files&.compact&.blank? ? "" : audio_files.compact.join(', ')
end

def get_video_boxes_file_names(page)
  video_boxes = page&.elements&.select { |element| element.name == 'video_box' }

  video_files = video_boxes&.flat_map do |video_box|
    video_box.contents&.map do |content|
      essence = content.essence
      essence.respond_to?(:attachment) ? essence.attachment&.file_name : nil
    end
  end

  return video_files&.compact&.blank? ? "" : video_files.compact.join(', ')
end

def get_pdf_boxes_file_names(page)
  pdf_boxes = page&.elements&.select { |element| element.name == 'pdf_box' }

  pdf_files = pdf_boxes&.flat_map do |pdf_box|
    pdf_box.contents&.map do |content|
      essence = content.essence
      essence.respond_to?(:attachment) ? essence.attachment&.file_name : nil
    end
  end

  return pdf_files&.compact&.blank? ? "" : pdf_files.compact.join(', ')
end

def get_single_pictures_file_names(page)
  single_picture_elements = page&.elements&.select { |element| element.name == 'single_picture' }

  picture_files = single_picture_elements&.flat_map do |single_picture|
    single_picture.contents&.map do |content|
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
      error_message: ''
    }
  end

  result = {
    status: 'not started',
    error_message: '',
  }

  begin

    intro_element = page.elements.find { |element| element.name.include?('intro') }
    creator_essence = intro_element&.content_by_name(:creator)&.essence

    unless creator_essence
      result[:status] = 'error'
      result[:error_message] = "Creator essence not found"
      return result
    end

    author_list = authors_str.split(',').map(&:strip)
    users = []

    for author in author_list
      flag = true
      user = Alchemy::User.find_by(login: author)
      user_error_message = "Users with the following logins not found: "

      if user.nil?
        user_error_message += "'#{author}', "
        flag = false
      end

      if flag
        users << user
      end
    end

    if !flag
      result[:status] = 'error'
      user_error_message = user_error_message[0..-3]
      result[:error_message] = user_error_message
      return result
    end

    creator_essence.alchemy_users = users.uniq.compact
    creator_essence.save!

    result[:status] = 'success'

  rescue => e
    result[:status] = 'error'
    result[:error_message] = e.message

  ensure
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

  page_report = {
    _sort: row['_sort'],
    id: row['id'],  # page
    name: row['name'],  # page
    title: row['title'],  # page
    language_code: row['language_code'],  # page
    urlname: row['urlname'],  # page
    slug: row['slug'],  # "#{page.language_code}/#{page.urlname}" or just page.urlname if language_code == "en_UK"
    link: row['link'],  # "https://www.philosophie.ch/#{slug}"
    _request: row['_request'],
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

    intro_box_image: row['intro_box_image'],  # element
    audio_box_files: row['audio_box_files'],  # element
    video_box_files: row['video_box_files'],  # element
    pdf_box_files: row['pdf_box_files'],  # element
    picture_box_files: row['picture_box_files'],  # element

    has_picture_with_text: row['has_picture_with_text'],  # element
    has_html_header_tags: row['has_html_header_tags'],  # element

    themetags: row['themetags'],  # themetags

    status: '',
    changes_made: '',
    error_message: '',
  }


  begin

    Rails.logger.info("Processing page '#{page_report[:slug]}'...")

    # Control
    supported_requests = ['POST', 'UPDATE', 'GET', 'DELETE']
    req = page_report[:_request]

    if req.nil? || req.strip.empty? || req.strip == ''
      page_report[:status] = ""
    else
      unless supported_requests.include?(req)
        page_report[:status] = "error"
        page_report[:error_message] = "Unsupported request '#{req}'. Skipping"
      end
    end

    if req == 'POST'
      retreived_pages = Alchemy::Page.where(urlname: urlname)
      exact_page_match = retreived_pages.find { |p| p.language_code == language_code }
      if exact_page_match
        page_report[:status] = "error"
        page_report[:error_message] = "Page already exists. Skipping"
        next
      end
    end

    if req == 'UPDATE' || req == 'GET' || req == 'DELETE'
      id = page_report[:id] || ''
      if id.blank? || id == '' || id.nil?
        page_report[:status] = "error"
        page_report[:error_message] = "ID is empty, but required for '#{req}'. Skipping."
        next
      end
    end

    if req == 'UPDATE'
      language_code = page_report[:language_code]
      urlname = page_report[:urlname]

      if language_code.blank? || language_code == '' || language_code.nil? || urlname.blank? || urlname == '' || urlname.nil?
        page_report[:status] = "error"
        page_report[:error_message] = "language_code or urlname is empty. Skipping!"
        next
      end

    end


    # Parsing
    Rails.logger.info("Processing page '#{page_report[:slug]}': Parsing")
    id = page_report[:id] || ''
    name = page_report[:name] || ''
    title = page_report[:title] || ''
    language_code = page_report[:language_code] || ''
    urlname = page_report[:urlname] || ''
    slug = page_report[:slug] || ''
    link = page_report[:link] || ''
    page_layout = page_report[:page_layout] || ''

    tag_page_type = page_report[:tag_page_type] || ''
    tag_media_1 = page_report[:tag_media_1] || ''
    tag_media_2 = page_report[:tag_media_2] || ''
    tag_language = page_report[:tag_language] || ''
    tag_university = page_report[:tag_university] || ''
    tag_canton = page_report[:tag_canton] || ''
    tag_special_content_1 = page_report[:tag_special_content_1] || ''
    tag_special_content_2 = page_report[:tag_special_content_2] || ''
    tag_references = page_report[:tag_references] || ''
    tag_footnotes = page_report[:tag_footnotes] || ''
    tag_others = page_report[:tag_others] || ''

    assigned_authors = page_report[:assigned_authors] || ''

    intro_box_image = page_report[:intro_box_image] || ''

    audio_box_files = page_report[:audio_box_files] || ''
    video_box_files = page_report[:video_box_files] || ''
    pdf_box_files = page_report[:pdf_box_files] || ''
    picture_box_files = page_report[:picture_box_files] || ''

    has_picture_with_text = page_report[:has_picture_with_text] || ''
    has_html_header_tags = page_report[:has_html_header_tags] || ''

    themetags = page_report[:themetags] || ''


    # Setup
    Rails.logger.info("Processing page '#{page_report[:slug]}': Setup")

    if req == 'POST'
      page = Alchemy::Page.new

    elsif req == 'UPDATE' || req == 'GET' || req == 'DELETE'
      page = Alchemy::Page.find(id)

      if page.nil?
        Rails.logger.error("Page with ID '#{id}' not found. Skipping")
        page_report[:status] = "error"
        page_report[:error_message] = "Page with ID '#{id}' not found. Skipping"
        next
      end

    else  # Should not happen
      Rails.logger.error("Unsupported request '#{req}'. Skipping")
      page_report[:status] = "error"
      page_report[:error_message] = "Unsupported request '#{req}'. Skipping"
      next
    end

    if req == 'DELETE'
      page.delete
      if Alchemy::Page.find(id).exists?
        page_report[:status] = "error"
        page_report[:error_message] = "Page not deleted by an unknown reason!. Skipping"
        next
      else
        page_report[:status] = "success"
        next
      end
    end

    if req == 'UPDATE' || req == 'GET'
      old_page_tag_names = page.tag_names
      old_page_tag_columns = tag_array_to_columns(old_page_tag_names)
      old_page_assigned_authors = get_assigned_authors(page)

      old_page = {
        _sort: page_report[:_sort],
        id: page.id,
        name: page.name,
        title: page.title,
        language_code: page.language_code,
        urlname: page.urlname,
        slug: page_report[:slug],
        link: page_report[:link],
        _request: page_report[:_request],
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

        _to_do_on_the_portal: page_report[:_to_do_on_the_portal],

        assigned_authors: old_page_assigned_authors,

        intro_box_image: get_intro_box_image(page),
        audio_box_files: get_audio_boxes_file_names(page),
        video_box_files: get_video_boxes_file_names(page),
        pdf_box_files: get_pdf_boxes_file_names(page),
        picture_box_files: get_single_pictures_file_names(page),

        has_picture_with_text: page.elements.any? { |element| element.name == 'text_and_picture' } ? "yes" : "",
        has_html_header_tags: has_html_header_tags(page),

        themetags: get_themetags(page),

        status: '',
        changes_made: '',
        error_message: '',
      }
    end

    # Execution
    Rails.logger.info("Processing page '#{page_report[:slug]}': Execution")

    if req == "POST" || req == "UPDATE"
      Rails.logger.info("Processing page '#{page_report[:slug]}': Setting attributes")
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

      update_authors_report = update_assigned_authors(page, page_report[:assigned_authors])

      if update_authors_report[:status] != 'success'
        page_report[:status] = 'error'
        page_report[:error_message] = update_authors_report[:error_message]
        page_report[:error_message] += ". Skipping the rest!"
        next
      end

      update_intro_box_image_report = update_intro_box_image(page, intro_box_image)

      if update_intro_box_image_report[:status] != 'success'
        page_report[:status] = 'error'
        page_report[:error_message] = update_intro_box_image_report[:error_message]
        page_report[:error_message] += ". Skipping the rest!"
        next
      end

      # TODO: update_themetags

      # Saving
      successful_page_save = page.save!
      succcessful_page_publish = page.publish!
      successful_save = successful_page_save && succcessful_page_publish

      if successful_save
        page_report[:status] = 'success'
        page_report[:changes_made] = 'created'
      else
        page_report[:status] = 'error'
        page_report[:error_message] = 'Error while saving or publishing page'
        next
      end
    end

    # Update report
    Rails.logger.info("Processing page '#{page_report[:slug]}': Updating report")
    tags_to_cols = tag_array_to_columns(page.tag_names)
    retrieved_slug = Alchemy::Engine.routes.url_helpers.show_page_path({
      locale: !page.language.default ? page.language_code : nil, urlname: page.urlname
    })

    page_report.merge!({
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
      intro_box_image: get_intro_box_image(page),
      audio_box_files: get_audio_boxes_file_names(page),
      video_box_files: get_video_boxes_file_names(page),
      pdf_box_files: get_pdf_boxes_file_names(page),
      picture_box_files: get_single_pictures_file_names(page),
      has_picture_with_text: page.elements.any? { |element| element.name == 'text_and_picture' } ? "yes" : "",
      has_html_header_tags: has_html_header_tags(page),
      themetags: get_themetags(page),
    })


    if req == "UPDATE" || req == "GET"
      changes = []
      page_report.each do |key, value|
        if old_page[key] != value && key != :changes_made && key != :status && key != :error_message
          # Skip if both old and new values are empty
          unless old_page[key].to_s.empty? && value.to_s.empty?
            changes << "#{key}: #{old_page[key]} => #{value}"
          end
        end
      end
      page_report[:changes_made] = changes.join(' ;;; ')
    end

    page_report[:status] = 'success'
    Rails.logger.info("Processing page '#{page_report[:slug]}': Done")


  rescue => e
    Rails.logger.error("Error while processing page '#{page_report[:slug]}': #{e.message}")
    page_report[:status] = 'unexpected error'
    page_report[:error_message] = e.message

  ensure
    report << page_report
  end

end


generate_csv_report(report)
