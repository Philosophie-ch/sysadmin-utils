require 'csv'


begin
  parent_page = Alchemy::Page.find(5098)

  child_pages_info = []

  parent_page.children.each do |child|

    page_info = {

      # Basic page info
      id: child.id,
      name: child.name || "",
      title: child.title || "",
      urlname: child.urlname || "",
      page_layout: child.page_layout || "",
      tags: child.tag_names || [],
      users: [],

      # Alchemy elements
      has_audio_box_element: "",
      has_video_box_element: "",
      has_pdf_box_element: "",
      has_single_picture_element: "",
      has_picture_gallery_element: "",
      has_text_and_picture_element: "",
      has_embed_element: "",

      # Raw HTML tags
      has_html_header_tags: "",
      has_html_audio_tags: "",
      has_html_video_tags: "",
      has_html_picture_tags: "",
      has_html_iframe_tags: "",

      # Topics, AKA "themetags"
      themetags: "",

      page_report: [],
    }


    begin

      ############
      # User information, gotten from the box
      ############
      box = Box.find_by(page_id: child.id) # Query once and use the result

      if box
        if box.respond_to?(:users) && box.users.present?
          box.users.each do |user|
            page_info[:users] << { id: user.id, login: user.login }
          end
        elsif box.respond_to?(:user) && box.user
          page_info[:page_report] << "Info: page box, with box ID #{box.id}, has .user, not .users"
          page_info[:users] << { id: box.user.id, login: box.user.login }
        else
          page_info[:page_report] << "Info: page box, with box ID #{box.id}, has no .users nor .user"
        end
      end

      elements = child.elements

      ############
      # Alchemy element information
      ############
      page_info[:has_audio_box_element] = elements.any? { |element| element.name == 'audio_box' } ? "yes" : ""
      page_info[:has_video_box_element] = elements.any? { |element| element.name == 'video_box' } ? "yes" : ""
      page_info[:has_pdf_box_element] = elements.any? { |element| element.name == 'pdf_box' } ? "yes" : ""
      page_info[:has_single_picture_element] = elements.any? { |element| element.name == 'single_picture' } ? "yes" : ""
      page_info[:has_picture_gallery_element] = elements.any? { |element| element.name == 'picture_gallery' } ? "yes" : ""
      page_info[:has_text_and_picture_element] = elements.any? { |element| element.name == 'text_and_picture' } ? "yes" : ""
      page_info[:has_embed_element] = elements.any? { |element| element.name == 'embed' } ? "yes" : ""


      ############
      # HTML tag information
      ############
      elements.each do |element|
        case element.name

        when 'intro', 'text_block', 'text_and_picture'
          richtext_contents = element.contents.where(name: ['pre_headline', 'lead_text', 'text'])
          richtext_contents.each do |content|
            essence = content.essence

            body = essence.body? ? essence.body : ""

            # Regex to match any header tag from h1 to h6, even if multi-line
            has_html_header_tags = body.match?(/<h[1-6][^>]*>.*?<\/h[1-6]>/m)
            # Regex to match any audio tag, even if multi-line
            has_html_audio_tags = body.match?(/<audio[^>]*>.*?<\/audio>/m)
            # Regex to match any video tag, even if multi-line
            has_html_video_tags = body.match?(/<video[^>]*>.*?<\/video>/m)
            # Regex to match any picture tag, even if multi-line
            has_html_picture_tags = body.match?(/<img[^>]*>/m)
            # Regex to match any iframe tag, even if multi-line
            has_html_iframe_tags = body.match?(/<iframe[^>]*>.*?<\/iframe>/m)

            page_info[:has_html_header_tags] = "yes" if has_html_header_tags
            page_info[:has_html_audio_tags] = "yes" if has_html_audio_tags
            page_info[:has_html_video_tags] = "yes" if has_html_video_tags
            page_info[:has_html_picture_tags] = "yes" if has_html_picture_tags
            page_info[:has_html_iframe_tags] = "yes" if has_html_iframe_tags

            page_info[:page_report] << "Info: #{element.name} element with ID #{element.id} has header tags" if has_html_header_tags
            page_info[:page_report] << "Info: #{element.name} element with ID #{element.id} has audio tags" if has_html_audio_tags
            page_info[:page_report] << "Info: #{element.name} element with ID #{element.id} has video tags" if has_html_video_tags
            page_info[:page_report] << "Info: #{element.name} element with ID #{element.id} has picture tags" if has_html_picture_tags
            page_info[:page_report] << "Info: #{element.name} element with ID #{element.id} has iframe tags" if has_html_iframe_tags

          end

        when 'aside_column'
          # This one has nested elements
          element.elements.each do |nested_element|
            nested_element.contents.each do |content|
              essence = content.essence

              body = essence.body? ? essence.body : ""

              # Regex to match any header tag from h1 to h6, even if multi-line
              has_html_header_tags = body.match?(/<h[1-6][^>]*>.*?<\/h[1-6]>/m)
              # Regex to match any audio tag, even if multi-line
              has_html_audio_tags = body.match?(/<audio[^>]*>.*?<\/audio>/m)
              # Regex to match any video tag, even if multi-line
              has_html_video_tags = body.match?(/<video[^>]*>.*?<\/video>/m)
              # Regex to match any picture tag, even if multi-line
              has_html_picture_tags = body.match?(/<img[^>]*>/m)
              # Regex to match any iframe tag, even if multi-line
              has_html_iframe_tags = body.match?(/<iframe[^>]*>.*?<\/iframe>/m)

              page_info[:has_html_header_tags] = "yes" if has_html_header_tags
              page_info[:has_html_audio_tags] = "yes" if has_html_audio_tags
              page_info[:has_html_video_tags] = "yes" if has_html_video_tags
              page_info[:has_html_picture_tags] = "yes" if has_html_picture_tags
              page_info[:has_html_iframe_tags] = "yes" if has_html_iframe_tags

              page_info[:page_report] << "Info: aside_column element with ID #{element.id} has header tags" if has_html_header_tags
              page_info[:page_report] << "Info: aside_column element with ID #{element.id} has audio tags" if has_html_audio_tags
              page_info[:page_report] << "Info: aside_column element with ID #{element.id} has video tags" if has_html_video_tags
              page_info[:page_report] << "Info: aside_column element with ID #{element.id} has picture tags" if has_html_picture_tags
              page_info[:page_report] << "Info: aside_column element with ID #{element.id} has iframe tags" if has_html_iframe_tags
            end
          end
        end
      end


      ############
      # Themetags, which are essences inside the intro element
      ############
      intro_element = elements.find { |element| element.name == 'intro' }
      if intro_element
        topic_content = intro_element.contents.find { |content| content.name == 'topics' }
        topics = topic_content&.essence&.topics&.map(&:name).uniq.join(', ')
        page_info[:themetags] = topics
      end


    rescue => e
      page_info[:page_report] << "Unexpected error: #{e.message}"
    ensure
      child_pages_info << page_info
    end

  end


  # Find the maximum number of users for any page to determine the number of user columns
  max_users = child_pages_info.map { |page| page[:users].size }.max


  # Headers
  headers = ['id', 'name', 'title', 'slug', 'page_layout', 'tag_page_type', 'tag_media_1', 'tag_media_2', 'tag_language', 'tag_university', 'tag_canton', 'tag_special_content_1', 'tag_special_content_2', 'tag_references', 'tag_footnotes', 'tag_others']

  headers += (1..max_users).map { |i| "user_#{i}_id" } + (1..max_users).map { |i| "user_#{i}_username" }

  headers += ['has_audio_box_element', 'has_video_box_element', 'has_pdf_box_element', 'has_single_picture_element', 'has_picture_gallery_element', 'has_text_and_picture_element', 'has_embed_element']

  headers += ['has_html_header_tags', 'has_html_audio_tags', 'has_html_video_tags', 'has_html_picture_tags', 'has_html_iframe_tags']

  headers += ['themetags']

  headers += ['page_report']


  # Write the CSV file
  timestamp = Time.now.strftime("%y%m%d")

  CSV.open("#{timestamp}_multilingual_pages.csv", "wb", col_sep: ',', force_quotes: true) do |csv|
    csv << headers

    child_pages_info.each do |page|

      split_tags = page[:tags]

      tag_page_type_raw = split_tags.select { |tag| tag.include?('page type') }
      tag_page_type = tag_page_type_raw.first.split(':').last.strip if tag_page_type_raw.any?

      tag_media_1_raw = split_tags.select { |tag| tag.include?('media 1') }
      tag_media_1 = tag_media_1_raw.first.split(':').last.strip if tag_media_1_raw.any?

      tag_media_2_raw = split_tags.select { |tag| tag.include?('media 2') }
      tag_media_2 = tag_media_2_raw.first.split(':').last.strip if tag_media_2_raw.any?

      tag_language_raw = split_tags.select { |tag| tag.include?('language') }
      tag_language = tag_language_raw.first.split(':').last.strip if tag_language_raw.any?

      tag_university_raw = split_tags.select { |tag| tag.include?('university') }
      tag_university = tag_university_raw.first.split(':').last.strip if tag_university_raw.any?

      tag_canton_raw = split_tags.select { |tag| tag.include?('canton') }
      tag_canton = tag_canton_raw.first.split(':').last.strip if tag_canton_raw.any?

      tag_special_content_1_raw = split_tags.select { |tag| tag.include?('special content 1') }
      tag_special_content_1 = tag_special_content_1_raw.first.split(':').last.strip if tag_special_content_1_raw.any?

      tag_special_content_2_raw = split_tags.select { |tag| tag.include?('special content 2') }
      tag_special_content_2 = tag_special_content_2_raw.first.split(':').last.strip if tag_special_content_2_raw.any?

      tag_references_raw = split_tags.select { |tag| tag.include?('references') }
      tag_references = tag_references_raw.first.split(':').last.strip if tag_references_raw.any?

      tag_footnotes_raw = split_tags.select { |tag| tag.include?('footnotes') }
      tag_footnotes = tag_footnotes_raw.first.split(':').last.strip if tag_footnotes_raw.any?

      tag_others = split_tags.select { |tag| !tag.include?('page type') && !tag.include?('media 1') && !tag.include?('media 2') && !tag.include?('language') && !tag.include?('university') && !tag.include?('canton') && !tag.include?('special content 1') && !tag.include?('special content 2') && !tag.include?('references') && !tag.include?('footnotes') }

      if tag_others.length == 0
        tag_others = ""
      else
        tag_others = tag_others.join(', ')
      end


      # Basic page info
      row = [
        page[:id],
        page[:name],
        page[:title],
        page[:urlname],
        page[:page_layout],
        page[:tag_page_type] = tag_page_type,
        page[:tag_media_1] = tag_media_1,
        page[:tag_media_2] = tag_media_2,
        page[:tag_language] = tag_language,
        page[:tag_university] = tag_university,
        page[:tag_canton] = tag_canton,
        page[:tag_special_content_1] = tag_special_content_1,
        page[:tag_special_content_2] = tag_special_content_2,
        page[:tag_references] = tag_references,
        page[:tag_footnotes] = tag_footnotes,
        page[:tag_others] = tag_others,
      ]

      # User info
      page[:users].each_with_index do |user, index|
        row << user[:id]  # Assuming IDs are integers and don't need to be wrapped
        row << user[:login]
      end

      # If this page has fewer users than the max, fill the remaining user columns with nil
      ((page[:users].size * 2)...(max_users * 2)).each { row << nil }

      # Alchemy elements
      row << page[:has_audio_box_element]
      row << page[:has_video_box_element]
      row << page[:has_pdf_box_element]
      row << page[:has_single_picture_element]
      row << page[:has_picture_gallery_element]
      row << page[:has_text_and_picture_element]
      row << page[:has_embed_element]

      # HTML tags
      row << page[:has_html_header_tags]
      row << page[:has_html_audio_tags]
      row << page[:has_html_video_tags]
      row << page[:has_html_picture_tags]
      row << page[:has_html_iframe_tags]

      # Themetags
      row << page[:themetags]

      # Page report
      row << page[:page_report].join("; ")

      csv << row
    end
  end


rescue => e
  puts "\n\n\t============ Error ============\n\n#{e.message}\n\n"

end
