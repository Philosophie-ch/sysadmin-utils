# Portal Tasks Context & Architecture

## Portal Codebase Location

The full target code of the portal is located at: `~/philosophie-ch/portal/legacy`

## Overview

The Portal Tasks system is a collection of Ruby scripts designed to manage and synchronize content for the Philosophie.ch portal through CSV-based batch processing. These scripts integrate deeply with Rails/Alchemy CMS to handle bulk operations on pages, profiles, publications, journals, publishers, events, notes, thematic tags, translation groups, site sections and side column blocks.

## Design Rules

The scripts are deliberately simple. The full rules are in `.claude/CLAUDE.md`; in short:
- Admins look at the report columns (`status`, `changes_made`, `error_message`, `error_trace`, `warning_messages`) only when a row failed. Logs and stdout are never seen.
- A script writes what the CSV says and validates only what the model or database would reject. Failures go in the row.
- Read-only columns (computed, or stored elsewhere) are silently ignored on UPDATE and POST. The report returns a fresh GET value.
- The Google Sheet is the authority for column names and order. `cols.rb` compares the sheet with the scripts.

## Directory Structure

```
portal-tasks/
├── pages.rb                    # Page content processing (CSV-driven)
├── profiles.rb                 # User profile management (CSV-driven)
├── publications.rb             # Publication records processing (CSV-driven)
├── journals.rb                 # Journal management (CSV-driven)
├── publishers.rb               # Publisher information processing (CSV-driven)
├── topics.rb                # Thematic tag/topic management (CSV-driven)
├── events.rb                   # Event data processing (CSV-driven)
├── notes.rb                    # Note management (CSV-driven)
├── translation_groups.rb       # Page translation groups (CSV-driven)
├── site_sections.rb            # Site sections and their translations (CSV-driven)
├── side_column_blocks.rb       # Side column blocks (CSV-driven)
├── news.rb                     # All IDs per entity (report)
├── deletions.rb                # IDs/keys from the sheets that no longer exist (report)
├── cols.rb                     # Sheet headers compared with the script columns (report)
├── links.rb                    # Link extraction and validation
├── export_pages.rb             # Bulk page export
├── export_page_topics.rb       # Read-only: the four topic columns of a pages sheet, in its row order
├── export_profiles.rb          # Bulk profile export
├── export_side_column_blocks.rb  # Bulk side column block export
├── swap_webp_asset_urls.rb     # Page images: non-webp URL to .webp when it exists
├── swap_webp_profile_picture_urls.rb        # Same for profile pictures
├── swap_webp_publication_cover_pictures.rb  # Same for publication covers
├── bulk_image_migration.rb     # Scan/migrate images to the asset server
├── bulk_media_migration.rb     # Scan/migrate audio/video/pdf to the asset server
├── lib/
│   ├── utils.rb                # Core shared utilities
│   ├── export_utils.rb         # Export-specific utilities (ID parsing, validation)
│   ├── page_tools.rb           # Page-specific utilities, PAGE_REPORT_COLUMNS
│   ├── profile_tools.rb        # Profile-specific utilities
│   ├── publication_tools.rb    # Publication-specific utilities, PUBLICATION_REPORT_COLUMNS
│   ├── note_tools.rb           # Note-specific utilities
│   ├── journal_publisher_tools.rb
│   ├── topics_tools.rb
│   ├── link_tools.rb           # Link extraction/validation
│   ├── ah-page-tools.rb        # Advanced page manipulation
│   └── *.csv                   # Data files
├── cols.csv                    # Export of the _cols tab (input of cols.rb)
└── portal-tasks-reports/       # Generated reports (created at runtime)
```

## Core Concepts

### 1. CSV-Driven Workflow

All main task scripts follow a CSV-driven pattern:
1. **Input**: CSV file with entity data and action requests
2. **Processing**: Validate, create, update, or delete entities based on CSV instructions
3. **Output**: Generate detailed CSV report with results, errors, and warnings

**CSV Encoding**: UTF-16 for most scripts. `topics.rb` and `events.rb` read UTF-8. `pages.rb`, `translation_groups.rb`, `site_sections.rb` and `side_column_blocks.rb` detect UTF-16 or UTF-8 themselves.

**Input file and arguments**: the CRUD scripts read a fixed file, `portal-tasks/<name>.csv` (for example `portal-tasks/pages.csv`). The only argument is the log level.

### 2. Request Types

