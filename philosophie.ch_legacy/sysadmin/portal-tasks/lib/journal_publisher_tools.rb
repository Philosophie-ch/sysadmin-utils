require 'cgi'
require 'json'


def get_entity_link(entity_key, entity_name)
  if entity_key.blank? || entity_name.blank?
    return ""
  else
    return "https://www.philosophie.ch/#{entity_name}/#{entity_key}"
  end
end


def get_entity_presentation_page(entity, entity_name)
  urlname = entity&.presentation_page&.urlname.to_s.strip || ''
  language_code = entity&.presentation_page&.language_code.to_s.strip || ''

  if urlname.blank? || language_code.blank?
    return nil
  end

  Alchemy::Page.find_by(urlname: urlname, language_code: language_code)
end


# ISSNs are not stored in the portal database. They live on the journal in Alexandria
# (issn_print / issn_electronic), so the portal tasks can only READ them.
# Returns [{ issn_print:, issn_electronic: }, ''] or [nil, reason]. nil means "could not be read": the caller
# keeps what the sheet has instead of blanking it. After Alexandria is found unreachable it is not asked again
# during the same run.
ISSN_LOOKUP_STATE = { down: nil }

def fetch_journal_issns(journal_key)
  return [nil, 'no journal key to look up'] if journal_key.blank?
  return [nil, "not refreshed, #{ISSN_LOOKUP_STATE[:down]}"] if ISSN_LOOKUP_STATE[:down]

  response = AlexandriaClient.connection.get("/api/v1/journals/by-key/#{CGI.escape(journal_key)}") do |req|
    req.headers['Authorization'] = "Bearer #{AlexandriaClient::API_KEY}"
  end

  return [nil, "journal '#{journal_key}' not found in Alexandria"] if response.status == 404
  return [nil, "Alexandria answered #{response.status}"] unless response.success?

  journal = JSON.parse(response.body)
  [{ issn_print: journal['issn_print'].to_s.strip, issn_electronic: journal['issn_electronic'].to_s.strip }, '']
rescue Faraday::ConnectionFailed, Faraday::TimeoutError => e
  ISSN_LOOKUP_STATE[:down] = "Alexandria unreachable (#{e.class})"
  [nil, "not refreshed, #{ISSN_LOOKUP_STATE[:down]}"]
rescue JSON::ParserError
  [nil, 'Alexandria sent an unreadable answer']
end
