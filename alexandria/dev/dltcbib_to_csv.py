#!/usr/bin/env python3
"""Convert a DLTC .bib file (Philipp Blum's Dialectica bibliography)
to a CSV matching the biblio-v11-table column layout.

Usage: python3 dltcbib_to_csv.py input.bib [output.csv]

If output.csv is omitted, writes to input-table.csv alongside the input.
"""

from __future__ import annotations

import csv
import logging
import re
import sys
from collections.abc import Generator, Mapping
from dataclasses import dataclass
from typing import Final

logger = logging.getLogger(__name__)

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

V11_COLUMNS: Final[tuple[str, ...]] = (
    "_to-do general", "_change-request", "entry_type", "bibkey",
    "author", "_author_ids", "editor", "_editor_ids", "author_ids",
    "options", "shorthand", "date", "pubstate", "title", "_title-unicode",
    "booktitle", "crossref", "journal", "journal-id", "volume", "number",
    "pages", "start_page", "", "end_page", "", "eid", "series", "address",
    "institution", "school", "publisher", "publisher-id", "type", "edition",
    "note", "_issuetitle", "_guesteditor", "_extra-note", "urn", "eprint",
    "doi", "url", "_kw-level1", "_kw-level2", "_kw-level3", "_epoch",
    "_person", "_comm_for_profile_bib", "_langid", "_lang-der",
    "_further_refs", "_depends_on", "_dltc-num", "_spec-interest",
    "_note-perso", "_note-stock", "_has-link-to-full-text", "_note-status",
    "_num-inwork-coll", "_num-inwork", "_num-coll", "_dltc_copyediting_note",
    "_note-missing", "_num-sort",
)

BIB_FIELD_TO_CSV: Final[Mapping[str, str]] = {
    "author":       "author",
    "editor":       "editor",
    "options":      "options",
    "shorthand":    "shorthand",
    "date":         "date",
    "pubstate":     "pubstate",
    "title":        "title",
    "booktitle":    "booktitle",
    "crossref":     "crossref",
    "journal":      "journal",
    "volume":       "volume",
    "number":       "number",
    "pages":        "pages",
    "eid":          "eid",
    "series":       "series",
    "address":      "address",
    "institution":  "institution",
    "school":       "school",
    "publisher":    "publisher",
    "type":         "type",
    "edition":      "edition",
    "note":         "note",
    "issuetitle":   "_issuetitle",
    "guesteditor":  "_guesteditor",
    "extra-note":   "_extra-note",
    "eprint":       "eprint",
    "doi":          "doi",
    "url":          "url",
}

# ---------------------------------------------------------------------------
# Models
# ---------------------------------------------------------------------------


@dataclass(frozen=True, slots=True)
class ParsedEntry:
    entry_type: str
    bibkey: str
    fields: Mapping[str, str]


# ---------------------------------------------------------------------------
# Pure functions (logic)
# ---------------------------------------------------------------------------


def strip_enclosing_braces(s: str) -> str:
    """Strip one outer ``{…}`` pair only if it wraps the entire value.

    Handles the BibTeX ``{{Title}}`` convention: after the parser extracts
    the value from ``title = {{Title}}``, we get ``{Title}``; this function
    removes that remaining layer while keeping inner braces (e.g.
    ``\\citet{key}``, ``{\\\"o}``) intact.

    Args:
        s: Value already extracted from the BibTeX ``field = {…}`` wrapper.

    Returns:
        The value with the enclosing pair removed, or unchanged if the
        opening brace does not span the full string.
    """
    if not s or s[0] != "{":
        return s
    depth = 0
    for i, ch in enumerate(s):
        if ch == "{":
            depth += 1
        elif ch == "}":
            depth -= 1
            if depth == 0:
                if i == len(s) - 1:
                    return s[1:-1]
                return s
    return s


def strip_name_braces(s: str) -> str:
    """Strip BibTeX casing braces around last names in author/editor values.

    Removes ``{LastName}`` wrappers (where the braces do not span the whole
    name component) but keeps ``{Organization Name}`` braces (where they do)
    and LaTeX accent braces like ``{\\'{e}}``.

    Args:
        s: Raw author or editor string with components separated by
           `` and ``.

    Returns:
        The string with last-name braces removed.
    """
    parts = s.split(" and ")
    result: list[str] = []
    for part in parts:
        stripped = part.strip()
        if not stripped or stripped[0] != "{":
            result.append(part)
            continue
        depth = 0
        for i, ch in enumerate(stripped):
            if ch == "{":
                depth += 1
            elif ch == "}":
                depth -= 1
                if depth == 0:
                    if i == len(stripped) - 1:
                        result.append(part)
                    else:
                        inner = stripped[1:i]
                        rest = stripped[i + 1 :]
                        result.append(inner + rest)
                    break
        else:
            result.append(part)
    return " and ".join(result)


def _parse_bib_value(line: str, start: int) -> tuple[str, int]:
    """Parse a brace-delimited value starting at *start*.

    Args:
        line: Full line text.
        start: Index of the opening ``{``.

    Returns:
        ``(value, end_pos)`` where *end_pos* is the index after the
        closing ``}``.
    """
    depth = 0
    vstart = start + 1
    pos = start
    while pos < len(line):
        if line[pos] == "{":
            depth += 1
        elif line[pos] == "}":
            depth -= 1
            if depth == 0:
                return line[vstart:pos], pos + 1
        pos += 1
    return line[vstart:], len(line)


