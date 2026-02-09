# frozen_string_literal: true

require 'csv'
require 'fileutils'

require_relative 'lib/utils'
require_relative 'lib/page_tools'
require_relative 'lib/export_utils'
require_relative 'lib/bulk_image_migration_tools'


def bulk_image_migration(mode, log_level = 'info', entity_filter = nil)

  ############
  # SETUP
  ############

  ExportUtils.setup_logging(log_level)

  unless %w[scan migrate].include?(mode)
    puts "Invalid mode: '#{mode}'. Must be 'scan' or 'migrate'."
    return
  end

  valid_filters = [nil, 'pages', 'profiles']
  unless valid_filters.include?(entity_filter)
    puts "Invalid entity filter: '#{entity_filter}'. Must be 'pages', 'profiles', or omitted for both."
    return
  end

  Rails.logger.info("=== Bulk Image Migration ===")
  Rails.logger.info("Mode: #{mode} | Log level: #{log_level} | Filter: #{entity_filter || 'all'}")

  report = []
  scan_results = { pages: [], profiles: [] }


  ############
  # PHASE 1: SCAN
  ############

  Rails.logger.info("--- Phase 1: Scanning ---")

  # Scan pages
  if entity_filter.nil? || entity_filter == 'pages'
    Rails.logger.info("Scanning pages...")
    page_count = 0
    total_pages = Alchemy::Page.count

    Alchemy::Page
      .includes(elements: { contents: :essence })
      .find_each(batch_size: 100) do |page|
        page_count += 1
        ExportUtils.log_progress(page_count, total_pages, "pages (scan)")

        begin
          images = BulkImageMigrationTools.scan_page_images(page)
          images.each do |img|
            action = if img[:has_asset_url] && img[:has_essence_picture]
                       'cleanup'
                     elsif img[:has_essence_picture] && !img[:has_asset_url]
                       'migrate'
                     elsif img[:has_asset_url] && !img[:has_essence_picture]
                       'already_done'
                     else
                       'no_image'
                     end

            scan_results[:pages] << {
              page_id: page.id,
              urlname: page.urlname,
              element_id: img[:element_id],
              element_type: img[:element_type],
              picture_id: img[:picture_id],
              target_filename: img[:target_filename],
              action: action,
            }
          end
        rescue StandardError => e
          Rails.logger.error("Scan error for page #{page.id}: #{e.message}")
          scan_results[:pages] << {
            page_id: page.id,
            urlname: page.urlname,
            element_id: nil,
            element_type: nil,
            picture_id: nil,
            target_filename: nil,
            action: 'scan_error',
          }
        end
      end

    # Summarize page scan
    page_actions = scan_results[:pages].group_by { |r| r[:action] }.transform_values(&:count)
    Rails.logger.info("Page scan complete: #{page_actions.inspect}")
  end

  # Scan profiles
  if entity_filter.nil? || entity_filter == 'profiles'
    Rails.logger.info("Scanning profiles...")
    profile_count = 0
    total_profiles = Profile.count

    Profile
      .includes(:avatar_attachment, :avatar_blob, :user)
      .find_each(batch_size: 100) do |profile|
        profile_count += 1
        ExportUtils.log_progress(profile_count, total_profiles, "profiles (scan)")

        begin
          img = BulkImageMigrationTools.scan_profile_image(profile)

          action = if img[:has_asset_url] && img[:has_avatar]
                     'cleanup'
                   elsif img[:has_avatar] && !img[:has_asset_url]
                     'migrate'
                   elsif img[:has_asset_url] && !img[:has_avatar]
                     'already_done'
                   else
                     'no_image'
                   end

          scan_results[:profiles] << {
            profile_id: profile.id,
            user_login: profile.user&.login || "unknown-#{profile.id}",
            target_filename: img[:target_filename],
            action: action,
          }
        rescue StandardError => e
          Rails.logger.error("Scan error for profile #{profile.id}: #{e.message}")
          scan_results[:profiles] << {
            profile_id: profile.id,
            user_login: profile.user&.login || "unknown-#{profile.id}",
            target_filename: nil,
            action: 'scan_error',
          }
        end
      end

    # Summarize profile scan
    profile_actions = scan_results[:profiles].group_by { |r| r[:action] }.transform_values(&:count)
    Rails.logger.info("Profile scan complete: #{profile_actions.inspect}")
  end

  # Print scan summary
  puts "\n=== Scan Summary ==="
  if entity_filter.nil? || entity_filter == 'pages'
    page_actions = scan_results[:pages].group_by { |r| r[:action] }.transform_values(&:count)
    puts "Pages:"
    page_actions.each { |action, count| puts "  #{action}: #{count}" }
  end
  if entity_filter.nil? || entity_filter == 'profiles'
    profile_actions = scan_results[:profiles].group_by { |r| r[:action] }.transform_values(&:count)
    puts "Profiles:"
    profile_actions.each { |action, count| puts "  #{action}: #{count}" }
  end
  puts ""

  # If scan-only mode, write report and exit
  if mode == 'scan'
    write_scan_report(scan_results, entity_filter)
    Rails.logger.info("Scan complete. No changes made.")
    return
  end


  ############
  # PHASE 2: CLEANUP ALREADY-MIGRATED
  ############

  Rails.logger.info("--- Phase 2: Cleanup already-migrated ---")

  # Cleanup pages
  if entity_filter.nil? || entity_filter == 'pages'
    cleanup_entries = scan_results[:pages].select { |r| r[:action] == 'cleanup' }
    Rails.logger.info("Cleaning up #{cleanup_entries.size} already-migrated page elements...")

    cleanup_entries.each do |entry|
      begin
        element = Alchemy::Element.includes(contents: :essence).find(entry[:element_id])

        ActiveRecord::Base.transaction do
          cleanup_report = BulkImageMigrationTools.cleanup_legacy_picture(element)

          report << {
            entity_type: 'page',
            entity_id: entry[:page_id],
            entity_identifier: entry[:urlname],
            element_type: entry[:element_type],
            source_info: "picture_id=#{entry[:picture_id]}",
            target_filename: entry[:target_filename],
            action: 'cleanup',
            status: cleanup_report[:status],
            error_message: cleanup_report[:error_message],
            error_trace: cleanup_report[:error_trace],
          }
        end

        Rails.logger.debug("Cleaned up element #{entry[:element_id]} on page #{entry[:urlname]}")
      rescue StandardError => e
        Rails.logger.error("Cleanup failed for element #{entry[:element_id]}: #{e.message}")
        report << {
          entity_type: 'page',
          entity_id: entry[:page_id],
          entity_identifier: entry[:urlname],
          element_type: entry[:element_type],
          source_info: "picture_id=#{entry[:picture_id]}",
          target_filename: entry[:target_filename],
          action: 'cleanup',
          status: 'error',
          error_message: "#{e.class} :: #{e.message}",
          error_trace: e.backtrace.join(" ::: "),
        }
      end
    end
  end

  # Cleanup profiles
  if entity_filter.nil? || entity_filter == 'profiles'
    cleanup_entries = scan_results[:profiles].select { |r| r[:action] == 'cleanup' }
    Rails.logger.info("Cleaning up #{cleanup_entries.size} already-migrated profile avatars...")

    cleanup_entries.each do |entry|
      begin
        # Profile already has asset_url set; avatar still attached.
        # Do not purge avatar yet — just log that cleanup is not needed at this stage.
        report << {
          entity_type: 'profile',
          entity_id: entry[:profile_id],
          entity_identifier: entry[:user_login],
          element_type: 'avatar',
          source_info: 'ActiveStorage avatar',
          target_filename: entry[:target_filename],
          action: 'cleanup',
          status: 'skipped',
          error_message: 'Avatar purge deferred — not deleting portal assets yet',
          error_trace: '',
        }

        Rails.logger.debug("Skipped avatar cleanup for profile #{entry[:user_login]} (deferred)")
      rescue StandardError => e
        Rails.logger.error("Cleanup failed for profile #{entry[:profile_id]}: #{e.message}")
        report << {
          entity_type: 'profile',
          entity_id: entry[:profile_id],
          entity_identifier: entry[:user_login],
          element_type: 'avatar',
          source_info: 'ActiveStorage avatar',
          target_filename: entry[:target_filename],
          action: 'cleanup',
          status: 'error',
          error_message: "#{e.class} :: #{e.message}",
          error_trace: e.backtrace.join(" ::: "),
        }
      end
    end
  end


  ############
  # PHASE 3: MIGRATE
  ############

  Rails.logger.info("--- Phase 3: Migrate ---")

  # Migrate pages
  if entity_filter.nil? || entity_filter == 'pages'
    migrate_entries = scan_results[:pages].select { |r| r[:action] == 'migrate' }

    # Group by page_id so we can do per-page transactions
    entries_by_page = migrate_entries.group_by { |r| r[:page_id] }
    Rails.logger.info("Migrating images on #{entries_by_page.size} pages (#{migrate_entries.size} elements total)...")

    migrated_page_count = 0
    entries_by_page.each do |page_id, entries|
      migrated_page_count += 1
      ExportUtils.log_progress(migrated_page_count, entries_by_page.size, "pages (migrate)")

      begin
        page = Alchemy::Page.includes(elements: { contents: :essence }).find(page_id)

        ActiveRecord::Base.transaction do
          entries.each do |entry|
            element = page.elements.find { |el| el.id == entry[:element_id] }

            unless element
              report << {
                entity_type: 'page',
                entity_id: page_id,
                entity_identifier: entry[:urlname],
                element_type: entry[:element_type],
                source_info: "picture_id=#{entry[:picture_id]}",
                target_filename: entry[:target_filename],
                action: 'migrate',
                status: 'error',
                error_message: "Element #{entry[:element_id]} not found on page",
                error_trace: '',
              }
              next
            end

            migration_report = BulkImageMigrationTools.migrate_page_image(page, element, entry[:target_filename])

            report << {
              entity_type: 'page',
              entity_id: page_id,
              entity_identifier: entry[:urlname],
              element_type: entry[:element_type],
              source_info: "picture_id=#{entry[:picture_id]}",
              target_filename: entry[:target_filename],
              action: 'migrate',
              status: migration_report[:status],
              error_message: migration_report[:error_message],
              error_trace: migration_report[:error_trace],
            }

            if migration_report[:status] != 'success'
              raise ActiveRecord::Rollback, "Migration failed for element #{entry[:element_id]}: #{migration_report[:error_message]}"
            end
          end

          page.publish!
        end

        Rails.logger.debug("Migrated page #{page_id} (#{entries.size} elements)")
      rescue StandardError => e
        Rails.logger.error("Migration failed for page #{page_id}: #{e.message}")

        # If the transaction was rolled back, mark remaining entries as errors
        already_reported = report.select { |r| r[:entity_id] == page_id && r[:action] == 'migrate' }.map { |r| r[:element_type] + r[:target_filename] }
        entries.each do |entry|
          key = entry[:element_type] + entry[:target_filename]
          next if already_reported.include?(key)

          report << {
            entity_type: 'page',
            entity_id: page_id,
            entity_identifier: entry[:urlname],
            element_type: entry[:element_type],
            source_info: "picture_id=#{entry[:picture_id]}",
            target_filename: entry[:target_filename],
            action: 'migrate',
            status: 'error',
            error_message: "#{e.class} :: #{e.message}",
            error_trace: e.backtrace.join(" ::: "),
          }
        end
      end
    end
  end

  # Migrate profiles
  if entity_filter.nil? || entity_filter == 'profiles'
    migrate_entries = scan_results[:profiles].select { |r| r[:action] == 'migrate' }
    Rails.logger.info("Migrating #{migrate_entries.size} profile avatars...")

    migrated_profile_count = 0
    migrate_entries.each do |entry|
      migrated_profile_count += 1
      ExportUtils.log_progress(migrated_profile_count, migrate_entries.size, "profiles (migrate)")

      begin
        profile = Profile.includes(:avatar_attachment, :avatar_blob, :user).find(entry[:profile_id])
        user = profile.user

        unless user
          report << {
            entity_type: 'profile',
            entity_id: entry[:profile_id],
            entity_identifier: entry[:user_login],
            element_type: 'avatar',
            source_info: 'ActiveStorage avatar',
            target_filename: entry[:target_filename],
            action: 'migrate',
            status: 'error',
            error_message: 'User not found for profile',
            error_trace: '',
          }
          next
        end

        ActiveRecord::Base.transaction do
          migration_report = BulkImageMigrationTools.migrate_profile_image(profile, user)

          report << {
            entity_type: 'profile',
            entity_id: entry[:profile_id],
            entity_identifier: entry[:user_login],
            element_type: 'avatar',
            source_info: 'ActiveStorage avatar',
            target_filename: entry[:target_filename],
            action: 'migrate',
            status: migration_report[:status],
            error_message: migration_report[:error_message],
            error_trace: migration_report[:error_trace],
          }
        end

        Rails.logger.debug("Migrated profile for #{entry[:user_login]}")
      rescue StandardError => e
        Rails.logger.error("Migration failed for profile #{entry[:profile_id]}: #{e.message}")
        report << {
          entity_type: 'profile',
          entity_id: entry[:profile_id],
          entity_identifier: entry[:user_login],
          element_type: 'avatar',
          source_info: 'ActiveStorage avatar',
          target_filename: entry[:target_filename],
          action: 'migrate',
          status: 'error',
          error_message: "#{e.class} :: #{e.message}",
          error_trace: e.backtrace.join(" ::: "),
        }
      end
    end
  end


  ############
  # PHASE 4: REPORT
  ############

  Rails.logger.info("--- Phase 4: Report ---")

  # Print summary
  puts "\n=== Migration Summary ==="
  report_actions = report.group_by { |r| [r[:action], r[:status]] }.transform_values(&:count)
  report_actions.each { |(action, status), count| puts "  #{action}/#{status}: #{count}" }
  puts "Total entries: #{report.size}"
  puts ""

  # Write CSV report
  if report.any?
    generate_csv_report(report, "bulk_image_migration")
  else
    Rails.logger.info("No actions taken, no report to generate.")
    puts "No actions taken."
  end

  Rails.logger.info("=== Bulk Image Migration Complete ===")
