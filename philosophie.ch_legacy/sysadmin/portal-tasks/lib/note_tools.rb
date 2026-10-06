TRUTHY_FLAGS = ['TRUE', '1', 'YES', 'T'].freeze


# Mark a row as failed. The caller is expected to `next` afterwards.
def set_row_error(subreport, req_err, message, trace)
  subreport[:_request] = req_err
  subreport[:status] = "error"
  subreport[:error_message] = message
  subreport[:error_trace] = trace
end


# 'PUBLISHED' / 'UNPUBLISHED' (or legacy boolean-like values). Blank returns nil (= leave unchanged).
def parse_published_flag(published_str)
  value = published_str.to_s.strip.upcase
  return nil if value.blank?
  return true if value == 'PUBLISHED'
  return false if value == 'UNPUBLISHED'

  TRUTHY_FLAGS.include?(value)
end


# 'TRUE' / 'FALSE'. Blank returns nil (= leave unchanged).
def parse_boolean_flag(flag_str)
  value = flag_str.to_s.strip.upcase
  return nil if value.blank?

  TRUTHY_FLAGS.include?(value)
end


# ISO 8601 datetime. Blank returns [nil, nil] (= leave unchanged).
# Returns [time, error_message]
def parse_published_at(published_at_str)
  value = published_at_str.to_s.strip
  return [nil, nil] if value.blank?

  parsed = Time.zone.parse(value) rescue nil
  return [nil, "Invalid published_at '#{value}'. Use ISO 8601, e.g. 2026-09-20T12:00:00Z"] if parsed.nil?

  [parsed, nil]
end


# Comma-separated language codes, validated against the Language table.
# Returns [codes, error_message]
def parse_content_languages(languages_str)
  codes = languages_str.to_s.split(',').map(&:strip).reject(&:blank?).uniq
  return [codes, nil] if codes.empty?

  unknown = codes - Language.where(code: codes).pluck(:code)
  return [[], "Unknown language code(s): #{unknown.join(', ')}"] unless unknown.empty?

  [codes, nil]
end


# All the columns that come from the database, in report format.
# Used both for the "before" snapshot and for the final report row.
def note_to_row(note)
  {
    id: note.id.to_s,
    title: note.title.to_s,
    summary: note.summary.to_s,
    body: note.body.to_s,
    author: note.author&.slug.to_s,
    content_languages: note.note_languages.order(:language_code).pluck(:language_code).join(','),
    slug: note.slug.to_s,
    link: get_entity_link(note.slug, ''),
    created_at: note.created_at.nil? ? '' : note.created_at.strftime('%Y-%m-%d'),
    last_updated_date: note.updated_at.nil? ? '' : note.updated_at.strftime('%Y-%m-%d'),
    anonymous: note.anonymous? ? 'TRUE' : 'FALSE',
    published: note.published? ? 'PUBLISHED' : 'UNPUBLISHED',
    published_at: note.published_at&.iso8601 || '',
    interest_count: note.note_interests.count.to_s,
    comment_count: note.comments.count.to_s,
  }
end
