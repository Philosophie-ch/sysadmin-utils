require 'csv'

require_relative 'lib/utils'
require_relative 'lib/page_tools'
require_relative 'lib/export_utils'


def export_pages(ids_or_file = nil, log_level = 'info', merge_mode: false)

  ############
  # SETUP
  ############

  ExportUtils.setup_logging(log_level)

  report = []
  processed_count = 0

  # Merge mode variables
  input_csv_data = nil
  preserved_columns = nil
  output_filename = nil

  # Preload attachments data once
  all_attachments_with_pages = get_all_attachments_with_pages()


  ############
  # ID PARSING AND VALIDATION
  ############

  ids = nil

  if ids_or_file.present?
    # Check if it's a file path
    if File.exist?(ids_or_file.to_s)

      # Check if merge mode is enabled and file is CSV
      if merge_mode && ids_or_file.to_s.end_with?('.csv')
        Rails.logger.info("MERGE MODE: Reading input CSV: #{ids_or_file}")

        # Read CSV data for later merging
        input_csv_data = ExportUtils.read_input_csv_data(ids_or_file)
        Rails.logger.info("Read #{input_csv_data.keys.length} rows from input CSV")

        # Parse IDs from CSV
        ids = ExportUtils.parse_ids_from_csv(ids_or_file)

        # Determine preserved columns
        csv_headers = CSV.read(ids_or_file, headers: true, encoding: 'UTF-8').headers rescue CSV.read(ids_or_file, headers: true, encoding: 'UTF-16').headers
        preserved_columns = ExportUtils.get_preserved_columns('pages', csv_headers)
        Rails.logger.info("Will preserve #{preserved_columns.length} columns from input CSV")

        # Generate output filename
        output_filename = ExportUtils.generate_merge_output_filename(ids_or_file)

      else
        # Regular file with IDs (one per line)
        Rails.logger.info("Parsing IDs from file: #{ids_or_file}")
        ids = ExportUtils.parse_ids_from_file(ids_or_file)
      end

    else
      # Assume it's a comma-separated string of IDs
      Rails.logger.info("Parsing IDs from argument: #{ids_or_file}")
      ids = ExportUtils.parse_ids(ids_or_file)
    end

    # Validate and fetch in order
    Rails.logger.info("Validating and fetching pages in specified order...")
    pages = ExportUtils.validate_and_fetch_ordered(Alchemy::Page, ids)
    total_pages = pages.length

  else
    # Export ALL pages
    Rails.logger.info("No IDs specified - exporting ALL pages")
    pages = nil  # Will use find_each for all pages
    total_pages = Alchemy::Page.count
  end

  Rails.logger.info("Starting export of #{total_pages} pages...")


  ############
  # MAIN EXPORT LOOP
  ############

  # Define the page processing logic
  process_page = lambda do |page|
    begin
      processed_count += 1
      ExportUtils.log_progress(processed_count, total_pages, "pages")

      # Check if page exists (nil when ID not found in DB)
      unless page
        Rails.logger.warn("Page ID not found in database - skipping (row #{processed_count})")
        error_data = {
          _to_do: "", _sort: "", id: "", published: "", name: "", pre_headline: "",
          title: "", lead_text: "", embedded_html_base_name: "", language_code: "",
          urlname: "", slug: "", link: "", _request: "", bibkey: "", how_to_cite: "",
          pure_html_asset: "", pure_pdf_asset: "", doi: "", metadata_json: "",
          created_at: "", page_layout: "", created_by: "", last_updated_by: "",
          last_updated_date: "", replies_to: "", replied_by: "",
          tag_page_type: "", tag_media: "", tag_content_type: "", tag_language: "",
          tag_institution: "", tag_canton: "", tag_project: "", tag_public: "",
          tag_references: "", tag_footnotes: "", ref_bib_keys: "", _ref_people: "",
          references_asset_url: "", _further_refs: "", further_references_asset_url: "",
          _depends_on: "", _presentation_of: "", _link: "", _abstract: "",
          assigned_authors: "", anon: "", intro_image_asset: "", intro_image_portal: "",
          audio_assets: "", audios_portal: "", video_assets: "", videos_portal: "",
          pdf_assets: "", pdfs_portal: "", picture_assets: "", pictures_portal: "",
          text_and_picture_assets: "", text_and_pictures_portal: "", box_assets: "",
          embed_blocks: "", _attachment_links_assets: "", attachment_links_portal: "",
          has_html_header_tags: "", themetags_discipline: "", themetags_focus: "",
          themetags_badge: "", themetags_structural: "",
          status: 'error', changes_made: '',
          error_message: "Page ID not found in database",
          error_trace: '', result_order: processed_count,
        }
        report << error_data
        return
      end

      # Track if page has intro-related issues
      partial_success = false
      partial_error_messages = []

      # Determine if this page layout should have an intro element
      # Based on page_tools.rb patterns: article, event, info, note have intros
      # Also: call_for_papers, job, topic, standard (based on intro element names and metadata usage)
      layouts_with_intro = ['article', 'event', 'info', 'note', 'call_for_papers', 'job', 'topic', 'standard']
      should_have_intro = layouts_with_intro.include?(page.page_layout)

      # Build the report row with the same structure as pages.rb
      tags_to_cols = tag_array_to_columns(page.tag_names)
      retrieved_slug = retrieve_page_slug(page)
      retrieved_intro_image_portal = get_intro_image_show_url(page)

      # Get intro-dependent fields with error handling
      begin
        pre_headline = get_pre_headline(page)
      rescue => e
        pre_headline = ""
        if should_have_intro
          partial_success = true
          partial_error_messages << "pre_headline: #{e.message}"
          Rails.logger.warn("Page #{page.id} (#{page.page_layout}): Could not get pre_headline - #{e.message}")
        end
      end

      begin
        lead_text = get_lead_text(page)
      rescue => e
        lead_text = ""
        if should_have_intro
          partial_success = true
          partial_error_messages << "lead_text: #{e.message}"
          Rails.logger.warn("Page #{page.id} (#{page.page_layout}): Could not get lead_text - #{e.message}")
        end
      end

      begin
        themetags_hashmap = get_themetags(page)
      rescue => e
        themetags_hashmap = {discipline: "", focus: "", badge: "", structural: ""}
        if should_have_intro
          partial_success = true
          partial_error_messages << "themetags: #{e.message}"
          Rails.logger.warn("Page #{page.id} (#{page.page_layout}): Could not get themetags - #{e.message}")
        end
      end

      begin
        assigned_authors = get_assigned_authors(page)
      rescue => e
        assigned_authors = ""
        if should_have_intro
          partial_success = true
          partial_error_messages << "assigned_authors: #{e.message}"
          Rails.logger.warn("Page #{page.id} (#{page.page_layout}): Could not get assigned_authors - #{e.message}")
        end
      end

      begin
        intro_image_asset = get_asset_names(page, "intro", ELEMENT_NAME_AND_URL_FIELD_MAP[:"intro"])
      rescue => e
        intro_image_asset = ""
        if should_have_intro
          partial_success = true
          partial_error_messages << "intro_image_asset: #{e.message}"
          Rails.logger.warn("Page #{page.id} (#{page.page_layout}): Could not get intro_image_asset - #{e.message}")
        end
      end

      # Get references info
      references_base_url = "https://assets.philosophie.ch/references/articles/"
      all_references_urls = get_references_urls(page)
      references_asset_url = all_references_urls[:references_url] ? all_references_urls[:references_url].gsub(references_base_url, '') : ''
      further_references_asset_url = all_references_urls[:further_references_url] ? all_references_urls[:further_references_url].gsub(references_base_url, '') : ''

      # Get article metadata (if article layout)
      if page.page_layout == "article"
        aside_column = get_aside_column(page)
        article_metadata_element = get_article_metadata_element(aside_column)

        pure_links_base_url = "https://assets.philosophie.ch/dialectica/"

        if article_metadata_element.nil?
          doi = ''
          how_to_cite = ''
          pure_html_asset = ''
          pure_pdf_asset = ''
        else
          doi = get_doi(article_metadata_element)
          how_to_cite = get_how_to_cite(article_metadata_element)
          pure_html_asset = get_pure_html_asset(article_metadata_element, pure_links_base_url)
          pure_pdf_asset = get_pure_pdf_asset(article_metadata_element, pure_links_base_url)
        end
      else
        doi = ''
        how_to_cite = ''
        pure_html_asset = ''
        pure_pdf_asset = ''
      end

      # Get academic metadata (for article or standard layouts)
      if page.page_layout == "article" || page.page_layout == "standard"
        metadata_json = get_academic_metadata_json(page)
      else
        metadata_json = ''
      end

      # Get published status once to avoid inconsistency
      published_status = get_published(page)

      # Generate appropriate link based on published status
      page_link = if published_status == "PUBLISHED"
        "https://www.philosophie.ch#{retrieved_slug}"
      else
        "https://www.philosophie.ch/admin/pages/#{page.id}/edit"
      end

      # Build the report hash - MUST match the structure from pages.rb exactly
      page_data = {
        _to_do: "",
        _sort: "",
        id: page.id,
        published: published_status,
        name: page.name,
        pre_headline: pre_headline,
        title: page.title,
        lead_text: lead_text,
        embedded_html_base_name: "",
        language_code: page.language_code,
        urlname: page.urlname,
        slug: retrieved_slug,
        link: page_link,
        _request: "",
        bibkey: page.bibkey || '',
        how_to_cite: how_to_cite,
        pure_html_asset: pure_html_asset,
        pure_pdf_asset: pure_pdf_asset,
        doi: doi,
        metadata_json: metadata_json,
        created_at: get_created_at(page),
        page_layout: page.page_layout,
        created_by: get_creator(page),
        last_updated_by: get_last_updater(page),
        last_updated_date: get_last_updated_date(page),
        replies_to: get_reply_target_urlname(page),
        replied_by: get_replied_by(page),

        tag_page_type: tags_to_cols[:tag_page_type],
        tag_media: tags_to_cols[:tag_media],
        tag_content_type: tags_to_cols[:tag_content_type],
        tag_language: tags_to_cols[:tag_language],
        tag_institution: tags_to_cols[:tag_institution],
        tag_canton: tags_to_cols[:tag_canton],
        tag_project: tags_to_cols[:tag_project],
        tag_public: tags_to_cols[:tag_public],
        tag_references: tags_to_cols[:tag_references],
        tag_footnotes: tags_to_cols[:tag_footnotes],

        ref_bib_keys: get_references_bib_keys(page),
        _ref_people: "",
        references_asset_url: references_asset_url,
        _further_refs: "",
        further_references_asset_url: further_references_asset_url,
        _depends_on: "",
        _presentation_of: "",
        _link: "",
        _abstract: "",

        assigned_authors: assigned_authors,
        anon: get_anon(page),

        intro_image_asset: intro_image_asset,
        intro_image_portal: retrieved_intro_image_portal,
        audio_assets: get_asset_names(page, "audio_block", ELEMENT_NAME_AND_URL_FIELD_MAP[:"audio_block"]),
        audios_portal: get_media_blocks_download_urls(page, "audio"),
        video_assets: get_asset_names(page, "video_block", ELEMENT_NAME_AND_URL_FIELD_MAP[:"video_block"]),
        videos_portal: get_media_blocks_download_urls(page, "video"),
        pdf_assets: get_asset_names(page, "pdf_block", ELEMENT_NAME_AND_URL_FIELD_MAP[:"pdf_block"]),
        pdfs_portal: get_media_blocks_download_urls(page, "pdf"),
        picture_assets: get_asset_names(page, "picture_block", ELEMENT_NAME_AND_URL_FIELD_MAP[:"picture_block"]),
        pictures_portal: get_picture_blocks_show_links(page, "picture_block"),
        text_and_picture_assets: get_asset_names(page, "text_and_picture", ELEMENT_NAME_AND_URL_FIELD_MAP[:"text_and_picture"]),
        text_and_pictures_portal: get_picture_blocks_show_links(page, "text_and_picture"),
        box_assets: get_asset_names(page, "box", ELEMENT_NAME_AND_URL_FIELD_MAP[:"box"]),

        embed_blocks: has_embed_blocks(page),
        _attachment_links_assets: "",
        attachment_links_portal: get_attachment_links_portal(page, all_attachments_with_pages),
        has_html_header_tags: has_html_header_tags(page),

        themetags_discipline: themetags_hashmap[:discipline],
        themetags_focus: themetags_hashmap[:focus],
        themetags_badge: themetags_hashmap[:badge],
        themetags_structural: themetags_hashmap[:structural],

        status: partial_success ? 'partial success' : 'success',
        changes_made: '',
        error_message: partial_error_messages.join(' | '),
        error_trace: '',
        result_order: processed_count,
      }

      report << page_data
      Rails.logger.debug("Exported page #{page.id}: #{page.urlname}")

    rescue => e
      Rails.logger.error("Error exporting page #{page&.id || 'unknown'}: #{e.message}")
      error_data = {
        _to_do: "",
        _sort: "",
        id: page&.id || "",
        published: "",
        name: page&.name || "",
        pre_headline: "",
        title: page&.title || "",
        lead_text: "",
        embedded_html_base_name: "",
        language_code: page&.language_code || "",
        urlname: page&.urlname || "",
        slug: "",
        link: "",
        _request: "",
        bibkey: "",
        how_to_cite: "",
        pure_html_asset: "",
        pure_pdf_asset: "",
        doi: "",
        metadata_json: "",
        created_at: "",
        page_layout: page&.page_layout || "",
        created_by: "",
        last_updated_by: "",
        last_updated_date: "",
        replies_to: "",
        replied_by: "",
        tag_page_type: "",
        tag_media: "",
        tag_content_type: "",
        tag_language: "",
        tag_institution: "",
        tag_canton: "",
        tag_project: "",
        tag_public: "",
        tag_references: "",
        tag_footnotes: "",
        ref_bib_keys: "",
        _ref_people: "",
        references_asset_url: "",
        _further_refs: "",
        further_references_asset_url: "",
        _depends_on: "",
        _presentation_of: "",
        _link: "",
        _abstract: "",
        assigned_authors: "",
        anon: "",
        intro_image_asset: "",
        intro_image_portal: "",
        audio_assets: "",
        audios_portal: "",
        video_assets: "",
        videos_portal: "",
        pdf_assets: "",
        pdfs_portal: "",
        picture_assets: "",
        pictures_portal: "",
        text_and_picture_assets: "",
        text_and_pictures_portal: "",
        box_assets: "",
        embed_blocks: "",
        _attachment_links_assets: "",
        attachment_links_portal: "",
        has_html_header_tags: "",
        themetags_discipline: "",
        themetags_focus: "",
        themetags_badge: "",
        themetags_structural: "",
        status: 'unhandled error',
        changes_made: '',
        error_message: "#{e.class} :: #{e.message}",
        error_trace: e.backtrace.join(" ::: "),
        result_order: processed_count,
      }
      report << error_data
    end
  end

  # Execute based on whether we have specific IDs or exporting all
  if pages
    # Process specific pages in order
    pages.each(&process_page)
  else
    # Use find_each for memory-efficient iteration through all pages
    # Eager load associations to minimize queries
    Alchemy::Page
      .includes(
        :elements,
        :taggings,
        :tags,
        :language,
        :creator,
        :updater,
        :authors,
        elements: :contents
      )
      .find_each(batch_size: 100, &process_page)
  end


  ############
  # REPORT GENERATION
  ############

  Rails.logger.info("Export complete. Generating report...")

  # If in merge mode, merge with input CSV data
  if merge_mode && input_csv_data && preserved_columns
    Rails.logger.info("Merging exported data with input CSV...")
    report = ExportUtils.merge_with_input_csv(report, input_csv_data, preserved_columns)
  end

  # Generate CSV output
  if output_filename
    # Custom filename for merge mode
    Rails.logger.info("Writing merged output to: #{output_filename}")
    headers = report.first.keys
    csv_string = CSV.generate do |csv|
      csv << headers
      report.each do |row|
        csv << headers.map { |header| row[header] }
      end
    end
    File.write(output_filename, csv_string)
    Rails.logger.info("Successfully wrote merged CSV to #{output_filename}")
  else
    # Standard report generation
    generate_csv_report(report, "pages")
  end

  Rails.logger.info("Successfully exported #{processed_count} pages")

