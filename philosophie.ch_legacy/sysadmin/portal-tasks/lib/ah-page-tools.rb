require_relative 'utils'
require_relative 'page_tools'


def migrate_text_block_headlines_to_title_blocks_old(page)
  report = {
    status: 'not started',
    error_message: '',
    error_trace: '',
  }

  begin

    unless page.elements.where(name: "text_block").any?
      report[:status] = 'success'
      report[:error_message] = "No text blocks found. Skipping..."
      return report
    end

    # WARNING: this reloads the page!
    page.reload
    elements = page.elements.order(:position) # Ensure correct ordering

    ActiveRecord::Base.transaction do
      elements.each do |element|
        next unless element.name == "text_block"
        headline_essence = element.contents.find_by(name: "headline").essence
        if headline_essence.body&.strip.blank? # Skip if no headline
          report[:error_message] += "Text block with ID #{element.id} has no headline. Skipping... ::: "
          next
        end

        title_block_position = element.position
        # Create a new title_block element at the same position
        title_block = page.elements.create!(name: "title_block", position: title_block_position, public: true)

        # Adjust positions for all subsequent elements
        elements_after = elements.where('position > ?', title_block_position)
        elements_after.each do |e|
          e.position += 1
          e.save!
        end

        # Transfer the headline text into the new title_block
        title_block.contents.find_by(name: "text")&.essence&.update!(body: headline_essence.body)

        # Adjust positions for all subsequent elements
        headline_essence.body = ""

        # Save everything
        headline_essence.save!
        title_block.save!
        elements.each(&:save!)
        elements.each(&:reload)
      end

      page.elements = elements.reorder('position ASC')
      # Save and publish page
      page.reload
      page.save!
      page.publish!
      page.reload
    end

    report[:status] = 'success'

  rescue => e
    Rails.logger.error("Error while migrating text block headlines: #{e.message}")
    report[:status] = 'error'
    report[:error_message] = "#{e.class} :: #{e.message}"
    report[:error_trace] = e.backtrace.join(" ::: ")
  end

  return report
end

def csv_backup_title_blocks()
  title_blocks = Alchemy::Element.where(name: "title_block")
  CSV.open("title_blocks_backup.csv", "wb") do |csv|
    csv << ["page_id", "title_block_element_id", "position", "text"]
    title_blocks.each do |title_block|
      page = title_block.page
      position = title_block.position
      text = title_block.contents.find_by(name: "text")&.essence&.body
      csv << [page.id, title_block.id, position, text]
    end
  end
end

def csv_backup_subtitle_blocks()
  subtitle_blocks = Alchemy::Element.where(name: "subtitle_block")
  CSV.open("subtitle_blocks_backup.csv", "wb") do |csv|
    csv << ["page_id", "subtitle_block_element_id", "position", "text"]
    subtitle_blocks.each do |subtitle_block|
      page = subtitle_block.page
      position = subtitle_block.position
      text = subtitle_block.contents.find_by(name: "text")&.essence&.body
      csv << [page.id, subtitle_block.id, position, text]
    end
  end
end

def repristine_title_blocks()
  old_title_blocks = Alchemy::Element.where(name: "title_block")

  CSV.open("title_blocks_migration_report.csv", "wb") do |csv|
    csv << ["page_id", "element_id", "position", "text", "transaction_status", "status_message", "trace"]

    old_title_blocks.each do |title_block|
      ActiveRecord::Base.transaction do
        page = title_block.page
        position = title_block.position
        text = title_block.contents.find_by(name: "text")&.essence&.body
        page_urlname = page.urlname
        transaction_status = "error"
        status_message = ""
        trace = ""

        begin
          new_title_block = page.elements.create!(name: "title_block", position: title_block.position, public: true)
          new_title_block.contents.find_by(name: "text")&.essence&.update!(body: title_block.contents.find_by(name: "text")&.essence&.body)
          new_title_block.save!
          title_block.destroy!
          page.save!
          page.publish!
          transaction_status = "success"
        rescue => e
          Rails.logger.error("Error while migrating title block with ID #{title_block.id} on page #{page_urlname}: #{e.message}")
          transaction_status = "error"
          status_message = "#{e.class} ::: #{e.message}"
          trace = e.backtrace.join(" ::: ")
        end

        csv << [page.id, title_block.id, position, text, transaction_status, status_message, trace]
      end
    end
  end

  Rails.logger.info("Title blocks migration report written to title_blocks_migration_report.csv")
