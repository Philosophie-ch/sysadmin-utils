require 'csv'

rp = Alchemy::Page.find(5098)

if rp.urlname != "index"
  # ABORT!!
  puts "The ID given as 'rp' is not the root page. Aborting."
  puts "The ID given as 'rp' was #{rp.id} and the urlname is #{rp.urlname}"
  exit
end

# Main loop for single pages
moved_single_pages = []
mismatched_slugs_single_pages = []
errors_single_pages = []

CSV.foreach('210524_migration_phase_4_single_pages.csv', col_sep: ',', headers: false) do |row|
  l = row[0]  
  slug_raw = row[1]
  id = row[2]
  tags = row[3..-1]
  page = Alchemy::Page.find(id)
  ids_match = page.urlname == slug_raw

  if !ids_match
    mismatched_slugs_single_pages << [id, slug_raw, page.urlname]
    next
  end

  begin
    if page.parent_id != rp.id
      #puts "Dry moving page #{id} to #{rp.id}"
      page.tag_names = tags
      page.language_id = rp.language_id
      page.language_code = rp.language_code
      page.parent_id = rp.id
      page.save
      moved_single_pages << [id, slug_raw]
    else
      errors_single_pages << [id, slug_raw, "Page already moved"]
    end
  rescue => e
    errors_single_pages << [id, slug_raw, e.message]
    next
  end 
end


# Main loop for parents
moved_parents = []
mismatched_slugs_parents = []
errors_parents = []

CSV.foreach('210524_migration_phase_4_parents.csv', col_sep: ',', headers: false) do |row|
  l = row[0]  
  slug_raw = row[1]
  id = row[2]
  tags = row[3..-1]
  page = Alchemy::Page.find(id)
  ids_match = page.urlname == slug_raw

  if !ids_match
    mismatched_slugs_parents << [id, slug_raw, page.urlname]
    next
  end

  begin
    if page.parent_id != rp.id
      #puts "Dry moving all children of page #{id} to #{rp.id}"
      page.children.each do |child|
        child.tag_names = tags
        child.language_id = rp.language_id
        child.language_code = rp.language_code
        child.parent_id = rp.id
        child.save
      end
      moved_parents << [id, slug_raw]
    else
      errors_parents << [id, slug_raw, "Page already moved"]
    end
  rescue => e
    errors_parents << [id, slug_raw, e.message]
    next
  end 
end


puts "\n\n***Single pages report***\n\n
==> Moved pages:\n#{moved_single_pages.join("\n")}\n\n
==> Mismatched slugs:\n#{mismatched_slugs_single_pages.join("\n")}\n\n
==> Errors:\n#{errors_single_pages.join("\n")}\n\n
***End of single pages report***\n\n"


puts "\n\n***Parents report***\n\n
==> Moved pages:\n#{moved_parents.join("\n")}\n\n
==> Mismatched slugs:\n#{mismatched_slugs_parents.join("\n")}\n\n
==> Errors:\n#{errors_parents.join("\n")}\n\n
***End of parents report***\n\n"