def parse_entry(line: str) -> ParsedEntry | None:
    """Parse one BibTeX entry from a single line.

    Args:
        line: Raw line from the ``.bib`` file.

    Returns:
        A ``ParsedEntry`` or ``None`` if the line is not a valid entry.
    """
    line = line.strip()
    if not line.startswith("@"):
        return None

    brace = line.find("{")
    if brace == -1:
        return None
    entry_type = line[: brace + 1]

    comma = line.find(",", brace)
    if comma == -1:
        return None
    bibkey = line[brace + 1 : comma]

    fields: dict[str, str] = {}
    pos = comma + 1
    end = len(line) - 1

    while pos < end:
        while pos < end and line[pos] in " \t,":
            pos += 1
        if pos >= end:
            break

        eq = line.find("=", pos)
        if eq == -1 or eq >= end:
            break
        field_name = line[pos:eq].strip()
        pos = eq + 1

        while pos < end and line[pos] in " \t":
            pos += 1

        if pos < end and line[pos] == "{":
            value, pos = _parse_bib_value(line, pos)
            fields[field_name] = value
        else:
            nxt = line.find(",", pos)
            if nxt == -1 or nxt > end:
                nxt = end
            fields[field_name] = line[pos:nxt].strip()
            pos = nxt

    return ParsedEntry(entry_type=entry_type, bibkey=bibkey, fields=fields)


def entry_to_csv_row(entry: ParsedEntry) -> tuple[str, ...]:
    """Map a parsed BibTeX entry to a v11 CSV row.

    Args:
        entry: Parsed bibliography entry.

    Returns:
        Tuple of string values aligned to ``V11_COLUMNS``.
    """
    values: dict[str, str] = {
        "entry_type": entry.entry_type,
        "bibkey": entry.bibkey,
    }

    _ENCLOSING = frozenset({"title", "booktitle", "note", "issuetitle", "series"})
    _NAME = frozenset({"author", "editor", "guesteditor"})

    for bib_field, csv_col in BIB_FIELD_TO_CSV.items():
        if bib_field not in entry.fields:
            continue
        raw = entry.fields[bib_field]
        if bib_field in _ENCLOSING:
            values[csv_col] = strip_enclosing_braces(raw)
        elif bib_field in _NAME:
            values[csv_col] = strip_name_braces(raw)
        else:
            values[csv_col] = raw

    return tuple(values.get(col, "") for col in V11_COLUMNS)


# ---------------------------------------------------------------------------
# I/O (adapters)
# ---------------------------------------------------------------------------


def read_entries(input_path: str) -> Generator[ParsedEntry, None, None]:
    """Yield parsed entries from a DLTC ``.bib`` file.

    Unparseable lines are logged as warnings and skipped.

    Args:
        input_path: Path to the ``.bib`` file.

    Yields:
        One ``ParsedEntry`` per valid BibTeX line.
    """
    with open(input_path, "r", encoding="utf-8") as f:
        for lineno, line in enumerate(f, 1):
            line = line.strip()
            if not line:
                continue
            entry = parse_entry(line)
            if entry is None:
                logger.warning(
                    "Could not parse line %d: %s…", lineno, line[:80],
                )
                continue
            yield entry


def write_csv(
    rows: Generator[tuple[str, ...], None, None],
    output_path: str,
) -> int:
    """Write v11-format CSV rows to *output_path*.

    Args:
        rows: Generator of row tuples aligned to ``V11_COLUMNS``.
        output_path: Destination file path.

    Returns:
        Number of data rows written (excluding the header).
    """
    count = 0
    with open(output_path, "w", encoding="utf-8", newline="") as f:
        writer = csv.writer(f)
        writer.writerow(V11_COLUMNS)
        for row in rows:
            writer.writerow(row)
            count += 1
    return count


# ---------------------------------------------------------------------------
# Wiring
# ---------------------------------------------------------------------------


def convert(input_path: str, output_path: str) -> None:
    """Read a DLTC .bib, convert entries, and write a v11-format CSV.

    Args:
        input_path: Path to the input ``.bib`` file.
        output_path: Path for the output CSV.
    """
    entries = read_entries(input_path)
    rows = (entry_to_csv_row(e) for e in entries)
    count = write_csv(rows, output_path)
    logger.info("Converted %d entries → %s", count, output_path)


def main() -> None:
    """CLI entry point."""
    logging.basicConfig(
        level=logging.INFO,
        format="%(levelname)s: %(message)s",
    )

    if len(sys.argv) < 2:
        logger.error("Usage: %s input.bib [output.csv]", sys.argv[0])
        sys.exit(1)

    input_path = sys.argv[1]
    if len(sys.argv) >= 3:
        output_path = sys.argv[2]
    else:
        output_path = re.sub(r"\.bib$", "", input_path) + "-table.csv"

    convert(input_path, output_path)


if __name__ == "__main__":
    main()