end

def repristine_subtitle_blocks()
  old_subtitle_blocks = Alchemy::Element.where(name: "subtitle_block")

  CSV.open("subtitle_blocks_migration_report.csv", "wb") do |csv|
    csv << ["page_id", "element_id", "position", "text", "transaction_status", "status_message", "trace"]

    old_subtitle_blocks.each do |subtitle_block|
      ActiveRecord::Base.transaction do
        page = subtitle_block.page
        position = subtitle_block.position
        text = subtitle_block.contents.find_by(name: "text")&.essence&.body
        page_urlname = page.urlname
        transaction_status = "error"
        status_message = ""
        trace = ""

        begin
          new_subtitle_block = page.elements.create!(name: "subtitle_block", position: subtitle_block.position, public: true)
          new_subtitle_block.contents.find_by(name: "text")&.essence&.update!(body: subtitle_block.contents.find_by(name: "text")&.essence&.body)
          new_subtitle_block.save!
          subtitle_block.destroy!
          page.save!
          page.publish!
          transaction_status = "success"
        rescue => e
          Rails.logger.error("Error while migrating subtitle block with ID #{subtitle_block.id} on page #{page_urlname}: #{e.message}")
          transaction_status = "error"
          status_message = "#{e.class} ::: #{e.message}"
          trace = e.backtrace.join(" ::: ")
        end

        csv << [page.id, subtitle_block.id, position, text, transaction_status, status_message, trace]
      end
    end
  end

  Rails.logger.info("Subtitle blocks migration report written to subtitle_blocks_migration_report.csv")
end


def migrate_text_block_headlines_to_title_blocks()
  #all_pages = Alchemy::Page.all

  selected_ids = [7681, 9462, 10148, 9463, 9464, 4404, 2124, 2436, 3865, 5844, 5845, 8228, 9412, 10132, 10130, 10129, 10131, 10046, 10128, 10045]
  all_pages = Alchemy::Page.where(id: selected_ids)


  base_folder = 'portal-tasks-reports'
  FileUtils.mkdir_p(base_folder) unless Dir.exist?(base_folder)

  CSV.open("#{base_folder}/text_block_migration_report.csv", "wb") do |csv|
    csv << ["page_id", "text_block_id", "in_aside_column", "position", "headline", "transaction_status", "status_message", "trace"]


    all_pages.each do |page|

      begin
        page.reload

        elements = page.elements.order(:position) # Ensure correct ordering
        ActiveRecord::Base.transaction do
          elements.each do |element|
            begin
              next unless element.name == "text_block"
              headline_essence = element.contents.find_by(name: "headline")&.essence
              next unless headline_essence

              headline = headline_essence.body&.strip
              if headline.blank?
                csv << [page.id, element.id, "no", element.position, headline, "skipped", "No headline found", ""]
                next
              end

              title_block_position = element.position
              # Create a new title_block element at the same position
              title_block = page.elements.create!(name: "title_block", position: title_block_position, public: true)

              # Adjust positions for all subsequent elements
              elements_after = elements.where('position > ?', title_block_position)
              elements_after.each do |e|
                e.position += 1
                e.save!
              end

              # Transfer the headline text into the new title_block
              title_block.contents.find_by(name: "text")&.essence&.update!(body: headline)

              # Clear the original headline
              headline_essence.update!(body: "")

              # Save everything
              headline_essence.save!
              title_block.save!
              csv << [page.id, element.id, "yes", element.position, headline, "success", "", ""]
              elements.each(&:save!)
              elements.each(&:reload)
            rescue => e
              Rails.logger.error("Error while migrating text block headlines for page #{page.urlname}: #{e.message}")
              csv << [page.id, element.id, "no", element.position, headline, "error", "#{e.class} :: #{e.message}", e.backtrace.join(" ::: ")]
            end
          end

          page.elements = elements.reorder('position ASC')
          # Save and publish page
          page.reload
          page.save!
          page.publish!
          page.reload

          aside_column = page.fixed_elements.find_by(name: "aside_column")

          if aside_column.present?
            Rails.logger.info("Migrating text block headlines to title blocks in aside column for page #{page.urlname}")

            aside_column_nested_elements = aside_column.nested_elements.order(:position) # Ensure correct ordering

            ActiveRecord::Base.transaction do
              aside_column_nested_elements.each do |element|
                begin
                  next unless element.name == "text_block"
                  headline_essence = element.contents.find_by(name: "headline")&.essence
                  next unless headline_essence

                  headline = headline_essence.body&.strip
                  if headline.blank?
                    csv << [page.id, element.id, "yes", element.position, headline, "skipped", "No headline found", ""]
                    next
                  end

                  title_block_position = element.position
                  # Create a new title_block element at the same position
                  title_block = aside_column.nested_elements.create!(name: "title_block", position: title_block_position, public: true, parent_element_id: aside_column.id, page_id: page.id)

                  # Adjust positions for all subsequent elements
                  elements_after = aside_column_nested_elements.where('position > ?', title_block_position)
                  elements_after.each do |e|
                    e.position += 1
                    e.save!
                  end

                  # Transfer the headline text into the new title_block
                  title_block.contents.find_by(name: "text")&.essence&.update!(body: headline)

                  # Clear the original headline
                  headline_essence.update!(body: "")

                  # Save everything
                  headline_essence.save!
                  title_block.save!
                  csv << [page.id, element.id, "yes", element.position, headline, "success", "", ""]
                  aside_column_nested_elements.each(&:save!)
                  aside_column_nested_elements.each(&:reload)
                rescue => e
                  Rails.logger.error("Error while migrating text block headlines for page #{page.urlname}: #{e.message}")
                  csv << [page.id, element.id, "yes", element.position, headline, "error", "#{e.class} :: #{e.message}", e.backtrace.join(" ::: ")]

                end
              end

              aside_column.nested_elements = aside_column_nested_elements.reorder('position ASC')
              # Save and publish aside column
              aside_column.reload
              aside_column.save!
              aside_column.reload
            end

            page.reload
            page.save!
            page.publish!
            page.reload

          end

        end

      rescue => e
        Rails.logger.error("Error while migrating text block headlines: #{e.message}")
        csv << [page.id, "", "", "", "", "error", "#{e.class} :: #{e.message}", e.backtrace.join(" ::: ")]

      end

    end
  end

  Rails.logger.info("Text block migration report written to text_block_migration_report.csv")
