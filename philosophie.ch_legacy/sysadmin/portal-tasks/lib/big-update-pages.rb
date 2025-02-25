require_relative 'utils'
require_relative 'page_tools'

require 'open-uri'
require 'nokogiri'


# Cited in
def get_references_with_main_url()
  return Alchemy::Element.where(name: "references").reject { |element| element.ingredient("references_asset_url").blank? }
end

def update_cited_in(references_elements)

  begin
    ActiveRecord::Base.transaction do

      references_elements.each do |element|

        url = element.ingredient("references_asset_url")
        if url.blank?
          next
        end

        html_content = URI.open(url).read
        doc = Nokogiri::HTML(html_content)

        # Get all the href attributes of the a tags, filter only those that include "/profil" as substring
        profile_links = doc.css('a').map { |link| link['href'] }.filter { |href| href.include? "/profil" }

        logins = profile_links.map { |link| link.split("profil/").last }.uniq.compact

        ids = Alchemy::User.where(login: logins).pluck(:id).uniq.compact

        ids_s = ids.join(", ")

        cited_ids_content = element.content_by_name("cited_author_ids")

        # If the ingredient doesn't exist, create it
        if cited_ids_content.nil?
          cited_ids_content = Alchemy::Content.create(
            element: element,
            name: "cited_author_ids",
            essence_type: "Alchemy::EssenceText",
          )
        end

        element.save!
        element.reload
        element.page.save!
        element.page.publish!

        # For some reason not blasting with saves and publishes prevents the update from actually happening
        cited_ids_content.essence.update(body: ids_s)
        cited_ids_content.save!
        cited_ids_content.reload
        element.save!
        element.reload
        element.page.save!
        element.page.publish!

      end
    end

  rescue => e
    puts "Error: #{e}"
  end
end
