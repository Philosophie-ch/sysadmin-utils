#!/usr/bin/env python3
"""Generate error report files from validation and import results.

Cross-references every error back to concrete rows in the original source CSVs
so the team knows exactly what to fix and where.

Reads from environment:
  ALEXANDRIA_DATA_DIR     — directory containing the portal source CSVs
  ALEXANDRIA_DB_CONTAINER — docker container name for DB fuzzy-match queries
"""

import csv
import json
import os
import sys
from collections import defaultdict

SRC = os.environ.get("ALEXANDRIA_DATA_DIR", os.path.dirname(os.path.abspath(__file__)))
DB_CONTAINER = os.environ.get("ALEXANDRIA_DB_CONTAINER", "alexandria-db")
OUT = sys.argv[1] if len(sys.argv) > 1 else os.path.join(os.path.dirname(os.path.abspath(__file__)), "reports", "report")

BIBLIO_CSV = os.path.join(SRC, "biblio-v11-table.csv")
PROFILES_PR = os.path.join(SRC, "portal data - profiles.csv")
PROFILES_BP = os.path.join(SRC, "portal data - biblio profiles.csv")
JOURNALS_CSV = os.path.join(SRC, "portal data - journals.csv")
PUBLISHERS_CSV = os.path.join(SRC, "portal data - publishers.csv")

csv.field_size_limit(1_000_000)

import subprocess
import difflib


def db_query(sql):
    """Run a SQL query against the Alexandria DB and return rows."""
    result = subprocess.run(
        ["docker", "exec", DB_CONTAINER,
         "psql", "-U", "alexandria", "-d", "alexandria", "-t", "-A", "-c", sql],
        capture_output=True, text=True,
    )
    return [line for line in result.stdout.strip().split("\n") if line]


def load_db_names(table, name_col="name_latex"):
    """Load all name_latex values from a DB table."""
    rows = db_query(f"SELECT {name_col} FROM {table}")
    return set(rows)


def normalize_latex(s):
    """Normalize LaTeX escaping for comparison (collapse double backslashes)."""
    return (
        s.replace("\\\\", "\\")
        .replace("~", " ")
        .replace("’", "'")
        .replace("‘", "'")
        .replace("“", '"')
        .replace("”", '"')
        .lower()
    )


def describe_diff(a, b):
    """Describe the concrete difference between two strings."""
    diffs = []
    for i, (ca, cb) in enumerate(zip(a, b)):
        if ca != cb:
            diffs.append(f"position {i}: {repr(ca)} vs {repr(cb)}")
            if len(diffs) >= 3:
                break
    if len(a) != len(b) and len(diffs) < 3:
        diffs.append(f"different lengths: {len(a)} vs {len(b)}")
    return "; ".join(diffs) if diffs else "unknown difference"


def find_closest_match(name, db_names, cutoff=0.8):
    """Find the closest match in the DB for a missing name."""
    if name in db_names:
        return name

    name_lower = name.lower()
    for db_name in db_names:
        if db_name.lower() == name_lower:
            return db_name

    name_norm = normalize_latex(name)
    for db_name in db_names:
        if normalize_latex(db_name) == name_norm:
            return db_name

    norm_to_orig = {normalize_latex(n): n for n in db_names}
    matches = difflib.get_close_matches(name_norm, norm_to_orig.keys(), n=1, cutoff=cutoff)
    if matches:
        return norm_to_orig[matches[0]]

    return None


def load_json(name):
    with open(os.path.join(OUT, name)) as f:
        return json.load(f)


def write_report(filename, header, lines):
    path = os.path.join(OUT, filename)
    with open(path, "w", encoding="utf-8") as f:
        f.write(header + "\n")
        f.write("=" * min(len(header), 80) + "\n\n")
        for line in lines:
            f.write(line + "\n")
    print(f"  {filename}: {len(lines)} entries")


def read_source_csv(path):
    """Read a portal CSV (row 0=descriptions, row 1=headers, row 2+=data)."""
    rows = []
    with open(path, newline="", encoding="utf-8") as f:
        reader = csv.reader(f)
        next(reader)  # skip descriptions
        headers = next(reader)
        idx = {h.strip(): i for i, h in enumerate(headers)}
        for i, row in enumerate(reader, start=3):
            rows.append((i, row, idx))
    return idx, rows


# ─────────────────────────────────────────────────────────────────────────────
# Build indexes from biblio CSV
# ─────────────────────────────────────────────────────────────────────────────

print("Building indexes from biblio CSV...")
biblio_by_bibkey = defaultdict(list)
author_to_bibkeys = defaultdict(set)
journal_to_bibkeys = defaultdict(set)
publisher_to_bibkeys = defaultdict(set)
institution_to_bibkeys = defaultdict(set)
series_to_bibkeys = defaultdict(set)
crossref_to_bibkeys = defaultdict(set)
person_to_bibkeys = defaultdict(set)