end


def get_aside_columns(page_id)
  Alchemy::Element.where(parent_element_id: nil, page_id: page_id, name: "aside_column")
end

def get_nested_elements_per_ac(page_id)
  result = []
  acs = get_aside_columns(page_id)

  acs.map do |ac|
    result << {
      aside_column_id: ac.id,
      nested_elements: ac.nested_elements
    }
  end

  return result
end

def destroy_ac(ac_id)
  acs = Alchemy::Element.where(id: ac_id, name: "aside_column")

  if acs.length > 1
    Rails.logger.error("More than one aside column found with ID #{ac_id}. Skipping...")
    return
  elsif acs.length == 0
    Rails.logger.error("No aside column found with ID #{ac_id}. Skipping...")
    return
  end

  acs.first.destroy!
end



def migrate_ac_text_block_headlines(page)
  aside_column = page.fixed_elements.find_by(name: "aside_column")

  if aside_column.present?
    Rails.logger.info("Migrating text block headlines to title blocks in aside column for page #{page.urlname}")

    aside_column_nested_elements = aside_column.nested_elements.order(:position) # Ensure correct ordering

    ActiveRecord::Base.transaction do
      aside_column_nested_elements.each do |element|
        next unless element.name == "text_block"
        headline_essence = element.contents.find_by(name: "headline")&.essence
        next unless headline_essence.present?

        headline = headline_essence.body&.strip
        if headline.blank?
          csv << [page.id, element.id, "yes", element.position, headline, "skipped", "No headline found", ""]
          next
        end

        title_block_position = element.position
        # Create a new title_block element at the same position
        title_block = aside_column.nested_elements.create!(name: "title_block", position: title_block_position, public: true, parent_element_id: aside_column.id, page_id: page.id)

        # Adjust positions for all subsequent elements
        elements_after = aside_column_nested_elements.where('position > ?', title_block_position)
        elements_after.each do |e|
          e.position += 1
          e.save!
        end

        # Transfer the headline text into the new title_block
        title_block.contents.find_by(name: "text")&.essence&.update!(body: headline)

        # Clear the original headline
        headline_essence.update!(body: "")

        # Save everything
        headline_essence.save!
        title_block.save!
        csv << [page.id, element.id, "yes", element.position, headline, "success", "", ""]
        aside_column_nested_elements.each(&:save!)
        aside_column_nested_elements.each(&:reload)
      end

      aside_column.nested_elements = aside_column_nested_elements.reorder('position ASC')
      # Save and publish aside column
      aside_column.reload
      aside_column.save!
      aside_column.publish!
      aside_column.reload
    end

    page.reload
    page.save!
    page.publish!
    page.reload

  end
