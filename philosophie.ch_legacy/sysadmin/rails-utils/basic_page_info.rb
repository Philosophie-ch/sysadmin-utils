# Description: This script fetches basic information about articles from the Alchemy CMS database.
# Usage: Run this script from the Rails console.

# Define the article IDs you want to fetch
article_ids = [9112, 8949, 9114, 7150, 7147, 9142, 7680, 8567, 8088, 8919, 8038, 8037]

article_ids.each do |id|
  article = Alchemy::Page.find(id)

  puts "Article ID: #{article.id}"
  puts "Name: #{article.name}"
  puts "Language Code: #{article.language_code}"
  puts "Language Root: #{article.language_root}"
  puts "URL Name: #{article.urlname}"
  puts "Creator ID: #{article.creator_id}"
  puts "Creator name: #{Alchemy::User.find(article.creator_id).name}"
  puts "\n"
end


# Hot patch the Box model to fix the users method
Box.class_eval do
  def users_custom
    Alchemy::User.where(id: user_ids)
  end
end

parent_page = Alchemy::Page.find(5098)

child_pages_info = []

parent_page.children.each do |child|
  page_info = {
    id: child.id,
    name: child.name || "<no_name>",
    title: child.title || "<no_title>",
    urlname: child.urlname || "<no_urlname>",
    page_layout: child.page_layout || "<no_page_layout>",
    tags: Array(child.tags).map(&:name),
    users: []
  }

  box = Box.find_by(page_id: child.id) # Query once and use the result

  if box
    if box.respond_to?(:users_custom) && box.users_custom.present?
      box.users_custom.each do |user|
        page_info[:users] << { id: user.id, login: user.login }
      end
    elsif box.respond_to?(:user) && box.user
      page_info[:users] << { id: box.user.id, login: box.user.login }
    end
  end

  child_pages_info << page_info
end


require 'csv'

# Find the maximum number of users for any page to determine the number of user columns
max_users = child_pages_info.map { |page| page[:users].size }.max

headers = ['id', 'name', 'title', 'slug', 'page_layout', 'tags'] + (1..max_us
ers).map { |i| "user_#{i}_id" } + (1..max_users).map { |i| "user_#{i}_username" }


CSV.open("child_pages_info.csv", "wb", col_sep: ',', force_quotes: true) do |csv|
  csv << headers

  child_pages_info.each do |page|
    # Basic page info
    row = [
      page[:id],
      page[:name],
      page[:title],
      page[:urlname],
      page[:page_layout],
      page[:tags].join('; ')
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
