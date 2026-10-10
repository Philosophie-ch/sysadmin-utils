require 'csv'
require 'fileutils'

# Compares the column headers of the Google Sheets tabs with the columns the portal-tasks scripts write.
#
# Input:  portal-tasks/sheet_headers.csv, wide: row 1 = tab names, below each tab name that tab's headers
#         in order (build it with a tab of =TRANSPOSE(FILTER('tab'!2:2, 'tab'!2:2<>"")) formulas).
#         Optional argument: another path to that CSV.
# Output: report on stdout, plus portal-tasks-reports/YYMMDD_check_headers_report.{txt,csv}
#
# Read-only and side-effect free: it never runs the other scripts. It reads their SOURCE (the hash that
# defines each report row) and, to expand the per-language columns, asks the app for the language codes
# (the same query site_sections.rb and translation_groups.rb use). Runs with `rails runner` or plain `ruby`.

TASKS_DIR = __dir__

# sheet tab => CRUD script that owns the layout (its `subreport = {` hash, plus what is added to it before processing starts)
TABS = {
  'themetags' => 'themetags',
  'profiles' => 'profiles',
  'biblio profiles' => 'profiles',
  'events' => 'events',
  'pages' => 'pages',
  'presentation pages' => 'pages',
  'notes' => 'notes',
  'publications' => 'publications',
  'translation_groups' => 'translation_groups',
  'site_sections' => 'site_sections',
  'sidecolumn_blocks' => 'side_column_blocks',
  'publishers' => 'publishers',
  'journals' => 'journals',
}.freeze

# Other scripts that write rows in a tab's layout. Every big hash in them is a row layout (success row,
# error row...) and every one of them must match the sheet. script => CRUD script it belongs to
ROW_SCRIPTS = {
  'export_profiles' => 'profiles',
  'swap_webp_profile_picture_urls' => 'profiles',
  'export_pages' => 'pages',
  'swap_webp_asset_urls' => 'pages',
  'export_side_column_blocks' => 'side_column_blocks',
  'swap_webp_publication_cover_pictures' => 'publications',
}.freeze

MIN_KEYS_FOR_ROW_LAYOUT = 10


############
# SHEET SIDE
############

def normalize_tab(name)
  name.to_s.strip.downcase.gsub(/[\s_\-]+/, '')
end

def read_text_any_encoding(path)
  bytes = File.binread(path)
  if bytes.start_with?("\xFF\xFE".b, "\xFE\xFF".b)
    bytes.force_encoding('utf-16').encode('utf-8')
  else
    bytes.force_encoding('utf-8').sub("﻿", '').scrub('?')
  end
end

# => { 'tab name' => ['col1', 'col2', ...] }
def read_sheet_headers(path)
  rows = CSV.parse(read_text_any_encoding(path))
  abort("#{path} is empty") if rows.empty?

  tabs = {}
  rows.first.each_with_index do |tab, col|
    next if tab.to_s.strip.empty?

    columns = rows.drop(1).map { |row| row[col].to_s.strip }
    columns.pop while columns.last == ''  # trailing blanks come from transposing a whole row; blanks in the middle are kept
    tabs[tab.strip] = columns
  end
  tabs
end


############
# SCRIPT SIDE (source files)
############

def script_lines(script)
  File.read(File.join(TASKS_DIR, "#{script}.rb"), encoding: 'utf-8').split("\n")
end

# The key column of the script, e.g. `KEY = :publication_key`
def key_constant(lines)
  line = lines.find { |l| l =~ /^KEY\s*=\s*:(\w+)/ }
  line && line[/^KEY\s*=\s*:(\w+)/, 1]
end

# Keys of the hash literal that opens on lines[start], in order (a key can appear twice: Ruby then keeps
# the first position and the last value). Several `key: value,` pairs may share a line.
# Returns [keys, index of the closing line].
def literal_keys(lines, start, key_const)
  keys = []
  indent = nil
  i = start + 1

  while i < lines.length && lines[i] !~ /^\s*\}\)?\s*$/
    line_indent = lines[i][/^\s*/]
    found = lines[i].scan(/(?:\A\s+|,\s+)(\w+):(?=\s)/).flatten
    found = [(key_const || 'KEY')] if found.empty? && lines[i] =~ /^\s+KEY\s*=>/

    unless found.empty?
      indent ||= line_indent
      keys.concat(found) if line_indent == indent
    end
    i += 1
  end

  [keys, i]
