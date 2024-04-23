# WARNING: be sure of what you are doing before using this script
# You have been warned

# Setup
new_root_page = Alchemy::Page.find(5098)  # The page where you want to move the children
parent_page = Alchemy::Page.find_by(urlname: "The urlname of the parent whose children you want to move")

# Main
parent_page.children.each do |child|
  child.tag_names = ["new tag 1", "new tag 2"]
  child.language_id = new_root_page.language_id
  child.language_code = new_root_page.language_code
  child.parent_id = new_root_page.id
  child.save
end

# With error handling
parent_page.children.each do |child|
  begin
    child.tag_names = ["new tag 1", "new tag 2"]
    child.language_id = new_root_page.language_id
    child.language_code = new_root_page.language_code
    child.parent_id = new_root_page.id
    child.save
  rescue => e
    puts "Failed to save child #{child.urlname}: #{e.message}"
    next
  end
end