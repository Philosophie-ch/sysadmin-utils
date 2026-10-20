require 'csv'

require_relative 'lib/utils'
require_relative 'lib/page_tools'
require_relative 'lib/export_utils'


# Read-only. The topics of the pages of a pages sheet export, one row per input row and in the same order, so that
# the four columns can be pasted over topics_discipline, topics_focus, topics_badge and topics_structural of the sheet.
# Nothing else of the sheet is touched. A row without a page id, or with an id that is not a page, gets blank cells.
#
#   rails runner portal-tasks/export_page_topics.rb [csv file] [log level]    (default file: portal-tasks/pages.csv)
def export_page_topics(csv_file, log_level = 'info')

  ExportUtils.setup_logging(log_level)

  rows = ExportUtils.read_input_rows(csv_file)
  ids = rows.map { |row| ExportUtils.parse_row_id(row['id']) }
  pages = Alchemy::Page.where(id: ids.compact.uniq).index_by(&:id)

  report = rows.each_with_index.map do |row, index|
    id = ids[index]
    topics = { discipline: '', focus: '', badge: '', structural: '' }
    error = ''

    if id.nil?
      error = ''
    elsif pages[id].nil?
      error = "Page ID #{id} not found in database"
    else
      begin
        topics = get_topics(pages[id])
      rescue => e
        error = "#{e.class} :: #{e.message}"
      end
    end

    {
      id: row['id'].to_s,
      topics_discipline: topics[:discipline],
      topics_focus: topics[:focus],
      topics_badge: topics[:badge],
      topics_structural: topics[:structural],
      error: error,
    }
  end

  generate_csv_report(report, "pages_topics")
end


csv_file = ARGV[0].present? && File.exist?(ARGV[0]) ? ARGV[0] : "portal-tasks/pages.csv"
log_level = ARGV.find { |arg| ['debug', 'info', 'warn', 'error'].include?(arg.to_s.downcase) } || 'info'

export_page_topics(csv_file, log_level)
