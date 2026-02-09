# frozen_string_literal: true

require 'csv'
require 'fileutils'

require_relative 'lib/utils'
require_relative 'lib/page_tools'
require_relative 'lib/export_utils'
require_relative 'lib/bulk_media_migration_tools'


def bulk_media_migration(mode, log_level = 'info')

  ############
  # SETUP
  ############

  ExportUtils.setup_logging(log_level)

  unless %w[scan migrate].include?(mode)
    puts "Invalid mode: '#{mode}'. Must be 'scan' or 'migrate'."
    return
  end

  Rails.logger.info("=== Bulk Media Migration (Audio, Video, PDF) ===")
  Rails.logger.info("Mode: #{mode} | Log level: #{log_level}")

  report = []
  scan_results = []


  ############
  # PHASE 1: SCAN
  ############

  Rails.logger.info("--- Phase 1: Scanning ---")

  page_count = 0
  total_pages = Alchemy::Page.count

  Alchemy::Page
    .includes(elements: { contents: :essence })
    .find_each(batch_size: 100) do |page|
      page_count += 1
      ExportUtils.log_progress(page_count, total_pages, "pages (scan)")

      begin
        media = BulkMediaMigrationTools.scan_page_media(page)
        media.each do |m|
          action = if m[:has_asset_url] && m[:has_attachment]
                     'cleanup'
                   elsif m[:has_attachment] && !m[:has_asset_url]
                     'migrate'
                   elsif m[:has_asset_url] && !m[:has_attachment]
                     'already_done'
                   else
                     'no_file'
                   end

          scan_results << {
            page_id: page.id,
            urlname: page.urlname,
            element_id: m[:element_id],
            element_name: m[:element_name],
            attachment_id: m[:attachment_id],
            target_filename: m[:target_filename],
            action: action,
          }
        end
      rescue StandardError => e
        Rails.logger.error("Scan error for page #{page.id}: #{e.message}")
        scan_results << {
          page_id: page.id,
          urlname: page.urlname,
          element_id: nil,
          element_name: nil,
          attachment_id: nil,
          target_filename: nil,
          action: 'scan_error',
        }
      end
    end

  # Print scan summary
  actions_summary = scan_results.group_by { |r| r[:action] }.transform_values(&:count)
  Rails.logger.info("Scan complete: #{actions_summary.inspect}")

  puts "\n=== Scan Summary ==="
  actions_summary.each { |action, count| puts "  #{action}: #{count}" }
  puts ""

  # If scan-only mode, write report and exit
  if mode == 'scan'
    write_media_scan_report(scan_results)
    Rails.logger.info("Scan complete. No changes made.")
    return
  end


  ############
  # PHASE 2: CLEANUP ALREADY-MIGRATED
  ############

  Rails.logger.info("--- Phase 2: Cleanup already-migrated ---")

  cleanup_entries = scan_results.select { |r| r[:action] == 'cleanup' }
  Rails.logger.info("Cleaning up #{cleanup_entries.size} already-migrated media elements...")

  cleanup_entries.each do |entry|
    begin
      element = Alchemy::Element.includes(contents: :essence).find(entry[:element_id])

      ActiveRecord::Base.transaction do
        cleanup_report = BulkMediaMigrationTools.cleanup_media_association(element)

        report << {
          entity_type: 'page',
          entity_id: entry[:page_id],
          entity_identifier: entry[:urlname],
          element_type: entry[:element_name],
          source_info: "attachment_id=#{entry[:attachment_id]}",
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
        element_type: entry[:element_name],
        source_info: "attachment_id=#{entry[:attachment_id]}",
        target_filename: entry[:target_filename],
        action: 'cleanup',
        status: 'error',
        error_message: "#{e.class} :: #{e.message}",
        error_trace: e.backtrace.join(" ::: "),
      }
    end
  end


  ############
  # PHASE 3: MIGRATE
  ############

  Rails.logger.info("--- Phase 3: Migrate ---")

  migrate_entries = scan_results.select { |r| r[:action] == 'migrate' }
  entries_by_page = migrate_entries.group_by { |r| r[:page_id] }
  Rails.logger.info("Migrating media on #{entries_by_page.size} pages (#{migrate_entries.size} elements total)...")

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
              element_type: entry[:element_name],
              source_info: "attachment_id=#{entry[:attachment_id]}",
              target_filename: entry[:target_filename],
              action: 'migrate',
              status: 'error',
              error_message: "Element #{entry[:element_id]} not found on page",
              error_trace: '',
            }
            next
          end

          migration_report = BulkMediaMigrationTools.migrate_media_element(element, entry[:target_filename])

          report << {
            entity_type: 'page',
            entity_id: page_id,
            entity_identifier: entry[:urlname],
            element_type: entry[:element_name],
            source_info: "attachment_id=#{entry[:attachment_id]}",
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

      Rails.logger.debug("Migrated page #{page_id} (#{entries.size} media elements)")
    rescue StandardError => e
      Rails.logger.error("Migration failed for page #{page_id}: #{e.message}")

      already_reported = report.select { |r| r[:entity_id] == page_id && r[:action] == 'migrate' }.map { |r| r[:target_filename] }
      entries.each do |entry|
        next if already_reported.include?(entry[:target_filename])

        report << {
          entity_type: 'page',
          entity_id: page_id,
          entity_identifier: entry[:urlname],
          element_type: entry[:element_name],
          source_info: "attachment_id=#{entry[:attachment_id]}",
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

  puts "\n=== Migration Summary ==="
  report_actions = report.group_by { |r| [r[:action], r[:status]] }.transform_values(&:count)
  report_actions.each { |(action, status), count| puts "  #{action}/#{status}: #{count}" }
  puts "Total entries: #{report.size}"
  puts ""

  if report.any?
    generate_csv_report(report, "bulk_media_migration")
  else
    Rails.logger.info("No actions taken, no report to generate.")
    puts "No actions taken."
  end

  Rails.logger.info("=== Bulk Media Migration Complete ===")
end


def write_media_scan_report(scan_results)
  report = scan_results.map do |entry|
    {
      entity_type: 'page',
      entity_id: entry[:page_id],
      entity_identifier: entry[:urlname],
      element_type: entry[:element_name] || '',
      source_info: entry[:attachment_id] ? "attachment_id=#{entry[:attachment_id]}" : '',
      target_filename: entry[:target_filename] || '',
      action: entry[:action],
      status: 'scan_only',
      error_message: '',
      error_trace: '',
    }
  end

  if report.any?
    generate_csv_report(report, "bulk_media_migration_scan")
  else
    puts "No media elements found to report."
  end
end


############
# CLI ENTRY POINT
############

if __FILE__ == $0
  # Usage:
  #   ruby bulk_media_migration.rb scan [log_level]
  #   ruby bulk_media_migration.rb migrate [log_level]
  #
  # Examples:
  #   ruby bulk_media_migration.rb scan
  #   ruby bulk_media_migration.rb scan debug
  #   ruby bulk_media_migration.rb migrate
  #   ruby bulk_media_migration.rb migrate debug

  if ARGV.empty? || !%w[scan migrate].include?(ARGV[0])
    puts "Usage:"
    puts "  ruby bulk_media_migration.rb scan [log_level]"
    puts "  ruby bulk_media_migration.rb migrate [log_level]"
    puts ""
    puts "Modes:"
    puts "  scan     : Dry-run, report only (no changes)"
    puts "  migrate  : Upload files and cleanup legacy associations"
    puts ""
    puts "Arguments:"
    puts "  log_level : debug, info, warn, or error (default: info)"
    puts ""
    puts "Examples:"
    puts "  ruby bulk_media_migration.rb scan                # Scan all"
    puts "  ruby bulk_media_migration.rb scan debug          # Scan all with debug"
    puts "  ruby bulk_media_migration.rb migrate             # Migrate all"
    puts "  ruby bulk_media_migration.rb migrate debug       # Migrate with debug"
    exit 1
  end

  mode = ARGV[0]
  log_level = ARGV[1] || 'info'

  bulk_media_migration(mode, log_level)
end