with open(BIBLIO_CSV, newline="", encoding="utf-8") as f:
    reader = csv.reader(f)
    headers = next(reader)
    hi = {h.strip(): i for i, h in enumerate(headers)}

    for row_num, row in enumerate(reader, start=2):
        bk = row[hi["bibkey"]].strip() if hi["bibkey"] < len(row) else ""
        if not bk:
            continue
        biblio_by_bibkey[bk].append(row_num)

        for col in ["author", "editor", "_guesteditor"]:
            val = row[hi[col]].strip() if hi.get(col) is not None and hi[col] < len(row) else ""
            if val:
                for name in val.split(" and "):
                    name = name.strip()
                    if name:
                        author_to_bibkeys[name].add(bk)

        person = row[hi["_person"]].strip().rstrip(";") if hi.get("_person") is not None and hi["_person"] < len(row) else ""
        if person:
            person_to_bibkeys[person].add(bk)
            author_to_bibkeys[person].add(bk)

        for col, index in [
            ("journal", journal_to_bibkeys),
            ("publisher", publisher_to_bibkeys),
            ("institution", institution_to_bibkeys),
            ("series", series_to_bibkeys),
        ]:
            val = row[hi[col]].strip() if hi.get(col) is not None and hi[col] < len(row) else ""
            if val:
                index[val].add(bk)

        xref = row[hi["crossref"]].strip() if hi.get("crossref") is not None and hi["crossref"] < len(row) else ""
        if xref:
            crossref_to_bibkeys[xref].add(bk)


def bibkeys_sample(bibkeys, max_show=5):
    bks = sorted(bibkeys)
    if len(bks) <= max_show:
        return ", ".join(bks)
    return ", ".join(bks[:max_show]) + f", ... ({len(bks)} total)"


# ─────────────────────────────────────────────────────────────────────────────
# Load results
# ─────────────────────────────────────────────────────────────────────────────

val = load_json("07_validate.json")
ent = load_json("06_entities.json")

print("Generating reports...")

# ─── 1. Parse errors ────────────────────────────────────────────────────────
lines = []
for e in val["errors"]:
    bk = e["bibkey"]
    row_num = e.get("row")
    if row_num:
        row_str = f"biblio-v11-table.csv row {row_num}"
    else:
        rows = biblio_by_bibkey.get(bk, [])
        row_str = f"biblio-v11-table.csv row {rows[0]}" if rows else "row unknown"
    for field_err in e["errors"]:
        lines.append(
            f"{row_str} | bibkey: {bk} | field: {field_err['field']} | {field_err['error']}"
        )
write_report(
    "errors_parse.txt",
    "Parse errors — malformed field values in biblio-v11-table.csv\n"
    "Fix these values in the biblio spreadsheet.",
    lines,
)

# ─── 2. Missing authors ────────────────────────────────────────────────────
lines = []
for name in sorted(val["missing_authors"]):
    bks = author_to_bibkeys.get(name, set())
    if not bks:
        bks = person_to_bibkeys.get(name, set())
    if not bks:
        first_word = name.split(",")[0].split()[0].lower()
        if len(first_word) >= 4:
            for indexed_name, indexed_bks in author_to_bibkeys.items():
                if indexed_name.lower().startswith(first_word):
                    bks = bks | indexed_bks
    lines.append(f"{name}")
    if bks:
        lines.append(f"  Referenced by: {bibkeys_sample(bks)}")
    else:
        lines.append(f"  Referenced by: (could not trace back to specific bibkeys)")
    lines.append("")
write_report(
    "errors_missing_authors.txt",
    "Missing authors — referenced in biblio CSV but no matching profile found\n"
    "Action: add these to a profile CSV (biblio profiles or profiles), or fix the\n"
    "spelling in the biblio spreadsheet's author/editor/_person column.",
    lines,
)

# ─── 3. Ambiguous authors ──────────────────────────────────────────────────
def build_id_to_profile(path, source_label):
    result = {}
    with open(path, newline="", encoding="utf-8") as f:
        reader = csv.reader(f)
        next(reader)
        headers = next(reader)
        idx = {h.strip(): i for i, h in enumerate(headers)}
        for i, row in enumerate(reader, start=3):
            rid = row[idx["id"]].strip() if idx["id"] < len(row) else ""
            if rid:
                key = row[idx["_biblio_name"]].strip() if idx["_biblio_name"] < len(row) else ""
                bfn = row[idx["_biblio_full_name"]].strip() if idx["_biblio_full_name"] < len(row) else ""
                result[rid] = (source_label, i, key, bfn)
    return result

