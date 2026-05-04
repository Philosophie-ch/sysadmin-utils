#!/usr/bin/env python3
"""Convert portal CSVs to Alexandria import format.

All source files have: row 0 = descriptions, row 1 = headers, row 2+ = data.
Only rows with a non-empty key are included.

Reads ALEXANDRIA_DATA_DIR from environment (see .env.example).
"""

import csv
import os
import re

SRC = os.environ.get("ALEXANDRIA_DATA_DIR", os.path.dirname(os.path.abspath(__file__)))
csv.field_size_limit(1_000_000)

PHILOSOPHIE_CH_PUBLISHER_KEY = "philosophie-ch"
LICENSE_CC_BY_3 = "https://creativecommons.org/licenses/by/3.0/"
LICENSE_CC_BY_4 = "https://creativecommons.org/licenses/by/4.0/"

_publisher_name_cache: dict[str, str] | None = None


def _get_publisher_name_latex(publishers_csv_path: str, publisher_key: str) -> str | None:
    global _publisher_name_cache
    if _publisher_name_cache is None:
        _publisher_name_cache = {}
        try:
            with open(publishers_csv_path, newline="", encoding="utf-8") as f:
                for row in csv.DictReader(f):
                    _publisher_name_cache[row["publisher_key"]] = row["name_latex"]
        except FileNotFoundError:
            pass
    return _publisher_name_cache.get(publisher_key)


def _extract_year(date_str: str) -> int | None:
    m = re.search(r"\d{4}", date_str)
    return int(m.group()) if m else None


def parse_biblio_full_name(biblio_full):
    """Parse _biblio_full_name into (family_latex, given_latex, mononym_latex).

    Patterns:
      "Family, Given"           -> (Family, Given, "")
      "{Mononym}"               -> ("", "", Mononym-with-braces)
      "Mononym"  (no comma)     -> ("", "", Mononym)
    """
    if not biblio_full:
        return "", "", ""

    if "," in biblio_full:
        parts = biblio_full.split(",", 1)
        return parts[0].strip(), parts[1].strip(), ""
    else:
        return "", "", biblio_full.strip()


def convert_profiles(src_name, out_name):
    """Convert profile CSV to Alexandria author import format."""
    src = os.path.join(SRC, src_name)
    out = os.path.join(SRC, out_name)

    fields = [
        "id", "author_key",
        "family_name_latex", "given_name_latex", "mononym_latex",
        "family_name_unicode", "given_name_unicode", "mononym_unicode",
        "famous",
    ]

    with open(src, newline="", encoding="utf-8") as fin, \
         open(out, "w", newline="", encoding="utf-8") as fout:

        reader = csv.reader(fin)
        next(reader)  # skip description row
        headers = next(reader)
        idx = {h.strip(): i for i, h in enumerate(headers)}

        writer = csv.DictWriter(fout, fieldnames=fields)
        writer.writeheader()

        written = 0
        skipped = 0
        for row in reader:
            key = row[idx["_biblio_name"]].strip() if idx["_biblio_name"] < len(row) else ""
            if not key:
                skipped += 1
                continue

            biblio_full = row[idx["_biblio_full_name"]].strip() if idx["_biblio_full_name"] < len(row) else ""
            family_latex, given_latex, mononym_latex = parse_biblio_full_name(biblio_full)

            firstname = row[idx["firstname"]].strip() if idx["firstname"] < len(row) else ""
            lastname = row[idx["lastname"]].strip() if idx["lastname"] < len(row) else ""
            row_id = row[idx["id"]].strip() if idx["id"] < len(row) else ""
            famous_raw = row[idx["famous"]].strip() if "famous" in idx and idx["famous"] < len(row) else ""
            famous = "TRUE" if famous_raw.upper() in ("TRUE", "1", "YES") else "FALSE"

            if mononym_latex:
                out_row = {
                    "id": row_id,
                    "author_key": key,
                    "family_name_latex": "",
                    "given_name_latex": "",
                    "mononym_latex": mononym_latex,
                    "family_name_unicode": "",
                    "given_name_unicode": "",
                    "mononym_unicode": lastname or firstname,
                    "famous": famous,
                }
            else:
                out_row = {
                    "id": row_id,
                    "author_key": key,
                    "family_name_latex": family_latex,
                    "given_name_latex": given_latex,
                    "mononym_latex": "",
                    "family_name_unicode": lastname,
                    "given_name_unicode": firstname,
                    "mononym_unicode": "",
                    "famous": famous,
                }

            writer.writerow(out_row)
            written += 1

    print(f"{src_name} -> {out_name}: {written} rows, {skipped} skipped")


