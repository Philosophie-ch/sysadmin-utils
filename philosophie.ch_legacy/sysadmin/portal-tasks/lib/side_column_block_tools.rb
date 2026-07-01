require 'erb'

FIELD_SEPARATOR = ' || '
LINK_SEPARATOR = '; '
LINK_KV_SEPARATOR = ': '

# ---------- content → CSV cell ----------

def serialize_content(block)
  case block.block_type
  when 'text'
    block.content['body'].to_s

  when 'picture'
    url = block.content['asset_url'].to_s
    url = url.sub('https://assets.philosophie.ch/', '')
    url.sub(/\.webp\z/i, '')

  when 'embed'
    parts = [block.content['html'].to_s]
    caption = block.content['caption'].to_s
    wrap = block.content['wrap']
    if caption.present? || wrap == true
      parts << caption
      parts << wrap.to_s if wrap == true
    end
    parts.join(FIELD_SEPARATOR)

  when 'download_asset_button'
    parts = [block.content['asset_url'].to_s]
    label = block.content['button_label'].to_s
    parts << label if label.present?
    parts.join(FIELD_SEPARATOR)

  when 'links'
    title = block.content['title'].to_s
    links = block.content['links'] || []
    link_strs = links.map { |l| "#{l['title']}#{LINK_KV_SEPARATOR}#{l['url']}" }
    "#{title}#{FIELD_SEPARATOR}#{link_strs.join(LINK_SEPARATOR)}"

  else
    block.content.to_json
  end
end

# ---------- CSV cell → content hash ----------

def parse_content(block_type, raw)
  case block_type
  when 'text'
    { 'body' => raw.to_s }

  when 'picture'
    { 'asset_url' => raw.to_s.strip }

  when 'embed'
    parts = raw.to_s.split(FIELD_SEPARATOR, 3)
    result = { 'html' => parts[0].to_s }
    result['caption'] = parts[1].to_s if parts.length > 1
    if parts.length > 2
      result['wrap'] = parts[2].to_s.strip.downcase == 'true'
    end
    result

  when 'download_asset_button'
    parts = raw.to_s.split(FIELD_SEPARATOR, 2)
    result = { 'asset_url' => parts[0].to_s.strip }
    result['button_label'] = parts[1].to_s.strip if parts.length > 1 && parts[1].present?
    result

  when 'links'
    parts = raw.to_s.split(FIELD_SEPARATOR, 2)
    title = parts[0].to_s.strip
    links = []
    if parts.length > 1 && parts[1].present?
      parts[1].split(LINK_SEPARATOR).each do |entry|
        entry = entry.strip
        next if entry.blank?
        label, url = entry.split(LINK_KV_SEPARATOR, 2)
        next if label.blank? || url.blank?
        links << { 'title' => label.strip, 'url' => url.strip }
      end
    end
    { 'title' => title, 'links' => links }

  else
    raise "Unknown block_type '#{block_type}'"
  end
end

# ---------- admin link (GET-only) ----------

def get_block_admin_link(block)
  encoded_key = ERB::Util.url_encode(block.key)
  "https://www.philosophie.ch/admin/side_column_blocks?utf8=%E2%9C%93&q%5Bkey_or_block_type_cont%5D=#{encoded_key}"
end

# ---------- pages display (GET-only) ----------

def get_block_pages_display(block)
  block.alchemy_page_side_column_blocks.order(:position).map do |join|
    page = join.page
    "#{page.urlname} (pos. #{join.position + 1})"
  end.join(', ')
end
