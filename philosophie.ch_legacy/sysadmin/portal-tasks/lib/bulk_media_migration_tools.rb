# frozen_string_literal: true

module BulkMediaMigrationTools

  MEDIA_BLOCK_TYPES = {
    "audio_block" => { file_content: "audio_file", url_content: "audio_asset_url", counter_prefix: "audio" },
    "video_block" => { file_content: "video_file", url_content: "video_asset_url", counter_prefix: "video" },
    "pdf_block"   => { file_content: "pdf_file",   url_content: "pdf_asset_url",   counter_prefix: "pdf" },
  }.freeze

  # Scans a page for all media-bearing elements (audio, video, pdf).
  # Returns an array of hashes, one per media element:
  #   { element_id:, element_name:, has_asset_url:, has_attachment:,
  #     attachment_id:, target_filename: }
  def self.scan_page_media(page)
    results = []
    counters = Hash.new(0)

    media_elements = page.elements
      .select { |el| MEDIA_BLOCK_TYPES.key?(el.name) }
      .sort_by { |el| el.position.to_i }

    media_elements.each do |element|
      config = MEDIA_BLOCK_TYPES[element.name]
      counters[config[:counter_prefix]] += 1

      file_content = element.contents.find { |c| c.name == config[:file_content] }
      url_content = element.contents.find { |c| c.name == config[:url_content] }

      attachment = file_content&.essence&.respond_to?(:attachment) ? file_content.essence.attachment : nil
      has_attachment = attachment&.id.present?
      has_asset_url = url_content&.essence&.body.present?

      # Compute target filename using original extension from attachment
      ext = attachment ? File.extname(attachment.file_name) : ""
      target = "#{page.urlname}-#{config[:counter_prefix]}#{counters[config[:counter_prefix]]}#{ext}"

      results << {
        element_id: element.id,
        element_name: element.name,
        has_asset_url: has_asset_url,
        has_attachment: has_attachment,
        attachment_id: attachment&.id,
        target_filename: target,
      }
    end

    results
  end

  # Migrates a single media element: upload file -> set asset_url -> nullify association.
  # No compression — files are uploaded as-is.
  # Returns a report hash with :status, :error_message, :error_trace.
  def self.migrate_media_element(element, target_filename)
    report = { status: 'not started', error_message: '', error_trace: '' }

    config = MEDIA_BLOCK_TYPES[element.name]
    unless config
      report[:status] = 'error'
      report[:error_message] = "Unknown element type: #{element.name}"
      return report
    end

    file_content = element.contents.find { |c| c.name == config[:file_content] }
    essence = file_content&.essence
    attachment = essence&.respond_to?(:attachment) ? essence.attachment : nil

    unless attachment&.id.present?
      report[:status] = 'skipped'
      report[:error_message] = "No attachment found on element #{element.id}"
      return report
    end

    # Get file path via Dragonfly and upload
    source_path = attachment.file.path
    uploaded_path = FilebrowserClient.upload(source_path, target_filename)

    # Set asset_url on the element
    set_element_media_url(element, config[:url_content], uploaded_path)

    # Nullify legacy association (do not destroy the Attachment record)
    Alchemy::EssenceFile.where(id: essence.id).update_all(attachment_id: nil)

    report[:status] = 'success'
    report
  rescue StandardError => e
    report[:status] = 'error'
    report[:error_message] = "#{e.class} :: #{e.message}"
    report[:error_trace] = e.backtrace.join(" ::: ")
    report
  end

  # Cleanup for already-migrated media elements: nullify EssenceFile.attachment_id.
  # Does NOT destroy the Alchemy::Attachment record.
  # Returns a report hash.
  def self.cleanup_media_association(element)
    report = { status: 'not started', error_message: '', error_trace: '' }

    config = MEDIA_BLOCK_TYPES[element.name]
    unless config
      report[:status] = 'error'
      report[:error_message] = "Unknown element type: #{element.name}"
      return report
    end

    file_content = element.contents.find { |c| c.name == config[:file_content] }
    essence = file_content&.essence
    attachment_id = essence&.respond_to?(:attachment_id) ? essence.attachment_id : nil

    unless attachment_id.present?
      report[:status] = 'skipped'
      report[:error_message] = "No attachment association to clean up on element #{element.id}"
      return report
    end

    Alchemy::EssenceFile.where(id: essence.id).update_all(attachment_id: nil)

    report[:status] = 'success'
    report
  rescue StandardError => e
    report[:status] = 'error'
    report[:error_message] = "#{e.class} :: #{e.message}"
    report[:error_trace] = e.backtrace.join(" ::: ")
    report
  end

  # --- Private helpers ---

  def self.set_element_media_url(element, url_content_name, uploaded_path)
    url_content = element.contents.find { |c| c.name == url_content_name }

    if url_content&.essence
      url_content.essence.update!(body: uploaded_path)
    else
      new_essence = Alchemy::EssenceText.create!(body: uploaded_path)
      element.contents.create!(name: url_content_name, essence: new_essence)
    end
  end

  private_class_method :set_element_media_url
end