end


############
# CLI ENTRY POINT
############

if __FILE__ == $0
  # Parse command line arguments
  # Usage:
  #   ruby export_pages.rb [log_level]                        # Export all pages
  #   ruby export_pages.rb [ids_or_file] [log_level]          # Export specific IDs
  #   ruby export_pages.rb -m [csv_file] [log_level]          # Merge mode with CSV

  merge_mode = false
  ids_or_file = nil
  log_level = 'info'

  # Check for merge mode flag
  if ARGV.include?('-m') || ARGV.include?('--merge')
    merge_mode = true
    ARGV.delete('-m')
    ARGV.delete('--merge')
  end

  if ARGV.length == 0
    # No arguments - export all with default log level
    export_pages(nil, 'info', merge_mode: merge_mode)

  elsif ARGV.length == 1
    # One argument - could be log level OR ids/file
    arg = ARGV[0]

    # Check if it's a log level
    if ['debug', 'info', 'warn', 'error'].include?(arg.downcase)
      export_pages(nil, arg, merge_mode: merge_mode)
    else
      # Assume it's IDs or a file
      export_pages(arg, 'info', merge_mode: merge_mode)
    end

  elsif ARGV.length == 2
    # Two arguments - ids/file and log level
    export_pages(ARGV[0], ARGV[1], merge_mode: merge_mode)

  else
    puts "Usage:"
    puts "  ruby export_pages.rb [log_level]                       # Export all pages"
    puts "  ruby export_pages.rb [ids_or_file] [log_level]         # Export specific IDs"
    puts "  ruby export_pages.rb -m [csv_file] [log_level]         # Merge mode with CSV"
    puts ""
    puts "Arguments:"
    puts "  -m, --merge   : Enable merge mode (preserve manual columns from input CSV)"
    puts "  ids_or_file   : File path (with one ID per line) OR comma-separated IDs"
    puts "  csv_file      : CSV file with 'id' column (for merge mode)"
    puts "  log_level     : debug, info, warn, or error (default: info)"
    puts ""
    puts "Examples:"
    puts "  ruby export_pages.rb                                   # Export all pages, info logging"
    puts "  ruby export_pages.rb debug                             # Export all pages, debug logging"
    puts "  ruby export_pages.rb ids.txt                           # Export IDs from file"
    puts "  ruby export_pages.rb '123,456,789'                     # Export specific IDs"
    puts "  ruby export_pages.rb ids.txt debug                     # Export IDs from file with debug"
    puts "  ruby export_pages.rb -m articles.csv                   # Merge mode: updates articles_updated.csv"
    puts "  ruby export_pages.rb -m articles.csv debug             # Merge mode with debug logging"
    puts ""
    puts "Merge Mode:"
    puts "  - Reads IDs from 'id' column in input CSV"
    puts "  - Fetches fresh DB data for those IDs"
    puts "  - Preserves manual/metadata columns from input CSV"
    puts "  - Outputs to {input_name}_updated.csv"
    exit 1
  end
end