Each CSV row includes a `_request` field that determines the action:

| Request Type | Description |
|--------------|-------------|
| **POST** | Create new entity |
| **UPDATE** | Update existing entity |
| **GET** | Retrieve entity information (read-only) |
| **DELETE** | Remove entity |
| **AD HOC** | Script-specific custom actions |

### 3. CSV Field Conventions

Fields follow naming conventions to indicate purpose:

| Prefix | Purpose | Example |
|--------|---------|---------|
| `_incoming` | Data from external source (e.g., PURE) | `_incoming_bibkey` |
| `_sort` | Sorting/ordering information | `_sort_order` |
| `_request` | Action type (POST/UPDATE/GET/DELETE) | `_request` |
| `_todo` | Manual task tracking notes | `_todo` |
| `_comments_on_*` | Internal documentation | `_comments_on_metadata` |
| (no prefix) | Direct model attributes | `title`, `name`, `slug` |

### 4. Script Structure Pattern

All CSV-based scripts follow this structure:

```ruby
require 'csv'
require_relative 'lib/utils'
require_relative 'lib/[entity]_tools'

# Constants
MODEL = [RailsModelClass]      # e.g., Publication, Alchemy::Page
KEY = :[entity_key]             # Unique identifier field
ENTITY_NAME = '[entity_name]'  # For reporting

def main(csv_file, log_level = 'info')
  # 1. SETUP
  #    - Configure Rails/ActiveRecord loggers
  #    - Parse log level (debug, info, warn, error)

  # 2. LOAD CSV DATA
  #    - Read CSV with UTF-16 encoding
  #    - Parse headers

  # 3. PROCESS EACH ROW
  #    - Extract and validate fields
  #    - Execute action based on _request type
  #    - Build subreport with status/errors

  # 4. GENERATE REPORT
  #    - Create CSV in portal-tasks-reports/
  #    - Include all input + processing results
end

main(ARGV[0], ARGV[1])
```

## Task Scripts Inventory

### CSV-Based Processing Scripts

#### pages.rb
**Purpose**: Manage page content, metadata, elements, and assets

**Key Features**:
- Tag system: Converts between array format and individual columns (page_type, media, content_type, language, institution, canton, project, public, references, footnotes)
- Asset management: Images, videos, PDFs, audio with URL validation
- Element manipulation: Create/update/position Alchemy page elements
- Intro element handling: Special element type with custom logic
- Publishing workflow integration

**CSV**: `pages.csv` (~240KB)

#### profiles.rb
**Purpose**: Manage user profiles and their metadata

**Key Features**:
- User account creation/updates
- Bibliography data management
- Profile link generation and migration
- Newsletter and institutional affiliation tracking
- Password and email generation
- `spps_access`: raw key from `Profile::SPPS_ACCESS_TYPES` (`no_access`, `access_requested`, `access_granted`). A blank cell on POST/UPDATE leaves the value unchanged; any other value not in the list is a row error. The report always returns the real stored value. Column sits after `type_of_studies`; also in `export_profiles.rb` and `swap_webp_profile_picture_urls.rb`.

**CSV**: `profiles.csv` (~22KB)
**Encoding**: UTF-16

#### publications.rb
**Purpose**: Process publication records with full metadata

**Key Features**:
- Author relationship management via `publication_authors` join table
- Open access and publication type fields
- URL prefix handling for flexible entity URLs
- Metadata JSON support for structured data
- DOI and citation handling
- External link validation

**CSV**: `publications.csv` (~7.5GB - largest dataset)
**Model**: `Publication`

#### journals.rb
**Purpose**: Manage journal records

**CSV**: `journals.csv` (~21KB)
**Model**: `Journal`

**ISSNs**: `issn_print` and `issn_electronic` are read-only. They are stored in Alexandria, not in the portal database. GET reads them from Alexandria (`GET /api/v1/journals/by-key/{key}`), UPDATE and POST ignore them. If Alexandria cannot be read, the sheet's cells are kept and GET adds a warning.

#### publishers.rb
**Purpose**: Process publisher information

**CSV**: `publishers.csv` (~2.8KB)
**Model**: `Publisher`

#### topics.rb
**Purpose**: Manage topics

**CSV**: `topics.csv`
**Model**: `Topic`
**Encoding**: UTF-8

