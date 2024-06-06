require 'csv'

rp = Alchemy::Page.find(5098)

if rp.urlname != "index"
  # ABORT!!
  puts "The ID given as 'rp' is not the root page. Aborting."
  puts "The ID given as 'rp' was #{rp.id} and the urlname is #{rp.urlname}"
  exit
end

# Main loop for parents
moved_parents = []
mismatched_slugs_parents = []
errors_parents = []

CSV.foreach('060624_migration_phase_5_parents.csv', col_sep: ',', headers: false) do |row|
  begin
    l = row[0]
    slug_raw = row[1]
    id = row[2]
    new_tags = row[3..-1]
    page = Alchemy::Page.find_by(id: id)
    ids_match = page.urlname == slug_raw
  rescue => e
    errors_parents << [id, slug_raw, e.message]
    next
  end

  if ids_match
    begin
      if page.parent_id != rp.id
        #puts "Dry moving all children of page #{id} to #{rp.id}"
        page.children.each do |child|

          tags = child.tag_names
          new_tags.each do |new_tag|
            tags << new_tag unless tags.include?(new_tag)
          end
          page.tag_names = tags

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
    end
  else
    mismatched_slugs_parents << [id, slug_raw, page.urlname]
  end
end

puts "\n\n***Parents report***\n\n
==> Moved pages:\n#{moved_parents.join("\n")}\n\n
==> Mismatched slugs:\n#{mismatched_slugs_parents.join("\n")}\n\n
==> Errors:\n#{errors_parents.join("\n")}\n\n
***End of parents report***\n\n"
