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

CSV.foreach('060624_migration_phase_5_single_pages.csv', col_sep: ',', headers: false) do |row|
  begin
    l = row[0]
    slug_raw = row[1]
    id = row[2]
    new_tags = row[3..-1]
    page = Alchemy::Page.find_by(id: id)
    ids_match = page.urlname == slug_raw
  rescue => e
    errors_single_pages << [id, slug_raw, e.message]
    next
  end

  if ids_match
    begin
      if page.parent_id != rp.id

        tags = page.tag_names
        new_tags.each do |new_tag|
          tags << new_tag unless tags.include?(new_tag)
        end
        page.tag_names = tags

        page.language_id = rp.language_id
        page.language_code = rp.language_code
        page.parent_id = rp.id

        page.save

        new_page = Alchemy::Page.find(id)

        if new_page.parent_id == rp.id
          moved_single_pages << [id, slug_raw]
        else
          errors_single_pages << [id, slug_raw, "Page not moved for unknown reason"]
        end
      else
        errors_single_pages << [id, slug_raw, "Page already moved"]
      end
    rescue => e
      errors_single_pages << [id, slug_raw, e.message]
    end
  else
    mismatched_slugs_single_pages << [id, slug_raw, page.urlname]
  end

end


puts "\n\n***Single pages report***\n\n
==> Moved pages:\n#{moved_single_pages.join("\n")}\n\n
==> Mismatched slugs:\n#{mismatched_slugs_single_pages.join("\n")}\n\n
==> Errors:\n#{errors_single_pages.join("\n")}\n\n
***End of single pages report***\n\n"
