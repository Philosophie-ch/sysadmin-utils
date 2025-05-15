import csv
from io import TextIOWrapper
from pathlib import Path
import traceback
from typing import Any, Dict, Generator, Literal, Tuple
from pydantic import BaseModel, field_validator
from copyright.image_hashing import (
    COMPOSITE_HASH_LENGTH,
    KnownImageComparison,
)

HASHES_SEPARATOR = ", "


###
# CopyrightedImage
###

class CopyrightedImage(BaseModel):
    id: str
    hash: str
    original_name: str
    link: str

    @field_validator("hash")
    def validate_hash_separator_count(cls, v: str) -> str:
        expected = COMPOSITE_HASH_LENGTH - 1
        actual = v.count(HASHES_SEPARATOR)
        if actual != expected:
            raise ValueError(
                f"'hash' must contain exactly {expected} occurences of [[ {HASHES_SEPARATOR} ]], got {actual}"
            )

        return v

COPYRIGHTED_IMAGE_FIELDS = list(CopyrightedImage.model_fields.keys())

def parse_copyrighted_image(raw_obj: Dict[str | Any, str | Any]) -> CopyrightedImage:
    parsed_id = f"{raw_obj.get('id', '<unknown>')}"
    parsed_hash = f"{raw_obj.get('hash', '')}"
    parsed_original_name = f"{raw_obj.get('original_name', '')}"
    parsed_link = f"{raw_obj.get('link', '')}"

    if parsed_hash == "":
        raise ValueError(f"Hash is empty for image with id: {parsed_id}")

    obj = {
        "id": parsed_id,
        "hash": parsed_hash,
        "original_name": parsed_original_name,
        "link": parsed_link,
    }
    return CopyrightedImage.model_validate(obj)


def _read_known_copyrighted_images_from_csv(file: TextIOWrapper) -> Tuple[Tuple[CopyrightedImage, ...], int]:
    d = csv.DictReader(file)

    headers = d.fieldnames
    if headers is None:
        raise ValueError("CSV file has no headers")

    headers_list = [header for header in headers]

    if headers_list != COPYRIGHTED_IMAGE_FIELDS:
        raise ValueError(
            f"CSV file headers do not match expected fields, expected, in order {COPYRIGHTED_IMAGE_FIELDS}, got {headers_list}"
        )

    amount_of_rows = sum(1 for _ in d)
    images = tuple(
        parse_copyrighted_image(row)
        for row in d
    )

    return images, amount_of_rows
    

def read_known_copyrighted_images(file_path: str) -> Tuple[Tuple[CopyrightedImage, ...], int]:

    path = Path(file_path)
    if not path.exists():
        raise FileNotFoundError(f"File not found: {file_path}")

    extension = path.suffix

    match extension:
        case ".csv":
            with path.open("r") as file:
                return _read_known_copyrighted_images_from_csv(file)

        case _:
            raise ValueError(f"Unsupported file format: {extension}")


###
# ImageCompared
###

type TRequest = Literal["", "COMPUTE HASH", "COMPARE"]
type TStatus = Literal["", "not started", "processing", "success", "error", "unhandled error"]

class ImageCompared(BaseModel):
    id: str
    request: TRequest
    asset_path: str
    hash: str
    copyright_comparisons: str
    status: TStatus
    message: str
    traceback: str
    object_dump: str

    @field_validator("hash")
    def validate_hash_separator_count(cls, v: str) -> str:
        if v is "":
            return v
        expected = COMPOSITE_HASH_LENGTH - 1
        actual = v.count(HASHES_SEPARATOR)
        if actual != expected:
            raise ValueError(
                f"'hash' must contain exactly {expected} occurences of [[ {HASHES_SEPARATOR} ]], got {actual}"
            )
        return v

IMAGE_COMPARED_FIELDS = list(ImageCompared.model_fields.keys())


def parse_image_metadata(raw_obj: Dict[str | Any, str | Any]) -> ImageCompared:

    try:
        parsed_id = f"{raw_obj.get("id", "<unknown>")}"
        parsed_request = f"{raw_obj.get("request", "")}"
        parsed_asset_path = f"{raw_obj.get("asset_path", "")}"
        parsed_hash = f"{raw_obj.get("hash", "")}"

        if parsed_asset_path == "":
            raise ValueError(f"Asset path is empty for image with id: {parsed_id}")

        obj = {
            "id": parsed_id,
            "request": parsed_request,
            "asset_path": parsed_asset_path,
            "hash": parsed_hash,
            "copyright_comparisons": {},
            "status": "not started",
            "message": "",
            "traceback": "",
            "object_dump": "",
        }
        return ImageCompared.model_validate(obj)
    
    except Exception as e:
        parsed_id = f"{obj.get("id", "<unknown>")}"
        return ImageCompared(
            id = parsed_id,
            request = "",
            asset_path = "",
            hash = "",
            copyright_comparisons="",
            status = "error",
            message = f"Error parsing image metadata: {e}",
            traceback = str(traceback.format_exc()),
            object_dump = str(obj),
        )
            

def _read_image_metadata_from_csv(file: TextIOWrapper) -> Tuple[Generator[ImageCompared, None, None], int]:

    d = csv.DictReader(file)

    headers = d.fieldnames
    if headers is None:
        raise ValueError("CSV file has no headers")

    headers_list = [header for header in headers]

    if headers_list != IMAGE_COMPARED_FIELDS:
        raise ValueError(
            f"CSV file headers do not match expected fields, expected, in order {IMAGE_COMPARED_FIELDS}, got {headers_list}"
        )

    amount_of_rows = sum(1 for _ in d)
    images = (
            parse_image_metadata(row)
            for row in d
    )

    return images, amount_of_rows
          

def read_image_metadata(file_path: str) -> Tuple[Generator[ImageCompared, None, None], int]:
    path = Path(file_path)
    if not path.exists():
        raise FileNotFoundError(f"File not found: {file_path}")

    extension = path.suffix

    match extension:
        case ".csv":
            with path.open("r") as file:
                return _read_image_metadata_from_csv(file)

        case _:
            raise ValueError(f"Unsupported file format: {extension}")


