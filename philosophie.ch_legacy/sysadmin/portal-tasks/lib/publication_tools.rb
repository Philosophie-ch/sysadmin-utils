def get_entity_link(entity_key, url_prefix)
  if entity_key.blank?
    return ""

  else
    if url_prefix.blank?
      return "https://www.philosophie.ch/#{entity_key}"
    else
      return "https://www.philosophie.ch/#{url_prefix}/#{entity_key}"
    end

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
  added_slugs = []

  publication.publication_authors.destroy_all

  author_slugs.each_with_index do |slug, index|
    profile = Profile.find_by(slug: slug)
    if profile
      begin
        publication.publication_authors.create!(
          profile: profile,
          position: index
        )
        added_slugs << slug
      rescue => e
        errors << "Failed to add author '#{slug}' at position #{index}: #{e.message}"
      end
    else
      warnings << "Profile with slug '#{slug}' not found"
    end
  end

  if errors.empty? && added_slugs.any?
    Rails.logger.warn("Re-added authors: #{added_slugs.join(', ')}")
  end

  {
    success: errors.empty?,
    warnings: warnings,
    errors: errors
  }
end

def get_pure_html_asset(entity, pure_links_base_url)
  full_url = entity.pure_html_asset.to_s.strip
  return "" if full_url.blank?
  return full_url.start_with?(pure_links_base_url) ? full_url.gsub(pure_links_base_url, "") : full_url
end

def resolve_supervisor_slugs_to_ids(slugs)
  warnings = []
  ids = []
  slugs.each do |slug|
    profile = Profile.find_by(slug: slug)
    if profile
      ids << profile.id
    else
      warnings << "Supervisor profile with slug '#{slug}' not found"
    end
  end
  { ids: ids, warnings: warnings }
end

def resolve_supervisor_ids_to_slugs(profile_ids)
  return '' if profile_ids.blank?
  profile_ids.map { |pid| Profile.find_by(id: pid)&.slug }.compact.join(',')
end


############
# REPORT ROW (same columns, in the same order, as the publications.rb report)
# Used by the scripts that re-export publications (swap_webp_publication_cover_pictures.rb).
############

PUBLICATION_REPORT_COLUMNS = %i[
  _incoming _sort id published hidden name
  pre_headline title lead_text embedded_html_base_name date publication_key
  url_prefix open_access pub_type link _request bibkey
  pure_html_asset doi spps_type spps_type_other work_type work_type_other
  institution institution_other supervisors supervisors_others ects mark
  mark_max distinction embedded_content_asset_url created_at _kw_level1 _kw_level2
  _kw_level3 _epoch _person _comm_for_profile_bib language _lang_der
  ref_bib_keys references_asset_url _further_refs further_references_asset_url _depends_on external_link
  abstract assigned_authors cover_picture_asset pdf1_asset pdf1_availability pdf2_asset
  pdf2_availability pdf3_asset pdf3_availability additional_material _refs_in_xml breadcrumb_key
  rejected_at status changes_made error_message error_trace warning_messages
  original_order result_order
].freeze

# A row with every column blank (or the given values). Raises on a column that is not in the layout.
def blank_publication_report_row(values = {})
  unknown = values.keys - PUBLICATION_REPORT_COLUMNS
  raise ArgumentError, "Unknown publication report column(s): #{unknown.join(', ')}" unless unknown.empty?

  PUBLICATION_REPORT_COLUMNS.to_h { |column| [column, ''] }.merge(values)
end

# The database-derived columns of a publication, in report format (as publications.rb GET reports them).
def build_publication_report_row(publication, result_order)
  asset = ->(url) { url.to_s.strip.blank? ? 'empty' : unprocess_asset_urls([url.to_s.strip]).strip }
  or_empty = ->(value) { value.blank? ? 'empty' : value }

  blank_publication_report_row(
    id: publication.id,  # an integer: the merge with the input CSV matches rows by it
    published: publication.published ? 'PUBLISHED' : 'UNPUBLISHED',
    hidden: publication.hidden? ? 'TRUE' : 'FALSE',
    name: publication.name.to_s.strip,
    pre_headline: publication.pre_headline.to_s.strip,
    title: publication.title.to_s.strip,
    lead_text: publication.lead_text.to_s.strip,
    date: publication.date.to_s.strip,
    publication_key: publication.publication_key.to_s.strip,
    url_prefix: publication.url_prefix.to_s,
    open_access: publication.open_access ? 'TRUE' : 'FALSE',
    pub_type: publication.pub_type.to_s.strip,
    link: get_entity_link(publication.publication_key, publication.url_prefix),
    bibkey: publication.bibkey.to_s.strip,
    pure_html_asset: asset.(publication.pure_html_asset),
    doi: publication.doi.to_s.strip,
    spps_type: publication.spps_type.to_s.strip,
    spps_type_other: publication.spps_type_other.to_s.strip,
    work_type: publication.work_type.to_s.strip,
    work_type_other: publication.work_type_other.to_s.strip,
    institution: publication.institution.to_s.strip,
    institution_other: publication.institution_other.to_s.strip,
    supervisors: resolve_supervisor_ids_to_slugs(publication.supervisor_profile_ids),
    supervisors_others: publication.supervisor_other.to_s.strip,
    ects: publication.ects.present? ? publication.ects.to_s : '',
    mark: publication.mark.present? ? publication.mark.to_s : '',
    mark_max: publication.mark_max.present? ? publication.mark_max.to_s : '',
    distinction: publication.distinction.to_s.strip,
    embedded_content_asset_url: publication.embedded_content_asset_url.to_s.strip,
    created_at: publication.created_at.nil? ? '' : publication.created_at.strftime('%Y-%m-%d'),
    ref_bib_keys: publication.ref_bib_keys.to_s.strip,
    references_asset_url: or_empty.(publication.references_asset_url),
    further_references_asset_url: or_empty.(publication.further_references_asset_url),
    external_link: publication.external_link.to_s.strip,
    abstract: publication.abstract.to_s.strip,
    assigned_authors: publication.publication_authors.order(:position).map { |pa| pa.profile.slug }.join(','),
    cover_picture_asset: asset.(publication.cover_picture_asset),
    pdf1_asset: asset.(publication.pdf1_asset),
    pdf1_availability: publication.pdf1_availability || 'missing',
    pdf2_asset: asset.(publication.pdf2_asset),
    pdf2_availability: publication.pdf2_availability || 'missing',
    pdf3_asset: asset.(publication.pdf3_asset),
    pdf3_availability: publication.pdf3_availability || 'missing',
    breadcrumb_key: publication.breadcrumb_key.to_s,
    rejected_at: publication.rejected_at&.iso8601 || '',
    result_order: result_order,
  )
end

# Row for a publication that is missing or failed. The caller sets status and result_order.
def build_error_publication_data(publication, error_message, error_trace = "")
  blank_publication_report_row(
    id: publication&.id || '',
    publication_key: publication&.publication_key.to_s,
    name: publication&.name.to_s.strip,
    title: publication&.title.to_s.strip,
    status: 'error',
    error_message: error_message,
    error_trace: error_trace,
  )
end