id_to_profile = {}
id_to_profile.update(build_id_to_profile(PROFILES_PR, "portal data - profiles.csv"))
id_to_profile.update(build_id_to_profile(PROFILES_BP, "portal data - biblio profiles.csv"))

lines = []
for a in val["ambiguous_authors"]:
    name = a["name"]
    ids = a["matching_ids"]
    bks = author_to_bibkeys.get(name, set())
    lines.append(f"{name}")
    lines.append(f"  Referenced by: {bibkeys_sample(bks)}")
    for mid in ids:
        info = id_to_profile.get(str(mid))
        if info:
            source, _, pkey, bfn = info
            lines.append(f"  ID {mid}: key={pkey}, name={repr(bfn[:60])}  ({source})")
        else:
            lines.append(f"  ID {mid}: (not found in profile CSVs)")
    lines.append(f"  → Deduplicate: keep one profile, delete or merge the other")
    lines.append("")
write_report(
    "errors_ambiguous_authors.txt",
    "Ambiguous authors — name matches multiple profiles\n"
    "For each matching profile, the source spreadsheet and row number are shown.",
    lines,
)

# ─── 4. Missing journals ───────────────────────────────────────────────────
print("  Loading DB names for fuzzy matching...")
db_journal_names = load_db_names("journals")
db_publisher_names = load_db_names("publishers")
db_series_names = load_db_names("series")

lines = []
for name in sorted(val["missing_journals"]):
    bks = journal_to_bibkeys.get(name, set())
    closest = find_closest_match(name, db_journal_names)
    lines.append(f"{name}")
    lines.append(f"  Referenced by: {bibkeys_sample(bks)}")
    if closest:
        diff = describe_diff(name, closest)
        lines.append(f"  In biblio-v11-table.csv (journal column):          {repr(name)}")
        lines.append(f"  In portal data - journals.csv (_biblio_full_name): {repr(closest)}")
        lines.append(f"  Difference: {diff}")
        lines.append(f"  → Fix: make these two values identical")
    else:
        lines.append(f"  No close match in journals spreadsheet — add this journal")
    lines.append("")
write_report(
    "errors_missing_journals.txt",
    "Missing journals — journal name in biblio CSV not found in DB\n"
    "When a close match is shown, the two spreadsheets use slightly different\n"
    "names for the same journal. Fix whichever has the typo.",
    lines,
)

# ─── 5. Missing publishers ─────────────────────────────────────────────────
lines = []
for name in sorted(val["missing_publishers"]):
    bks = publisher_to_bibkeys.get(name, set())
    closest = find_closest_match(name, db_publisher_names)
    lines.append(f"{name}")
    lines.append(f"  Referenced by: {bibkeys_sample(bks)}")
    if closest:
        diff = describe_diff(name, closest)
        lines.append(f"  In biblio-v11-table.csv (publisher column):         {repr(name)}")
        lines.append(f"  In portal data - publishers.csv (_biblio_full_name): {repr(closest)}")
        lines.append(f"  Difference: {diff}")
        lines.append(f"  → Fix: make these two values identical")
    else:
        lines.append(f"  No close match in publishers spreadsheet — add this publisher")
    lines.append("")
write_report(
    "errors_missing_publishers.txt",
    "Missing publishers — publisher name in biblio CSV not found in DB\n"
    "When a close match is shown, the two spreadsheets use slightly different\n"
    "names for the same publisher. Fix whichever has the typo.",
    lines,
)

# ─── 6. Missing institutions ───────────────────────────────────────────────
db_institution_names = load_db_names("institutions")
lines = []
for name in sorted(val["missing_institutions"]):
    bks = institution_to_bibkeys.get(name, set())
    closest = find_closest_match(name, db_institution_names)
    lines.append(f"{name}")
    lines.append(f"  Referenced by: {bibkeys_sample(bks)}")
    if closest:
        diff = describe_diff(name, closest)
        lines.append(f"  Spelling used by some rows:  {repr(name)}")
        lines.append(f"  Spelling used by other rows: {repr(closest)}")
        lines.append(f"  Difference: {diff}")
        lines.append(f"  → Fix: the biblio spreadsheet uses two spellings for the same institution. Pick one and fix all rows.")
    else:
        lines.append(f"  No close match — this institution was not created")
    lines.append("")
write_report(
    "errors_missing_institutions.txt",
    "Missing institutions — institution name in biblio CSV not found in DB\n"
    "Institutions are auto-created from the biblio CSV. If a close match is shown,\n"
    "the same institution is spelled differently across rows.",
    lines,
)

