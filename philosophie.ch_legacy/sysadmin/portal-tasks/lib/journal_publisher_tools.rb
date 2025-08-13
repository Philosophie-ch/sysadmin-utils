
def get_entity_link(entity_key, entity_name)
  if entity_key.blank? || entity_name.blank?
    return ""
  else
    return "https://www.philosophie.ch/#{entity_name}/#{entity_key}"
  end
end


def get_entity_presentation_page(entity, entity_name)
  urlname = entity&.presentation_page&.urlname.to_s.strip || ''
  language_code = entity&.presentation_page&.language_code.to_s.strip || ''

  if urlname.blank? || language_code.blank?
    return nil
  end

  Alchemy::Page.find_by(urlname: urlname, language_code: language_code)
end
