from dataclasses import dataclass
from typing import Literal, TypedDict


type TStatus = Literal[
    "",
    "ok",
    "not_found",
    "error",
]


@dataclass(frozen=True, slots=True)
class ExifReport:
    exif_copyright: str
    status: TStatus
    error_message: str
    error_context: str


@dataclass(frozen=True, slots=True)
class ImageReport:
    image_name: str
    image_path: str
    exif_status: TStatus
    exif_copyright: str
    exif_error_message: str
    exif_error_context: str
    status: TStatus
    error_message: str
    error_context: str

