require 'csv'

filename = ARGV[0]

if filename.nil?
  puts "Please provide a filename as the first argument."
  exit
end

# Check that the file actually exists
unless File.exist?(filename)
  puts "The file '#{filename}' does not exist. Please provide a valid filename."
  exit
end

successes = []
errors = []
new_topics = []


# 1. Populate new topics by parsing the CSV
CSV.foreach(filename, headers: true, col_sep: ",") do |row|

  begin

    status = row["status"]

    if status == "exists"
      errors << ["Topic defined in row '#{row}' already exists"]
      next
    end

    name = row["name"]
    if Topic.find_by(name: name)
      errors << ["Topic with name '#{name}' already exists"]
      next
    end

    if status == "new"
      group = row["group"]
      type = row["type"]

      if name.to_s.strip.empty? || group.to_s.strip.empty? || type.to_s.strip.empty?
        errors << ["At least one of the required fields (name, group, type) is empty for row: '#{row}'"]
        next
      end

      group_sym = group.to_sym
      type_sym = type.to_sym
      new_topic = Topic.new(name: name, group: group_sym, interest_type: type_sym)
      new_topics << new_topic

    else
      errors << ["Status '#{status}' is not recognized for row: '#{row}'"]
      next
    end

  rescue => e
    errors << ["Error in row: '#{row}' - Error message: '#{e.message}'"]
    next
  end
end


# 2. Save the new topics
new_topics.each do |new_topic|
  begin
    new_topic.save
    successes << ["Topic '#{new_topic.name}' created successfully"]
  rescue => e
    errors << ["Error saving topic '#{new_topic.name}': '#{e.message}'"]
  end
end


# 3. Report
puts "\n\n***New topics report***\n\n
==> Successes:\n#{successes.join("\n")}\n\n
==> Errors:\n#{errors.join("\n")}\n\n
***End of new topics report***\n\n"