end

# Splits a raw key list into the columns Ruby really produces and the keys written twice
def unique_keys(keys)
  [keys.uniq, keys.select { |k| keys.count(k) > 1 }.uniq]
end

# Columns of a CRUD script's report: the `subreport = {` hash, then (before the first `begin`, i.e. before any
# row is processed) the per-language columns and the `subreport.merge!({...})` it adds.
def crud_layout(script, language_codes)
  lines = script_lines(script)
  key_const = key_constant(lines)
  start = lines.index { |l| l =~ /^\s*subreport\s*=\s*\{\s*$/ }
  return nil if start.nil?

  keys, i = literal_keys(lines, start, key_const)
  stop = (i...lines.length).find { |n| lines[n] =~ /^\s*begin\s*$/ } || lines.length

  n = i + 1
  while n < stop
    if (m = lines[n].match(/subreport\[:"(\w+?)_#\{code\}"\]\s*=/))
      keys.concat(language_codes.map { |code| "#{m[1]}_#{code}" }.reject { |k| keys.include?(k) })
    elsif lines[n] =~ /^\s*subreport\.merge!\(\{\s*$/
      merged, n = literal_keys(lines, n, key_const)
      keys.concat(merged.reject { |k| keys.include?(k) })
    end
    n += 1
  end

  keys, duplicates = unique_keys(keys)
  { line: start + 1, keys: keys, duplicates: duplicates }
end

# Every big hash literal is a row layout. Keys assigned to the same variable right after the literal
# (`row[:result_order] = ...` before the row goes into the report) are part of the layout too.
# Returns [{ line:, keys: }, ...]
def row_layouts(script)
  lines = script_lines(script)
  key_const = key_constant(lines)
  layouts = []
  i = 0

  while i < lines.length
    if lines[i] =~ /(=\s*\{|<<\s*\{|return\s*\{|^\s*\{)\s*$/
      keys, closing = literal_keys(lines, i, key_const)

      if keys.length >= MIN_KEYS_FOR_ROW_LAYOUT
        opening = lines[i].match(/^(\s*)(\w+)\s*=\s*\{\s*$/)
        if opening
          indent, variable = opening[1], opening[2]
          j = closing + 1
          while j < lines.length && j < closing + 40
            line = lines[j]
            break if line =~ /^\s*report\s*<</
            break if line =~ /\S/ && line[/^\s*/].length < indent.length

            assigned = line.match(/^#{indent}#{variable}\[:(\w+)\]\s*=/)
            keys << assigned[1] if assigned && !keys.include?(assigned[1])
            j += 1
          end
        end
        keys, duplicates = unique_keys(keys)
        layouts << { line: i + 1, keys: keys, duplicates: duplicates }
      end

      i = closing
    end
    i += 1
  end

  layouts.concat(shared_column_lists(lines))
  layouts
end

# Scripts can share an ordered `SOMETHING_REPORT_COLUMNS = %i[...]` list defined in a lib file they require
def shared_column_lists(script_source_lines)
  libs = script_source_lines.map { |l| l[/^require_relative\s+'lib\/(\w+)'/, 1] }.compact
  lists = []

  libs.each do |lib|
    path = File.join(TASKS_DIR, 'lib', "#{lib}.rb")
    next unless File.exist?(path)

    lib_lines = File.read(path, encoding: 'utf-8').split("\n")
    lib_lines.each_index do |i|
      declaration = lib_lines[i].match(/^([A-Z_]+_REPORT_COLUMNS)\s*=\s*%i\[\s*$/)
      next unless declaration

      words = []
      j = i + 1
      while j < lib_lines.length && lib_lines[j] !~ /^\]/
        words.concat(lib_lines[j].split)
        j += 1
      end
      keys, duplicates = unique_keys(words)
      lists << { line: i + 1, keys: keys, duplicates: duplicates, source: "#{declaration[1]} in lib/#{lib}.rb, line #{i + 1}" }
    end
  end

  lists
end

def language_codes
  Language.public_languages.ordered.pluck(:code)
rescue NameError, NoMethodError
  warn('NOTE: no Rails app, assuming languages de, fr, it, en for the per-language columns')
  %w[de fr it en]
end


############
# COMPARISON
############

# Indexes of one longest increasing subsequence
def longest_increasing_subsequence(seq)
  best = Array.new(seq.length, 1)
  prev = Array.new(seq.length, -1)
  seq.each_index do |i|
    i.times do |j|
      if seq[j] < seq[i] && best[j] + 1 > best[i]
        best[i] = best[j] + 1
        prev[i] = j
      end
    end
  end

  index = best.each_with_index.max_by { |length, _| length }&.last
  result = []
  while index && index != -1
    result << index
    index = prev[index]
  end
  result
end

# => array of problem lines (empty when identical, same order)
def compare(sheet, script, sheet_label: 'sheet', script_label: 'script')
  problems = []
  show = ->(list) { list.map { |c| c.empty? ? '(empty header)' : c }.join(', ') }

  [[sheet_label, sheet], [script_label, script]].each do |label, columns|
    empty_positions = columns.each_index.select { |i| columns[i].empty? }.map { |i| i + 1 }
    problems << "empty header cell(s) in #{label} at position(s): #{empty_positions.join(', ')}" unless empty_positions.empty?

    duplicates = columns.select { |c| !c.empty? && columns.count(c) > 1 }.uniq
    problems << "duplicate column names in #{label}: #{duplicates.join(', ')}" unless duplicates.empty?
  end

  missing = (sheet - script) - ['']
  extra = (script - sheet) - ['']
  problems << "in #{sheet_label} but not in #{script_label} (#{missing.length}): #{show.(missing)}" unless missing.empty?
  problems << "in #{script_label} but not in #{sheet_label} (#{extra.length}): #{show.(extra)}" unless extra.empty?

  squash = ->(name) { name.downcase.gsub(/\s+/, '') }
  extra.each do |column|
    twin = missing.find { |m| squash.(m) == squash.(column) }
    problems << "name differs only by case or whitespace: #{sheet_label} '#{twin}' vs #{script_label} '#{column}'" if twin
  end

  # Order of the columns both sides have (so a missing column does not hide an order problem)
  shared_in_sheet = sheet.uniq.select { |c| !c.empty? && script.include?(c) }
  shared_in_script = script.uniq.select { |c| !c.empty? && sheet.include?(c) }
  if shared_in_sheet != shared_in_script
    in_script_order = shared_in_script.each_with_index.to_h
    out_of_place = longest_increasing_subsequence(shared_in_sheet.map { |c| in_script_order[c] })
    first = shared_in_sheet.each_index.find { |i| shared_in_sheet[i] != shared_in_script[i] }
    scope = (missing.empty? && extra.empty?) ? 'same columns' : "the #{shared_in_sheet.length} columns both have"
    problems << "#{scope}, different order. First difference at shared position #{first + 1}: #{sheet_label} '#{shared_in_sheet[first]}' vs #{script_label} '#{shared_in_script[first]}'"
    moved = shared_in_sheet.each_index.reject { |i| out_of_place.include?(i) }
    problems << "#{moved.length} column(s) out of place (#{sheet_label} position -> #{script_label} position):"
    moved.each { |i| problems << "    #{shared_in_sheet[i]}: #{sheet.index(shared_in_sheet[i]) + 1} -> #{script.index(shared_in_sheet[i]) + 1}" }
  end

  problems
end


############
# MAIN
############

sheet_path = ARGV[0].to_s.strip.empty? ? File.join(TASKS_DIR, 'sheet_headers.csv') : ARGV[0]
abort("#{sheet_path} not found. Export your _headers tab as CSV there (see the header of this script).") unless File.exist?(sheet_path)

sheet_tabs = read_sheet_headers(sheet_path).map { |tab, columns| [normalize_tab(tab), [tab, columns]] }.to_h
languages = language_codes

text = []
csv_rows = []
ok_count = 0
problem_count = 0

record = lambda do |tab, script, layout, problems, duplicates = []|
  problems += ["keys written twice in the hash (Ruby produces one column for each): #{duplicates.join(', ')}"] unless duplicates.empty?
  status = problems.empty? ? 'OK' : 'MISMATCH'
  problems.empty? ? ok_count += 1 : problem_count += 1
  csv_rows << [tab, script, layout, status, problems.join(' ;;; ')]
  text << "   #{status.ljust(8)} #{script}.rb [#{layout}]"
  problems.each { |problem| text << "            - #{problem}" }
end

TABS.each do |tab, owner|
  scripts = [owner] + ROW_SCRIPTS.select { |_, o| o == owner }.keys
  text << ''
  text << "## #{tab}   (scripts: #{scripts.map { |s| "#{s}.rb" }.join(', ')})"

  found = sheet_tabs[normalize_tab(tab)]
  if found.nil?
    text << '   MISSING TAB in the sheet CSV'
    csv_rows << [tab, '', '', 'MISSING TAB', 'tab not found in the sheet CSV']
    problem_count += 1
    next
  end

  sheet_columns = found[1]
  text << "   sheet: #{sheet_columns.length} columns"

  crud = crud_layout(owner, languages)
  if crud.nil?
    text << "   ERROR    #{owner}.rb: no `subreport = {` hash found"
    csv_rows << [tab, owner, 'subreport', 'ERROR', 'no subreport hash found']
    problem_count += 1
  else
    record.call(tab, owner, "subreport, line #{crud[:line]}", compare(sheet_columns, crud[:keys]), crud[:duplicates])
  end

  scripts.drop(1).each do |script|
    layouts = row_layouts(script)
    text << "   ERROR    #{script}.rb: no row layout found" if layouts.empty?
    problem_count += 1 if layouts.empty?
    layouts.each { |layout| record.call(tab, script, "row layout, #{layout[:source] || "line #{layout[:line]}"}", compare(sheet_columns, layout[:keys]), layout[:duplicates]) }
  end
end

# Tabs that share their scripts must be identical to each other
TABS.group_by { |_, owner| owner }.each_value do |pairs|
  names = pairs.map(&:first)
  next if names.length < 2

  first = sheet_tabs[normalize_tab(names.first)]
  names.drop(1).each do |other|
    second = sheet_tabs[normalize_tab(other)]
    next if first.nil? || second.nil?

    problems = compare(first[1], second[1], sheet_label: names.first, script_label: other)
    text << ''
    text << "## tabs '#{names.first}' vs '#{other}' (same scripts, must be identical): #{problems.empty? ? 'OK' : 'MISMATCH'}"
    problems.each { |problem| text << "   - #{problem}" }
    csv_rows << ["#{names.first} vs #{other}", '', 'tab vs tab', problems.empty? ? 'OK' : 'MISMATCH', problems.join(' ;;; ')]
    problems.empty? ? ok_count += 1 : problem_count += 1
  end
end

unmapped = sheet_tabs.reject { |key, _| TABS.keys.map { |t| normalize_tab(t) }.include?(key) }.values.map(&:first)
text << '' << "Note: tabs in the sheet CSV that are not mapped in this script (ignored): #{unmapped.join(', ')}" unless unmapped.empty?
text << '' << "#{ok_count} checks OK, #{problem_count} with problems (languages used for per-language columns: #{languages.join(', ')})"

puts text.join("\n")

FileUtils.mkdir_p('portal-tasks-reports')
base = "portal-tasks-reports/#{Time.now.strftime('%y%m%d')}_check_headers_report"
File.write("#{base}.txt", text.join("\n") + "\n")
File.write("#{base}.csv", CSV.generate { |csv| csv << %w[tab script layout status problems]; csv_rows.each { |row| csv << row } })
puts "\nReport written to #{base}.txt and #{base}.csv"
