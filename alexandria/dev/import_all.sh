#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [ ! -f "${SCRIPT_DIR}/.env" ]; then
  echo "=> No .env file found in ${SCRIPT_DIR}"
  echo "=> Copy .env.example to .env and fill in the values"
  exit 1
fi

set -o allexport
source "${SCRIPT_DIR}/.env"
set +o allexport

required_vars=( "ALEXANDRIA_API_URL" "ALEXANDRIA_API_KEY" "ALEXANDRIA_DATA_DIR" )
BIBLIO_CSV="${ALEXANDRIA_BIBLIO_CSV}"
var_err_msg=
for var in "${required_vars[@]}"; do
  if [ -z "${!var}" ]; then
    var_err_msg="${var_err_msg}=> Error: Missing required environment variable: $var\n"
  fi
done
if [ -n "$var_err_msg" ]; then
  echo -e "$var_err_msg"
  exit 1
fi

API="${ALEXANDRIA_API_URL}/api/v1"
KEY="${ALEXANDRIA_API_KEY}"
DIR="${ALEXANDRIA_DATA_DIR}"
OUT="${DIR}/reports/$(date +%Y%m%d_%H%M%S)_report"

mkdir -p "$OUT"

import() {
    local endpoint="$1" file="$2" label="$3" out_file="$4"
    echo "--- $label ---"
    curl -s -o "$out_file" -w "HTTP %{http_code}\n" \
        -X POST "${API}/${endpoint}" \
        -H "Authorization: Bearer $KEY" \
        -F "file=@$file"
}

summary() {
    python3 -c "
import json, sys
d = json.load(open(sys.argv[1]))
imp = d.get('imported', 0)
upd = d.get('updated', 0)
fail = d.get('failed', 0)
print(f'  imported={imp}, updated={upd}, failed={fail}')
" "$1"
}

echo "========================================="
echo "Step 0: Convert portal CSVs"
echo "========================================="
ALEXANDRIA_BIBLIO_CSV="${BIBLIO_CSV}" python3 "${SCRIPT_DIR}/convert.py"

echo ""
echo "========================================="
echo "Step 1: Import profiles as authors"
echo "========================================="
echo "--- Wiping dev DB ---"
curl -sS --fail-with-body -X POST "${API}/admin/wipe?confirm=true" \
    -H "Authorization: Bearer $KEY" | python3 -m json.tool
echo ""
import "admin/import/authors" "$DIR/authors_pr.csv" "Profiles (pr)" "$OUT/01_authors_pr.json"
summary "$OUT/01_authors_pr.json"

import "admin/import/authors" "$DIR/authors_bp.csv" "Biblio profiles (bp)" "$OUT/02_authors_bp.json"
summary "$OUT/02_authors_bp.json"

echo ""
echo "========================================="
echo "Step 1b: Import author name variants"
echo "========================================="
import "admin/import/author-name-variants" "$DIR/author_name_variants.csv" "Author name variants" "$OUT/01b_name_variants.json"
summary "$OUT/01b_name_variants.json"

echo ""
echo "========================================="
echo "Step 2: Import journals and publishers"
echo "========================================="
import "admin/import/journals" "$DIR/journals.csv" "Journals" "$OUT/04_journals.json"
summary "$OUT/04_journals.json"

import "admin/import/publishers" "$DIR/publishers.csv" "Publishers" "$OUT/05_publishers.json"
summary "$OUT/05_publishers.json"

echo ""
echo "========================================="
echo "Step 3: Import entities from biblio CSV"
echo "========================================="
# Institutions, schools, series, and keywords are derived solely from the biblio CSV
# (not maintained in portal data). We pre-import them from the corpus so their IDs
# stay stable across wipe+reimport cycles. import-entities-from-full-csv then skips
# existing entities and only auto-assigns IDs for genuinely new ones.
if [ -n "${ALEXANDRIA_CORPUS_PATH:-}" ] && [ -d "${ALEXANDRIA_CORPUS_PATH}/data" ]; then
    echo "--- Pre-importing entities from corpus (stable IDs) ---"
    import "admin/import/institutions" "${ALEXANDRIA_CORPUS_PATH}/data/institution/all.csv" "Institutions (corpus)" "$OUT/06a_institutions.json"
    summary "$OUT/06a_institutions.json"
    import "admin/import/schools" "${ALEXANDRIA_CORPUS_PATH}/data/school/all.csv" "Schools (corpus)" "$OUT/06b_schools.json"
    summary "$OUT/06b_schools.json"
    import "admin/import/series" "${ALEXANDRIA_CORPUS_PATH}/data/series/all.csv" "Series (corpus)" "$OUT/06c_series.json"
    summary "$OUT/06c_series.json"
    import "admin/import/keywords" "${ALEXANDRIA_CORPUS_PATH}/data/keyword/all.csv" "Keywords (corpus)" "$OUT/06d_keywords.json"
    summary "$OUT/06d_keywords.json"