def convert_simple(src_name, out_name, key_col, col_map):
    """Convert a simple entity CSV (journals, publishers)."""
    src = os.path.join(SRC, src_name)
    out = os.path.join(SRC, out_name)

    with open(src, newline="", encoding="utf-8") as fin, \
         open(out, "w", newline="", encoding="utf-8") as fout:

        reader = csv.reader(fin)
        next(reader)  # skip description row
        headers = next(reader)
        idx = {h.strip(): i for i, h in enumerate(headers)}

        out_fields = list(col_map.values())
        writer = csv.DictWriter(fout, fieldnames=out_fields)
        writer.writeheader()

        key_idx = idx[key_col]
        written = 0
        skipped = 0
        for row in reader:
            if len(row) <= key_idx or not row[key_idx].strip():
                skipped += 1
                continue

            out_row = {}
            for src_col, alx_col in col_map.items():
                i = idx[src_col]
                out_row[alx_col] = row[i].strip() if i < len(row) else ""
            writer.writerow(out_row)
            written += 1

    print(f"{src_name} -> {out_name}: {written} rows, {skipped} skipped")


# --- Profiles -> Authors ---
convert_profiles("portal data - profiles.csv", "authors_pr.csv")
convert_profiles("portal data - biblio profiles.csv", "authors_bp.csv")

# --- Journals ---
convert_simple(
    "portal data - journals.csv", "journals.csv",
    key_col="journal_key",
    col_map={
        "id": "id",
        "journal_key": "journal_key",
        "_biblio_full_name": "name_latex",
        "name": "name_unicode",
        "issn_print": "issn_print",
        "issn_electronic": "issn_electronic",
    },
)

# --- Publishers ---
convert_simple(
    "portal data - publishers.csv", "publishers.csv",
    key_col="publisher_key",
    col_map={
        "id": "id",
        "publisher_key": "publisher_key",
        "_biblio_full_name": "name_latex",
    },
)


def preprocess_biblio(src_name, out_name):
    """Copy the biblio CSV, applying two conventions:

    1. Empty _langid defaults to 'english'.
    2. philosophie-ch publisher entries get a CC license based on year
       (CC BY 4.0 from 2026 onwards, CC BY 3.0 for 2025 and earlier),
       but only if the license column is currently empty.
    """
    src = os.path.join(SRC, src_name)
    out = os.path.join(SRC, out_name)

    publishers_csv = os.path.join(SRC, "publishers.csv")
    phch_name_latex = _get_publisher_name_latex(publishers_csv, PHILOSOPHIE_CH_PUBLISHER_KEY)

    with open(src, newline="", encoding="utf-8") as fin, \
         open(out, "w", newline="", encoding="utf-8") as fout:

        reader = csv.reader(fin)
        headers = next(reader)
        writer = csv.writer(fout)
        writer.writerow(headers)

        langid_idx = headers.index("_langid") if "_langid" in headers else None
        publisher_idx = headers.index("publisher") if "publisher" in headers else None
        license_idx = headers.index("license") if "license" in headers else None
        date_idx = headers.index("date") if "date" in headers else None

        langid_filled = 0
        license_filled = 0
        for row in reader:
            row = list(row)

            if langid_idx is not None:
                while len(row) <= langid_idx:
                    row.append("")
                if not row[langid_idx].strip():
                    row[langid_idx] = "english"
                    langid_filled += 1

            if (phch_name_latex and publisher_idx is not None
                    and license_idx is not None and date_idx is not None):
                while len(row) <= max(publisher_idx, license_idx, date_idx):
                    row.append("")
                if row[publisher_idx].strip() == phch_name_latex and not row[license_idx].strip():
                    date_val = row[date_idx].strip().lower()
                    if date_val == "forthcoming":
                        row[license_idx] = LICENSE_CC_BY_4
                        license_filled += 1
                    else:
                        year = _extract_year(row[date_idx])
                        if year is not None:
                            row[license_idx] = LICENSE_CC_BY_4 if year >= 2026 else LICENSE_CC_BY_3
                            license_filled += 1

            writer.writerow(row)

    print(f"{src_name} -> {out_name}: {langid_filled} rows defaulted to langid=english, {license_filled} philosophie-ch license rows filled")


# --- Biblio CSV preprocessing ---
BIBLIO_CSV = os.environ.get("ALEXANDRIA_BIBLIO_CSV", "biblio-v11-table.csv")
preprocess_biblio(BIBLIO_CSV, "biblio-processed.csv")
