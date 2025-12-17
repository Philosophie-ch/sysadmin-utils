require_relative 'utils'
require_relative 'profile_tools'


# Cited in
# For an update, execute first 'update_cited_in' on big-update-pages.rb, which will update the references_elements, then come back here
def generate_cited_on_cache()
  references_elements = Alchemy::Element.where(name: "references").reject { |element| element.ingredient("cited_author_ids").blank? }

  refs_cache = Hash.new { |h, k| h[k] = [] }
  references_authors = references_elements.map { |element| refs_cache[element.id] = element.ingredient("cited_author_ids")&.split(",")&.map(&:strip)&.uniq&.compact&.map(&:to_i) }

  filtered_cache = refs_cache.select { |k, v| v.present? }

  cache = Hash.new { |h, k| h[k] = [] }
  filtered_cache.each do |k, v|
    v.each do |id|
      cache[id] << k
    end
  end

  page_ids_cache = Hash.new { |h, k| h[k] = [] }
  cache.each do |user_id, element_ids|
    page_ids_cache[user_id] = Alchemy::Element.where(id: element_ids).pluck(:page_id)
  end

  return page_ids_cache
end

def update_cited_on(page_ids_cache)

  begin
    ActiveRecord::Base.transaction do

      # 1. Repristine profiles cited_on data completely
      Profile.update_all(pages_id_cited_on: [])

      # 2. Update profiles cited_on data
      page_ids_cache.each do |user_id, page_ids|
        user = Alchemy::User.find(user_id)
        profile = user.profile
        profile.update!(pages_id_cited_on: page_ids)
        user.save!
      end

    end

  rescue => e
    puts e
    puts e.class
    puts e.backtrace
  end

end


# Mentioned on
# This is an optimization over the one that happens in the loop in profile_tools.rb; the speed-up is of more than one order of magnitude (from ~16h for 6k profiles to ~1 minute)
def generate_profiles_pages_cache()

  richtexts = Alchemy::EssenceRichtext
    .left_outer_joins(element: :parent_element)
    .joins(:page)
    .where.not("alchemy_pages.urlname": MENTIONED_ON_PAGES_TO_EXCLUDE)
    .where("body LIKE ?", "%profil/%")
    .where("parent_elements_alchemy_elements.name IS NULL OR parent_elements_alchemy_elements.name != ?", "aside_column")
    .reject { |richtext| richtext.page.nil? }
  #.joins(:page).pluck("alchemy_contents.element_id")

  page_profile_hash = Hash.new { |h, k| h[k] = [] }
  # richtext_profile_hash[richtext_id] = [profile_id, profile_id, ...]
  richtexts.each_with_object(page_profile_hash) do |richtext, hash|
    profile_identifiers = richtext.body.scan(/profil\/([^"']+)["']/).flatten.map(&:strip).uniq.compact.map { |identifier| identifier.gsub("profil", "").gsub("/", "") }.uniq.compact.map { |identifier| identifier.split("%").first }.uniq.compact
    hash[richtext.page.id] += profile_identifiers
  end

  cache = Hash.new { |h, k| h[k] = [] }
  page_profile_hash.each do |page_id, profile_identifiers|
    profile_identifiers.each do |identifier|
      user = Alchemy::User.find_by(login: identifier)
      cache[user.id] << page_id if user.present?
    end
  end

  return cache

end

def update_mentioned_on(users_pages_cache)

  begin
    ActiveRecord::Base.transaction do

      # 1. Repristine profiles mentioned_on data completely
      Profile.update_all(pages_id_mentioned_on: [])

      # 2. Update profiles mentioned_on data
      users_pages_cache.each do |profile_id, page_ids|
        user = Alchemy::User.find(profile_id)
        user.profile.update!(pages_id_mentioned_on: page_ids)
        user.profile.save!
        user.save!
      end

    end

  rescue => e
    puts e
    puts e.class
    puts e.backtrace

  end
end
