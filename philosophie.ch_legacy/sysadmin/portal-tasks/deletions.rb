require 'csv'

require_relative 'lib/utils'

# Counterpart of news.rb: given lists of IDs (or keys) that you have in your spreadsheets, reports
# which ones no longer exist in the app (everything is hard-deleted, there is no soft delete).
#
# Input: portal-tasks/deletions.csv, one column per entity, any subset of the columns below, any lengths.
# Blank cells are ignored. Output: one column per entity with the missing IDs, padded like news.rb.
#
# Read-only: it only runs `SELECT id FROM ... WHERE id IN (...)`.
#
# NOTE: profile_id holds Alchemy::User ids (the `id` column of the profiles sheet and the profile_id
# column of news.rb), NOT Profile ids.

TABLE_NAME = 'deletions'
BATCH_SIZE = 10_000

# input column => output column, model and the column that identifies a record
ENTITIES = [
  { input: 'page_id', output: :deleted_pages, model: 'Alchemy::Page', column: :id },
  { input: 'profile_id', output: :deleted_profiles, model: 'Alchemy::User', column: :id },
  { input: 'event_id', output: :deleted_events, model: 'Event', column: :id },
  { input: 'themetag_id', output: :deleted_themetags, model: 'Topic', column: :id },
  { input: 'side_column_block_id', output: :deleted_side_column_blocks, model: 'SideColumnBlock', column: :id },
  { input: 'note_id', output: :deleted_notes, model: 'Note', column: :id },
  { input: 'publication_id', output: :deleted_publications, model: 'Publication', column: :id },
  { input: 'journal_id', output: :deleted_journals, model: 'Journal', column: :id },
  { input: 'publisher_id', output: :deleted_publishers, model: 'Publisher', column: :id },
  { input: 'translation_group_key', output: :deleted_translation_groups, model: 'PageTranslationGroup', column: :key },
  { input: 'site_section_key', output: :deleted_site_sections, model: 'SiteSection', column: :key },
].freeze


# Handles UTF-16 (Google Sheets exports used by the other scripts) and UTF-8, with or without BOM
def read_csv_any_encoding(file_path)
  bytes = File.binread(file_path)
  content = if bytes.start_with?("\xFF\xFE".b, "\xFE\xFF".b)
              bytes.force_encoding('utf-16').encode('utf-8')
            else
              bytes.force_encoding('utf-8').sub("\xEF\xBB\xBF".force_encoding('utf-8'), '').scrub('?')
            end
  CSV.parse(content, col_sep: ',', headers: true)
end


# Returns [values, invalid_values]. IDs must be digits only; keys are taken as they are.
def clean_values(raw_values, numeric)
  values = []
  invalid = []

  raw_values.each do |raw|
    value = raw.to_s.strip
    next if value.blank?

    if numeric
      if value.match?(/\A\d+\z/)
        values << value.to_i
      else
        invalid << value
      end
    else
      values << value
    end
  end

  [values.uniq, invalid.uniq]
end


def existing_values(model, column, values)
  values.each_slice(BATCH_SIZE).flat_map { |batch| model.where(column => batch).pluck(column) }
end


def main(csv_file, log_level = 'info')

  ############
  # SETUP
  ############

  ActiveRecord::Base.logger.level = Logger::WARN
  ActiveSupport::Deprecation.behavior = :silence  # silence useless deprecation warnings
  ActiveSupport::Deprecation.silenced = true
  ActiveSupport::Deprecation.debug = false  # Disable debug mode for deprecations

  case log_level.downcase
  when 'debug'
    Rails.logger.level = Logger::DEBUG
  when 'info'
    Rails.logger.level = Logger::INFO
  when 'warn'
    Rails.logger.level = Logger::WARN
  when 'error'
    Rails.logger.level = Logger::ERROR
  else
    Rails.logger.level = Logger::INFO
  end

  csv_data = read_csv_any_encoding(csv_file)

  results = {}  # output column => array of missing values
  extra_columns = {
    profiles_without_profile: [],
    invalid_values: [],
    warnings: [],
    summary: [],
  }


  ############
  # MAIN
  ############

  known_inputs = ENTITIES.map { |entity| entity[:input] }
  (csv_data.headers.compact.map(&:strip) - known_inputs).each do |unknown|
    extra_columns[:warnings] << "Unknown input column '#{unknown}' ignored. Known columns: #{known_inputs.join(', ')}"
  end

  ENTITIES.each do |entity|
    results[entity[:output]] = []
    next unless csv_data.headers.map { |h| h.to_s.strip }.include?(entity[:input])

    model = Object.const_get(entity[:model])
    numeric = entity[:column] == :id

    raw_values = csv_data.map { |row| row[entity[:input]] }
    values, invalid = clean_values(raw_values, numeric)

    Rails.logger.info("Checking #{values.length} #{entity[:input]} values against #{entity[:model]}")

    existing = existing_values(model, entity[:column], values)
    missing = values - existing

    results[entity[:output]] = missing
    invalid.each { |value| extra_columns[:invalid_values] << "#{entity[:input]}: #{value}" }
    extra_columns[:summary] << "#{entity[:output]}: #{missing.length} of #{values.length} checked"

    # Users that still exist but have no profile attached
    if entity[:input] == 'profile_id'
      with_profile = existing.each_slice(BATCH_SIZE).flat_map { |batch| Profile.where(user_id: batch).pluck(:user_id) }
      extra_columns[:profiles_without_profile] = existing - with_profile
      extra_columns[:summary] << "profiles_without_profile: #{extra_columns[:profiles_without_profile].length} of #{existing.length} existing users"
    end
  end


  ############
  # REPORT
  ############

  columns = results.merge(extra_columns)
  max_length = [columns.values.map(&:length).max || 0, 1].max

  report = (0...max_length).map do |index|
    columns.transform_values { |list| list[index] || '' }
  end

  puts extra_columns[:summary].join("\n")

  generate_csv_report(report, TABLE_NAME)

end



if ARGV[0].blank?
  log_level = ""

else
  log_level = ARGV[0]
end

main("portal-tasks/#{TABLE_NAME}.csv", log_level)
