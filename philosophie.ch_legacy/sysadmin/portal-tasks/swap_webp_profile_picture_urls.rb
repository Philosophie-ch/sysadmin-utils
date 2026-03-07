require 'csv'

require_relative 'lib/utils'
require_relative 'lib/profile_tools'
require_relative 'lib/export_utils'


def swap_webp_profile_picture_urls(csv_file, log_level = 'info')

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
  preserved_columns = ExportUtils.get_preserved_columns('profiles', csv_headers)
  Rails.logger.info("Will preserve #{preserved_columns.length} columns from input CSV")

  # Generate output filename
  output_filename = ExportUtils.generate_merge_output_filename(csv_file)

  # Validate and fetch users in order
  Rails.logger.info("Validating and fetching users in specified order...")
  users = ExportUtils.validate_and_fetch_ordered(Alchemy::User, ids)
  total_users = users.length

  # Precompute expensive lookups
  user_articles_map = precompute_user_articles_map

  Rails.logger.info("Starting webp swap for #{total_users} profiles...")


  ############
  # MAIN PROCESSING LOOP
  ############

  ids.zip(users).each do |original_id, user|
    begin
      processed_count += 1
      ExportUtils.log_progress(processed_count, total_users, "profiles")

      # Handle missing users (nil when ID not found in DB)
      unless user
        Rails.logger.warn("User ID #{original_id} not found in database - skipping (row #{processed_count})")
        error_data = build_error_profile_data(nil, "User ID not found in database")
        error_data[:result_order] = processed_count
        error_data[:status] = 'error'
        report << error_data
        next
      end

      # Handle users without profiles
      unless user.profile
        Rails.logger.warn("User #{user.id} (#{user.login}) has no profile - skipping")
        error_data = build_error_profile_data(user, "User has no profile attached")
        error_data[:result_order] = processed_count
        error_data[:status] = 'error'
        report << error_data
        next
      end

      # Process this profile's picture
      error_messages = []
      changes = []

      current_url = user.profile.profile_picture_url

      # Skip if blank
      if current_url.blank?
        Rails.logger.debug("User #{user.id} (#{user.login}) has no profile picture - skipping")
      else
        ext = File.extname(current_url).downcase

        if ext == '.webp'
          # Already webp, nothing to do
          Rails.logger.debug("User #{user.id} (#{user.login}) already has webp profile picture - skipping")
        elsif !NON_WEBP_IMAGE_EXTENSIONS.include?(ext)
          # Not a known image extension, skip
          Rails.logger.debug("User #{user.id} (#{user.login}) has unknown image extension (#{ext}) - skipping")
        else
          # Build the expected webp URL
          webp_url = current_url.sub(/#{Regexp.escape(ext)}$/i, '.webp')
          original_relative_path = current_url.gsub('https://assets.philosophie.ch/', '')
          webp_relative_path = webp_url.gsub('https://assets.philosophie.ch/', '')

          Rails.logger.debug("Checking webp for: #{original_relative_path} -> #{webp_relative_path}")

          # (1a) Check cache
          if webp_cache.key?(current_url)
            cached_webp = webp_cache[current_url]
            Rails.logger.debug("Cache hit: #{original_relative_path} -> #{cached_webp}")
            user.profile.profile_picture_url = cached_webp
            user.profile.save!
            user.save!
            changes << "profile_picture_url: #{original_relative_path} => #{cached_webp.gsub('https://assets.philosophie.ch/', '')} (cached)"
          else
            # (1b) Check asset server
            webp_check = check_asset_urls_resolve([webp_url])
            if webp_check[:status] == 'success'
              # Webp exists on server — swap and cache
              user.profile.profile_picture_url = webp_url
              user.profile.save!
              user.save!
              webp_cache[current_url] = webp_url
              changes << "profile_picture_url: #{original_relative_path} => #{webp_relative_path}"
              Rails.logger.info("Swapped: #{original_relative_path} => #{webp_relative_path}")
            else
              # No webp found
              error_messages << "NO-WEBP: #{original_relative_path}"
              Rails.logger.warn("NO-WEBP: #{original_relative_path} (user #{user.id}, #{user.login})")
            end
          end
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

      # Build report row (same structure as export_profiles.rb)
      profile_data = build_profile_report_row(user, user_articles_map, processed_count)
      profile_data[:status] = status
      profile_data[:changes_made] = changes.join(' ;; ')
      profile_data[:error_message] = error_messages.join(' --- ')
      profile_data[:error_trace] = status == 'error' || status == 'partial success' ? 'swap_webp_profile_picture_urls.rb' : ''

      report << profile_data

    rescue => e
      Rails.logger.error("Unhandled error for user #{user&.id || 'unknown'} (#{user&.login || 'unknown'}): #{e.message}")
      error_data = build_error_profile_data(user, "#{e.class} :: #{e.message}", e.backtrace.join(" ::: "))
      error_data[:result_order] = processed_count
      error_data[:status] = 'unhandled error'
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

  Rails.logger.info("Successfully processed #{processed_count} profiles")
  Rails.logger.info("Cache stats: #{webp_cache.size} unique webp mappings cached")
  Rails.logger.info("\n\n\n============ Report generated at #{output_filename} ============\n\n\n")
end


############
# HELPER: Build a full profile report row (re-exports fresh data after swap)
############

def build_profile_report_row(user, user_articles_map, result_order)
  # Bibliography base URL
  bibliography_base_url = "https://assets.philosophie.ch/references/"

  # Extract bibliography URLs and strip base URL
  bibliography_asset_url = user.profile.bibliography_asset_url.blank? ? "" : user.profile.bibliography_asset_url.gsub(bibliography_base_url, '')
  bibliography_further_asset_url = user.profile.bibliography_further_references_asset_url.blank? ? "" : user.profile.bibliography_further_references_asset_url.gsub(bibliography_base_url, '')

  # Use precomputed map
  assigned_articles = user_articles_map[user.login] || []
  assigned_articles_urlnames = assigned_articles.map(&:urlname).join(', ')
  assigned_articles_links = assigned_articles.map { |a| get_page_link(a) }.join(', ')
  commented_pages = get_commented_pages_urlnames(user)
  potential_duplicates = get_potential_duplicates(user)

  {
    _sort: "",
    _correspondence: "",
    _todo_person: "",
    _request: "",
    alchemy_roles: user.alchemy_roles.join(', '),
    _member_subcategory: "",
    _status_wrt_association: "",
    membership_wanted: user.profile.membership_wanted,
    id: user.id,
    _role_wrt_portal: "",
    _biblio_name: "",
    _biblio_full_name: "",
    profile_name: user.profile.name,
    firstname: user.firstname,
    lastname: user.lastname,
    email_addresses: user.profile.email_addresses,
    newsletter: user.profile.newsletter,
    academic_page: user.profile.academic_page,
    abbreviation: user.profile.abbreviation,
    _function: "",
    login: user.login,
    _old_login: "",
    _link: "https://www.philosophie.ch/profil/#{user.login}",
    password: "",
    language: user.language,
    gender: user.gender,
    last_updaters: user.profile.last_updaters.to_json,

    _contact_person: "",
    _contact_person_email: "",
    _articles_assigned_to_profile: assigned_articles_urlnames,
    _articles_assigned_to_profile_links: assigned_articles_links,
    biblio_keys: "",
    bibliography_asset_url: bibliography_asset_url,
    biblio_keys_further_references: "",
    bibliography_further_references_asset_url: bibliography_further_asset_url,
    biblio_dependencies_keys: "",
    pages_commented: commented_pages,
    mentioned_on: "",
    _comments_on_contacts: "",
    institutional_affiliation: user.profile.institutional_affiliation,
    _comments_on_employment: "",
    _form_of_address: "",
    _title: "",
    type_of_affiliation: type_of_affiliation_to_string(user.profile.type_of_affiliation),
    other_type_of_affiliation: user.profile.other_type_of_affiliation,
    type_of_studies: type_of_studies_to_string(user.profile.type_of_studies),
    _function_title: "",
    _function_standardised: "",

    country: user.profile.country,
    area: user.profile.area,
    _canton: "",
    description: user.profile.description,
    website: user.profile.website,
    teacher_at_institution: user.profile.teacher_at_institution,
    teacher_at_other_institution: user.profile.teacher_at_other_institution,
    _interests: "",
    _projects: "",
    societies: user.profile.societies.map(&:name).join(', '),
    cms_public_email_toggle: user.profile.cms_public_email_toggle,
    profile_picture_asset: get_profile_picture_asset_name(user),
    facebook_profile: user.profile.facebook_profile,

    status: '',
    changes_made: '',
    error_message: '',
    error_trace: '',
    update_links_report: '',
    result_order: result_order,

    public: user.profile.public,
    other_personal_information: user.profile.other_personal_information,
    confirmed_at: user.profile.confirmed_at,
    potential_duplicates: potential_duplicates,
  }
end


############
# CLI ENTRY POINT
############

if __FILE__ == $0
  if ARGV.length < 1
    puts "Usage:"
    puts "  ruby swap_webp_profile_picture_urls.rb <csv_file> [log_level]"
    puts ""
    puts "Arguments:"
    puts "  csv_file    : CSV file with 'id' column (user IDs)"
    puts "  log_level   : debug, info, warn, or error (default: info)"
    puts ""
    puts "Description:"
    puts "  For each user profile, checks if the profile_picture_url points to a"
    puts "  non-webp file. If a .webp version exists on the asset server, swaps"
    puts "  the reference. If no webp found, reports NO-WEBP error."
    puts ""
    puts "Examples:"
    puts "  ruby swap_webp_profile_picture_urls.rb profiles.csv"
    puts "  ruby swap_webp_profile_picture_urls.rb profiles.csv debug"
    exit 1
  end

  csv_file = ARGV[0]
  log_level = ARGV[1] || 'info'

  swap_webp_profile_picture_urls(csv_file, log_level)
end
