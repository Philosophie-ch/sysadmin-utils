require 'csv'

require_relative 'lib/utils'
require_relative 'lib/profile_tools'
require_relative 'lib/export_utils'


def export_profiles(ids_or_file = nil, log_level = 'info')

  ############
  # SETUP
  ############

  ExportUtils.setup_logging(log_level)

  report = []
  processed_count = 0

  ############
  # PRECOMPUTE EXPENSIVE LOOKUPS
  ############

  Rails.logger.info("Precomputing article assignments for all users...")

  # Build a mapping of user_login => [articles]
  # This prevents calling get_assigned_articles() 7000+ times which queries ALL articles each time
  user_articles_map = {}

  all_articles = Alchemy::Page.where(page_layout: 'article')
                              .includes(elements: { contents: :essence })

  all_articles.each do |article|
    intro_element = article.elements.find { |e| e.name == 'intro' }
    next unless intro_element

    creator_content = intro_element.content_by_name(:creator)
    next unless creator_content&.essence

    author_logins = creator_content.essence.alchemy_users.map(&:login)
    author_logins.each do |login|
      user_articles_map[login] ||= []
      user_articles_map[login] << article
    end
  end

  Rails.logger.info("Precomputed article assignments for #{user_articles_map.keys.length} users")


  ############
  # ID PARSING AND VALIDATION
  ############

  ids = nil

  if ids_or_file.present?
    # Check if it's a file path
    if File.exist?(ids_or_file.to_s)
      Rails.logger.info("Parsing IDs from file: #{ids_or_file}")
      ids = ExportUtils.parse_ids_from_file(ids_or_file)

    else
      # Assume it's a comma-separated string of IDs
      Rails.logger.info("Parsing IDs from argument: #{ids_or_file}")
      ids = ExportUtils.parse_ids(ids_or_file)
    end

    # Validate and fetch in order
    Rails.logger.info("Validating and fetching users in specified order...")
    users = ExportUtils.validate_and_fetch_ordered(Alchemy::User, ids)
    total_users = users.length

  else
    # Export ALL users
    Rails.logger.info("No IDs specified - exporting ALL users/profiles")
    users = nil  # Will use find_each for all users
    total_users = Alchemy::User.count
  end

  Rails.logger.info("Starting export of #{total_users} profiles...")


  ############
  # MAIN EXPORT LOOP
  ############

  # Define the user processing logic
  process_user = lambda do |user|
    begin
      processed_count += 1
      ExportUtils.log_progress(processed_count, total_users, "profiles")

      # Check if user has a profile
      unless user.profile
        Rails.logger.warn("User #{user.id} (#{user.login}) has no profile - skipping")
        error_data = build_error_profile_data(user, "User has no profile attached")
        error_data[:result_order] = processed_count
        report << error_data
        return
      end

      # Bibliography base URL
      bibliography_base_url = "https://assets.philosophie.ch/references/"

      # Extract bibliography URLs and strip base URL
      bibliography_asset_url = user.profile.bibliography_asset_url.blank? ? "" : user.profile.bibliography_asset_url.gsub(bibliography_base_url, '')
      bibliography_further_asset_url = user.profile.bibliography_further_references_asset_url.blank? ? "" : user.profile.bibliography_further_references_asset_url.gsub(bibliography_base_url, '')

      # Cache expensive lookups (called once per user instead of multiple times)
      # Use precomputed map instead of calling get_assigned_articles (which queries ALL articles)
      assigned_articles = user_articles_map[user.login] || []
      assigned_articles_urlnames = assigned_articles.map(&:urlname).join(', ')
      assigned_articles_links = assigned_articles.map { |a| get_page_link(a) }.join(', ')
      commented_pages = get_commented_pages_urlnames(user)
      potential_duplicates = get_potential_duplicates(user)

      # Build the report hash - MUST match the structure from profiles.rb exactly
      profile_data = {
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
        last_updated_by: get_last_updater(user),
        last_updated_date: get_last_updated_date(user),

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
        profile_picture: get_profile_picture_file_name(user),
        profile_picture_asset: get_profile_picture_asset_name(user),
        facebook_profile: user.profile.facebook_profile,

        status: 'success',
        changes_made: '',
        error_message: '',
        error_trace: '',
        update_links_report: '',
        result_order: processed_count,

        public: user.profile.public,
        other_personal_information: user.profile.other_personal_information,
        confirmed_at: user.profile.confirmed_at,
        potential_duplicates: potential_duplicates,
      }

      report << profile_data
      Rails.logger.debug("Exported profile #{user.id}: #{user.login}")

    rescue => e
      Rails.logger.error("Error exporting user #{user&.id || 'unknown'} (#{user&.login || 'unknown'}): #{e.message}")
      error_data = build_error_profile_data(user, "#{e.class} :: #{e.message}", e.backtrace.join(" ::: "))
      error_data[:result_order] = processed_count
      report << error_data
    end
  end

  # Helper function to build error profile data
  def build_error_profile_data(user, error_message, error_trace = "")
    {
      _sort: "",
      _correspondence: "",
      _todo_person: "",
      _request: "",
      alchemy_roles: user&.alchemy_roles&.join(', ') || "",
      _member_subcategory: "",
      _status_wrt_association: "",
      membership_wanted: "",
      id: user&.id || "",
      _role_wrt_portal: "",
      _biblio_name: "",
      _biblio_full_name: "",
      profile_name: "",
      firstname: user&.firstname || "",
      lastname: user&.lastname || "",
      email_addresses: "",
      newsletter: "",
      academic_page: "",
      abbreviation: "",
      _function: "",
      login: user&.login || "",
      _old_login: "",
      _link: "",
      password: "",
      language: user&.language || "",
      gender: user&.gender || "",
      last_updated_by: "",
      last_updated_date: "",
      _contact_person: "",
      _contact_person_email: "",
      _articles_assigned_to_profile: "",
      _articles_assigned_to_profile_links: "",
      biblio_keys: "",
      bibliography_asset_url: "",
      biblio_keys_further_references: "",
      bibliography_further_references_asset_url: "",
      biblio_dependencies_keys: "",
      pages_commented: "",
      mentioned_on: "",
      _comments_on_contacts: "",
      institutional_affiliation: "",
      _comments_on_employment: "",
      _form_of_address: "",
      _title: "",
      type_of_affiliation: "",
      other_type_of_affiliation: "",
      _function_title: "",
      _function_standardised: "",
      country: "",
      area: "",
      _canton: "",
      description: "",
      website: "",
      teacher_at_institution: "",
      teacher_at_other_institution: "",
      _interests: "",
      _projects: "",
      societies: "",
      cms_public_email_toggle: "",
      profile_picture: "",
      profile_picture_asset: "",
      facebook_profile: "",
      status: 'unhandled error',
      changes_made: '',
      error_message: error_message,
      error_trace: error_trace,
      update_links_report: '',
      result_order: 0,
      public: "",
      other_personal_information: "",
      confirmed_at: "",
      potential_duplicates: "",
    }
  end

  # Execute based on whether we have specific IDs or exporting all
  if users
    # Process specific users in order
    users.each(&process_user)
  else
    # Use find_each for memory-efficient iteration through all users
    # Eager load associations to minimize queries
    Alchemy::User
      .includes(
        :profile,
        profile: [:societies]
      )
      .find_each(batch_size: 100, &process_user)
  end


  ############
  # REPORT GENERATION
  ############

  Rails.logger.info("Export complete. Generating report...")
  generate_csv_report(report, "profiles")

  Rails.logger.info("Successfully exported #{processed_count} profiles")

