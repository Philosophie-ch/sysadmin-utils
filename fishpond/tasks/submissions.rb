require_relative 'utils'


RELEVANT_REFEREE_SUBMISSION_STATUS = [
  "positive",
  "negative",
]

OUTPUT_DIR = "tasks-output"

def main(base_output_dir, log_level = 'info')

  case log_level.downcase
  when 'debug'
    Rails.logger.level = Logger::DEBUG
  when 'info'
    Rails.logger.level = Logger::INFO
  when 'warn'
    Rails.logger.level = Logger::WARN
  when 'error'
    Rails.logger.level = Logger::ERROR
  else
    Rails.logger.level = Logger::INFO
  end

  FileUtils.mkdir_p(base_output_dir) unless Dir.exist?(base_output_dir)

  report = []
  processed = 0

  #submissions = Submission.all[0..10]  # to test
  #submissions = Submission.all
  submissions = Submission.where(id: [298, 100]).all
  total_submisions = submissions.length
  Rails.logger.info("Processing #{total_submisions} submissions...")

  submissions.each do |submission|
    processed += 1
    Rails.logger.info("Processing submission #{processed} of #{total_submisions}...")

    subreport = {
      _process: "not started",
      _error_message: "",
      _error_trace: "",

      id: "",
      fishpond_id: "",
      received: "",
      date_received: "",
      year_received: "",

      status: "",
      decision_raw: "",
      decision_status: "",
      decision_communicated: "",

      date_decided: "",
      name: "",
      email: "",
      country: "",
      sex: "",
      title: "",
      latest_pdf_file: "",

      # We'll have more columns, four per external_referee
    }

    begin

      # IDs
      id = submission.dialectica_id.to_s.strip
      fishpond_id = submission.id.to_s.strip

      # PDF
      unless id.blank?
        download_res = download_submission_pdf(submission, base_output_dir)
        if download_res[:status] != "success"
          subreport[:id] = id
          subreport[:fishpond_id] = fishpond_id
          subreport[:_process] = "download pdf failed"
          subreport[:_error_message] = download_res[:error_message]
          subreport[:_error_trace] = download_res[:error_trace]
          next
        end

      end

      # Basic attributes
      received = submission.appearance_date.to_s.strip
      year_received = submission.appearance_date.strftime("%Y")

      sorted_histories = submission.histories.order(created_at: :desc)
      latest_history = sorted_histories.first
      date_decided = latest_history&.created_at&.strftime("%Y-%m-%d").to_s.strip
      decision_raw = latest_history&.content&.to_s.strip

      first_author = [submission.firstname.to_s.strip, submission.lastname.to_s.strip].reject(&:blank?).join(" ")
      if first_author.blank?
        first_author = "N/D"
      end
      name = [first_author, submission.other_authors.to_s.strip].reject(&:blank?).join(" and ").strip

      email = submission.email.to_s.strip
      country = ISO3166::Country[submission.country]&.name.to_s.strip
      title = submission.title.to_s.strip

      subreport.merge!({
        id: id,
        fishpond_id: fishpond_id,
        received: received,
        year_received: year_received,

        decision_raw: decision_raw,
        date_decided: date_decided,
        name: name,
        email: email,
        country: country,
        title: title,
        latest_pdf_file: "#{id}.pdf",
      })


      # External referees
      er_submissions = submission.external_referee_submissions.where(status: RELEVANT_REFEREE_SUBMISSION_STATUS).order(created_at: :desc)

      er_submissions.each_with_index do |er_submission, index|
        er = er_submission.external_referee
        er_name = [er&.lastname.to_s.strip, er&.firstname.to_s.strip].reject(&:blank?).join(", ").to_s.strip
        er_email = er_submission.external_referee&.email.to_s.strip
        ers_sent = er_submission.created_at&.strftime("%Y-%m-%d")&.to_s.strip
        ers_status = er_submission.status.to_s.strip
        ers_answer = er_submission.date_of_answer.to_s.strip

        subreport.merge!({
          "referee_#{index + 1}_name" => er_name,
          "referee_#{index + 1}_email" => er_email,
          "referee_#{index + 1}_sent" => ers_sent,
          "referee_#{index + 1}_back" => ers_answer,
          "referee_#{index + 1}_status" => ers_status,
        })
      end

      subreport[:_process] = "success"
      Rails.logger.info("Processed submission #{processed} of #{total_submisions}, with title '#{title}' and id '#{id}': Success!")

    rescue => e
      error_message = "main ::: main ::: #{e.class} ::: #{e.message}"
      error_trace = e.backtrace.join(" ::: ")
      subreport[:_process] = "unhandled exception"
      subreport[:_error_message] = error_message
      subreport[:_error_trace] = error_trace

      Rails.logger.error(error_message)

    ensure
      report << subreport
      Rails.logger.info("Processed submission #{processed} of #{total_submisions}")
    end

  end

  # REPORT

  # Find the subreport with the most keys
  max_keys = report.map { |r| r.keys.length }.max
  # Use those keys as headers
  headers = report.find { |r| r.keys.length == max_keys }.keys

  generate_csv_report(headers, report, base_output_dir, "submissions")

end


if ARGV[0].blank?
  log_level = ""

else
  log_level = ARGV[0]
end

main(OUTPUT_DIR, log_level)
