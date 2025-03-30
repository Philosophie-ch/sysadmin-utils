import csv
import os
import shutil
from dataclasses import dataclass
from typing import Generic, TypeVar

T = TypeVar("T")


@dataclass
class Ok(Generic[T]):
    out: T


@dataclass
class Err:
    msg: str


def rename_file(old: str, new: str) -> Ok[tuple[str, str]] | Err:
    try:
        # Assert that the old file exists
        if not os.path.exists(old):
            return Err(f"File '{old}' does not exist.")

        # Copy instead of moving, in case the input batch mentions the same file multiple times
        shutil.copy2(old, new)

    except Exception as e:
        return Err(str(e))

    return Ok((old, new))


@dataclass
class MainOutput:
    header: list[str]
    results: list[tuple[str, str, str]]


def main(input_csv: str, encoding: str) -> Ok[MainOutput] | Err:
    try:
        with open(input_csv, 'r', encoding=encoding) as f:
            reader = csv.DictReader(f)

            required_columns = ['old', 'new']
            if not all(col in reader.fieldnames for col in required_columns):
                return Err("The CSV file needs to have a header row with at least 'old' and 'new'.")

            rows = [row for row in reader]

        if not rows:
            return Err("No rows found in the CSV file.")

        results = []
        for row in rows:
            result = rename_file(row['old'], row['new'])
            match result:
                case Ok(out):
                    results.append((out[0], out[1], "OK"))
                case Err(msg):
                    results.append((row['old'], row['new'], f"ERR: {msg}"))

    except Exception as e:
        return Err(str(e))

    out = MainOutput(header=["old", "new", "status"], results=results)
    return Ok(out)


def cli(result: Ok[MainOutput] | Err) -> None:

    match result:

        case Ok(out):
            print(",".join(out.header))
            for row in out.results:
                print(f"\"{row[0]}\",\"{row[1]}\",\"{row[2]}\"")

        case Err(msg):
            print(f"\n============ Error ============\n\t{msg}")
            print("")


if __name__ == "__main__":
    import argparse

    parser = argparse.ArgumentParser(description="Rename assets")
    parser.add_argument(
        "-i",
        "--input",
        type=str,
        help="CSV file with old and new filenames. Needs to have a header row with 'old' and 'new' columns, with the corresponding filenames. Prints the result to the stdout.",
        required=True,
    )
    parser.add_argument("-e", "--encoding", type=str, help="CSV file encoding", default='utf-8')

    args = parser.parse_args()

    csv_file = args.input
    encoding = args.encoding

    result = main(csv_file, encoding)
    cli(result)
