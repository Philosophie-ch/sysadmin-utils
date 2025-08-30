def get_entity_link(entity_key, entity_name)
  if entity_key.blank? || entity_name.blank?
    return ""
  else
    return "https://www.philosophie.ch/#{entity_name}/#{entity_key}"
  end
end


#def get_entity_presentation_page(entity, entity_name)
  #urlname = entity&.presentation_page&.urlname.to_s.strip || ''
  #language_code = entity&.presentation_page&.language_code.to_s.strip || ''

  #if urlname.blank? || language_code.blank?
    #return nil
  #end

  #Alchemy::Page.find_by(urlname: urlname, language_code: language_code)
#end

def parse_authors_list(authors_string)
  return [] if authors_string.blank?

  authors_string.split(',').map(&:strip).reject(&:blank?)
end

def process_publication_authors(publication, author_slugs)
  return { success: true, warnings: [] } if author_slugs.blank?

  warnings = []
  errors = []
  
  publication.publication_authors.destroy_all

  author_slugs.each_with_index do |slug, index|
    profile = Profile.find_by(slug: slug)
    if profile
      begin
        publication.publication_authors.create!(
          profile: profile,
          position: index
        )
      rescue => e
        errors << "Failed to add author '#{slug}' at position #{index}: #{e.message}"
      end
    else
      warnings << "Profile with slug '#{slug}' not found"
    end
  end
  
  { 
    success: errors.empty?, 
    warnings: warnings,
    errors: errors
  }
end
