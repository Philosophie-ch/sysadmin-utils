import csv
from dataclasses import asdict
import traceback
from typing import Iterable, Tuple
from base_types import ImageReport
from pathlib import Path
from aletk.utils import get_logger
from aletk.ResultMonad import main_try_except_wrapper, Ok, Err
from check_image_metadata import check_exif_copyright

lgr = get_logger(__name__)


def multi_check(image_path: str) -> ImageReport:

    try:

        image_name = Path(image_path).name
        image_path_abs = Path(image_path).absolute()
        if not image_path_abs.is_file():
            raise FileNotFoundError(f"The file {image_path} does not exist.")

        exif_report = check_exif_copyright(image_path)

        return ImageReport(
            image_name=image_name,
            image_path=str(image_path),
            exif_copyright=exif_report.exif_copyright,
            exif_status=exif_report.status,
            exif_error_message=exif_report.error_message,
            exif_error_context=exif_report.error_context,
            status="ok",
            error_message="",
            error_context="",
        )

    except Exception as e:
        return ImageReport(
            image_name="",
            image_path=image_path,
            exif_copyright="",
            exif_status="",
            exif_error_message="",
            status="error",
            error_message=str(e),
            error_context=f"Error processing image: '{image_path}'. Traceback: {traceback.format_exc()}",
        )


def read_image_paths_from_file(file_path: str) -> Tuple[str, ...]:
    """
    Read image paths from a file.
    """
    try:
        with open(file_path, "r") as f:
            image_paths = tuple(line.strip() for line in f.readlines())
        return image_paths

    except Exception as e:
        lgr.error(f"Error reading file {file_path}: {e}")
        return ()


def write_image_reports_to_csv(image_reports: Iterable[ImageReport], output_file: str) -> None:
    """
    Write image reports to a CSV file, using .asdict() and write DictWriter.
    """
    if not image_reports:
        raise ValueError("No image reports to write.")

    with open(output_file, "w", newline="") as csvfile:
        fieldnames = list(ImageReport.__annotations__.keys())
        writer = csv.DictWriter(csvfile, fieldnames=fieldnames)
        writer.writeheader()

        for report in image_reports:
            writer.writerow(asdict(report))

    lgr.info(f"Image reports written to {output_file}")


@main_try_except_wrapper(logger=lgr)
def main(
    input_file: str,
    output_file: str,
) -> None:
    """
    Main function to read image paths from a file, check each image for copyright information, and write the reports to a CSV file.
    """
    lgr.info(f"Reading image paths from '{input_file}'")
    image_paths = read_image_paths_from_file(input_file)

    lgr.info(f"Checking {len(image_paths)} images for copyright information and writing to '{output_file}'...")
    image_reports = (multi_check(image_path) for image_path in image_paths)

    # Stream the reports to CSV, line by line directly
    write_image_reports_to_csv(image_reports, output_file)

    lgr.info(f"All image reports written to '{output_file}'")


def cli() -> None:
    import argparse

    parser = argparse.ArgumentParser(
        description="Check images for copyright information and write reports to a CSV file."
    )

    parser.add_argument(
        "-i",
        "--input_file",
        type=str,
        required=True,
        help="Path to the input file containing image paths.",
    )

    parser.add_argument(
        "-o",
        "--output_file",
        type=str,
        required=True,
        help="Path to the output CSV file.",
    )

    args = parser.parse_args()

    result = main(
        input_file=args.input_file,
        output_file=args.output_file,
    )

    match result:
        case Ok(out=_):
            pass
        case Err(err):
            lgr.error(f"Error: {err}")


if __name__ == "__main__":
    cli()
