require 'csv'

require_relative 'lib/utils'
require_relative 'lib/publication_tools'

TABLE_NAME = 'publications'
ENTITY_NAME = 'publication'
KEY = :publication_key  # indexed unique key to identify an entity
KEY_NAME = KEY.to_s
MODEL = Publication
MODEL_NAME = "#{MODEL.name}"
FILE_NAME = "#{__FILE__}"


def main(csv_file, log_level = 'info')

  ############
  # SETUP
  ############

  ActiveRecord::Base.logger.level = Logger::WARN
  ActiveSupport::Deprecation.behavior = :silence  # silence useless deprecation warnings
  ActiveSupport::Deprecation.silenced = true
  ActiveSupport::Deprecation.debug = false  # Disable debug mode for deprecations


  Rails.logger.level = Logger::INFO

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


  report = []
  processed_lines = 0

  csv_data = CSV.read(csv_file, col_sep: ',', headers: true, encoding: 'utf-16')
  total_lines = csv_data.size


  ############
  # MAIN
  ############

  csv_data.each do |row|
    Rails.logger.info("Processing row #{processed_lines + 1} of #{total_lines}")
    # Read data
    subreport = {
      _incoming: row['_incoming'] || '',
      _sort: row['_sort'] || '',
      id: row['id'] || '',
      published: row['published'] || '',
      name: row['name'] || '',
      pre_headline: row['pre_headline'] || '',
      title: row['title'] || '',
      lead_text: row['lead_text'] || '',
      embedded_html_base_name: row['embedded_html_base_name'] || '',
      KEY => row[KEY_NAME] || '',
      url_prefix: row['url_prefix'] || '',
      open_access: row['open_access'] || '',
      pub_type: row['pub_type'] || '',
      link: row['link'] || '',
      _request: row['_request'] || '',
      bibkey: row['bibkey'] || '',
      how_to_cite: row['how_to_cite'] || '',
      doi: row['doi'] || '',
      metadata_json: row['metadata_json'] || '',
      aside_column: row['aside_column'] || '',
      created_at: row['created_at'] || '',
      ref_bib_keys: row['ref_bib_keys'] || '',
      references_asset_url: row['references_asset_url'] || '',
      _further_refs: row['_further_refs'] || '',
      further_references_asset_url: row['further_references_asset_url'] || '',
      _depends_on: row['_depends_on'] || '',
      external_link: row['external_link'] || '',
      abstract: row['abstract'] || '',
      assigned_authors: row['assigned_authors'] || '',
      cover_picture_asset: row['cover_picture_asset'] || '',
      pdf_asset: row['pdf_asset'] || '',
      pdf_availability: row['pdf_availability'] || '',
      themetags_discipline: row['themetags_discipline'] || '',
      themetags_focus: row['themetags_focus'] || '',
      themetags_badge: row['themetags_badge'] || '',
      themetags_structural: row['themetags_structural'] || '',
      additional_material: row['additional_material'] || '',
      _refs_in_xml: row['_refs_in_xml'] || '',

      # Tags (shared with pages via tag_tools.rb)
      tag_page_type: row['tag_page_type'] || '',
      tag_media: row['tag_media'] || '',
      tag_content_type: row['tag_content_type'] || '',
      tag_language: row['tag_language'] || '',
      tag_institution: row['tag_institution'] || '',
      tag_canton: row['tag_canton'] || '',
      tag_project: row['tag_project'] || '',
      tag_public: row['tag_public'] || '',
      tag_references: row['tag_references'] || '',
      tag_footnotes: row['tag_footnotes'] || '',

      status: '',
      changes_made: '',
      error_message: '',
      error_trace: '',
      warning_messages: '',
      original_order: '',
      result_order: '',
    }


    begin

      # Control
      Rails.logger.info("Processing #{ENTITY_NAME}: Control")
      supported_requests = ['POST', 'UPDATE', 'GET', 'DELETE', 'AD HOC']

      req = subreport[:_request].strip.upcase
      req_err = "Z_ERROR -- #{req}"

      if req.blank?
        subreport[:status] = ""
        subreport[:warning_messages] += " ::: Request is blank. Skipping."
        next
      else
        unless supported_requests.include?(req)
          subreport[:_request] = req_err
          subreport[:status] = "error"
          subreport[:error_message] = "Unsupported request '#{req}'. Skipping"
          subreport[:error_trace] = "#{FILE_NAME}.rb::main::Control::Main"
          next
        end
      end

      id = subreport[:id].strip
      entity_key = subreport[KEY].strip

      title = subreport[:title].strip

      if req == 'POST'
        if title.blank? || entity_key.blank?
          subreport[:_request] = req_err
          subreport[:status] = "error"
          subreport[:error_message] = "Need title and entity_key for POST. Skipping"
          subreport[:error_trace] = "#{FILE_NAME}::main::Control::POST"

          next
        end
        retrieved = MODEL.where(KEY => entity_key)

        if retrieved.present?
          subreport[:_request] = req_err
          subreport[:status] = "error"
          subreport[:error_message] = "#{MODEL_NAME} with key '#{entity_key}' already exists. Skipping"
          subreport[:error_trace] = "#{FILE_NAME}::main::Control::POST"

          next
        end
      end

      if ['UPDATE', 'GET', 'DELETE', 'AD HOC'].include?(req)
        if id.blank? && entity_key.blank?
          subreport[:_request] = req_err
          subreport[:status] = "error"
          subreport[:error_message] = "Need ID or #{KEY_NAME} for '#{req}'. Skipping"
          subreport[:error_trace] = "#{FILE_NAME}::main::Control::UPDATE-GET-DELETE"

          next
        end
      end

      entity_display_name = title.blank? ? (entity_key.blank? ? id : entity_key) : title

      # Parsing
      Rails.logger.info("Processing #{ENTITY_NAME} '#{entity_display_name}': Parsing")

      # Parse published field as boolean for model
      published_str = subreport[:published].strip.upcase
      published = nil
      unless published_str.blank?
        if published_str == 'PUBLISHED'
          published = true
        elsif published_str == 'UNPUBLISHED'
          published = false
        else
          # Handle legacy boolean values
          published = ['TRUE', '1', 'YES', 'T'].include?(published_str)
        end
      end

      # Parse url_prefix
      url_prefix = subreport[:url_prefix].strip

      # Validate external_link URL
      external_link_str = subreport[:external_link].to_s.strip
      external_link = ""
      unless external_link_str.blank?
        # Validate URL format
        unless external_link_str.start_with?("http://") || external_link_str.start_with?("https://")
          subreport[:_request] = req_err
          subreport[:status] = "error"
          subreport[:error_message] = "external_link '#{external_link_str}' is not a valid URL. Must start with http:// or https://"
          subreport[:error_trace] = "#{FILE_NAME}::main::Parsing::external_link"
          next
        end

        # Validate URI format
        begin
          uri = URI.parse(external_link_str)
          unless uri.is_a?(URI::HTTP) || uri.is_a?(URI::HTTPS)
            subreport[:_request] = req_err
            subreport[:status] = "error"
            subreport[:error_message] = "external_link '#{external_link_str}' is not a valid HTTP/HTTPS URL"
            subreport[:error_trace] = "#{FILE_NAME}::main::Parsing::external_link"
            next
          end
          external_link = external_link_str
        rescue URI::InvalidURIError => e
          subreport[:_request] = req_err
          subreport[:status] = "error"
          subreport[:error_message] = "external_link '#{external_link_str}' is not a valid URL: #{e.message}"
          subreport[:error_trace] = "#{FILE_NAME}::main::Parsing::external_link"
          next
        end
      end

      # Parse authors list
      assigned_authors = parse_authors_list(subreport[:assigned_authors])

      # Parse and validate metadata_json - required field
      metadata_json_str = subreport[:metadata_json].to_s.strip
      if metadata_json_str.blank?
        subreport[:_request] = req_err
        subreport[:status] = "error"
        subreport[:error_message] = "metadata_json is required and cannot be empty"
        subreport[:error_trace] = "#{FILE_NAME}::main::Parsing::metadata_json"
        next
      end
      begin
        JSON.parse(metadata_json_str)
      rescue JSON::ParserError => e
        subreport[:_request] = req_err
        subreport[:status] = "error"
        subreport[:error_message] = "Invalid metadata_json '#{metadata_json_str[0..100]}...'. Must be valid JSON: #{e.message}"
        subreport[:error_trace] = "#{FILE_NAME}::main::Parsing::metadata_json"
        next
      end

      # Parse open_access field as boolean for model
      open_access_str = subreport[:open_access].strip.upcase
      open_access = nil
      unless open_access_str.blank?
        open_access = ['TRUE', '1', 'YES', 'T', 'OPEN ACCESS'].include?(open_access_str)
      end

      # Parse pub_type field - validate against MODEL::PUB_TYPES constant
      pub_type_str = subreport[:pub_type].strip
      pub_type = nil
      unless pub_type_str.blank?
        # Check if the provided pub_type is valid
        unless MODEL::PUB_TYPES.include?(pub_type_str)
          subreport[:_request] = req_err
          subreport[:status] = "error"
          subreport[:error_message] = "Invalid pub_type '#{pub_type_str}'. Must be one of: #{MODEL::PUB_TYPES.join(', ')}"
          subreport[:error_trace] = "#{FILE_NAME}::main::Parsing::pub_type"
          next
        end
        pub_type = pub_type_str
      end

      # Parse pdf_availability field - validate against MODEL::PDF_AVAILABILITY_TYPES constant
      pdf_availability_str = subreport[:pdf_availability].strip
      pdf_availability = nil
      unless pdf_availability_str.blank?
        # Check if the provided pdf_availability is valid
        unless MODEL::PDF_AVAILABILITY_TYPES.include?(pdf_availability_str)
          subreport[:_request] = req_err
          subreport[:status] = "error"
          subreport[:error_message] = "Invalid pdf_availability '#{pdf_availability_str}'. Must be one of: #{MODEL::PDF_AVAILABILITY_TYPES.join(', ')}"
          subreport[:error_trace] = "#{FILE_NAME}::main::Parsing::pdf_availability"
          next
        end
        pdf_availability = pdf_availability_str
      end

      # Setup
      Rails.logger.info("Processing #{ENTITY_NAME} '#{entity_display_name}': Setup")

      raw_cover_picture_asset = subreport[:cover_picture_asset].strip
      cover_picture_asset = raw_cover_picture_asset.blank? ? 'empty' : raw_cover_picture_asset

      raw_pdf_asset = subreport[:pdf_asset].strip
      pdf_asset = raw_pdf_asset.blank? ? 'empty' : raw_pdf_asset

      raw_references_asset_url = subreport[:references_asset_url].strip
      references_asset_url = raw_references_asset_url.blank? ? 'empty' : raw_references_asset_url

      raw_further_references_asset_url = subreport[:further_references_asset_url].strip
      further_references_asset_url = raw_further_references_asset_url.blank? ? 'empty' : raw_further_references_asset_url

      unprocessed_assets = [
        cover_picture_asset,
        pdf_asset,
        references_asset_url,
        further_references_asset_url
      ].join(',').strip

      if ['POST', 'UPDATE', 'AD HOC'].include?(req)

        processed_assets = process_asset_urls(unprocessed_assets)
        urls_check = check_asset_urls_resolve(processed_assets)

        if urls_check[:status] != 'success'
          subreport[:_request] = req_err
          subreport[:status] = "error"
          subreport[:error_message] = urls_check[:error_message]
          subreport[:error_trace] = urls_check[:error_trace]
          next
        end

      end

      processed_cover_picture_asset = process_asset_urls(cover_picture_asset).first.to_s.strip
      processed_pdf_asset = process_asset_urls(pdf_asset).first.to_s.strip
      processed_references_asset_url = process_asset_urls(references_asset_url).first.to_s.strip
      processed_further_references_asset_url = process_asset_urls(further_references_asset_url).first.to_s.strip


      entity = nil
      if ['UPDATE', 'GET', 'DELETE', 'AD HOC'].include?(req)
        entity_by_id = MODEL.find_by(id: id)
        entity_by_key = MODEL.find_by(KEY => entity_key)

        if entity_by_id.nil? && entity_by_key.nil?
          Rails.logger.error("#{MODEL_NAME} with ID '#{id}' or #{KEY_NAME} '#{entity_key} not found. Skipping")
          subreport[:_request] = req_err
          subreport[:status] = "error"
          subreport[:error_message] = "#{MODEL_NAME} with ID '#{id}' or #{KEY_NAME} '#{entity_key} not found. Skipping"
          subreport[:error_trace] = "#{FILE_NAME}::main::Setup::UPDATE-GET-DELETE"
          next
        end

        if entity_by_id && entity_by_key && entity_by_id.id != entity_by_key.id
          Rails.logger.error("Both #{MODEL_NAME} with ID '#{id}' and #{KEY_NAME} '#{entity_key}' found, but they are not the same. Skipping")
          subreport[:_request] = req_err
          subreport[:status] = "error"
          subreport[:error_message] = "Both #{MODEL_NAME} with ID '#{id}' and #{KEY_NAME} '#{entity_key}' found, but they are not the same: found by_id: [[ #{entity_by_id.id}, #{entity_by_id[KEY]} ]], found by_key: [[ #{entity_by_key.id}, #{entity_by_key[KEY]} ]]. Skipping"
          subreport[:error_trace] = "#{FILE_NAME}::main::Setup::UPDATE-GET-DELETE"
          next
        end

        if entity_by_id
          entity = entity_by_id
        else
          entity = entity_by_key
        end

      end


      # Execution
      Rails.logger.info("Processing #{ENTITY_NAME} '#{entity_display_name}': Execution")

      if req == 'DELETE'
        entity.delete

        entity_present = MODEL.find_by(id: id).present?

        if entity_present
          subreport[:_request] = req_err
          subreport[:status] = "error"
          subreport[:error_message] = "#{MODEL_NAME} with ID '#{id}' was not deleted for an unknown reason. Skipping"
          subreport[:error_trace] = "#{FILE_NAME}::main::Execution::DELETE"
          next
        else
          subreport[:id] = ''
          subreport[KEY] = ''
          subreport[:link] = ''
          subreport[:status] = "success"
          subreport[:changes_made] = "#{MODEL_NAME.upcase} WAS DELETED IN THE SERVER"
          next
        end
      end

      if req == "POST"

        entity = MODEL.new(
          KEY => entity_key,
        )

      end

      if ['UPDATE', 'GET'].include?(req)

        old_entity_key = entity[KEY]

        # Get current authors for comparison
        old_authors = entity.publication_authors.order(:position).map { |pa| pa.profile.slug }.join(',')

        old_entity = {
          _incoming: subreport[:_incoming],
          _sort: subreport[:_sort],
          id: subreport[:id],
          published: entity.published ? 'PUBLISHED' : 'UNPUBLISHED',
          name: entity.name || '',
          pre_headline: entity.pre_headline || '',
          title: entity.title || '',
          lead_text: entity.lead_text || '',
          embedded_html_base_name: subreport[:embedded_html_base_name],
          KEY => old_entity_key,
          url_prefix: entity.url_prefix,
          open_access: entity.open_access ? 'TRUE' : 'FALSE',
          pub_type: entity.pub_type || '',
          link: get_entity_link(old_entity_key, entity.url_prefix),
          _request: subreport[:_request],
          bibkey: entity.bibkey || '',
          how_to_cite: entity.how_to_cite || '',
          doi: entity.doi || '',
          metadata_json: entity.academic_metadata.blank? ? '' : entity.academic_metadata.to_json,
          aside_column: entity.aside_column || '',
          created_at: entity.created_at.nil? ? '' : entity.created_at.strftime('%Y-%m-%d'),
          ref_bib_keys: entity.ref_bib_keys || '',
          references_asset_url: entity.references_asset_url || '',
          _further_refs: subreport[:_further_refs],
          further_references_asset_url: entity.further_references_asset_url || '',
          _depends_on: subreport[:_depends_on],
          external_link: entity.external_link.to_s.strip || '',
          abstract: entity.abstract || '',
          assigned_authors: old_authors,
          cover_picture_asset: entity.cover_picture_asset || '',
          pdf_asset: entity.pdf_asset || '',
          pdf_availability: subreport[:pdf_availability],
          themetags_discipline: subreport[:themetags_discipline],
          themetags_focus: subreport[:themetags_focus],
          themetags_badge: subreport[:themetags_badge],
          themetags_structural: subreport[:themetags_structural],
          additional_material: subreport[:additional_material],
          _refs_in_xml: subreport[:_refs_in_xml],

          # Tags (from entity via tag_tools.rb)
        }.merge(tag_array_to_columns(entity.tag_names)).merge({
          status: '',
          changes_made: '',
          error_message: '',
          error_trace: '',
          warning_messages: '',
          original_order: '',
          result_order: '',
        })

      end

      if req == "UPDATE" || req == "POST"

        entity[KEY] = entity_key
        entity.published = published unless published.nil?
        entity.url_prefix = url_prefix
        entity.name = subreport[:name].to_s.strip
        entity.pre_headline = subreport[:pre_headline].to_s.strip
        entity.title = title
        entity.lead_text = subreport[:lead_text].to_s.strip
        entity.abstract = subreport[:abstract].to_s.strip

        entity.bibkey = subreport[:bibkey].to_s.strip
        entity.how_to_cite = subreport[:how_to_cite].to_s.strip
        entity.doi = subreport[:doi].to_s.strip
        entity.open_access = open_access unless open_access.nil?
        entity.pub_type = pub_type unless pub_type.nil?
        entity.aside_column = subreport[:aside_column].to_s.strip

        entity.ref_bib_keys = subreport[:ref_bib_keys].to_s.strip
        entity.references_asset_url = processed_references_asset_url
        entity.further_references_asset_url = processed_further_references_asset_url

        entity.external_link = external_link

        entity.cover_picture_asset = processed_cover_picture_asset
        entity.pdf_asset = processed_pdf_asset

        # Set tags from CSV columns (shared with pages via tag_tools.rb)
        tag_columns = {
          tag_page_type: subreport[:tag_page_type],
          tag_media: subreport[:tag_media],
          tag_content_type: subreport[:tag_content_type],
          tag_language: subreport[:tag_language],
          tag_institution: subreport[:tag_institution],
          tag_canton: subreport[:tag_canton],
          tag_project: subreport[:tag_project],
          tag_public: subreport[:tag_public],
          tag_references: subreport[:tag_references],
          tag_footnotes: subreport[:tag_footnotes],
        }
        entity.tag_names = tag_columns_to_array(tag_columns)

        # Set academic metadata from JSON string if provided
        unless metadata_json_str.blank?
          begin
            entity.set_academic_metadata_from_json(metadata_json_str)
          rescue => e
            Rails.logger.warn("Failed to set academic_metadata: #{e.message}")
            subreport[:warning_messages] += " ::: Failed to set academic_metadata: #{e.message}"
          end
        end

        entity.save!

        # Process authors after saving the entity
        if assigned_authors.any?
          authors_result = process_publication_authors(entity, assigned_authors)

          if authors_result[:warnings].any?
            subreport[:warning_messages] += " ::: Authors: #{authors_result[:warnings].join('; ')}"
          end

          if authors_result[:errors].any?
            subreport[:status] = "partial error"
            subreport[:error_message] += " ::: Authors: #{authors_result[:errors].join('; ')}"
          end
        end
      end

      # Update report
      Rails.logger.info("Processing #{ENTITY_NAME} '#{entity_display_name}': Updating report")


      #######
      # AD HOC
      # Special request not to be commited
      #######

      if req == 'AD HOC'

      end


      ############
      # REPORT
      ############
      updated_entity = MODEL.find_by(id: entity.id)

      new_link = get_entity_link(updated_entity[KEY], updated_entity.url_prefix)

      # Get current authors for report
      current_authors = updated_entity.publication_authors.order(:position).map { |pa| pa.profile.slug }.join(',')

      unprocessed_references_asset_url = updated_entity.references_asset_url.blank? ? 'empty' : updated_entity.references_asset_url
      unprocessed_further_references_asset_url = updated_entity.further_references_asset_url.blank? ? 'empty' : updated_entity.further_references_asset_url

      cover_pic_url = updated_entity.cover_picture_asset.to_s.strip || ''
      unprocessed_cover_picture_asset = cover_pic_url.blank? ? 'empty' : unprocess_asset_urls([cover_pic_url]).strip

      pdf_url = updated_entity.pdf_asset.to_s.strip || ''
      unprocessed_pdf_asset = pdf_url.blank? ? 'empty' : unprocess_asset_urls([pdf_url]).strip

      subreport.merge!({
        id: "#{updated_entity.id}".strip,
        KEY => updated_entity[KEY].strip,
        url_prefix: updated_entity.url_prefix,
        open_access: updated_entity.open_access ? 'TRUE' : 'FALSE',
        pub_type: updated_entity.pub_type.to_s.strip || '',

        published: updated_entity.published ? 'PUBLISHED' : 'UNPUBLISHED',
        name: updated_entity.name.to_s.strip || '',
        pre_headline: updated_entity.pre_headline.to_s.strip || '',
        title: updated_entity.title.to_s.strip || '',
        lead_text: updated_entity.lead_text.to_s.strip || '',
        abstract: updated_entity.abstract.to_s.strip || '',
        link: new_link,

        bibkey: updated_entity.bibkey.to_s.strip || '',
        how_to_cite: updated_entity.how_to_cite.to_s.strip || '',
        doi: updated_entity.doi.to_s.strip || '',
        metadata_json: updated_entity.academic_metadata.blank? ? '' : updated_entity.academic_metadata.to_json,
        aside_column: updated_entity.aside_column.to_s.strip || '',

        created_at: updated_entity.created_at.nil? ? '' : updated_entity.created_at.strftime('%Y-%m-%d'),

        ref_bib_keys: updated_entity.ref_bib_keys.to_s.strip || '',
        references_asset_url: unprocessed_references_asset_url,
        further_references_asset_url: unprocessed_further_references_asset_url,

        external_link: updated_entity.external_link.to_s.strip || '',

        assigned_authors: current_authors,
        cover_picture_asset: unprocessed_cover_picture_asset,
        pdf_asset: unprocessed_pdf_asset,
        pdf_availability: subreport[:pdf_availability],

      })

      # Merge tag columns from entity (shared with pages via tag_tools.rb)
      subreport.merge!(tag_array_to_columns(updated_entity.tag_names))

      subreport[:status] = 'success'


      ############
      # COMPLEX TASKS ON UPDATE AND POST
      ############

      if req == "UPDATE" || req == "POST"
        ## If some complext task is added and it fails, the status should be "partial error" and the request "... PARTIAL"

        ## Saving
        #entity.save!
        #entity.publish!
      end


      ############
      # CHANGES MADE
      ############

      if ['UPDATE', 'GET', 'AD HOC'].include?(req)
        changes = []
        subreport.each do |key, value|
          if old_entity[key] != value && key != :changes_made && key != :status && key != :error_message && key != :error_trace && key != :_request && key != :warning_messages && key != :result_order && key != :original_order
            # Skip if both old and new values are empty
            unless old_entity[key].to_s.empty? && value.to_s.empty?
              changes << "#{key}: {{ #{old_entity[key]} }} => {{ #{value} }}"
            end
          end
        end
        subreport[:changes_made] = changes.join(' ;;; ')
      end

      Rails.logger.info("Processing #{ENTITY_NAME} '#{subreport[KEY]}': Success!")
      subreport[:_request] = "Z_SUCCESS -- #{req}"


    rescue => e
      error_message = "#{e.class} :: #{e.message}"
      Rails.logger.error("Processing #{ENTITY_NAME}: Unhandled error!: #{error_message}")
      subreport[:_request] = req_err
      subreport[:status] = 'unhandled error'
      subreport[:error_message] = error_message
      subreport[:error_trace] = e.backtrace.join(" ::: ")

    ensure
      report << subreport
      Rails.logger.info("Processing #{ENTITY_NAME}: Done!. Processed lines so far: #{processed_lines + 1} of #{total_lines}")
      processed_lines += 1
    end

  end


  ############
  # REPORT
  ############

  report.each_with_index do |subreport, index|
    subreport[:original_order] = index + 1
  end

  status_ordering = {
    'success' => 1,
    'partial error' => 2,
    'error' => 3,
    'unhandled error' => 4,
    'not started' => 5,
  }

  report.sort_by! { |subreport| status_ordering[subreport[:status]] || 9999 }
  report.each_with_index do |subreport, index|
    subreport[:result_order] = index + 1
  end

  report.sort_by! { |subreport| subreport[:original_order] }

  generate_csv_report(report, TABLE_NAME)

end



if ARGV[0].blank?
  log_level = ""

else
  log_level = ARGV[0]
end

main("portal-tasks/#{TABLE_NAME}.csv", log_level)
