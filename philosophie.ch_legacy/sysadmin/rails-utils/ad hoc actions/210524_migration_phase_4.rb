require 'csv'

rp = Alchemy::Page.find(5098)

mismatched_slugs_single_pages = []
errors_single_pages = []

CSV.foreach('210524_migration_phase_4_single_pages.csv', col_sep: ',', headers: false) do |row|
  l = row[0]  
  slug_raw = row[1]
  id = row[2]
  tags = row[3..-1].map(&:strip)
  page = Alchemy::Page.find(id)
  ids_match = page.urlname == slug_raw

  if !ids_match
    mismatched_slugs_single_pages << [id, slug_raw, page.urlname]
    next
  end

  begin
    if page.parent_id != rp.id
      puts "Dry moving page #{id} to #{rp.id}"
      #page.tag_names = tags
      #page.language_id = rp.language_id
      #page.language_code = rp.language_code
      #page.parent_id = rp.id
      #page.save
    else
      errors_single_pages << [id, slug_raw, "Page already moved"]
    end
  rescue => e
    errors_single_pages << [id, slug_raw, e.message]
    next
  end 
end

puts "\n\n***Single pages report***\n\n
==> Mismatched slugs:\n#{mismatched_slugs_single_pages.join("\n")}\n\n
==> Errors:\n#{errors_single_pages.join("\n")}\n\n
***End of single pages report***\n\n"