# ─── 7. Missing series ─────────────────────────────────────────────────────
lines = []
for name in sorted(val["missing_series"]):
    bks = series_to_bibkeys.get(name, set())
    closest = find_closest_match(name, db_series_names)
    lines.append(f"{name}")
    lines.append(f"  Referenced by: {bibkeys_sample(bks)}")
    if closest:
        diff = describe_diff(name, closest)
        lines.append(f"  Spelling used by some rows:  {repr(name)}")
        lines.append(f"  Spelling used by other rows: {repr(closest)}")
        lines.append(f"  Difference: {diff}")
        lines.append(f"  → Fix: the biblio spreadsheet uses two spellings for the same series. Pick one and fix all rows.")
    else:
        lines.append(f"  No close match in DB — this series was not created")
    lines.append("")
write_report(
    "errors_missing_series.txt",
    "Missing series — series name in biblio CSV doesn't match any series in DB\n"
    "These series were auto-created, but some biblio rows reference them with\n"
    "slightly different names. The closest DB match is shown for each.",
    lines,
)

# ─── 8. Missing crossrefs ──────────────────────────────────────────────────
lines = []
for bk in sorted(val.get("missing_crossrefs", [])):
    referencing = crossref_to_bibkeys.get(bk, set())
    lines.append(f"{bk}")
    lines.append(f"  Referenced by: {bibkeys_sample(referencing)}")
    lines.append("")
write_report(
    "errors_missing_crossrefs.txt",
    "Missing crossrefs — bibkeys in the 'crossref' column that don't exist as rows\n"
    "These are typically collection volumes or proceedings that individual articles\n"
    "reference but that aren't included in the biblio spreadsheet as standalone entries.\n"
    "Action: add the missing entries to the biblio spreadsheet, or remove the crossref.",
    lines,
)

# ─── 9. Skipped bibitems (import step) ─────────────────────────────────────

CONCEPT_NAMES = {"Indian", "Chinese", "African", "Buddhist", "Jewish", "Islamic",
                 "Arab", "Latin", "Ancient", "Medieval", "Western", "Eastern"}

imp = load_json("08_import_bibitems.json")
imported_count = imp.get("imported", 0)
skipped_count = imp.get("skipped", 0)

from collections import Counter as _Counter
person_counts = _Counter()
publisher_counts = _Counter()
other_counts = _Counter()

for e in imp.get("errors", []):
    for err in e.get("errors", []):
        msg = err["error"]
        if msg.startswith("unresolved person: "):
            person_counts[msg[len("unresolved person: "):]] += 1
        elif msg.startswith("missing publisher: "):
            publisher_counts[msg[len("missing publisher: "):]] += 1
        else:
            other_counts[msg] += 1

real_persons = {n: c for n, c in person_counts.items() if n not in CONCEPT_NAMES}
concept_persons = {n: c for n, c in person_counts.items() if n in CONCEPT_NAMES}

sk_lines = [
    f"Total bibitems imported:  {imported_count:,}",
    f"Total bibitems skipped:   {skipped_count:,}",
    "",
    "Rows are skipped when a required entity (author, publisher, etc.) cannot be",
    "resolved. The bibitem is not imported at all — no partial data is stored.",
    "",
    f"  {sum(real_persons.values()):>6,}  unresolved _person (philosopher not marked famous=TRUE)",
    f"  {sum(concept_persons.values()):>6,}  unresolved _person (philosophical tradition — not fixable)",
    f"  {sum(publisher_counts.values()):>6,}  missing publisher",
]
if other_counts:
    for msg, cnt in other_counts.most_common(5):
        sk_lines.append(f"  {cnt:>6,}  {msg}")
sk_lines += [
    "",
    "─── Unresolved persons — mark famous=TRUE in profiles spreadsheet ───",
    "",
    "Find each name below in 'portal data - profiles.csv' or",
    "'portal data - biblio profiles.csv' and set the 'famous' column to TRUE.",
    "Then re-run convert.py and re-import.",
    "",
]
for name, cnt in sorted(real_persons.items(), key=lambda x: -x[1]):
    bks = person_to_bibkeys.get(name, set())
    sk_lines.append(f"  {cnt:>5,}  {name}")
    if bks:
        sk_lines.append(f"         Bibkeys: {bibkeys_sample(bks, max_show=3)}")

sk_lines += [
    "",
    "─── Philosophical traditions — not resolvable, bibitems always skipped ───",
    "",
    "These _person values refer to traditions, not individuals.",
    "No fix needed — these bibitems are intentionally excluded.",
    "",
]
for name, cnt in sorted(concept_persons.items(), key=lambda x: -x[1]):
    bks = person_to_bibkeys.get(name, set())
    sk_lines.append(f"  {cnt:>5,}  {name}")
    if bks:
        sk_lines.append(f"         Bibkeys: {bibkeys_sample(bks, max_show=3)}")

