import os


def authenticate_google(json_key_filepath: str) -> None:
    os.environ["GOOGLE_APPLICATION_CREDENTIALS"] = json_key_filepath


def main(
    json_key_filepath: str,
) -> None:
    """
    Authenticate Google Cloud using a service account key file.

    Args:
        json_key_filepath (str): Path to the service account key file.
    """
    authenticate_google(json_key_filepath)


def cli() -> None:
    import argparse

    parser = argparse.ArgumentParser(description="Authenticate Google Cloud using a service account key file.")

    parser.add_argument(
        "-j",
        "--json-key-filepath",
        type=str,
        required=True,
        help="Path to the service account key file.",
    )

    args = parser.parse_args()

    main(
        json_key_filepath=args.json_key_filepath,
    )


if __name__ == "__main__":
    cli()
