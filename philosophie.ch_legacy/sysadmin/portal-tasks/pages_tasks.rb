require 'csv'

require_relative 'lib/utils'
require_relative 'lib/page_tools'


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

  csv_data = CSV.read(csv_file, col_sep: ',', headers: true)
  total_lines = csv_data.size


  all_attachments_with_pages = get_all_attachments_with_pages()


  ############
  # MAIN
  ############

  csv_data.each do |row|
    Rails.logger.info("Processing row #{processed_lines + 1} of #{total_lines}")
    # Read data
    subreport = {
      _sort: row['_sort'] || "",
      id: row['id'] || "",  # page
      published: row['published'] || "",  # page
      name: row['name'] || "",  # page
      pre_headline: row['pre_headline'] || "",  # intro element
      title: row['title'] || "",  # page
      lead_text: row['lead_text'] || "",  # intro element
      embedded_html_base_name: row['embedded_html_base_name'] || "",  # page
      language_code: row['language_code'] || "",  # page
      urlname: row['urlname'] || "",  # page
      slug: row['slug'] || "", # page
      link: row['link'] || "",  # crafted
      _request: row['_request'] || "",
      _article_bib_key: row['_article_bib_key'] || "",  # article
      how_to_cite: row['how_to_cite'] || "",  # article
      pure_html_asset: row['pure_html_asset'] || "",  # element
      pure_pdf_asset: row['pure_pdf_asset'] || "",  # element
      doi: row['doi'] || "",  # article
      created_at: row['created_at'] || "",  # page
      page_layout: row['page_layout'] || "",  # page

      tag_page_type: row['tag_page_type'] || "",  # tag
      tag_media_1: row['tag_media_1'] || "",  # tag
      tag_media_2: row['tag_media_2'] || "",  # tag
      tag_language: row['tag_language'] || "",  # tag
      tag_university: row['tag_university'] || "",  # tag
      tag_canton: row['tag_canton'] || "",  # tag
      tag_special_content_1: row['tag_special_content_1'] || "",  # tag
      tag_special_content_2: row['tag_special_content_2'] || "",  # tag
      tag_references: row['tag_references'] || "",  # tag
      tag_footnotes: row['tag_footnotes'] || "",  # tag

      ref_bib_keys: row['ref_bib_keys'] || "",  # element
      references_asset_url: row['references_asset_url'] || "",  # element
      _further_refs: row['_further_refs'] || "",
      further_references_asset_url: row['further_references_asset_url'] || "",  # element
      _depends_on: row['_depends_on'] || "",

      _to_do_on_the_portal: row['_to_do_on_the_portal'] || "",

      assigned_authors: row['assigned_authors'] || "",  # box

      intro_image_asset: row['intro_image_asset'] || "",  # element
      intro_image_portal: row['intro_image_portal'] || "",  # element
      audio_assets: row['audio_assets'] || "",
      audios_portal: row['audios_portal'] || "",  # element
      video_assets: row['video_assets'] || "",
      videos_portal: row['videos_portal'] || "",  # element
      pdf_assets: row['pdf_assets'] || "",
      pdfs_portal: row['pdfs_portal'] || "",  # element
      picture_assets: row['picture_assets'] || "",
      pictures_portal: row['pictures_portal'] || "",  # element
      text_and_picture_assets: row['text_and_picture_assets'] || "",  # element
      text_and_pictures_portal: row['text_and_pictures_portal'] || "",  # element
      box_assets: row['box_assets'] || "",  # nested element

      _attachment_links_assets: row['_attachment_links_assets'] || "",  # element
      attachment_links_portal: row['attachment_links_portal'] || "",  # element
      has_html_header_tags: row['has_html_header_tags'] || "",  # element
      external_links: row['external_links'] || "",

      themetags_discipline: row['themetags_discipline'] || "",  # themetags
      themetags_focus: row['themetags_focus'] || "",  # themetags
      themetags_structural: row['themetags_structural'] || "",  # themetags

      status: '',
      changes_made: '',
      error_message: '',
      error_trace: '',
    }


    begin

      # Control
      Rails.logger.info("Processing page: Control")
      supported_requests = ['POST', 'UPDATE', 'GET', 'DELETE', 'GET RAW FILENAMES', 'EMBED-HTML', 'DL-RN', 'AD HOC', 'REFS URLS', 'PUBLISH', 'UNPUBLISH']

      req = subreport[:_request].strip

      if req.blank?
        subreport[:status] = ""
        next
      else
        unless supported_requests.include?(req)
          subreport[:_request] += " ERROR"
          subreport[:status] = "error"
          subreport[:error_message] = "Unsupported request '#{req}'. Skipping"
          subreport[:error_trace] = "pages_tasks.rb::main::Control::Main"
        end
      end

      id = subreport[:id].strip
      urlname = subreport[:urlname].strip
      language_code = subreport[:language_code].strip

      if req == 'POST'
        if urlname.blank? || language_code.blank?
          subreport[:_request] += " ERROR"
          subreport[:status] = "error"
          subreport[:error_message] = "Need urlname and language code for 'POST'. Skipping"
          subreport[:error_trace] = "pages_tasks.rb::main::Control::POST"
          next
        end
        retreived_pages = Alchemy::Page.where(urlname: urlname)
        exact_page_match = retreived_pages.find { |p| p.language_code == language_code }
        if exact_page_match
          subreport[:_request] += " ERROR"
          subreport[:status] = "error"
          subreport[:error_message] = "Page already exists. Skipping"
          subreport[:error_trace] = "pages_tasks.rb::main::Control::POST"
          next
        end
      end

      if ['UPDATE', 'GET', 'DELETE', 'GET RAW FILENAMES', 'EMBED-HTML', 'DL-RN', 'AD HOC', 'REFS URLS', 'PUBLISH', 'UNPUBLISH'].include?(req)
        if id.blank? && (language_code.blank? || urlname.blank?)
          subreport[:_request] += " ERROR"
          subreport[:status] = "error"
          subreport[:error_message] = "Need ID, or urlname + language code for '#{req}'. Skipping"
          subreport[:error_trace] = "pages_tasks.rb::main::Control::UPDATE/GET/DELETE"
          next
        end
      end

      page_identifier = urlname.blank? ? id : urlname

      # Parsing
      Rails.logger.info("Processing page '#{page_identifier}': Parsing")
      id = subreport[:id].strip
      name = subreport[:name].strip
      pre_headline = subreport[:pre_headline].strip
      title = subreport[:title].strip
      lead_text = subreport[:lead_text].strip
      html_basename = subreport[:embedded_html_base_name].strip


      # Metadata block
      how_to_cite = subreport[:how_to_cite].strip

      pure_links_base_url = "https://assets.philosophie.ch/dialectica/"

      pure_html_asset = subreport[:pure_html_asset].strip
      if pure_html_asset.blank?
        pure_html_asset_full_url = ""
      else
        pure_html_asset_full_url = pure_links_base_url + pure_html_asset
      end

      pure_pdf_asset = subreport[:pure_pdf_asset].strip
      if pure_pdf_asset.blank?
        pure_pdf_asset_full_url = ""
      else
        pure_pdf_asset_full_url = pure_links_base_url + pure_pdf_asset
      end

      doi = subreport[:doi].strip
      ##

      created_at = subreport[:created_at].strip
      page_layout = subreport[:page_layout].strip

      tag_page_type = subreport[:tag_page_type].strip
      tag_media_1 = subreport[:tag_media_1].strip
      tag_media_2 = subreport[:tag_media_2].strip
      tag_language = subreport[:tag_language].strip
      tag_university = subreport[:tag_university].strip
      tag_canton = subreport[:tag_canton].strip
      tag_special_content_1 = subreport[:tag_special_content_1].strip
      tag_special_content_2 = subreport[:tag_special_content_2].strip
      tag_references = subreport[:tag_references].strip
      tag_footnotes = subreport[:tag_footnotes].strip


      # References urls
      references_base_url = "https://assets.philosophie.ch/references/articles/"
      references_asset_url = subreport[:references_asset_url].strip

      if references_asset_url.blank?
        references_asset_full_url = ""
        further_references_asset_full_url = ""
      else
        references_asset_full_url = references_base_url + references_asset_url

        further_references_asset_url = subreport[:further_references_asset_url].strip

        if further_references_asset_url.blank?
          further_references_asset_full_url = ""
        else
          further_references_asset_full_url = references_base_url + further_references_asset_url
        end
      end


      assigned_authors = subreport[:assigned_authors].strip

      # new asset system
      intro_image_asset = subreport[:intro_image_asset].strip
      audio_block_assets = subreport[:audio_assets].strip
      video_block_assets = subreport[:video_assets].strip
      pdf_block_assets = subreport[:pdf_assets].strip
      picture_block_assets = subreport[:picture_assets].strip
      text_and_picture_assets = subreport[:text_and_picture_assets].strip
      box_assets = subreport[:box_assets].strip

      themetags_discipline = subreport[:themetags_discipline].strip
      themetags_focus = subreport[:themetags_focus].strip
      themetags_structural = subreport[:themetags_structural].strip

      # Setup
      Rails.logger.info("Processing page '#{page_identifier}': Setup")

      if req == 'POST'
        page = Alchemy::Page.new

        alchemy_language_code = ''
        alchemy_country_code = ''
        if language_code.include?('-')
          alchemy_language_code = language_code.split('-').first
          alchemy_country_code = language_code.split('-').last
        else
          alchemy_language_code = language_code
        end

        language = Alchemy::Language.find_by(language_code: alchemy_language_code, country_code: alchemy_country_code)

        if language.nil?
          Rails.logger.error("Language with code '#{alchemy_language_code}' and country code '#{alchemy_country_code}' not found. Skipping")
          subreport[:_request] += " ERROR"
          subreport[:status] = "error"
          subreport[:error_message] = "Language with code '#{alchemy_language_code}' and country code '#{alchemy_country_code}' not found. Skipping"
          subreport[:error_trace] = "pages_tasks.rb::main::Setup::POST"
          next

        else
          root_page = Alchemy::Page.language_root_for(language.id)

          if root_page.nil?
            Rails.logger.error("Root page for language with code '#{alchemy_language_code}' and country code '#{alchemy_country_code}' not found. Skipping")
            subreport[:_request] += " ERROR"
            subreport[:status] = "error"
            subreport[:error_message] = "Root page for language with code '#{alchemy_language_code}' and country code '#{alchemy_country_code}' not found. Skipping"
            subreport[:error_trace] = "pages_tasks.rb::main::Setup::POST"
            next
          else
            page.parent_id = root_page.id
            page.language_id = root_page.language_id
            page.language_code = root_page.language_code
          end
        end

      elsif ['UPDATE', 'GET', 'DELETE', 'GET RAW FILENAMES', 'EMBED-HTML', 'DL-RN', 'AD HOC', 'REFS URLS', 'PUBLISH', 'UNPUBLISH'].include?(req)
        unless id.blank?
          page = Alchemy::Page.find(id)
        else
          unless urlname.blank? || language_code.blank?
            page = Alchemy::Page.find_by(urlname: urlname, language_code: language_code)  # this combination is unique
          else
            Rails.logger.error("Need ID, or urlname + language code for '#{req}'. Skipping")
            subreport[:_request] += " ERROR"
            subreport[:status] = "error"
            subreport[:error_message] = "Need ID, or urlname + language code for '#{req}'. Skipping"
            subreport[:error_trace] = "pages_tasks.rb::main::Setup::UPDATE-GET-DELETE"
            next
          end
        end

        if page.nil?
          Rails.logger.error("Page with ID '#{id}' or urlname '#{urlname}' and language code '#{language_code}' not found. Skipping")
          subreport[:_request] += " ERROR"
          subreport[:status] = "error"
          subreport[:error_message] = "Page with ID '#{id}' or urlname '#{urlname}' and language code '#{language_code}' not found, but needed for #{req}. Skipping"
          subreport[:error_trace] = "pages_tasks.rb::main::Setup::UPDATE-GET-DELETE"
          next
        end

      else  # Should not happen
        Rails.logger.error("How did we get here? Unsupported request '#{req}'. Skipping")
        subreport[:_request] += " ERROR"
        subreport[:status] = "error"
        subreport[:error_message] = "How did we get here? Unsupported request '#{req}'. Skipping"
        subreport[:error_trace] = "pages_tasks.rb::main::Setup::Main"
        next
      end

      if req == 'DELETE'
        page.delete
        if !id.blank?
          page_present = Alchemy::Page.find_by(id: id).present?
        elsif !urlname.blank? && !language_code.blank?
          page_present = Alchemy::Page.find_by(urlname: urlname, language_code: language_code).present?
        else
          page_present = false
        end

        if page_present
          subreport[:_request] += " ERROR"
          subreport[:status] = "error"
          subreport[:error_message] = "Page not deleted by an unknown reason!. Skipping"
          subreport[:error_trace] = "pages_tasks.rb::main::Setup::DELETE"
          next
        else
          subreport[:id] = ''
          subreport[:slug] = ''
          subreport[:link] = ''
          subreport[:status] = "success"
          subreport[:changes_made] = "PAGE WAS DELETED IN THE SERVER"
          next
        end
      end

      if req == 'PUBLISH'
        page.publish!
        subreport[:status] = "success"
        subreport[:changes_made] = "PAGE WAS PUBLISHED"
        next
      elsif req == 'UNPUBLISH'
        unpublish_report = unpublish_page(page)
        if unpublish_report[:status] != 'success'
          subreport[:_request] = "#{req} ERROR"
          subreport[:status] = "error"
          subreport[:error_message] = unpublish_report[:error_message]
          subreport[:error_trace] = unpublish_report[:error_trace]
        else
          subreport[:status] = "success"
          subreport[:changes_made] = "PAGE WAS UNPUBLISHED"
        end
        next
      end

      if ['UPDATE', 'GET', 'GET RAW FILENAMES', 'AD HOC', 'REFS URLS'].include?(req)
        old_page_tag_names = page.tag_names
        old_page_tag_columns = tag_array_to_columns(old_page_tag_names)
        old_page_assigned_authors = get_assigned_authors(page)

        all_references_urls = get_references_urls(page)
        old_references_asset_url = all_references_urls[:references_url] ? all_references_urls[:references_url].gsub(references_base_url, '') : ''
        old_further_references_asset_url = all_references_urls[:further_references_url] ? all_references_urls[:further_references_url].gsub(references_base_url, '') : ''

        article_metadata_element = get_article_metadata_element(page)
        if article_metadata_element.nil?
          old_doi = ''
          old_how_to_cite = ''
          old_pure_html_asset = ''
          old_pure_pdf_asset = ''
        else
          old_doi = get_doi(article_metadata_element)
          old_how_to_cite = get_how_to_cite(article_metadata_element)
          old_pure_html_asset = get_pure_html_asset(article_metadata_element, pure_links_base_url)
          old_pure_pdf_asset = get_pure_pdf_asset(article_metadata_element, pure_links_base_url)
        end

        old_page = {
          _sort: subreport[:_sort],
          id: page.id,
          name: page.name,
          pre_headline: get_pre_headline(page),
          title: page.title,
          lead_text: get_lead_text(page),
          embedded_html_base_name: subreport[:embedded_html_base_name],
          language_code: page.language_code,
          urlname: page.urlname,
          slug: subreport[:slug],
          link: subreport[:link],
          _request: subreport[:_request],
          _article_bib_key: subreport[:_article_bib_key],
          how_to_cite: old_how_to_cite,
          pure_html_asset: old_pure_html_asset,
          pure_pdf_asset: old_pure_pdf_asset,
          doi: old_doi,
          created_at: subreport[:created_at],
          page_layout: subreport[:page_layout],

          tag_page_type: old_page_tag_columns[:tag_page_type],
          tag_media_1: old_page_tag_columns[:tag_media_1],
          tag_media_2: old_page_tag_columns[:tag_media_2],
          tag_language: old_page_tag_columns[:tag_language],
          tag_university: old_page_tag_columns[:tag_university],
          tag_canton: old_page_tag_columns[:tag_canton],
          tag_special_content_1: old_page_tag_columns[:tag_special_content_1],
          tag_special_content_2: old_page_tag_columns[:tag_special_content_2],
          tag_references: old_page_tag_columns[:tag_references],
          tag_footnotes: old_page_tag_columns[:tag_footnotes],

          ref_bib_keys: subreport[:ref_bib_keys],
          references_asset_url: old_references_asset_url,
          _further_refs: subreport[:_further_refs],
          further_references_asset_url: old_further_references_asset_url,
          _depends_on: subreport[:_depends_on],

          _to_do_on_the_portal: subreport[:_to_do_on_the_portal],

          assigned_authors: old_page_assigned_authors,

          intro_image_asset: subreport[:intro_image_asset],
          intro_image_portal: subreport[:intro_image_portal],
          audio_assets: subreport[:audio_assets],
          audios_portal: subreport[:audios_portal],
          video_assets: subreport[:video_assets],
          videos_portal: subreport[:videos_portal],
          pdf_assets: subreport[:pdf_assets],
          pdfs_portal: subreport[:pdfs_portal],
          picture_assets: subreport[:picture_assets],
          pictures_portal: subreport[:pictures_portal],
          text_and_picture_assets: subreport[:text_and_picture_assets],
          text_and_pictures_portal: subreport[:text_and_pictures_portal],
          box_assets: subreport[:box_assets],

          attachment_links_portal: get_attachment_links_portal(page, all_attachments_with_pages),
          external_links: subreport[:external_links],
          has_html_header_tags: has_html_header_tags(page),

          themetags_discipline: subreport[:themetags_discipline],
          themetags_focus: subreport[:themetags_focus],
          themetags_structural: subreport[:themetags_structural],

          status: '',
          changes_made: '',
          error_message: '',
          error_trace: '',
        }
      end

      # Execution
      Rails.logger.info("Processing page '#{page_identifier}': Execution")

      if req == "POST" || req == "UPDATE"
        Rails.logger.info("\t...POST or UPDATE: '#{page_identifier}': Setting attributes")
        page.name = name
        page.title = title
        page.language_code = language_code
        page.urlname = urlname
        page.page_layout = page_layout
        page.created_at = parse_created_at(created_at)

        tag_columns = {
          tag_page_type: tag_page_type,
          tag_media_1: tag_media_1,
          tag_media_2: tag_media_2,
          tag_language: tag_language,
          tag_university: tag_university,
          tag_canton: tag_canton,
          tag_special_content_1: tag_special_content_1,
          tag_special_content_2: tag_special_content_2,
          tag_references: tag_references,
          tag_footnotes: tag_footnotes,
        }

        page.tag_names = tag_columns_to_array(tag_columns)

        page.save!
        page.publish!

        # Elements need to be set after page creation, in case of POST
        set_pre_headline(page, pre_headline)
        set_lead_text(page, lead_text)
        page.save!

      end

      # Update report
      Rails.logger.info("Processing page '#{page_identifier}': Updating report")
      tags_to_cols = tag_array_to_columns(page.tag_names)
      retrieved_slug = retrieve_page_slug(page)

      if req == 'GET RAW FILENAMES'
        retrieved_intro_image_portal = get_intro_image_portal_raw_filename(page)
      elsif req == 'GET'
        retrieved_intro_image_portal = get_intro_image_portal(page)
      else
        retrieved_intro_image_portal = get_intro_image_portal(page)
      end


      ############
      # EMBED-HTML
      ############

      if req == 'EMBED-HTML'

        Rails.logger.info("\t...EMBED-HTML: '#{page_identifier}': Setting embed block")

        html_file = "dltc-web/#{html_basename}"

        if !File.exist?(html_file)
          Rails.logger.error("HTML file '#{html_file}' not found. Skipping")
          subreport[:_request] += " ERROR"
          subreport[:status] = "error"
          subreport[:error_message] = "HTML file '#{html_file}' not found. Skipping"
          subreport[:error_trace] = "pages_tasks.rb::main::EMBED-HTML"
          next
        end

        html_content = read_raw_html(html_file)

        if html_content.blank?
          Rails.logger.error("HTML file '#{html_file}' is empty. Skipping")
          subreport[:_request] += " ERROR"
          subreport[:status] = "error"
          subreport[:error_message] = "HTML file '#{html_file}' is empty. Skipping"
          subreport[:error_trace] = "pages_tasks.rb::main::EMBED-HTML"
          next
        end

        dltc_set_embed_block(page, html_content)

        Rails.logger.info("\t...EMBED-HTML: '#{page_identifier}': Embed block set!")
      end

      ############
      # DL-RN
      ############

      if req == 'DL-RN'

        Rails.logger.info("\t...DL-RN: '#{page_identifier}': Downloading and renaming pictures from 'picture_block' elements...")

        pictures = page.elements.where(name: "picture_block").map(&:contents).flatten.filter { |content| content.name == "picture" }.map(&:essence).map(&:picture)

        if !pictures.empty?
          base_dir = "dl-rn"
          n = 1
          asset_names = []

          pictures.each do |picture|
            if picture.nil?
              Rails.logger.error("\t...DL-RN: '#{page_identifier}': Picture #{n} is nil. Skipping")
              subreport[:error_message] += " --- DL-RN: Picture object n. #{n} is nil. Skipping --- "
              next
            end
            picture_path = picture.image_file.path
            picture_extension = picture.image_file_format
            # replace slashes with dashes
            sanitized_urlname = page.urlname.gsub('/', '-')
            filename = "#{sanitized_urlname}-pic#{n}.#{picture_extension}"

            download_report = Utils.download_asset(base_dir, filename, picture_path, "picture_block")

            if !download_report[:status] == "success"
              Rails.logger.error("\t...DL-RN: '#{page_identifier}': Error downloading picture '#{picture_path}': #{download_report[:status]} --- #{download_report[:error_message]}")
              subreport[:_request] += " PARTIAL"
              subreport[:status] = 'partial success'
              subreport[:error_message] = download_report[:error_message]
              subreport[:error_trace] = download_report[:error_trace]
              asset_names << "ERROR"

            else
              asset_names << filename
            end
            n += 1
          end

          subreport[:picture_assets] = asset_names.join(', ')

          Rails.logger.info("\t...DL-RN: '#{page_identifier}': Pictures downloaded and renamed!")

        else
          Rails.logger.info("\t...DL-RN: '#{page_identifier}': No pictures found")
        end
      end

      #######
      # REFS URLS
      #######

      if req == 'REFS URLS'

        # References urls
        set_references_block(page, references_asset_full_url, further_references_asset_full_url)
        new_references_urls = get_references_urls(page)

        subreport[:references_asset_url] = new_references_urls[:references_url] ? new_references_urls[:references_url].gsub(references_base_url, '') : ''
        subreport[:further_references_asset_url] = new_references_urls[:further_references_url] ? new_references_urls[:further_references_url].gsub(references_base_url, '') : ''

      end

      #######
      # AD HOC
      # Special request not to be commited
      #######

      if req == 'AD HOC'


      end


      ############
      # REPORT
      ############

      themetags_hashmap = get_themetags(page)


      subreport.merge!({
        id: page.id,
        name: page.name,
        pre_headline: get_pre_headline(page),
        title: page.title,
        lead_text: get_lead_text(page),
        language_code: page.language_code,
        urlname: page.urlname,
        slug: retrieved_slug,
        link: "https://www.philosophie.ch#{retrieved_slug}",
        created_at: get_created_at(page),
        page_layout: page.page_layout,
        tag_page_type: tags_to_cols[:tag_page_type],
        tag_media_1: tags_to_cols[:tag_media_1],
        tag_media_2: tags_to_cols[:tag_media_2],
        tag_language: tags_to_cols[:tag_language],
        tag_university: tags_to_cols[:tag_university],
        tag_canton: tags_to_cols[:tag_canton],
        tag_special_content_1: tags_to_cols[:tag_special_content_1],
        tag_special_content_2: tags_to_cols[:tag_special_content_2],
        tag_references: tags_to_cols[:tag_references],
        tag_footnotes: tags_to_cols[:tag_footnotes],
        ref_bib_keys: get_references_bib_keys(page),
        assigned_authors: get_assigned_authors(page),

        intro_image_asset: get_asset_names(page, "intro", ELEMENT_NAME_AND_URL_FIELD_MAP[:"intro"]),
        intro_image_portal: retrieved_intro_image_portal,
        audio_assets: get_asset_names(page, "audio_block", ELEMENT_NAME_AND_URL_FIELD_MAP[:"audio_block"]),
        audios_portal: get_audio_blocks_file_names(page),
        video_assets: get_asset_names(page, "video_block", ELEMENT_NAME_AND_URL_FIELD_MAP[:"video_block"]),
        videos_portal: get_video_blocks_file_names(page),
        pdf_assets: get_asset_names(page, "pdf_block", ELEMENT_NAME_AND_URL_FIELD_MAP[:"pdf_block"]),
        pdfs_portal: get_pdf_blocks_file_names(page),
        picture_assets: get_asset_names(page, "picture_block", ELEMENT_NAME_AND_URL_FIELD_MAP[:"picture_block"]),
        pictures_portal: get_picture_blocks_file_names(page),
        text_and_picture_assets: get_asset_names(page, "text_and_picture", ELEMENT_NAME_AND_URL_FIELD_MAP[:"text_and_picture"]),
        text_and_pictures_portal: get_text_and_picture_blocks_file_names(page),
        box_assets: get_asset_names(page, "box", ELEMENT_NAME_AND_URL_FIELD_MAP[:"box"]),

        attachment_links_portal: get_attachment_links_portal(page, all_attachments_with_pages),
        has_html_header_tags: has_html_header_tags(page),
        themetags_discipline: themetags_hashmap[:discipline],
        themetags_focus: themetags_hashmap[:focus],
        themetags_structural: themetags_hashmap[:structural],
      })


      ############
      # COMPLEX TASKS ON UPDATE AND POST
      ############

      subreport[:status] = 'success'

      if req == "UPDATE" || req == "POST"
        Rails.logger.info("Processing page '#{page_identifier}': Complex tasks")


        # Authors
        update_authors_report = update_assigned_authors(page, assigned_authors)
        if update_authors_report[:status] != 'success'
          subreport[:_request] += " PARTIAL"
          subreport[:status] = 'partial success'
          subreport[:error_message] = update_authors_report[:error_message]
          subreport[:error_message] += ". Page saved, but update_assigned_authors failed! Stopping...\n"
          subreport[:error_trace] = update_authors_report[:error_trace] + "\n"
          next
        end
        subreport[:assigned_authors] = get_assigned_authors(page)


        # References bibkeys
        update_references_report = set_references_bib_keys(page, subreport[:ref_bib_keys])

        if update_references_report[:status] != 'success'
          subreport[:_request] += " PARTIAL"
          subreport[:status] = 'partial success'
          subreport[:error_message] += update_references_report[:error_message]
          subreport[:error_message] += ". Page saved, but set_references_bib_keys failed! Stopping...\n"
          subreport[:error_trace] += update_references_report[:error_trace] + "\n"
        end
        subreport[:ref_bib_keys] = get_references_bib_keys(page)


        # Themetags
        themetags = themetags_discipline.split(',').map(&:strip) + themetags_focus.split(',').map(&:strip) + themetags_structural.split(',').map(&:strip)
        update_themetags_report = set_themetags(page, themetags)

        if update_themetags_report[:status] != 'success'
          subreport[:_request] += " PARTIAL"
          subreport[:status] = 'partial success'
          subreport[:error_message] += update_themetags_report[:error_message]
          subreport[:error_message] += ". Page saved, but set_themetags failed! Stopping...\n"
          subreport[:error_trace] += update_themetags_report[:error_trace] + "\n"
        end

        new_themetags_hashmap = get_themetags(page)
        subreport[:themetags_discipline] = new_themetags_hashmap[:discipline]
        subreport[:themetags_focus] = new_themetags_hashmap[:focus]
        subreport[:themetags_structural] = new_themetags_hashmap[:structural]


        # Article metadata
        if !how_to_cite.blank? || !pure_html_asset_full_url.blank? || !pure_pdf_asset_full_url.blank? || !doi.blank?

          set_article_metadata_report = set_article_metadata(page, how_to_cite, pure_html_asset_full_url, pure_pdf_asset_full_url, doi)

          if set_article_metadata_report[:status] != 'success'
            subreport[:_request] += " PARTIAL"
            subreport[:status] = 'partial success'
            subreport[:error_message] += set_article_metadata_report[:error_message]
            subreport[:error_message] += ". Page saved, but set_article_metadata failed! Stopping...\n"
            subreport[:error_trace] += set_article_metadata_report[:error_trace] + "\n"
          end

          new_metadata_element = get_article_metadata_element(page)
          new_how_to_cite = get_how_to_cite(new_metadata_element)
          new_pure_html_asset = get_pure_html_asset(new_metadata_element, pure_links_base_url)
          new_pure_pdf_asset = get_pure_pdf_asset(new_metadata_element, pure_links_base_url)
          new_doi = get_doi(new_metadata_element)

          subreport[:how_to_cite] = new_how_to_cite
          subreport[:pure_html_asset] = new_pure_html_asset
          subreport[:pure_pdf_asset] = new_pure_pdf_asset
          subreport[:doi] = new_doi
        end


        # Handle asset tasks
        unprocessed_asset_urls = {
          "intro": intro_image_asset,
          "audio_block": audio_block_assets,
          "video_block": video_block_assets,
          "pdf_block": pdf_block_assets,
          "picture_block": picture_block_assets,
          "text_and_picture": text_and_picture_assets,
          "box": box_assets,
        }

        ELEMENT_NAME_AND_URL_FIELD_MAP.each do |element_name, url_field_name|
          set_asset_result = set_asset_blocks(page, unprocessed_asset_urls[element_name], element_name, url_field_name)

          if set_asset_result[:status] != 'success'
            subreport[:_request] += " PARTIAL"
            subreport[:status] = 'partial success'
            subreport[:error_message] += " --- #{element_name}: {{ #{set_asset_result[:error_message]} }}"
          end
        end

        subreport[:intro_image_asset] = get_asset_names(page, 'intro', ELEMENT_NAME_AND_URL_FIELD_MAP[:'intro'])
        subreport[:audio_assets] = get_asset_names(page, 'audio_block', ELEMENT_NAME_AND_URL_FIELD_MAP[:'audio_block'])
        subreport[:video_assets] = get_asset_names(page, 'video_block', ELEMENT_NAME_AND_URL_FIELD_MAP[:'video_block'])
        subreport[:pdf_assets] = get_asset_names(page, 'pdf_block', ELEMENT_NAME_AND_URL_FIELD_MAP[:'pdf_block'])
        subreport[:picture_assets] = get_asset_names(page, 'picture_block', ELEMENT_NAME_AND_URL_FIELD_MAP[:'picture_block'])
        subreport[:text_and_picture_assets] = get_asset_names(page, 'text_and_picture', ELEMENT_NAME_AND_URL_FIELD_MAP[:'text_and_picture'])
        subreport[:box_assets] = get_asset_names(page, 'box', ELEMENT_NAME_AND_URL_FIELD_MAP[:'box'])


        # Saving
        page.save!
        page.publish!
        Rails.logger.info("Processing page '#{page_identifier}': Complex tasks: Success!")
      end



      if req == "UPDATE" || req == "GET" || req == "GET RAW FILENAMES" || req == 'AD HOC' || req == 'REFS URLS'
        changes = []
        subreport.each do |key, value|
          if old_page[key] != value && key != :changes_made && key != :status && key != :error_message && key != :error_trace && key != :_request
            # Skip if both old and new values are empty
            unless old_page[key].to_s.empty? && value.to_s.empty?
              changes << "#{key}: {{ #{old_page[key]} }} => {{ #{value} }}"
            end
          end
        end
        subreport[:changes_made] = changes.join(' ;;; ')
      end

      Rails.logger.info("Processing page '#{subreport[:urlname]}': Success!")


    rescue => e
      Rails.logger.error("Error while processing page '#{subreport[:urlname].blank? ? subreport[:id] : subreport[:urlname]}': #{e.message}")
      subreport[:status] = 'unhandled error'
      subreport[:error_message] = "#{e.class} :: #{e.message}"
      subreport[:error_trace] = e.backtrace.join("\n")

    ensure
      report << subreport
      Rails.logger.info("Processing page: Done!. Processed lines so far: #{processed_lines + 1} of #{total_lines}")
      processed_lines += 1
    end

  end


  ############
  # REPORT
  ############

  Utils.generate_csv_report(report, "pages")

end



if ARGV[0].blank?
  log_level = ""

else
  log_level = ARGV[0]
end

main("portal-tasks/pages_tasks.csv", log_level)
