OUTPUT_DIR = "tasks-output/all-blobs"

FileUtils.mkdir_p(OUTPUT_DIR) unless Dir.exist?(OUTPUT_DIR)

blobs = ActiveStorage::Blob.all
total = blobs.count
puts "Downloading #{total} blobs..."

downloaded = 0
skipped = 0
failed = 0

blobs.find_each do |blob|
  filename = "#{blob.id}_#{blob.filename}"
  filepath = "#{OUTPUT_DIR}/#{filename}"

  if File.exist?(filepath)
    skipped += 1
    next
  end

  begin
    File.open(filepath, 'wb') do |f|
      f.write(blob.download)
    end
    downloaded += 1
    puts "  [#{downloaded + skipped + failed}/#{total}] #{filename} (#{(blob.byte_size / 1024.0).round(1)} KB)"
  rescue => e
    failed += 1
    puts "  [FAIL] #{filename}: #{e.message}"
  end
end

puts ""
puts "Done. Downloaded: #{downloaded}, Skipped: #{skipped}, Failed: #{failed}"
