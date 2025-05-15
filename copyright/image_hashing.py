from PIL import Image
import imagehash
from decimal import Decimal
from typing import Tuple, Literal, Dict, NamedTuple
import inspect


def fname() -> str:
    f = inspect.currentframe()
    if f is None:
        return "<unknown function>"

    f_back = f.f_back
    if f_back is None:
        return "<unknown function>"

    return f_back.f_code.co_name


CompositeHash = Tuple[str, ...]
type TCompositeHash = CompositeHash

HASH_FUNCTIONS = (imagehash.average_hash, imagehash.phash, imagehash.dhash, imagehash.whash)

COMPOSITE_HASH_LENGTH = len(HASH_FUNCTIONS)


def compute_composite_hash(image_path: str) -> TCompositeHash:
    img = Image.open(image_path)
    hashes = tuple(f"{f(img)}" for f in HASH_FUNCTIONS)

    return hashes


def serialize_hash(hash: TCompositeHash) -> str:
    return ", ".join(hash)


def deserialize_hash(hash_str: str) -> TCompositeHash:
    return tuple(hash_str.split(", "))


def _decode_single_hash(hash_str: str) -> imagehash.ImageHash:
    if not hash_str:
        raise ValueError(f"{__name__}::Empty hash string provided")
    try:
        return imagehash.hex_to_hash(hash_str)
    except Exception as e:
        raise e.__class__(
            f"{fname()}::Unexpected '{e.__class__.__name__}' while decoding hash string '{hash_str}': {e}"
        ) from e


def _single_hash_difference(hash1: str, hash2: str) -> Decimal:
    h1 = _decode_single_hash(hash1)
    h2 = _decode_single_hash(hash2)
    diff = h1 - h2
    return Decimal(diff)


def hash_difference(hash1: TCompositeHash, hash2: TCompositeHash) -> Decimal:
    if not hash1 or not hash2:
        raise ValueError(f"{fname()}::At least one empty hash string provided: '{hash1}', '{hash2}'")

    if len(hash1) != COMPOSITE_HASH_LENGTH or len(hash2) != COMPOSITE_HASH_LENGTH:
        raise ValueError(
            f"{fname()}::At least one invalid composite hash string provided, expected {COMPOSITE_HASH_LENGTH} serialized hashes, got {len(hash1)} and {len(hash2)}"
        )

    diff = (_single_hash_difference(h1, h2) for h1, h2 in zip(hash1, hash2))
    avg_diff = Decimal(sum(diff)) / Decimal(len(hash1))

    return avg_diff


type THashComparison = Literal["identical", "similar", "different"]


def hash_categorization(
    hash1: TCompositeHash, hash2: TCompositeHash, identity_threshold: int, similarity_threshold: int
) -> THashComparison:

    diff = hash_difference(hash1, hash2)

    result: THashComparison

    if diff <= identity_threshold:
        result = "identical"
    elif diff <= similarity_threshold:
        result = "similar"
    else:
        result = "different"

    return result


class KnownImage(NamedTuple):
    id: str
    hash: TCompositeHash


type KnownImageComparison = Dict[str, THashComparison]  # image id  # comparison result


def all_hash_categorizations(
    source_image_path: str,
    known_image_hashes: Tuple[KnownImage],
    identity_threshold: int,
    similarity_threshold: int,
) -> KnownImageComparison:
    """
    Compare a source image hash with a list of known image hashes and return the comparison results.

    :param source_image_path: Path to the source image.
    :param known_image_hashes: List of known image hashes.
    :param identity_threshold: Threshold for identical images.
    :param similarity_threshold: Threshold for similar images.
    :param lenght: Number of hashes in the composite hash.
    :return: Dictionary with image IDs as keys and comparison results as values.
    """

    source_hash = compute_composite_hash(source_image_path)

    result = {
        img.id: hash_categorization(source_hash, img.hash, identity_threshold, similarity_threshold)
        for img in known_image_hashes
    }

    return result


def filter_hash_categorizations(
    hash_categorizations: KnownImageComparison, filter_values: Tuple[THashComparison, ...]
) -> KnownImageComparison:
    """
    Filter the hash categorizations based on the provided filter values.

    :param hash_categorizations: Dictionary with image IDs as keys and comparison results as values.
    :param filter_values: Tuple of filter values to include in the result.
    :return: Filtered dictionary with image IDs as keys and comparison results as values.
    """

    return {img_id: result for img_id, result in hash_categorizations.items() if result in filter_values}


def serialize_hash_categorizations(
    hash_categorizations: KnownImageComparison,
) -> str:
    """
    Serialize the hash categorizations to a string.
    :param hash_categorizations: Dictionary with image IDs as keys and comparison results as values.
    :return: Serialized string.
    """
    return ", ".join(f"[ {img_id}: {result} ]" for img_id, result in hash_categorizations.items())