end


#def get_all_textblocks_with_nonempty_headlines()
  #ac_tb_with_headline_body = acs_tb.select { |e| e.nested_elements.any? { |ne| ne.name == "text_block" && ne.contents.any? { |content| content.name == "headline" && content.essence&.body&.present? } } }
#end



# Text and picture blocks
def csv_backup_text_and_picture_blocks_headlines()
  tp_blocks = Alchemy::Element.where(name: "text_and_picture")
  CSV.open("text_and_picture_blocks_backup.csv", "wb") do |csv|
    csv << ["page_id", "tp_block_element_id", "position", "headline"]
    tp_blocks.each do |tp_block|
      page = tp_block.page
      position = tp_block.position
      headline = tp_block.contents.find_by(name: "headline")&.essence&.body
      csv << [page.id, tp_block.id, position, headline]
    end
  end
end


def migrate_text_and_picture_block_headlines_to_title_blocks()
  all_pages = Alchemy::Page.all

  #selected_ids = [10551]
  #all_pages = Alchemy::Page.where(id: selected_ids)


  base_folder = 'portal-tasks-reports'
  FileUtils.mkdir_p(base_folder) unless Dir.exist?(base_folder)

  CSV.open("#{base_folder}/text_and_picture_block_migration_report.csv", "wb") do |csv|
    csv << ["page_id", "tp_block_id", "in_aside_column", "position", "headline", "transaction_status", "status_message", "trace"]

    all_pages.each do |page|

      begin
        page.reload

        elements = page.elements.order(:position) # Ensure correct ordering
        ActiveRecord::Base.transaction do
          elements.each do |element|
            begin
              next unless element.name == "text_and_picture"
              headline_essence = element.contents.find_by(name: "headline")&.essence
              next unless headline_essence

              headline = headline_essence.body&.strip
              if headline.blank?
                csv << [page.id, element.id, "no", element.position, headline, "skipped", "No headline found", ""]
                next
              end

              title_block_position = element.position
              # Create a new title_block element at the same position
              title_block = page.elements.create!(name: "title_block", position: title_block_position, public: true)

              # Adjust positions for all subsequent elements
              elements_after = elements.where('position > ?', title_block_position)
              elements_after.each do |e|
                e.position += 1
                e.save!
              end

              # Transfer the headline text into the new title_block
              title_block.contents.find_by(name: "text")&.essence&.update!(body: headline)

              # Clear the original headline
              headline_essence.update!(body: "")

              # Save everything
              headline_essence.save!
              title_block.save!
              csv << [page.id, element.id, "yes", element.position, headline, "success", "", ""]
              elements.each(&:save!)
              elements.each(&:reload)
            rescue => e
              Rails.logger.error("Error while migrating text_and_picture block headlines for page #{page.urlname}: #{e.message}")
              csv << [page.id, element.id, "no", element.position, headline, "error", "#{e.class} :: #{e.message}", e.backtrace.join(" ::: ")]
            end
          end

          page.elements = elements.reorder('position ASC')
          # Save and publish page
          page.reload
          page.save!
          page.publish!
          page.reload

          aside_column = page.fixed_elements.find_by(name: "aside_column")

          if aside_column.present?
            Rails.logger.info("Migrating text_and_picture block headlines to title blocks in aside column for page #{page.urlname}")

            aside_column_nested_elements = aside_column.nested_elements.order(:position) # Ensure correct ordering

            ActiveRecord::Base.transaction do
              aside_column_nested_elements.each do |element|
                begin
                  next unless element.name == "text_and_picture"
                  headline_essence = element.contents.find_by(name: "headline")&.essence
                  next unless headline_essence

                  headline = headline_essence.body&.strip
                  if headline.blank?
                    csv << [page.id, element.id, "yes", element.position, headline, "skipped", "No headline found", ""]
                    next
                  end

                  title_block_position = element.position
                  # Create a new title_block element at the same position
                  title_block = aside_column.nested_elements.create!(name: "title_block", position: title_block_position, public: true, parent_element_id: aside_column.id, page_id: page.id)

                  # Adjust positions for all subsequent elements
                  elements_after = aside_column_nested_elements.where('position > ?', title_block_position)
                  elements_after.each do |e|
                    e.position += 1
                    e.save!
                  end

                  # Transfer the headline text into the new title_block
                  title_block.contents.find_by(name: "text")&.essence&.update!(body: headline)

                  # Clear the original headline
                  headline_essence.update!(body: "")

                  # Save everything
                  headline_essence.save!
                  title_block.save!
                  csv << [page.id, element.id, "yes", element.position, headline, "success", "", ""]
                  aside_column_nested_elements.each(&:save!)
                  aside_column_nested_elements.each(&:reload)
                rescue => e
                  Rails.logger.error("Error while migrating text_and_picture block headlines for page #{page.urlname}: #{e.message}")
                  csv << [page.id, element.id, "yes", element.position, headline, "error", "#{e.class} :: #{e.message}", e.backtrace.join(" ::: ")]

                end
              end

              aside_column.nested_elements = aside_column_nested_elements.reorder('position ASC')
              # Save and publish aside column
              aside_column.reload
              aside_column.save!
              aside_column.reload
            end

            page.reload
            page.save!
            page.publish!
            page.reload

          end

        end

      rescue => e
        Rails.logger.error("Error while migrating text_and_picture block headlines: #{e.message}")
        csv << [page.id, "", "", "", "", "error", "#{e.class} :: #{e.message}", e.backtrace.join(" ::: ")]

      end

    end
  end

  Rails.logger.info("Text and picture block migration report written to text_and_picture_block_migration_report.csv")
