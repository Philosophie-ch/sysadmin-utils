# Publishing
Alchemy::Page.find(9235).publish!

# Tagging
page = Alchemy::Page.find(9112)  # The page you want to tag
page.tag_names << "new tag"
page.save

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