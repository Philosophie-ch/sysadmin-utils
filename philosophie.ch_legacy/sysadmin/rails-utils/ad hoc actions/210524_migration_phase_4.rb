require 'csv'

rp = Alchemy::Page.find(5098)

CSV.foreach('210524_migration_phase_4_single_pages.csv', col_sep: ',', headers: false) do |row|
  slug_raw = row[0]
  id = row[1]
  tags = row[2:row.size].map(&:strip)
  page = Alchemy::Page.find(id)
  ids_match = page.urlname == slug_raw
  puts "Page with id #{id} and urlname #{slug_raw} is matching? #{ids_match}"
end