end


# Replace names by links to their profiles
def replace_names_by_links()

  st = Time.now

  selected_richtext_elements = [
    'intro',
    #'text_block',
    'text_and_picture',
    'large_box',
    'xlarge_box',
    'box',
    'title_block',
    'subtitle_block',
    #'quote_block',  # ask if we want this
  ]

  selected_content_names = [
    'pre_headline',
    'lead_text',
    'text'
  ]

  selected_ids = Alchemy::Content.where(element: Alchemy::Element.where(name: selected_richtext_elements), name: selected_content_names).pluck(:essence_id)

  selected_essences = Alchemy::EssenceRichtext.where(id: selected_ids)
  total_essences = selected_essences.length

  # NOTE: hard-coded CSV file name
  replacement_data = CSV.read('portal-tasks/lib/rt.csv', col_sep: ',', headers: true, encoding: 'UTF-16')


  base_folder = 'portal-tasks-reports'
  FileUtils.mkdir_p(base_folder) unless Dir.exist?(base_folder)

  st_loop = Time.now
  CSV.open("#{base_folder}/name-links-report.csv", "wb") do |csv|
    csv << ["id", "page_id", "page_urlname", "old_body", "new_body", "strings_changed", "status", "error_message", "error_trace"]

    count = 1

    selected_essences.each do |essence|

      changed = false
      strings_changed_list = []

      subreport = {
        id: essence.id,
        page_id: essence.page.id,
        page_urlname: essence.page.urlname,

        old_body: essence&.body,
        new_body: '',
        strings_changed: '',

        status: 'not started',
        error_message: '',
        error_trace: '',
      }

      begin
        ActiveRecord::Base.transaction do
          replacement_data.each do |row|

            old_body = essence&.body.present? ? essence.body : ""
            new_body = old_body.gsub(row['string'], row['target'])

            if old_body != new_body
              essence.update!(body: new_body)
              strings_changed_list << "{{ #{row['string']} }}"
              changed = true
            end

          end
        end

      rescue => e
        Rails.logger.error("Error while replacing names by links: #{e.message}")
        subreport[:status] = 'error'
        subreport[:error_message] = "#{e.class} :: #{e.message}"
        subreport[:error_trace] = e.backtrace.join(" ::: ")

      end

      if changed
        subreport[:status] = 'success'
        subreport[:new_body] = essence&.body
      else
        subreport[:status] = 'no change'
      end

      subreport[:strings_changed] = strings_changed_list.join(" ::: ")

      csv << [subreport[:id], subreport[:page_id], subreport[:page_urlname], subreport[:old_body], subreport[:new_body], subreport[:strings_changed], subreport[:status], subreport[:error_message], subreport[:error_trace]]

      Rails.logger.info("Processed #{count} of #{total_essences} essences")
      count += 1
    end


  end

  et = Time.now
  Rails.logger.info("Time elapsed: #{et - st}")
  Rails.logger.info("Time elapsed (loop): #{et - st_loop}")
end
