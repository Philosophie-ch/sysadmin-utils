# frozen_string_literal: true

module BulkImageMigrationTools

  INTRO_ELEMENT_NAMES = %w[intro note_intro].freeze
  PIC_ELEMENT_NAMES = %w[picture_block text_and_picture].freeze

  # Scans a page for all image-bearing elements.
  # Returns an array of hashes, one per image-bearing element:
  #   { element_id:, element_type:, has_asset_url:, has_essence_picture:,
  #     picture_id:, target_filename:, essence_picture_content: }
  def self.scan_page_images(page)
    results = []

    # 1. Intro element
    intro_element = find_intro_element(page)
    if intro_element
      results << scan_element(intro_element, "intro", "#{page.urlname}.webp")
    end

    # 2. Picture blocks (picture_block and text_and_picture)
    pic_counter = 0
    pic_elements = page.elements
      .select { |el| PIC_ELEMENT_NAMES.include?(el.name) }
      .sort_by { |el| el.position.to_i }

    pic_elements.each do |element|
      pic_counter += 1
      target = "#{page.urlname}-pic#{pic_counter}.webp"
      results << scan_element(element, element.name, target)
    end

    results
  end

  # Scans a profile for avatar migration status.
  # Returns a hash:
  #   { has_asset_url:, has_avatar:, target_filename: }
  def self.scan_profile_image(profile)
    user = profile.user
    login = user&.login || "unknown-#{profile.id}"

    {
      has_asset_url: profile.profile_picture_url.present?,
      has_avatar: profile.avatar.attached?,
      target_filename: "people-#{login}.webp",
    }
  end

  # Migrates a single page element's image: compress -> upload -> set essence -> cleanup legacy.
  # Returns a report hash with :status, :error_message, :error_trace.
  def self.migrate_page_image(page, element, target_filename)
    report = { status: 'not started', error_message: '', error_trace: '' }

    essence_picture_content = find_essence_picture_content(element)
    unless essence_picture_content&.essence&.picture.present?
      report[:status] = 'skipped'
      report[:error_message] = "No EssencePicture found on element #{element.id}"
      return report
    end

    picture = essence_picture_content.essence.picture
    source_path = picture.image_file.path

    unless source_path && File.exist?(source_path)
      report[:status] = 'error'
      report[:error_message] = "Image file not found on disk (path: #{source_path.inspect}) for element #{element.id}"
      return report
    end

    result = ImageCompressor.compress(source_path, candidate_threshold: "1KB")
    begin
      uploaded_path = FilebrowserClient.upload(result.webp_path, target_filename)

      # Set asset_url on the element
      set_element_asset_url(element, uploaded_path)

      # Nullify legacy EssencePicture association
      Alchemy::EssencePicture.where(id: essence_picture_content.essence.id).update_all(picture_id: nil)

      # Destroy orphaned picture record (Dragonfly removes file from disk)
      if Alchemy::EssencePicture.where(picture_id: picture.id).none?
        picture.destroy
      end

      report[:status] = 'success'
      report[:uploaded_path] = uploaded_path
    ensure
      result.cleanup!
    end

    report
  rescue StandardError => e
    report[:status] = 'error'
    report[:error_message] = "#{e.class} :: #{e.message}"
    report[:error_trace] = e.backtrace.join(" ::: ")
    report
  end

  # Migrates a single profile's avatar: compress -> upload -> set column -> purge.
  # Returns a report hash.
  def self.migrate_profile_image(profile, user)
    report = { status: 'not started', error_message: '', error_trace: '' }

    unless profile.avatar.attached?
      report[:status] = 'skipped'
      report[:error_message] = "No avatar attached for user '#{user.login}'"
      return report
    end

    profile.avatar.open do |tempfile|
      result = ImageCompressor.compress(tempfile.path, candidate_threshold: "1KB")
      begin
        remote_path = "people-#{user.login}.webp"
        uploaded_path = FilebrowserClient.upload(result.webp_path, remote_path)

        profile.update_column(:profile_picture_url, uploaded_path)
      ensure
        result.cleanup!
      end
    end

    # Do not purge avatar yet — only set the asset_url column
    report[:status] = 'success'
    report
  rescue StandardError => e
    report[:status] = 'error'
    report[:error_message] = "#{e.class} :: #{e.message}"
    report[:error_trace] = e.backtrace.join(" ::: ")
    report
  end

  # Cleanup for already-migrated page elements: nullify EssencePicture association
  # and destroy orphaned Picture records (removes files from disk).
  # Returns a report hash.
  def self.cleanup_legacy_picture(element)
    report = { status: 'not started', error_message: '', error_trace: '' }

    essence_picture_content = find_essence_picture_content(element)
    unless essence_picture_content&.essence&.picture.present?
      report[:status] = 'skipped'
      report[:error_message] = "No EssencePicture to clean up on element #{element.id}"
      return report
    end

    picture = essence_picture_content.essence.picture
    Alchemy::EssencePicture.where(id: essence_picture_content.essence.id).update_all(picture_id: nil)

    # Destroy orphaned picture record (Dragonfly removes file from disk)
    if Alchemy::EssencePicture.where(picture_id: picture.id).none?
      picture.destroy
    end

    report[:status] = 'success'
    report
  rescue StandardError => e
    report[:status] = 'error'
    report[:error_message] = "#{e.class} :: #{e.message}"
    report[:error_trace] = e.backtrace.join(" ::: ")
    report
  end

  # --- Private helpers ---

  def self.find_intro_element(page)
    page.elements.find { |el| INTRO_ELEMENT_NAMES.include?(el.name) }
  end

  def self.find_essence_picture_content(element)
    element.contents.find { |c| c.essence.is_a?(Alchemy::EssencePicture) }
  end

  def self.scan_element(element, element_type, target_filename)
    essence_picture_content = find_essence_picture_content(element)
    has_essence_picture = essence_picture_content&.essence&.picture_id.present?
    picture_id = essence_picture_content&.essence&.picture_id

    url_content = element.contents.find { |c| c.name == "picture_asset_url" }
    has_asset_url = url_content&.essence&.body.present?

    {
      element_id: element.id,
      element_type: element_type,
      has_asset_url: has_asset_url,
      has_essence_picture: has_essence_picture,
      picture_id: picture_id,
      target_filename: target_filename,
    }
  end

  def self.set_element_asset_url(element, uploaded_path)
    url_content = element.contents.find { |c| c.name == "picture_asset_url" }

    if url_content&.essence
      url_content.essence.update!(body: uploaded_path)
    else
      # Determine the correct intro element if needed, then create content
      new_essence = Alchemy::EssenceText.create!(body: uploaded_path)
      element.contents.create!(name: "picture_asset_url", essence: new_essence)
    end
  end

  private_class_method :find_intro_element, :find_essence_picture_content,
                       :scan_element, :set_element_asset_url
end
