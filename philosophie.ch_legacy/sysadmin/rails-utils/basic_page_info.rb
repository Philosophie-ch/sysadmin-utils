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