end


def write_scan_report(scan_results, entity_filter)
  report = []

  if entity_filter.nil? || entity_filter == 'pages'
    scan_results[:pages].each do |entry|
      report << {
        entity_type: 'page',
        entity_id: entry[:page_id],
        entity_identifier: entry[:urlname],
        element_type: entry[:element_type] || '',
        source_info: entry[:picture_id] ? "picture_id=#{entry[:picture_id]}" : '',
        target_filename: entry[:target_filename] || '',
        action: entry[:action],
        status: 'scan_only',
        error_message: '',
        error_trace: '',
      }
    end
  end

  if entity_filter.nil? || entity_filter == 'profiles'
    scan_results[:profiles].each do |entry|
      report << {
        entity_type: 'profile',
        entity_id: entry[:profile_id],
        entity_identifier: entry[:user_login],
        element_type: 'avatar',
        source_info: '',
        target_filename: entry[:target_filename] || '',
        action: entry[:action],
        status: 'scan_only',
        error_message: '',
        error_trace: '',
      }
    end
  end

  if report.any?
    generate_csv_report(report, "bulk_image_migration_scan")
  else
    puts "No images found to report."
  end
end


############
# CLI ENTRY POINT
############

if __FILE__ == $0
  # Usage:
  #   ruby bulk_image_migration.rb scan [log_level] [entity_filter]
  #   ruby bulk_image_migration.rb migrate [log_level] [entity_filter]
  #
  # Examples:
  #   ruby bulk_image_migration.rb scan
  #   ruby bulk_image_migration.rb scan debug
  #   ruby bulk_image_migration.rb migrate
  #   ruby bulk_image_migration.rb migrate debug
  #   ruby bulk_image_migration.rb migrate info pages
  #   ruby bulk_image_migration.rb migrate info profiles

  if ARGV.empty? || !%w[scan migrate].include?(ARGV[0])
    puts "Usage:"
    puts "  ruby bulk_image_migration.rb scan [log_level] [entity_filter]"
    puts "  ruby bulk_image_migration.rb migrate [log_level] [entity_filter]"
    puts ""
    puts "Modes:"
    puts "  scan     : Dry-run, report only (no changes)"
    puts "  migrate  : Compress, upload, and cleanup legacy images"
    puts ""
    puts "Arguments:"
    puts "  log_level     : debug, info, warn, or error (default: info)"
    puts "  entity_filter : pages, profiles, or omit for both"
    puts ""
    puts "Examples:"
    puts "  ruby bulk_image_migration.rb scan                    # Scan all"
    puts "  ruby bulk_image_migration.rb scan debug              # Scan all with debug"
    puts "  ruby bulk_image_migration.rb migrate                 # Migrate all"
    puts "  ruby bulk_image_migration.rb migrate info pages      # Migrate pages only"
    puts "  ruby bulk_image_migration.rb migrate info profiles   # Migrate profiles only"
    exit 1
  end

  mode = ARGV[0]
  log_level = ARGV[1] || 'info'
  entity_filter = ARGV[2]

  bulk_image_migration(mode, log_level, entity_filter)
end