else
    echo "  (No corpus data found — first run, entities will be auto-assigned IDs)"
fi
echo "--- Biblio entities (new only) ---"
import "admin/import-entities-from-full-csv" "$DIR/biblio-processed.csv" "Biblio entities" "$OUT/06_entities.json"
python3 -c "
import json
d = json.load(open('$OUT/06_entities.json'))
print(f'  new: institutions={d[\"created_institutions\"]}, schools={d[\"created_schools\"]}, series={d[\"created_series\"]}, keywords={d[\"created_keywords\"]}')
print(f'  errors={len(d[\"errors\"])}')
"

echo ""
echo "========================================="
echo "Step 4: Validate biblio CSV"
echo "========================================="
import "admin/validate-full-csv" "$DIR/biblio-processed.csv" "Validation" "$OUT/07_validate.json"
python3 -c "
import json
d = json.load(open('$OUT/07_validate.json'))
print(f'  total_rows={d[\"total_rows\"]}, valid_rows={d[\"valid_rows\"]}')
print(f'  parse_errors={len(d[\"errors\"])}')
print(f'  missing_authors={len(d[\"missing_authors\"])}, ambiguous_authors={len(d[\"ambiguous_authors\"])}')
print(f'  missing_journals={len(d[\"missing_journals\"])}, missing_publishers={len(d[\"missing_publishers\"])}')
print(f'  missing_institutions={len(d[\"missing_institutions\"])}, missing_schools={len(d[\"missing_schools\"])}')
print(f'  missing_series={len(d[\"missing_series\"])}, missing_crossrefs={len(d.get(\"missing_crossrefs\", []))}')
print(f'  duplicate_bibkeys={len(d.get(\"duplicate_bibkeys\", []))}')
"

echo ""
echo "========================================="
echo "Step 5: Import bibitems from full CSV"
echo "========================================="
import "admin/import-full-csv?delete_stale=true" "$DIR/biblio-processed.csv" "Bibitems" "$OUT/08_import_bibitems.json"
python3 -c "
import json
d = json.load(open('$OUT/08_import_bibitems.json'))
imp = d.get('imported', 0)
upd = d.get('updated', 0)
dlt = d.get('deleted', 0)
fail = d.get('failed', 0)
print(f'  imported={imp}, updated={upd}, deleted={dlt}, failed={fail}')
"

echo ""
echo "========================================="
echo "Step 6: LaTeX -> Unicode bulk conversion"
echo "========================================="
curl -s -o "$OUT/09_latex_conversion.json" -w "HTTP %{http_code}\n" \
    -X POST "${API}/admin/convert-latex-columns" \
    -H "Authorization: Bearer $KEY"
python3 -c "
import json
d = json.load(open('$OUT/09_latex_conversion.json'))
total = d.get('total_updated', 0)
errors = len(d.get('errors', []))
print(f'  total_updated={total}, errors={errors}')
"

echo ""
echo "========================================="
echo "Step 7: Generate error report"
echo "========================================="
ALEXANDRIA_DATA_DIR="${DIR}" ALEXANDRIA_DB_CONTAINER="${ALEXANDRIA_DB_CONTAINER:-}" \
    python3 "${SCRIPT_DIR}/generate_report.py" "$OUT"
echo "Done. Report files in $OUT/"

echo ""
echo "========================================="
echo "Cleanup: removing intermediate CSVs"
echo "========================================="
rm -f "$DIR/authors_pr.csv" "$DIR/authors_bp.csv" \
      "$DIR/journals.csv" "$DIR/publishers.csv" \
      "$DIR/biblio-processed.csv"
echo "Done."
