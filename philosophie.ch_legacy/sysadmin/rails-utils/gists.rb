# Publishing
Alchemy::Page.find(9235).publish!

# Tagging
page = Alchemy::Page.find(9112)  # The page you want to tag
page.tag_names << "new tag"
page.save
# To remove a tag:
page.tag_names.delete("new tag")
page.save

# Creating topics
topic = Topic.new(name: "New Topic Name", description: "Description of the new topic", group: :logic, interest_type: :structural)
topic.save

# Remove all Tags:
Alchemy::Tag.destroy_all


# Remove all Legacy Urls:
Alchemy::LegacyPageUrl.destroy_all

# Force update all URLs (creates new legacy urls, just to be aware of):
Alchemy::Page.find_each{|p| p.update_urlname!}


# script to update the public_on on all pages, it outputs the page ids which have an invalid date in the URL:
Alchemy::Page.find_each do |page|
  part = page.urlname.split('/').last
  if part.starts_with?('20') || part.starts_with?('19')
    begin
       date = Date.parse part
      page.update public_on: date
    rescue ArgumentError => e
      puts "Invalid date on page with id #{page.id}"
    end
  end
end


# find the content of pages, through elements, contents, and essences

# rough way:
page_1 = Alchemy::Page.find(2)
page_1_elements = page_1.elements
page_1_element_1_contents = page_1_elements[1].contents

# Loop to retrieve the content of each essence:
page_1_element_1_contents .each do |c|
  essence = c.essence
  puts e.id
  puts e.body  # <= if it’s a Alchemy::EssenceText or Alchemy::EssenceRichText
  puts e.picture.image_file_name  # <= if it’s a Alchemy::EssencePicture
end; nil

# Flatten all essences in a page:
all_essences = page_1.elements.flat_map do |element|
  element.contents.map(&:essence)
end

all_essences.each do |essence|
  case essence
  when Alchemy::EssenceText, Alchemy::EssenceRichtext
	puts essence.body
  when Alchemy::EssencePicture
 	puts "\n<IMAGE>\n"
	puts essence.picture.image_file_name if essence.picture
	puts "\n</IMAGE>\n"
  else
	puts "Other essence type: #{essence.class.name}"
  end
end; nil

# Can also filter contents to grab only certain types of blocks
filtered_elements = page_1.elements.reject { |element| element.name == 'intro' }

# More complex filtering example: Find all articles with pictures
articles_with_pictures = Alchemy::Page.all.select do |p|
  # 1. Filter out non-article pages
  next unless p.page_layout == "article"

  p.elements.any? do |elem|
    # 2. Filter out intro elements
    next if elem.name == 'intro'

    # 3. Check if the element contains a picture
    elem.contents.any? { |c| c.essence.is_a?(Alchemy::EssencePicture) }
  end
end; nil