end


############
# CLI ENTRY POINT
############

if __FILE__ == $0
  # Parse command line arguments
  # Usage:
  #   ruby export_profiles.rb [log_level]                    # Export all profiles
  #   ruby export_profiles.rb [ids_or_file] [log_level]      # Export specific IDs

  if ARGV.length == 0
    # No arguments - export all with default log level
    export_profiles(nil, 'info')

  elsif ARGV.length == 1
    # One argument - could be log level OR ids/file
    arg = ARGV[0]

    # Check if it's a log level
    if ['debug', 'info', 'warn', 'error'].include?(arg.downcase)
      export_profiles(nil, arg)
    else
      # Assume it's IDs or a file
      export_profiles(arg, 'info')
    end

  elsif ARGV.length == 2
    # Two arguments - ids/file and log level
    export_profiles(ARGV[0], ARGV[1])

  else
    puts "Usage:"
    puts "  ruby export_profiles.rb [log_level]                   # Export all profiles"
    puts "  ruby export_profiles.rb [ids_or_file] [log_level]     # Export specific IDs"
    puts ""
    puts "Arguments:"
    puts "  ids_or_file   : File path (with one ID per line) OR comma-separated IDs"
    puts "  log_level     : debug, info, warn, or error (default: info)"
    puts ""
    puts "Examples:"
    puts "  ruby export_profiles.rb                               # Export all profiles, info logging"
    puts "  ruby export_profiles.rb debug                         # Export all profiles, debug logging"
    puts "  ruby export_profiles.rb ids.txt                       # Export IDs from file"
    puts "  ruby export_profiles.rb '123,456,789'                 # Export specific IDs"
    puts "  ruby export_profiles.rb ids.txt debug                 # Export IDs from file with debug"
    exit 1
  end
end
