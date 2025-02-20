require 'csv'

def clean_unused_html_tags(html)

  return "" if html.nil?

  html.gsub(/text-align:\s*justify;?/i, "")
      .gsub(/align\s*=\s*["']?justify["']?;?/i, "")
      .gsub(/font-size:[^;]*;/, "")
      .gsub(/font-family:[^;]*;/, "")
      .gsub(/line-height:[^;]*;/, "")
      .gsub(/color:[^;]*;/, "")
      .gsub(/margin-[^:]+:[^;]*;/, "")
      .gsub(/lang="[^"]*"/, "")
      .gsub("  ", " ")
      .gsub(/style=" "/, "")
      .gsub(/style=""/, "")
      .gsub("  ", " ")
end

all_pages = Alchemy::Page.all

report = []

all_pages.each do |page|

  page.elements.each do |element|

      case element.name

      when 'intro', 'text_block', 'text_and_picture', 'title_block', 'subtitle_block'

        richtext_contents = element.contents.where(name: ['pre_headline', 'lead_text', 'text'])


        richtext_contents.each do |content|
          essence = content.essence

          essence_report = {
            page_id: page.id,
            page_slug: page.urlname,
            element_id: element.id,
            element_name: element.name,
            content_id: content.id,
            content_name: content.name,
            essence_id: essence.id,
            essence_type: essence.class.name,
            essence_old_body: essence.body,
            essence_new_body: "",
            html_cleanup_status: "",
            unexpected_error: "",
          }

          begin

            cleaned_body = clean_unused_html_tags(essence.body)
            if cleaned_body != essence.body
              essence.body = cleaned_body
              essence.save!
              essence_report[:essence_new_body] = essence.body
              essence_report[:html_cleanup_status] = "success"
            else
              essence_report[:html_cleanup_status] = "skipped"
              essence_report[:unexpected_error] = "Cleanup produced no changes"
            end

            page.save!
            page.publish!

          rescue => e
            essence_report[:unexpected_error] = "#{e.class} - #{e.message} - #{e.backtrace.join(" ::: ")}"
          ensure
            report << essence_report
          end
        end

      else
        report << {
          page_id: page.id,
          page_slug: page.urlname,
          element_id: element.id,
          element_name: element.name,
          content_id: "",
          content_name: "",
          essence_id: "",
          essence_type: "",
          essence_old_body: "",
          essence_new_body: "",
          html_cleanup_status: "skipped",
          unexpected_error: "",
        }

    end


    aside_column = page.fixed_elements.find_by(name: "aside_column")
    if aside_column.present?

      # This one has nested elements
      aside_column_nested_elements = aside_column.nested_elements

      ActiveRecord::Base.transaction do
        aside_column_nested_elements.each do |nested_element|

          if ["text_block", "text_and_picture", "title_block", "subtitle_block"].include?(nested_element.name)

            richtext_contents = nested_element.contents.where(name: ['pre_headline', 'lead_text', 'text'])

            richtext_contents.each do |content|
              essence = content.essence

              essence_report = {
                page_id: page.id,
                page_slug: page.urlname,
                element_id: element.id,
                element_name: element.name,
                content_id: content.id,
                content_name: content.name,
                essence_id: essence.id,
                essence_type: essence.class.name,
                essence_old_body: essence.body,
                essence_new_body: "",
                html_cleanup_status: "",
                unexpected_error: "",
              }

              begin

                cleaned_body = clean_unused_html_tags(essence.body)
                if cleaned_body != essence.body
                  essence.body = cleaned_body
                  essence.save!
                  essence_report[:essence_new_body] = essence.body
                  essence_report[:html_cleanup_status] = "success"
                else
                  essence_report[:html_cleanup_status] = "skipped"
                  essence_report[:unexpected_error] = "Cleanup produced no changes"
                end

                  page.save!
                  page.publish!

              rescue => e
                essence_report[:unexpected_error] = "#{e.class} - #{e.message} - #{e.backtrace.join(" ::: ")}"
              ensure
                report << essence_report
              end
            end
          end
        end
      end
    end


  end
end


# Write report to CSV
base_folder = "portal-tasks-reports"
FileUtils.mkdir_p(base_folder) unless File.directory?(base_folder)

CSV.open("#{base_folder}/250213_html_cleanup_report.csv", "wb") do |csv|
  csv << report.first.keys
  report.each do |row|
    csv << row.values
  end
end
