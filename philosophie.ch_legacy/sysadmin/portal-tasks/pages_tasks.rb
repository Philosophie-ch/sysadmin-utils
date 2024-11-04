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


  ############
  # MAIN
  ############

  csv_data.each do |row|
    Rails.logger.info("Processing row #{processed_lines + 1} of #{total_lines}")
    subreport = {
      _sort: row['_sort'] || "",
      id: row['id'] || "",  # page
      name: row['name'] || "",  # page
      title: row['title'] || "",  # page
      language_code: row['language_code'] || "",  # page
      urlname: row['urlname'] || "",  # page
      slug: row['slug'] || "", # page
      link: row['link'] || "",  # crafted
      _request: row['_request'] || "",
      _article_bib_key: row['_article_bib_key'] || "",  # article
      _doi: row['_doi'] || "",  # article
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
      tag_others: row['tag_others'] || "",  # tag

      ref_bib_keys: row['ref_bib_keys'] || "",  # box

      _assets: row['_assets'] || "",
      _to_do_on_the_portal: row['_to_do_on_the_portal'] || "",

      assigned_authors: row['assigned_authors'] || "",  # box

      intro_block_image: row['intro_block_image'] || "",  # element
      audio_block_files: row['audio_block_files'] || "",  # element
      video_block_files: row['video_block_files'] || "",  # element
      pdf_block_files: row['pdf_block_files'] || "",  # element
      picture_block_files: row['picture_block_files'] || "",  # element

      has_picture_with_text: row['has_picture_with_text'] || "",  # element
      attachment_links: row['attachment_links'] || "",  # element
      _other_assets: row['_other_assets'] || "",
      has_html_header_tags: row['has_html_header_tags'] || "",  # element

      themetags: row['themetags'] || "",  # themetags

      status: '',
      changes_made: '',
      error_message: '',
      error_trace: '',
    }


    begin

      # Control
      Rails.logger.info("Processing page: Control")
      supported_requests = ['POST', 'UPDATE', 'GET', 'DELETE', 'GET RAW FILENAMES']
      req = subreport[:_request].strip

      if req.blank?
        subreport[:status] = ""
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

      if req == 'UPDATE' || req == 'GET' || req == 'DELETE' || req == 'GET RAW FILENAMES'
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
      title = subreport[:title].strip
      slug = subreport[:slug].strip
      link = subreport[:link].strip
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
      tag_others = subreport[:tag_others].strip

      assigned_authors = subreport[:assigned_authors].strip

      intro_block_image = subreport[:intro_block_image].strip

      audio_block_files = subreport[:audio_block_files].strip
      video_block_files = subreport[:video_block_files].strip
      pdf_block_files = subreport[:pdf_block_files].strip
      picture_block_files = subreport[:picture_block_files].strip

      has_picture_with_text = subreport[:has_picture_with_text].strip
      has_html_header_tags = subreport[:has_html_header_tags].strip

      themetags = subreport[:themetags].strip


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

      elsif req == 'UPDATE' || req == 'GET' || req == 'DELETE'|| req == 'GET RAW FILENAMES'
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

      if req == 'UPDATE' || req == 'GET' || req == 'GET RAW FILENAMES'
        old_page_tag_names = page.tag_names
        old_page_tag_columns = tag_array_to_columns(old_page_tag_names)
        old_page_assigned_authors = get_assigned_authors(page)

        if req == 'GET RAW FILENAMES'
          retrieved_intro_block_image = get_intro_block_image_raw_filename(page)
        elsif req == 'GET'
          retrieved_intro_block_image = get_intro_block_image(page)
        else
          retrieved_intro_block_image = get_intro_block_image(page)
        end

        old_page = {
          _sort: subreport[:_sort],
          id: page.id,
          name: page.name,
          title: page.title,
          language_code: page.language_code,
          urlname: page.urlname,
          slug: subreport[:slug],
          link: subreport[:link],
          _request: subreport[:_request],
          _article_bib_key: subreport[:_article_bib_key],
          _doi: subreport[:_doi],
          created_at: get_created_at(page),
          page_layout: page.page_layout,

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
          tag_others: old_page_tag_columns[:tag_others] || '',

          ref_bib_keys: get_references_bib_keys(page),

          _assets: subreport[:_assets],
          _to_do_on_the_portal: subreport[:_to_do_on_the_portal],

          assigned_authors: old_page_assigned_authors,

          intro_block_image: retrieved_intro_block_image,
          audio_block_files: get_audio_blocks_file_names(page),
          video_block_files: get_video_blocks_file_names(page),
          pdf_block_files: get_pdf_blocks_file_names(page),
          picture_block_files: get_picture_blocks_file_names(page),

          has_picture_with_text: page.elements.any? { |element| element.name == 'text_and_picture' } ? "yes" : "",
          attachment_links: get_attachment_links(page),
          _other_assets: subreport[:_other_assets],
          has_html_header_tags: has_html_header_tags(page),

          themetags: get_themetags(page),

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
        page.created_at = created_at

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
          tag_others: tag_others
        }

        page.tag_names = tag_columns_to_array(tag_columns)

        page.save!
        page.publish!

      end

      # Update report
      Rails.logger.info("Processing page '#{page_identifier}': Updating report")
      tags_to_cols = tag_array_to_columns(page.tag_names)
      retrieved_slug = retrieve_page_slug(page)

      if req == 'GET RAW FILENAMES'
        retrieved_intro_block_image = get_intro_block_image_raw_filename(page)
      elsif req == 'GET'
        retrieved_intro_block_image = get_intro_block_image(page)
      else
        retrieved_intro_block_image = get_intro_block_image(page)
      end

      subreport.merge!({
        id: page.id,
        name: page.name,
        title: page.title,
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
        tag_others: tags_to_cols[:tag_others],
        ref_bib_keys: get_references_bib_keys(page),
        assigned_authors: get_assigned_authors(page),
        intro_block_image: retrieved_intro_block_image,
        audio_block_files: get_audio_blocks_file_names(page),
        video_block_files: get_video_blocks_file_names(page),
        pdf_block_files: get_pdf_blocks_file_names(page),
        picture_block_files: get_picture_blocks_file_names(page),
        has_picture_with_text: page.elements.any? { |element| element.name == 'text_and_picture' } ? "yes" : "",
        attachment_links: get_attachment_links(page),
        has_html_header_tags: has_html_header_tags(page),
        themetags: get_themetags(page),
      })

      # Complex tasks
      if req == "UPDATE" || req == "POST"
        Rails.logger.info("Processing page '#{page_identifier}': Complex tasks")

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

        update_intro_block_image_report = update_intro_block_image(page, intro_block_image)
        if update_intro_block_image_report[:status] != 'success'
          subreport[:_request] += " PARTIAL"
          subreport[:status] = 'error'
          subreport[:error_message] = update_intro_block_image_report[:error_message]
          subreport[:error_message] += ". Page saved, but update_intro_block_image failed! Stopping...\n"
          subreport[:error_trace] = update_intro_block_image_report[:error_trace] + "\n"
          next
        end
        subreport[:intro_block_image] = get_intro_block_image(page)

        update_references_report = set_references_bib_keys(page, subreport[:ref_bib_keys])

        if update_references_report[:status] != 'success'
          subreport[:_request] += " PARTIAL"
          subreport[:status] = 'partial success'
          subreport[:error_message] = update_references_report[:error_message]
          subreport[:error_message] += ". Page saved, but set_references_bib_keys failed! Stopping...\n"
          subreport[:error_trace] = update_references_report[:error_trace] + "\n"
        end

        # TODO: update_themetags

        # Saving
        page.save!
        page.publish!
        Rails.logger.info("Processing page '#{page_identifier}': Complex tasks: Success!")
      end


      if req == "UPDATE" || req == "GET" || req == "GET RAW FILENAMES"
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

      subreport[:status] = 'success'
      Rails.logger.info("Processing page '#{subreport[:urlname]}': Success!")


    rescue => e
      Rails.logger.error("Error while processing page '#{subreport[:urlname].blank? ? subreport[:id] : subreport[:urlname]}': #{e.message}")
      subreport[:status] = 'unhandled error'
      subreport[:error_message] = e.message
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
