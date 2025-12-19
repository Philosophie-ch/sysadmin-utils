# Shared tag handling utilities for Alchemy::Page and Publication models
# Both models use Gutentag via Alchemy::Taggable with tag_names interface
#
# Tag format: "prefix: value" (e.g., "page type: article", "media: text")
# This allows multiple CSV columns to map to a single tag_names array

# Tag configuration: { column_symbol: "prefix: " }
TAG_CONFIG = {
  tag_page_type: "page type: ",
  tag_media: "media: ",
  tag_content_type: "content type: ",
  tag_language: "language: ",
  tag_institution: "institution: ",
  tag_canton: "canton: ",
  tag_project: "project: ",
  tag_public: "public: ",
  tag_references: "references?: ",
  tag_footnotes: "footnotes?: ",
}.freeze


# Convert CSV tag columns to an array of prefixed tag strings
#
# @param row [Hash] Row data with tag column symbols as keys
# @param config [Hash] Tag configuration mapping columns to prefixes
# @return [Array<String>] Array of prefixed tag strings for tag_names assignment
#
# Example:
#   row = { tag_page_type: "article", tag_media: "text" }
#   tag_columns_to_array(row)
#   # => ["page type: article", "media: text"]
#
def tag_columns_to_array(row, config = TAG_CONFIG)
  tags = []

  config.each do |col, prefix|
    value = row.fetch(col, '').to_s.strip
    tags << "#{prefix}#{value}" unless value.empty?
  end

  # Handle tag_others (catch-all for non-prefixed tags)
  others = row.fetch(:tag_others, '').to_s.strip
  tags += others.split(',').map(&:strip).reject(&:empty?) unless others.empty?

  tags
end


# Convert an array of prefixed tag strings back to CSV column values
#
# @param tag_names [Array<String>] Array of tag strings from entity.tag_names
# @param config [Hash] Tag configuration mapping columns to prefixes
# @return [Hash] Hash with tag column symbols as keys and extracted values
#
# Example:
#   tag_names = ["page type: article", "media: text", "custom tag"]
#   tag_array_to_columns(tag_names)
#   # => { tag_page_type: "article", tag_media: "text", ..., tag_others: "custom tag" }
#
def tag_array_to_columns(tag_names, config = TAG_CONFIG)
  result = {}
  prefixes = config.values

  # Extract value for each configured prefix
  config.each do |col, prefix|
    match = tag_names.find { |t| t.start_with?(prefix) }
    result[col] = match ? match.sub(prefix, '') : ''
  end

  # Collect unmatched tags into tag_others
  others = tag_names.reject { |t| prefixes.any? { |p| t.start_with?(p) } }
  result[:tag_others] = others.empty? ? '' : others.join(', ')

  result
end