**Key Features**:
- A topic is translated (`translated` TRUE: `translation_group` and the four `name_de`, `name_fr`, `name_it`, `name_en`, no `name`, no page) or untranslated (`name`, optional page from `page_language_code` + `page_urlname`, no names per language, no group). UPDATE writes the row; the model rejects a wrong combination and the reason is in the row. `topic_key` is the lowercase slug (the Pages sheet refers to topics by key).
- A translated UPDATE with page cells puts those pages in the translation group, which must exist.
- DELETE removes a topic that is on no page, and refuses one that is on pages. PURGE (maintainers only) removes a topic from all its pages, from the saved filters of the users and deletes it. PURGE DRY RUN runs the same and rolls it back, and reports how many pages and saved filters would be affected.
- The one-off merge of language variants into one topic (rows tied by `conceptual_group`) is done and was removed from the script, together with the `conceptual_group` and `language_code` columns of the sheet.
- Read-only: `url`.
- Helpers in `lib/topics_tools.rb`.

#### events.rb
**Purpose**: Process event data

**CSV**: `events.csv`
**Model**: `Event`
**Encoding**: UTF-8

**Key Features**:
- `dates`: one cell of comma-separated ISO dates (`2026-11-05, 2026-11-06`). UPDATE replaces the whole set. `Event#date` is only a cache of the earliest date.
- `speakers`: one cell, `@profile-slug | affiliation; Plain Name | affiliation`. The order is the position. UPDATE replaces all speakers, a blank cell clears them.
- `link` is not written for page-anchored events (the portal computes it). Without an `id` the event is found by title, region and earliest date.
- Old events can have a title longer than the 88 characters the model allows today. An UPDATE that does not change the title still saves (the title validation is skipped for it). Changing a title to one that is too long is an error.

#### notes.rb
**Purpose**: Manage notes (standalone `Note` model, not Alchemy pages)

**CSV**: `notes.csv`
**Model**: `Note`

**Key Features**:
- `slug` is the key. Blank on POST means the portal generates it. A note is renamed by sending its `id` with a new slug.
- `author` is a profile slug. `published` is `PUBLISHED` or `UNPUBLISHED`. `content_languages` is a comma-separated list, UPDATE replaces it.
- Read-only: `link`, `created_at`, `last_updated_date`, `interest_count`, `comment_count`.
- Helpers in `lib/note_tools.rb`.

#### translation_groups.rb, site_sections.rb, side_column_blocks.rb
CSV-driven CRUD by `key` for `PageTranslationGroup` (UPDATE with a new key renames the group: the foreign keys do not cascade, so `rename_translation_group` in `lib/translation_group_tools.rb` creates the group with the new key, moves every reference found in the database to it and deletes the old one, in one transaction; the group gets a new id), `SiteSection` (with its translations; renaming a key also updates `breadcrumb_key` on pages, publications, journals and publishers) and `SideColumnBlock`.

### Report-Only Scripts

#### news.rb
**Purpose**: Generate comprehensive news/overview report from existing portal data

**Features**:
- Query multiple entity types (pages, users, events, topics, side column blocks, notes)
- Generate snapshot reports without modifications
- No CSV input required

#### deletions.rb
**Purpose**: Counterpart of `news.rb`. Reports which IDs or keys from the sheets no longer exist (everything is hard-deleted). Read-only.

**Input**: `portal-tasks/deletions.csv`, any subset of the columns `page_id`, `profile_id` (user ids, as in the profiles sheet), `event_id`, `topic_id`, `side_column_block_id`, `note_id`, `publication_id`, `journal_id`, `publisher_id`, `translation_group_key`, `site_section_key`.

**Output**: `deleted_pages`, `deleted_profiles`, `deleted_events`, `deleted_topics`, `deleted_side_column_blocks`, `deleted_notes`, `deleted_publications`, `deleted_journals`, `deleted_publishers`, `deleted_translation_groups`, `deleted_site_sections`, plus `profiles_without_profile` (users that exist without a profile), `invalid_values`, `warnings` and `summary`.

#### cols.rb
**Purpose**: Compare the headers of the sheet tabs with the columns the scripts write. Read-only, it never runs the other scripts (it reads their source).

**Input**: `portal-tasks/cols.csv`, the export of a `_cols` tab: row 1 holds the tab names, below each name `=TRANSPOSE('<tab>'!2:2)`. Optional argument: another path.