if publisher_counts:
    sk_lines += [
        "",
        "─── Missing publishers — add to publishers spreadsheet ───",
        "",
    ]
    for name, cnt in sorted(publisher_counts.items(), key=lambda x: -x[1]):
        bks = publisher_to_bibkeys.get(name, set())
        sk_lines.append(f"  {cnt:>5,}  {name}")
        if bks:
            sk_lines.append(f"         Bibkeys: {bibkeys_sample(bks, max_show=3)}")
        sk_lines.append("")

write_report(
    "errors_skipped_bibitems.txt",
    "Skipped bibitems — rows not imported because a required entity was unresolvable",
    sk_lines,
)

# ─── 10. Entity import errors ───────────────────────────────────────────────
entity_errors_by_type = defaultdict(list)
for e in ent["errors"]:
    entity_errors_by_type[e["entity_type"]].append(e)

db_names_for = {
    "journals": db_journal_names,
    "publishers": db_publisher_names,
    "series": db_series_names,
    "institutions": load_db_names("institutions"),
    "schools": load_db_names("schools"),
}
bibkeys_for = {
    "journals": journal_to_bibkeys,
    "publishers": publisher_to_bibkeys,
    "series": series_to_bibkeys,
    "institutions": institution_to_bibkeys,
}

lines = []
for etype in sorted(entity_errors_by_type.keys()):
    errors = entity_errors_by_type[etype]
    lines.append(f"--- {etype} ({len(errors)} errors) ---")
    lines.append("")
    for e in errors:
        name = e["name"]
        err = e["error"]
        bks = bibkeys_for.get(etype, {}).get(name, set())
        lines.append(f"  {name}")
        if bks:
            lines.append(f"    Referenced by: {bibkeys_sample(bks)}")
        if "already exists" in err:
            closest = find_closest_match(name, db_names_for.get(etype, set()))
            if closest and closest != name:
                diff = describe_diff(name, closest)
                if etype == "series":
                    lines.append(f"    Spelling used by some rows:  {repr(name)}")
                    lines.append(f"    Spelling used by other rows: {repr(closest)}")
                    lines.append(f"    Difference: {diff}")
                    lines.append(f"    → Fix: pick one spelling and fix all rows in the biblio spreadsheet")
                else:
                    source = {"journals": "portal data - journals.csv", "publishers": "portal data - publishers.csv"}.get(etype, f"{etype} spreadsheet")
                    lines.append(f"    In biblio-v11-table.csv: {repr(name)}")
                    lines.append(f"    In {source}:  {repr(closest)}")
                    lines.append(f"    Difference: {diff}")
                    lines.append(f"    → Fix: make these two values identical")
            else:
                lines.append(f"    → Duplicate: auto-generated key collides with an existing entry")
        else:
            lines.append(f"    Error: {err}")
        lines.append("")
write_report(
    "errors_entity_import.txt",
    "Entity import errors — entities from biblio CSV that failed auto-creation\n"
    "For each, the closest existing DB entry is shown so you can see the mismatch.",
    lines,
)

# ─── 11. Author import errors ──────────────────────────────────────────────
def build_profile_index(path):
    index = defaultdict(list)
    with open(path, newline="", encoding="utf-8") as f:
        reader = csv.reader(f)
        next(reader)
        headers = next(reader)
        idx = {h.strip(): i for i, h in enumerate(headers)}
        for i, row in enumerate(reader, start=3):
            key = row[idx["_biblio_name"]].strip() if idx["_biblio_name"] < len(row) else ""
            rid = row[idx["id"]].strip() if idx["id"] < len(row) else ""
            bfn = row[idx["_biblio_full_name"]].strip() if idx["_biblio_full_name"] < len(row) else ""
            fn = row[idx["firstname"]].strip() if idx["firstname"] < len(row) else ""
            ln = row[idx["lastname"]].strip() if idx["lastname"] < len(row) else ""
            if key:
                index[key].append((i, rid, bfn, fn, ln))
    return index

pr_index = build_profile_index(PROFILES_PR)
bp_index = build_profile_index(PROFILES_BP)

step_to_source = {
    "01_authors_pr.json": ("portal data - profiles.csv", pr_index),
    "02_authors_bp1.json": ("portal data - biblio profiles.csv", bp_index),
    "03_authors_bp2.json": ("portal data - biblio profiles.csv", bp_index),
}

