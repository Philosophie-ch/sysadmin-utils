## Get these two from topic.rb in the portal code
# enum group: [:logic, :language, :ethic, :history, :aesthetic, :administrative, :badge_group]
SUPPORTED_GROUPS = ["logic", "language", "ethic", "history", "aesthetic", "administrative", "badge_group"]
# enum interest_type: [:structural, :discipline, :focus, :badge]
SUPPORTED_INTEREST_TYPES = ["structural", "discipline", "focus", "badge"]

TOPIC_LOCALES = ["de", "fr", "it", "en"]
TRANSLATED_TRUTHY = ["TRUE", "YES", "1"]

# The columns the report takes from the database after a request
TOPIC_NAME_COLUMNS = TOPIC_LOCALES.map { |locale| "name_#{locale}" }


# The fields of a row that are written to a topic, as stripped strings
def row_fields(row)
  fields = {}
  ["topic_key", "group", "interest_type", "color_theme", "translated", "translation_group", "name", "page_language_code", "page_urlname"].each do |column|
    fields[column.to_sym] = row[column].to_s.strip
  end
  TOPIC_LOCALES.each { |locale| fields[:"name_#{locale}"] = row["name_#{locale}"].to_s.strip }

  return fields
end


def parse_translated_flag(value)
  TRANSLATED_TRUTHY.include?(value.to_s.strip.upcase)
end


# The page of a topic in the report: its own page for an untranslated topic, none for a translated one
def topic_own_page(topic)
  return nil if topic.translated? || topic.page_id.blank?

  Alchemy::Page.find_by(id: topic.page_id)
end


def get_topic_url(topic)
  default_code = Language.default_language&.code
  path = TopicLinks.new(default_code).urls([topic.id])[topic.id]

  return path.nil? ? "" : "https://www.philosophie.ch#{path}"
end


# The columns of a row that come from the database, as strings
def topic_report_values(topic)
  page = topic_own_page(topic)

  values = {
    id: topic.id.to_s,
    topic_key: topic.key.to_s,
    group: topic.group.to_s,
    interest_type: topic.interest_type.to_s,
    color_theme: topic.color_theme.to_s,
    translated: topic.translated? ? "TRUE" : "FALSE",
    translation_group: topic.page_translation_group_key.to_s,
    name: topic.name.to_s,
    page_language_code: page ? page.language_code.to_s : "",
    page_urlname: page ? page.urlname.to_s : "",
    url: get_topic_url(topic),
  }

  TOPIC_LOCALES.each { |locale| values[:"name_#{locale}"] = topic["name_#{locale}"].to_s }

  return values
end


def find_topic_page(language_code, urlname)
  return nil if language_code.blank? && urlname.blank?

  if language_code.blank? || urlname.blank?
    raise "Page needs both page_language_code and page_urlname (got '#{language_code}' and '#{urlname}')."
  end

  page = Alchemy::Page.find_by(urlname: urlname, language_code: language_code)  # this combination is unique

  if page.nil?
    raise "Page with URL name '#{urlname}' and language code '#{language_code}' not found."
  end

  return page
end


# Puts the page in the translation group (which must exist). A page that is in another group is an error.
def put_page_in_translation_group(page, group_key)
  return if page.page_translation_group_key == group_key

  if page.page_translation_group_key.present?
    raise "Page #{page.id} ('#{page.urlname}') is already in the translation group '#{page.page_translation_group_key}'."
  end

  page.update!(page_translation_group_key: group_key)
end


# A translated topic needs the four names and a translation group and no name; an untranslated topic needs a name
# and none of the translated fields. Raises when the columns of the row do not match its translated flag.
def check_translation_columns(fields)
  filled_names = TOPIC_NAME_COLUMNS.select { |column| fields[column.to_sym].present? }
  empty_names = TOPIC_NAME_COLUMNS - filled_names

  if parse_translated_flag(fields[:translated])
    problems = []
    problems << "#{empty_names.join(', ')} empty" if empty_names.any?
    problems << "translation_group empty" if fields[:translation_group].blank?
    problems << "name filled" if fields[:name].present?
    raise "translated is TRUE but #{problems.join(', ')}." if problems.any?
  else
    problems = []
    problems << "name empty" if fields[:name].blank?
    problems << "#{filled_names.join(', ')} filled" if filled_names.any?
    problems << "translation_group filled" if fields[:translation_group].present?
    raise "translated is FALSE but #{problems.join(', ')}." if problems.any?
  end
end


# Sets the fields of a topic from the values of a row (strings) and saves it. `page` is the page found from
# page_language_code and page_urlname, or nil.
def apply_topic_fields(topic, fields, page)
  translated = parse_translated_flag(fields[:translated])

  topic.key = fields[:topic_key].presence
  topic.group = fields[:group]
  topic.interest_type = fields[:interest_type]
  topic.color_theme = fields[:interest_type] == "badge" ? fields[:color_theme].presence : topic.color_theme
  topic.translated = translated

  if translated
    topic.name = nil
    topic.page_id = nil
    topic.page_translation_group_key = fields[:translation_group].presence
    TOPIC_LOCALES.each { |locale| topic["name_#{locale}"] = fields[:"name_#{locale}"].presence }
  else
    topic.name = fields[:name].presence
    topic.page_id = page&.id
    topic.page_translation_group_key = nil
    TOPIC_LOCALES.each { |locale| topic["name_#{locale}"] = nil }
  end

  topic.save!
end


# The number of existing pages that carry the topic. Tags left behind by pages that were deleted do not count.
def topic_page_count(topic_id)
  AlchemyEssenceTopicsTopic
    .joins("JOIN alchemy_contents c ON c.essence_id = alchemy_essence_topics_topics.alchemy_essence_topic_id AND c.essence_type = 'Alchemy::EssenceTopic'")
    .joins("JOIN alchemy_elements e ON e.id = c.element_id")
    .joins("JOIN alchemy_pages p ON p.id = e.page_id")
    .where(topic_id: topic_id)
    .distinct
    .count("p.id")
end


# Replaces the topic ids in the saved article filters of the users with new_id (or removes them when new_id is nil).
# Returns the number of profiles changed.
def replace_topic_in_saved_filters(old_ids, new_id)
  old = old_ids.map(&:to_s)
  changed_profiles = 0

  Profile.where.not(saved_article_filters: {}).find_each do |profile|
    filters = profile.saved_article_filters.deep_dup
    changed = false

    ["badges", "topics", "disciplines"].each do |key|
      ids = filters[key]
      next unless ids.is_a?(Array) && (ids & old).any?

      filters[key] = ids.map { |id| old.include?(id) ? new_id&.to_s : id }.compact.uniq
      changed = true
    end

    if changed
      profile.update_column(:saved_article_filters, filters)
      changed_profiles += 1
    end
  end

  return changed_profiles
end