**Output**: report on stdout and `portal-tasks-reports/YYMMDD_cols_report.txt` / `.csv`. It checks each tab against its CRUD script and the `export_*.rb` / `swap_webp_*.rb` scripts of that tab, tabs that share scripts against each other, and reports missing columns, extra columns, empty headers, duplicate keys and order differences. Runs with plain `ruby` or as a normal task with `rails runner` (then it uses the app's language list). The tab to script mapping is at the top of the file.

#### links.rb
**Purpose**: Extract and validate all links from pages

**Features**:
- Extracts links from HTML essence types:
  - `EssenceRichtext` (body content)
  - `EssenceHtml` (raw HTML blocks)
  - `EssenceLink` (link elements)
- Validates URLs with redirect following
- Generates detailed link report with resolution status
- Checks multiple HTML attributes: href, src, action, cite, data, poster

**Output**: `portal-tasks-reports/[date]_links_report.csv`

## Library Components (lib/)

### utils.rb - Core Utilities
**Size**: ~4.3KB

**Key Functions**:
```ruby
generate_csv_report(report, models_affected)  # Create timestamped CSV reports
download_asset(base_dir, filename, asset_path, asset_type)
process_asset_urls(urls)                      # Normalize URLs for storage
unprocess_asset_urls(urls)                    # Denormalize for display
fetch_with_redirect(url, limit)               # HTTP requests with redirect support
check_asset_urls_resolve(urls)                # Validate URL resolution
get_page_by_urlname_and_language(...)         # Page lookup helper
```

### page_tools.rb
**Size**: ~44KB (largest library)

**Shared report layout**: `PAGE_REPORT_COLUMNS` is the ordered column list of the pages sheet (the `pages.rb` layout). `build_page_report_row`, `build_empty_page_row` and `build_error_page_row` build rows from it. `export_pages.rb` and `swap_webp_asset_urls.rb` both use them.

**Capabilities**:
- Tag conversion utilities (array ↔ individual columns)
- Asset block management for intro elements
- Image/video/PDF/audio block creation and updates
- Asset URL handling and validation
- Element mapping and positioning
- Complex page structure manipulation

### profile_tools.rb
**Size**: ~14KB

**Also**: `build_error_profile_data` (error row in the profiles layout, shared by `export_profiles.rb` and `swap_webp_profile_picture_urls.rb`).

**Functions**:
- Password and email generation for profiles
- Link updating when user credentials change
- Article assignment retrieval
- Profile metadata handling

### publication_tools.rb
**Size**: ~1.9KB

**Functions**:
```ruby
get_entity_link(entity_key, url_prefix)      # Generate URLs with flexible prefixes
parse_authors_list(authors_string)            # Parse comma-separated author slugs
process_publication_authors(pub, slugs)       # Update author relationships
get_pure_html_asset(entity, base_url)         # Extract pure HTML asset paths
get_pure_pdf_asset(entity, base_url)          # Extract pure PDF asset paths
```

**Shared report layout**: `PUBLICATION_REPORT_COLUMNS` is the ordered column list of the publications sheet (the `publications.rb` layout). `build_publication_report_row`, `blank_publication_report_row` and `build_error_publication_data` build rows from it (used by `swap_webp_publication_cover_pictures.rb`).

**Key Change**: Migrated from `root_level` (boolean) to `url_prefix` (string) for flexible URL generation:
- Empty prefix → `https://www.philosophie.ch/{entity_key}` (root-level)
- With prefix → `https://www.philosophie.ch/{prefix}/{entity_key}` (nested)

### link_tools.rb
**Size**: ~4.8KB

**Functions**:
- HTML tag parsing for multiple attributes
- URL extraction from different essence types
- Link resolution checking

### export_utils.rb
**Size**: ~6KB

**Key Functions**:
```ruby
setup_logging(log_level)                                    # Configure logging levels
generate_export_filename(entity_name)                       # Create timestamped export filenames
log_progress(current, total, entity_name)                   # Progress tracking for bulk operations
parse_ids_from_file(file_path)                              # Read IDs from text file (one per line)
parse_ids(ids_input)                                        # Parse comma-separated ID string
validate_and_fetch_ordered(model_class, ids)                # Fetch records with strict validation
parse_ids_from_csv(csv_file, id_column_name)                # Extract IDs from CSV column
read_input_csv_data(csv_file)                               # Load CSV into hash keyed by ID
get_preserved_columns(entity_type, input_headers)           # Determine columns to preserve (hybrid approach)
merge_with_input_csv(db_rows, input_csv_data, preserved_columns)  # Merge DB data with preserved CSV columns
```

**Merge Mode Support**:
- Hybrid column preservation strategy (all "_" prefix + known exceptions)
- UTF-8/UTF-16 encoding handling
- Order preservation from input CSV

### ah-page-tools.rb
**Size**: ~28KB

**Functions**:
- Text block to title block migration
- CSV backup utilities
- Complex page element transformations

### note_tools.rb

Parsing helpers for `notes.rb` (`parse_published_flag`, `parse_boolean_flag`, `parse_published_at`, `parse_content_languages`), `set_row_error`, and `note_to_row`, which builds the database-derived columns of a note for the report.

### journal_publisher_tools.rb

`get_entity_link`, `get_entity_presentation_page` and `fetch_journal_issns(journal_key)`, the read-only ISSN lookup in Alexandria used by `journals.rb`.

### topics_tools.rb

The supported groups and interest types, `row_fields`, `parse_translated_flag`, `topic_report_values` (the database columns of a row), `find_topic_page`, `put_page_in_translation_group`, `apply_topic_fields`, `topic_page_count` (existing pages that carry a topic) and `replace_topic_in_saved_filters`.

## Report Generation

### Output Location
All reports are generated in: `portal-tasks-reports/`

### Report Naming Convention
`[YYMMDD]_[entity_type]_tasks_report.csv`

**Examples**:
- `250123_pages_tasks_report.csv`
- `250123_publications_tasks_report.csv`
- `250123_links_report.csv`

### Report Contents

Each report includes:
- **All input CSV columns** (preserved for audit trail)
- **Processing results**:
  - `id`: Entity ID after creation/update
  - `status`: "success", "error", "skipped", etc.
  - `error_message`: Human-readable error description
  - `error_trace`: File location/function that failed
  - `warning_messages`: Non-fatal issues
  - `changes_made`: Description of modifications
- **Metadata**: Timestamps, entity keys, computed values

## Rails/Alchemy CMS Integration

### Models Used
- `Alchemy::Page` - Content pages
- `Alchemy::User` - User accounts and profiles
- `Alchemy::Element` - Page structural elements
- `Publication` - Publication records
- `Journal` - Journal information
- `Publisher` - Publisher data
- `Topic` - Thematic tags
- `Event` - Event records
- `Profile` - User profile metadata
- `PublicationAuthor` - Author-publication relationships

### Key Rails Features Used
- ActiveRecord for database operations
- Rails.logger for process tracking
- Transaction support for data integrity
- Model validations and callbacks
- Association management (has_many, belongs_to)

## Common Patterns

### Error Handling
```ruby
subreport = {
  # ... input data ...
  status: 'success',
  error_message: '',
  error_trace: '',
  warning_messages: ''
}

begin
  # Process entity
  entity.save!
rescue => e
  subreport[:status] = 'error'
  subreport[:error_message] = e.message
  subreport[:error_trace] = "#{__FILE__}:#{__LINE__}"
  Rails.logger.error("Error: #{e.message}")
end
```

### Logging Levels
Scripts support configurable logging via command-line argument:
```bash
ruby pages.rb pages.csv debug   # Verbose debugging
ruby pages.rb pages.csv info    # Normal operation (default)
ruby pages.rb pages.csv warn    # Warnings only
ruby pages.rb pages.csv error   # Errors only
```

### Validation Pattern
```ruby
# Validate required fields
if title.blank?
  subreport[:status] = 'error'
  subreport[:error_message] = "Title is required"
  next
end

# Validate URLs
unless valid_url?(external_link)
  subreport[:warning_messages] = "Invalid URL format"
end

# Validate entity existence
entity = MODEL.find_by(KEY => entity_key)
if entity.nil? && request == 'UPDATE'
  subreport[:status] = 'error'
  subreport[:error_message] = "Entity not found for UPDATE"
  next
end
```

## Usage Examples

The CRUD scripts run as `rails runner` tasks inside the portal container (push with `push-tasks.sh`, pull the reports with `pull-reports.sh`). They read `portal-tasks/<name>.csv`; the only argument is the log level.

### Basic Processing
```bash
bundle exec rails runner portal-tasks/pages.rb info
bundle exec rails runner portal-tasks/publications.rb info
bundle exec rails runner portal-tasks/links.rb info
```

### With Debugging
```bash
bundle exec rails runner portal-tasks/pages.rb debug     # verbose
bundle exec rails runner portal-tasks/publications.rb error   # errors only
```

## Best Practices

1. **Always backup**: CSV reports serve as backup/audit trail
2. **Test with GET first**: Use GET requests to verify data before UPDATE/POST
3. **Check encoding**: see the encoding note under Core Concepts
4. **Monitor reports**: Review generated reports for errors and warnings
5. **Incremental processing**: Process small batches when dealing with large datasets
6. **Validate URLs**: Use link validation tools before processing assets
7. **Log appropriately**: Use debug level during development, info/warn in production

## Architecture Strengths

- **Modularity**: Each entity type has dedicated tools library
- **Auditability**: Comprehensive CSV reports with full error traces
- **Flexibility**: Request-type driven actions (POST/UPDATE/GET/DELETE)
- **Robustness**: Extensive error handling and validation
- **Maintainability**: Consistent patterns across all scripts
- **Scalability**: Handles datasets from KB to GB range

## Architecture Considerations

- **Large datasets**: publications.csv is 7.5GB - may require memory optimization
- **Encoding complexity**: Mixed UTF-8/UTF-16 requires careful handling
- **Rails dependency**: Scripts must run in Rails environment
- **CSV limitations**: Complex relationships may be challenging in flat CSV format
- **URL validation**: Network-dependent operations may slow processing

## Export Scripts (Bulk GET Operations)

### Overview

The `export_*.rb` scripts provide high-performance bulk data extraction without requiring CSV input files. They are optimized for "DB dump" style operations.

### Available Scripts

#### `export_pages.rb`
Bulk export of all pages or specific page IDs with optimized database queries.

#### `export_profiles.rb`
Bulk export of all user profiles or specific user IDs with optimized database queries.

#### `export_side_column_blocks.rb`
Bulk export of side column blocks.

#### `swap_webp_*.rb`
`swap_webp_asset_urls.rb` (page images), `swap_webp_profile_picture_urls.rb` and `swap_webp_publication_cover_pictures.rb` take a CSV with an `id` column (merge mode). For every record whose image URL is a `.jpg`, `.jpeg`, `.png`, `.gif`, `.bmp` or `.tiff` they check the asset server for the same file as `.webp`. If it exists they switch the reference, if not the row gets `NO-WEBP`. The output is a re-export of the record in the same layout as the exports.

### Key Differences from CSV-Driven Scripts

| Feature | CSV-Driven (pages.rb) | Export Scripts (export_pages.rb) | Export + Merge Mode |
|---------|----------------------|----------------------------------|---------------------|
| Input | CSV file required | Optional: IDs or nothing | CSV file (Google Sheets) |
| Operations | GET, POST, UPDATE, DELETE | GET only | GET + preserve metadata |
| Performance | Slower (row-by-row iteration) | 15-30x faster (bulk queries) | 15-30x faster (bulk queries) |
| Use case | Selective CRUD operations | Bulk data extraction | Google Sheets round-trip |
| Order control | CSV row order | ID list order or DB order | Input CSV row order |
| Validation | Per-row errors continue | All IDs must exist (fail-fast) | All IDs must exist (fail-fast) |
| Metadata preservation | N/A | N/A | Preserves "_" columns + exceptions |
| Output filename | Standard timestamped | Standard timestamped | {input}_updated.csv |

### Usage

**Export all entities:**
```bash
ruby portal-tasks/export_pages.rb
ruby portal-tasks/export_profiles.rb
```

**Export specific IDs from file:**
```bash
# Create file with one ID per line
echo -e "123\n456\n789" > ids.txt
ruby portal-tasks/export_pages.rb ids.txt
```

**Export specific IDs inline:**
```bash
ruby portal-tasks/export_pages.rb '123,456,789'
```

**With Rails runner:**
```bash
bundle exec rails runner portal-tasks/export_pages.rb ids.txt debug
```

**Merge mode (Google Sheets workflow):**
```bash
# Download CSV from Google Sheets: team_profiles.csv
ruby portal-tasks/export_profiles.rb -m team_profiles.csv

# Output: team_profiles_updated.csv
# Mass paste back into Google Sheets
```

### Merge Mode

Merge mode solves the problem of working with Google Sheets CSVs by preserving manual metadata while fetching fresh database data.

**Workflow:**
1. Download Google Sheets as CSV (e.g., `team_profiles.csv`)
2. Run export in merge mode: `ruby export_profiles.rb -m team_profiles.csv`
3. Script extracts IDs from `id` column
4. Fetches fresh DB data for those IDs
5. Preserves manual/metadata columns from input CSV
6. Outputs merged CSV: `team_profiles_updated.csv`
7. Mass paste updated CSV back to Google Sheets

**Preserved Columns:**

The merge mode uses a hybrid approach to determine which columns to preserve:
- All columns starting with "_" (manual metadata fields)
- Plus known exceptions that don't start with "_"

**Pages preserved columns:**
- All "_" columns (e.g., `_incoming`, `_sort`, `_request`, `_further_refs`, `_depends_on`, etc.)
- `embedded_html_base_name`

**Profiles preserved columns:**
- All "_" columns (e.g., `_sort`, `_correspondence`, `_todo_person`, `_request`, etc.)
- `password`, `biblio_keys`, `biblio_keys_further_references`, `biblio_dependencies_keys`, `mentioned_on`

**Example:**
```bash
# Profiles merge mode
ruby portal-tasks/export_profiles.rb -m team_profiles.csv
ruby portal-tasks/export_profiles.rb -m team_profiles.csv debug

# Pages merge mode
ruby portal-tasks/export_pages.rb -m articles.csv
ruby portal-tasks/export_pages.rb -m articles.csv debug

# With Rails runner
bundle exec rails runner portal-tasks/export_profiles.rb -m team_profiles.csv
```

**One output row per input row**: in merge mode the output has exactly as many rows as the input CSV, in the same order, so it can be pasted back over the sheet. A row whose record cannot be exported (the ID no longer exists, a user has no profile, the export raised an error) or that has no valid `id` (blank or not a number) is returned exactly as it was in the input CSV. Only `status` and `error_message` (and `error_trace`) say what happened. A repeated ID keeps the manual columns of its own input row. This applies to `export_profiles.rb`, `export_pages.rb` and `export_side_column_blocks.rb` (`ExportUtils.read_input_rows` and `ExportUtils.merge_with_input_rows`). The `swap_webp_*.rb` scripts still use the older ID-keyed merge.

**Benefits:**
- Eliminates manual column-by-column copy/paste
- Preserves all manual metadata and TODOs
- Ensures fresh DB data in all other columns
- Same row order as input (no reordering needed)
- Single mass-paste operation back to Google Sheets

### Performance Optimizations

1. **Eager loading** with `includes()` - Preloads all associations in bulk
2. **Batch processing** with `find_each()` - Memory-efficient iteration (100 records/batch)
3. **Single bulk query** for selective exports - Fetches all specified IDs at once
4. **Order preservation** - Results match input ID order exactly
5. **Strict validation** - Fails immediately if any ID is missing

### Performance Benchmarks

**Pages (1000 entities):**
- CSV-driven: ~15-30 minutes
- Export script: ~30-60 seconds
- **Speedup: 15-30x**

**Profiles (1000 entities):**
- CSV-driven: ~10-20 minutes
- Export script: ~20-40 seconds
- **Speedup: 15-30x**

### Error Handling

**Intro element missing (pages only):**
- Pages that should have intros (`article`, `event`, `info`, `note`, etc.): Status = `partial success`, warnings logged
- Pages that shouldn't have intros (`index`, etc.): Status = `success`, no warnings

**Missing profiles:**
- Users without profiles are skipped with error in CSV

**All other errors:**
- Individual row errors logged but export continues
- Error details in `error_message` and `error_trace` columns

### Output

Same CSV structure as corresponding task scripts:
- `export_pages.rb` → Same columns as `pages.rb` GET operation
- `export_profiles.rb` → Same columns as `profiles.rb` GET operation
- `export_side_column_blocks.rb`, `swap_webp_*.rb` → Same columns as the CRUD script of their tab

The exports and swap scripts must keep the same layout as the sheet. `cols.rb` verifies it.

Reports saved to: `portal-tasks-reports/YYMMDD_[entity]_tasks_report.csv`

## Future Enhancements

Potential areas for improvement:
- Background job processing for large datasets
- Parallel processing support
- REST API integration for real-time updates
- Web UI for CSV management and report viewing
- Automated testing framework
- Migration to more structured data formats (JSON, XML)
- Additional export scripts (publications, journals, etc.)
- Filtering options for export scripts (e.g., --layout=article, --lang=de)