lines = []
for step_file in ["01_authors_pr.json", "02_authors_bp1.json", "03_authors_bp2.json"]:
    d = load_json(step_file)
    source_name, idx = step_to_source[step_file]
    errors = d.get("errors", [])
    if not errors:
        continue
    lines.append(f"--- From {source_name} ({len(errors)} errors) ---")
    lines.append("")
    for e in errors:
        key = e["identifier"]
        err = e["error"]
        occurrences = idx.get(key, [])
        lines.append(f"  author_key: {key}")
        lines.append(f"    Error: {err}")
        if len(occurrences) > 1:
            lines.append(f"    Appears {len(occurrences)} times in {source_name}:")
            for _, rid, bfn, fn, ln in occurrences:
                lines.append(f"      id={rid}, name={repr(bfn[:60])}")
        elif occurrences:
            _, rid, bfn, _, _ = occurrences[0]
            lines.append(f"    In {source_name}: id={rid}, name={repr(bfn[:60])}")
        if "ID" in err and "exists but has key" in err:
            import re
            id_match = re.search(r"ID (\d+)", err)
            if id_match:
                conflict_id = id_match.group(1)
                current_info = None
                for occ_row, occ_rid, occ_bfn, occ_fn, occ_ln in occurrences:
                    if occ_rid == conflict_id:
                        current_info = (occ_row, occ_bfn)
                        break
                other_info = None
                for other_key_name, other_rows in idx.items():
                    for other_row_num, other_rid, other_bfn, _, _ in other_rows:
                        if other_rid == conflict_id and other_key_name != key:
                            other_info = (other_row_num, other_key_name, other_bfn)
                            break
                    if other_info:
                        break
                if other_info:
                    o_row, o_key, o_name = other_info
                    c_name = current_info[1] if current_info else occurrences[0][2] if occurrences else "?"
                    lines.append(f"    → DUPLICATE ID {conflict_id} in {source_name}:")
                    lines.append(f"      Person 1: key={o_key}, name={repr(o_name[:60])}")
                    lines.append(f"      Person 2: key={key}, name={repr(c_name[:60])}")
                    lines.append(f"      Two different people have the same ID. Fix the ID on one of them.")
                else:
                    lines.append(f"    → ID conflict: ID {conflict_id} belongs to a different author in the DB")
            else:
                lines.append(f"    → ID conflict: the CSV row's id points to a different author in the DB")
        elif "already exists" in err:
            all_occurrences = []
            for src_label, src_idx in [
                ("portal data - profiles.csv", pr_index),
                ("portal data - biblio profiles.csv", bp_index),
            ]:
                for occ in src_idx.get(key, []):
                    _, occ_rid, occ_bfn, _, _ = occ
                    all_occurrences.append((src_label, occ_rid, occ_bfn))
            if len(all_occurrences) > 1:
                lines.append(f"    → Duplicate author_key '{key}' across profile spreadsheets:")
                for src_label, occ_rid, occ_bfn in all_occurrences:
                    lines.append(f"      id={occ_rid or '(none)'}, name={repr(occ_bfn[:60])}  ({src_label})")
                lines.append(f"      Keep one, remove the other.")
            elif len(all_occurrences) == 1:
                src_label, occ_rid, occ_bfn = all_occurrences[0]
                lines.append(f"    → Duplicate: key '{key}' already imported from another source")
            else:
                lines.append(f"    → Duplicate: another row with the same author_key was already imported")
        elif "family_name" in err or "mononym" in err:
            lines.append(f"    → Validation: the profile is missing required name fields")
        lines.append("")
write_report(
    "errors_author_import.txt",
    "Author import errors — profile rows that failed during import\n"
    "These reference the original portal spreadsheets (profiles / biblio profiles).",
    lines,
)

# ─── 12. Journal/Publisher import errors ────────────────────────────────────
def build_entity_index(path, key_col):
    index = defaultdict(list)
    with open(path, newline="", encoding="utf-8") as f:
        reader = csv.reader(f)
        next(reader)
        headers = next(reader)
        idx = {h.strip(): i for i, h in enumerate(headers)}
        for i, row in enumerate(reader, start=3):
            key = row[idx[key_col]].strip() if idx[key_col] < len(row) else ""
            rid = row[idx["id"]].strip() if idx["id"] < len(row) else ""
            bfn = row[idx["_biblio_full_name"]].strip() if idx["_biblio_full_name"] < len(row) else ""
            if key:
                index[key].append((i, rid, bfn))
    return index

jo_index = build_entity_index(JOURNALS_CSV, "journal_key")
pu_index = build_entity_index(PUBLISHERS_CSV, "publisher_key")

