require 'csv'

require_relative 'lib/utils'
require_relative 'lib/page_tools'
require_relative 'lib/export_utils'


def swap_webp_asset_urls(csv_file, log_level = 'info')

  ############
  # SETUP
  ############

  ExportUtils.setup_logging(log_level)

  report = []
  processed_count = 0

  # Cache: "https://assets.philosophie.ch/original.jpg" => "https://assets.philosophie.ch/original.webp"
  webp_cache = {}

  # Read input CSV data for merge
  Rails.logger.info("Reading input CSV: #{csv_file}")
  input_csv_data = ExportUtils.read_input_csv_data(csv_file)
  Rails.logger.info("Read #{input_csv_data.keys.length} rows from input CSV")

  # Parse IDs from CSV
  ids = ExportUtils.parse_ids_from_csv(csv_file)

  # Determine preserved columns
  csv_headers = CSV.read(csv_file, headers: true, encoding: 'UTF-8').headers rescue CSV.read(csv_file, headers: true, encoding: 'UTF-16').headers
  preserved_columns = ExportUtils.get_preserved_columns('pages', csv_headers)
  Rails.logger.info("Will preserve #{preserved_columns.length} columns from input CSV")

  # Generate output filename
  output_filename = ExportUtils.generate_merge_output_filename(csv_file)

  # Validate and fetch pages in order
  Rails.logger.info("Validating and fetching pages in specified order...")
  pages = ExportUtils.validate_and_fetch_ordered(Alchemy::Page, ids)
  total_pages = pages.length

  # Preload attachments data once
  all_attachments_with_pages = get_all_attachments_with_pages()

  Rails.logger.info("Starting webp swap for #{total_pages} pages...")


  ############
  # MAIN PROCESSING LOOP
  ############

  pages.each do |page|
    begin
      processed_count += 1
      ExportUtils.log_progress(processed_count, total_pages, "pages")

      # Handle missing pages (nil when ID not found in DB)
      unless page
        Rails.logger.warn("Page ID not found in database - skipping (row #{processed_count})")
        error_data = build_empty_page_row(processed_count)
        error_data[:status] = 'error'
        error_data[:error_message] = "Page ID not found in database"
        report << error_data
        next
      end

      # Process this page's images
      error_messages = []
      changes = []
      page_modified = false

      IMAGE_ELEMENT_TYPES.each do |element_name|
        url_field_name = "picture_asset_url"

        begin
          blocks = _get_asset_blocks(page, element_name, url_field_name)
        rescue => e
          error_messages << "NO-BLOCKS: #{element_name}: failed to get blocks: #{e.message}"
          next
        end

        blocks.each do |block|
          begin
            url_content = block.contents.find { |c| c.name == url_field_name }
            current_url = url_content&.essence&.body

            # Skip blank
            if current_url.blank?
              next
            end

            # Skip if already webp
            ext = File.extname(current_url).downcase
            if ext == '.webp'
              next
            end

            # Skip if not a known non-webp image extension
            unless NON_WEBP_IMAGE_EXTENSIONS.include?(ext)
              next
            end

            # Build the expected webp URL
            webp_url = current_url.sub(/#{Regexp.escape(ext)}$/i, '.webp')
            original_relative_path = current_url.gsub('https://assets.philosophie.ch/', '')
            webp_relative_path = webp_url.gsub('https://assets.philosophie.ch/', '')

            Rails.logger.debug("Checking webp for: #{original_relative_path} -> #{webp_relative_path}")

            # (1a) Check cache
            if webp_cache.key?(current_url)
              cached_webp = webp_cache[current_url]
              Rails.logger.debug("Cache hit: #{original_relative_path} -> #{cached_webp}")
              url_content.essence.update!(body: cached_webp)
              changes << "#{element_name}[#{block.id}]: #{original_relative_path} => #{cached_webp.gsub('https://assets.philosophie.ch/', '')} (cached)"
              page_modified = true
              next
            end

            # (1b) Check asset server
            webp_check = check_asset_urls_resolve([webp_url])
            if webp_check[:status] == 'success'
              # Webp exists on server — swap and cache
              url_content.essence.update!(body: webp_url)
              webp_cache[current_url] = webp_url
              changes << "#{element_name}[#{block.id}]: #{original_relative_path} => #{webp_relative_path}"
              page_modified = true
              Rails.logger.info("Swapped: #{original_relative_path} => #{webp_relative_path}")
            else
              # No webp found
              error_messages << "NO-WEBP: #{original_relative_path}"
              Rails.logger.warn("NO-WEBP: #{original_relative_path} (page #{page.id})")
            end

          rescue => e
            error_messages << "NO-WEBP: #{element_name}[#{block.id}]: #{e.class} :: #{e.message}"
          end
        end
      end

      # Save and publish if any changes were made
      if page_modified
        begin
          page.save!
          page.publish!
        rescue => e
          error_messages << "save/publish failed: #{e.class} :: #{e.message}"
        end
      end

      # Determine status
      status = if error_messages.empty? && changes.empty?
        'skipped'
      elsif error_messages.empty?
        'success'
      elsif changes.empty? && error_messages.any?
        'error'
      else
        'partial success'
      end

      # Build report row (same structure as export_pages.rb)
      page_data = build_page_report_row(page, all_attachments_with_pages, processed_count)
      page_data[:status] = status
      page_data[:changes_made] = changes.join(' ;; ')
      page_data[:error_message] = error_messages.join(' --- ')
      page_data[:error_trace] = status == 'error' || status == 'partial success' ? 'swap_webp_asset_urls.rb' : ''

      report << page_data

    rescue => e
      Rails.logger.error("Unhandled error for page #{page&.id || 'unknown'}: #{e.message}")
      error_data = build_error_page_row(page, processed_count)
      error_data[:status] = 'unhandled error'
      error_data[:error_message] = "#{e.class} :: #{e.message}"
      error_data[:error_trace] = e.backtrace.join(" ::: ")
      report << error_data
    end
  end


  ############
  # REPORT GENERATION
  ############

  Rails.logger.info("Processing complete. Generating report...")

  # Merge with input CSV data
  Rails.logger.info("Merging exported data with input CSV...")
  report = ExportUtils.merge_with_input_csv(report, input_csv_data, preserved_columns)

  # Write output
  Rails.logger.info("Writing output to: #{output_filename}")
  headers = report.first.keys
  csv_string = CSV.generate do |csv|
    csv << headers
    report.each do |row|
      csv << headers.map { |header| row[header] }
    end
  end
  File.write(output_filename, csv_string)

  Rails.logger.info("Successfully processed #{processed_count} pages")
  Rails.logger.info("Cache stats: #{webp_cache.size} unique webp mappings cached")
  Rails.logger.info("\n\n\n============ Report generated at #{output_filename} ============\n\n\n")
end


############
# HELPER: Build a full page report row (re-exports fresh data after swap)
############

def build_page_report_row(page, all_attachments_with_pages, result_order)
  # Track intro-related issues
  partial_error_messages = []
  layouts_with_intro = ['article', 'event', 'info', 'note', 'call_for_papers', 'job', 'topic', 'standard']
  should_have_intro = layouts_with_intro.include?(page.page_layout)

  tags_to_cols = tag_array_to_columns(page.tag_names)
  retrieved_slug = retrieve_page_slug(page)
  retrieved_intro_image_portal = get_intro_image_show_url(page)

  begin
    pre_headline = get_pre_headline(page)
  rescue => e
    pre_headline = ""
  end

  begin
    lead_text = get_lead_text(page)
  rescue => e
    lead_text = ""
  end

  begin
    themetags_hashmap = get_themetags(page)
  rescue => e
    themetags_hashmap = {discipline: "", focus: "", badge: "", structural: ""}
  end

  begin
    assigned_authors = get_assigned_authors(page)
  rescue => e
    assigned_authors = ""
  end

  begin
    intro_image_asset = get_asset_names(page, "intro", ELEMENT_NAME_AND_URL_FIELD_MAP[:"intro"])
  rescue => e
    intro_image_asset = ""
  end

  # Get references info
  references_base_url = "https://assets.philosophie.ch/references/articles/"
  all_references_urls = get_references_urls(page)
  references_asset_url = all_references_urls[:references_url] ? all_references_urls[:references_url].gsub(references_base_url, '') : ''
  further_references_asset_url = all_references_urls[:further_references_url] ? all_references_urls[:further_references_url].gsub(references_base_url, '') : ''

  # Get article metadata
  if page.page_layout == "article"
    aside_column = get_aside_column(page)
    article_metadata_element = get_article_metadata_element(aside_column)
    pure_links_base_url = "https://assets.philosophie.ch/dialectica/"
    if article_metadata_element.nil?
      doi = ''; how_to_cite = ''; pure_html_asset = ''; pure_pdf_asset = ''
    else
      doi = get_doi(article_metadata_element)
      how_to_cite = get_how_to_cite(article_metadata_element)
      pure_html_asset = get_pure_html_asset(article_metadata_element, pure_links_base_url)
      pure_pdf_asset = get_pure_pdf_asset(article_metadata_element, pure_links_base_url)
    end
  else
    doi = ''; how_to_cite = ''; pure_html_asset = ''; pure_pdf_asset = ''
  end

  # Academic metadata
  if page.page_layout == "article" || page.page_layout == "standard"
    metadata_json = get_academic_metadata_json(page)
  else
    metadata_json = ''
  end

  published_status = get_published(page)
  page_link = if published_status == "PUBLISHED"
    "https://www.philosophie.ch#{retrieved_slug}"
  else
    "https://www.philosophie.ch/admin/pages/#{page.id}/edit"
  end

  {
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

    status: '',
    changes_made: '',
    error_message: '',
    error_trace: '',
    result_order: result_order,
  }
end


############
# HELPER: Build empty row for missing pages
############

def build_empty_page_row(result_order)
  {
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
    status: '', changes_made: '', error_message: '', error_trace: '',
    result_order: result_order,
  }
end


############
# HELPER: Build error row for unhandled exceptions
############

def build_error_page_row(page, result_order)
  {
    _to_do: "", _sort: "",
    id: page&.id || "", published: "", name: page&.name || "",
    pre_headline: "", title: page&.title || "", lead_text: "",
    embedded_html_base_name: "", language_code: page&.language_code || "",
    urlname: page&.urlname || "", slug: "", link: "", _request: "",
    bibkey: "", how_to_cite: "", pure_html_asset: "", pure_pdf_asset: "",
    doi: "", metadata_json: "", created_at: "", page_layout: page&.page_layout || "",
    created_by: "", last_updated_by: "", last_updated_date: "",
    replies_to: "", replied_by: "",
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
    status: '', changes_made: '', error_message: '', error_trace: '',
    result_order: result_order,
  }
end


############
# CLI ENTRY POINT
############

if __FILE__ == $0
  if ARGV.length < 1
    puts "Usage:"
    puts "  ruby swap_webp_asset_urls.rb <csv_file> [log_level]"
    puts ""
    puts "Arguments:"
    puts "  csv_file    : CSV file with 'id' column (page IDs)"
    puts "  log_level   : debug, info, warn, or error (default: info)"
    puts ""
    puts "Description:"
    puts "  For each page, checks all image elements (intro, picture_block,"
    puts "  text_and_picture, box). If an image URL points to a non-webp file,"
    puts "  checks if a .webp version exists on the asset server. If yes, swaps"
    puts "  the reference. If no, reports NO-WEBP error."
    puts ""
    puts "Examples:"
    puts "  ruby swap_webp_asset_urls.rb pages.csv"
    puts "  ruby swap_webp_asset_urls.rb pages.csv debug"
    exit 1
  end

  csv_file = ARGV[0]
  log_level = ARGV[1] || 'info'

  swap_webp_asset_urls(csv_file, log_level)
end
