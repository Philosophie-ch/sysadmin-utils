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
      .gsub(/class="[^"]*"/, "")
      .gsub("  ", " ")
      .gsub(/style=" "/, "")
      .gsub(/style=""/, "")
      .gsub("  ", " ")
end

all_articles = Alchemy::Page.where(page_layout: 'article')

report = []

all_articles.each do |article|

  article.elements.each do |element|

      case element.name

      when 'intro', 'text_block', 'text_and_picture'

        richtext_contents = element.contents.where(name: ['pre_headline', 'lead_text', 'text'])


        richtext_contents.each do |content|
          essence = content.essence

          essence_report = {
            article_id: article.id,
            article_slug: article.urlname,
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
            essence.body = cleaned_body
            essence.save!

            essence_report[:essence_new_body] = essence.body
            essence_report[:html_cleanup_status] = "success"

          rescue => e
            essence_report[:unexpected_error] = e.message
          ensure
            report << essence_report
          end
        end

      when 'aside_column'
        # This one has nested elements
        element.elements.each do |nested_element|
          nested_element.contents.each do |content|
            essence = content.essence

            essence_report = {
              article_id: article.id,
              article_slug: article.urlname,
              element_id: element.id,
              element_name: element.name,
              content_id: content.id,
              content_name: content.name,
              essence_id: essence.id,
              essence_type: essence.type,
              essence_old_body: essence.body,
              essence_new_body: "",
              html_cleanup_status: "",
              unexpected_error: "",
            }

            begin

              cleaned_body = clean_unused_html_tags(essence.body)
              essence.body = cleaned_body
              essence.save!

              essence_report[:essence_new_body] = essence.body
              essence_report[:html_cleanup_status] = "success"

            rescue => e
              essence_report[:unexpected_error] = e.message
            ensure
              report << essence_report
            end
          end
        end

      else
        report << {
          article_id: article.id,
          article_slug: article.urlname,
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
  end
end

# Write report to CSV
CSV.open("240808_html_cleanup_report.csv", "wb") do |csv|
  csv << report.first.keys
  report.each do |row|
    csv << row.values
  end
end
