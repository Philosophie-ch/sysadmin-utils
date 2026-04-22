#!/usr/bin/env python3
"""Convert portal CSVs to Alexandria import format.

All source files have: row 0 = descriptions, row 1 = headers, row 2+ = data.
Only rows with a non-empty key are included.

Reads ALEXANDRIA_DATA_DIR from environment (see .env.example).
"""

import csv
import os

SRC = os.environ.get("ALEXANDRIA_DATA_DIR", os.path.dirname(os.path.abspath(__file__)))
csv.field_size_limit(1_000_000)


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
