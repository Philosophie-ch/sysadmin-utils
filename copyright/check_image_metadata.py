import traceback
from PIL import Image
import piexif
from pathlib import Path

from base_types import ExifReport


def check_exif_copyright(image_path: str) -> ExifReport:

    try:
        if not Path(image_path).is_file():
            raise FileNotFoundError(f"The file {image_path} does not exist.")

        img = Image.open(image_path)

        exif_data = img.info.get("exif")

        if exif_data:
            exif_dict = piexif.load(exif_data)
            copyright_info = exif_dict.get(piexif.ImageIFD.Copyright)
            if copyright_info:
                if isinstance(copyright_info, bytes):
                    copyright_info = copyright_info.decode("utf-8")
                return ExifReport(
                    exif_copyright=f"{copyright_info}",
                    status="ok",
                    error_message="",
                    error_context="",
                )

        return ExifReport(
            exif_copyright="",
            status="not_found",
            error_message="No copyright information found.",
            error_context="",
        )
    
    except Exception as e:
        return ExifReport(
            exif_copyright="",
            status="error",
            error_message=str(e),
            error_context=f"Error processing image: '{image_path}'. Traceback: {traceback.format_exc()}",
        )