lines = []
for step_file, label, idx in [
    ("04_journals.json", "journals", jo_index),
    ("05_publishers.json", "publishers", pu_index),
]:
    d = load_json(step_file)
    source_name = f"portal data - {label}.csv"
    errors = d.get("errors", [])
    if not errors:
        continue
    lines.append(f"--- {label} ({len(errors)} errors) ---")
    lines.append("")
    for e in errors:
        key = e["identifier"]
        err = e["error"]
        occurrences = idx.get(key, [])
        lines.append(f"  {label[:-1]}_key: {key}")
        lines.append(f"    Error: {err}")
        if len(occurrences) > 1:
            lines.append(f"    Appears {len(occurrences)} times in {source_name}:")
            for _, rid, bfn in occurrences:
                lines.append(f"      id={rid}, name={repr(bfn[:70])}")
        elif occurrences:
            _, rid, bfn = occurrences[0]
            lines.append(f"    In {source_name}: id={rid}, name={repr(bfn[:70])}")
        if "ID" in err and "exists but has key" in err:
            import re
            id_match = re.search(r"ID (\d+)", err)
            other_key_match = re.search(r"has key '([^']+)'", err)
            if id_match:
                conflict_id = id_match.group(1)
                other_key = other_key_match.group(1) if other_key_match else "?"
                found_other = False
                for other_k, other_rows in idx.items():
                    for _, other_rid, other_bfn in other_rows:
                        if other_rid == conflict_id and other_k != key:
                            lines.append(f"    → DUPLICATE ID {conflict_id} in {source_name}:")
                            lines.append(f"      Entry 1: key={other_k}, name={repr(other_bfn[:70])}")
                            lines.append(f"      Entry 2: key={key}")
                            lines.append(f"      Two different entries have the same ID. Fix the ID on one of them.")
                            found_other = True
                            break
                    if found_other:
                        break
                if not found_other:
                    lines.append(f"    → ID {conflict_id} was already used by key '{other_key}' (imported from a row without an ID)")
            else:
                lines.append(f"    → ID conflict: the row's id points to a different entity in the DB")
        elif "already exists" in err:
            if len(occurrences) > 1:
                lines.append(f"    → Duplicate key in {source_name}:")
                for _, rid, bfn in occurrences:
                    lines.append(f"      id={rid}, name={repr(bfn[:70])}")
                lines.append(f"      Remove the duplicate entry.")
            else:
                lines.append(f"    → Duplicate: another row with the same key was already imported")
        lines.append("")
write_report(
    "errors_journal_publisher_import.txt",
    "Journal and publisher import errors\n"
    "These reference the original portal spreadsheets.",
    lines,
)

# ─── Visual check: keyword data quality ─────────────────────────────────────
import re as _re

kw_counts = defaultdict(int)
with open(BIBLIO_CSV, newline="", encoding="utf-8") as f:
    reader = csv.DictReader(f)
    for row in reader:
        for col in ["_kw-level1", "_kw-level2", "_kw-level3"]:
            for kw in row.get(col, "").split(";"):
                kw = kw.strip()
                if kw:
                    kw_counts[kw] += 1

urls       = sorted([(k, v) for k, v in kw_counts.items() if "http" in k or k.startswith("www")], key=lambda x: -x[1])
numbers    = sorted([(k, v) for k, v in kw_counts.items() if _re.fullmatch(r"\d+", k)], key=lambda x: -x[1])
trail_col  = sorted([(k, v) for k, v in kw_counts.items() if k.endswith(":") and k != ":"], key=lambda x: -x[1])
trail_com  = sorted([(k, v) for k, v in kw_counts.items() if k.endswith(",") and k != ","], key=lambda x: -x[1])
punct_only = sorted([(k, v) for k, v in kw_counts.items() if _re.fullmatch(r"[,.:;/\-]+", k)], key=lambda x: -x[1])

vc_lines = []

def _kw_block(title, note, pairs):
    vc_lines.append(f"--- {title} ({len(pairs)} unique) ---")
    if note:
        vc_lines.append(f"Note: {note}")
    vc_lines.append("")
    for kw, cnt in pairs:
        vc_lines.append(f"  {cnt:>6}x  {kw}")
    vc_lines.append("")

_kw_block("URLs in keyword columns", "Column-shift in source: URL landed in _kw-level1/2/3 instead of the url column.", urls)
_kw_block("Pure numbers in keyword columns", "Column-shift in source: looks like internal spreadsheet row IDs.", numbers)
_kw_block("Keywords with trailing colon  (e.g. 'history-of-philosophy:')", "Trailing colon should be stripped from the keyword name in the source spreadsheet.", trail_col)
_kw_block("Keywords with trailing comma  (e.g. 'Pascal\\'s-wager,')", "Trailing comma should be stripped from the keyword name in the source spreadsheet.", trail_com)
_kw_block("Punctuation-only keyword values", "Stray cells — delete or fix in the source spreadsheet.", punct_only)

