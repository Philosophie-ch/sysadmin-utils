require 'csv'


begin
  parent_page = Alchemy::Page.find(5098)

  child_pages_info = []

  parent_page.children.each do |child|
    page_info = {
      id: child.id,
      name: child.name || "<no_name>",
      title: child.title || "<no_title>",
      urlname: child.urlname || "<no_urlname>",
      page_layout: child.page_layout || "<no_page_layout>",
      tags: child.tag_names || [],
      users: []
    }

    box = Box.find_by(page_id: child.id) # Query once and use the result

    if box
      if box.respond_to?(:users) && box.users.present?
        box.users.each do |user|
          page_info[:users] << { id: user.id, login: user.login }
        end
      elsif box.respond_to?(:user) && box.user
        page_info[:users] << { id: box.user.id, login: box.user.login }
      end
    end

    child_pages_info << page_info
  end


  # Find the maximum number of users for any page to determine the number of user columns
  max_users = child_pages_info.map { |page| page[:users].size }.max

  headers = ['id', 'name', 'title', 'slug', 'page_layout', 'tag_page_type', 'tag_media_1', 'tag_media_2', 'tag_language', 'tag_university', 'tag_canton', 'tag_special_content_1', 'tag_special_content_2', 'tag_references', 'tag_footnotes', 'tag_others'] + (1..max_users).map { |i| "user_#{i}_id" } + (1..max_users).map { |i| "user_#{i}_username" }


  CSV.open("multilingual_pages.csv", "wb", col_sep: ',', force_quotes: true) do |csv|
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
        page[:tag_others] = tag_others
      ]

      # User info
      page[:users].each_with_index do |user, index|
        row << user[:id]  # Assuming IDs are integers and don't need to be wrapped
        row << user[:login]
      end

      # If this page has fewer users than the max, fill the remaining user columns with nil
      ((page[:users].size * 2)...(max_users * 2)).each { row << nil }

      csv << row
    end
  end


rescue => e
  puts "\n\n\t============ Error ============\n\n#{e.message}\n\n"

end
