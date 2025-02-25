require_relative 'utils'
require_relative 'profile_tools'


# Cited in
def get_references_with_cited_authors()
  return Alchemy::Element.where(name: "references").reject { |element| element.ingredient("cited_author_ids").blank? }
end

def update_cited_on(references_elements)

  begin

    ActiveRecord::Base.transaction do

      # 0. Prepare data
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