write_report(
    "visual_check_keywords.txt",
    "Visual check — suspicious keyword values in biblio-v11-table.csv\n"
    "All issues below are data errors in the source spreadsheet, not import bugs.\n"
    "Fix the indicated cells in biblio-v11-table.csv.",
    vc_lines,
)

# ─── Summary ────────────────────────────────────────────────────────────────
summary_lines = [
    f"Total biblio rows:       {val['total_rows']:,}",
    f"Valid biblio rows:       {val['valid_rows']:,}",
    f"Bibitems imported:       {imported_count:,}",
    f"Bibitems skipped:        {skipped_count:,}         → errors_skipped_bibitems.txt",
    f"",
    f"Parse errors:            {len(val['errors'])}           → errors_parse.txt",
    f"Missing authors:         {len(val['missing_authors'])}           → errors_missing_authors.txt",
    f"Ambiguous authors:       {len(val['ambiguous_authors'])}            → errors_ambiguous_authors.txt",
    f"Missing journals:        {len(val['missing_journals'])}            → errors_missing_journals.txt",
    f"Missing publishers:      {len(val['missing_publishers'])}            → errors_missing_publishers.txt",
    f"Missing institutions:    {len(val['missing_institutions'])}             → errors_missing_institutions.txt",
    f"Missing schools:         {len(val['missing_schools'])}             → (none)",
    f"Missing series:          {len(val['missing_series'])}            → errors_missing_series.txt",
    f"Missing crossrefs:       {len(val.get('missing_crossrefs', []))}          → errors_missing_crossrefs.txt",
    f"Duplicate bibkeys:       {len(val.get('duplicate_bibkeys', []))}",
    "",
    "Entity import errors:    see errors_entity_import.txt",
    "Author import errors:    see errors_author_import.txt",
    "Journal/pub errors:      see errors_journal_publisher_import.txt",
    "Keyword data quality:    see visual_check_keywords.txt",
    "",
    "─── Skipped bibitems breakdown ───",
    "",
    f"  {sum(real_persons.values()):>6,}  philosopher not marked famous=TRUE in profiles",
    f"  {sum(concept_persons.values()):>6,}  philosophical tradition (Indian/Chinese/etc) — not fixable",
    f"  {sum(publisher_counts.values()):>6,}  missing publisher",
    "",
    "  Top missing famous philosophers (need famous=TRUE in profiles spreadsheet):",
]
for name, cnt in sorted(real_persons.items(), key=lambda x: -x[1])[:15]:
    summary_lines.append(f"    {cnt:>5,}  {name}")
if len(real_persons) > 15:
    summary_lines.append(f"    ... and {len(real_persons) - 15} more — see errors_skipped_bibitems.txt")

summary_lines += ["", "  Top missing publishers:"]
for name, cnt in sorted(publisher_counts.items(), key=lambda x: -x[1])[:5]:
    summary_lines.append(f"    {cnt:>5,}  {name[:80]}")

summary_lines += [
    "",
    "─── What to fix ───",
    "",
    "1. PARSE ERRORS (fix in biblio spreadsheet)",
    "   Open-ended page ranges like '215--' need an end page.",
    "",
    "2. MISSING AUTHORS (fix in profiles spreadsheets or biblio spreadsheet)",
    "   These names appear in the biblio but no matching profile exists.",
    "   Either add the author to a profile spreadsheet, or fix the name in biblio.",
    "",
    "3. AMBIGUOUS AUTHORS (fix in profiles spreadsheets)",
    "   These names match 2+ profiles. Deduplicate: keep one, delete/merge the other.",
    "",
    "4. MISSING JOURNALS/PUBLISHERS/SERIES (fix _biblio_full_name or add entry)",
    "   The biblio CSV references these by LaTeX name but no match was found.",
    "   Usually a _biblio_full_name mismatch between the entity and biblio spreadsheets.",
    "",
    "5. MISSING CROSSREFS (fix in biblio spreadsheet)",
    "   The 'crossref' column references bibkeys that don't exist as rows.",
    "   Add the missing entries or remove the crossref.",
    "",
    "6. DUPLICATE ROWS (fix in source spreadsheets)",
    "   See errors_author_import.txt and errors_journal_publisher_import.txt",
    "   for rows that appear twice with the same key.",
    "",
    "7. SKIPPED BIBITEMS (fix in profiles spreadsheet)",
    "   Set famous=TRUE for the philosophers listed above.",
    "   Then re-run convert.py and re-import. See errors_skipped_bibitems.txt.",
]
write_report("SUMMARY.txt", "Alexandria Import Validation Report", summary_lines)
