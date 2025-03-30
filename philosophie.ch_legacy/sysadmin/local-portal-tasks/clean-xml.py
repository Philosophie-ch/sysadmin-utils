import re


def clean_html(dirty_html: str) -> str:
    """
    Clean HTML content by removing MS Office conditional comments and XML tags.
    """
    # Remove MS Office conditional comments (e.g., <!--[if gte mso 9]> ... <![endif]-->)
    cleaned = re.sub(r'<!--\s*\[if.*?<!\[endif\]\s*-->', '', dirty_html, flags=re.DOTALL)

    # Remove any <xml>...</xml> blocks
    cleaned = re.sub(r'<xml>.*?</xml>', '', cleaned, flags=re.DOTALL)

    # Remove tags that use a namespace (e.g., <o:OfficeDocumentSettings>, <w:WordDocument>, etc.)
    cleaned = re.sub(r'</?\w+:\w+[^>]*>', '', cleaned)

    # Optionally, remove extra whitespace (if desired)
    cleaned = re.sub(r'\s+', ' ', cleaned)

    return cleaned.strip()


def main(input_filename: str, output_filename: str) -> None:
    """
    Main function to read a dirty HTML file, clean it, and write the cleaned content to a new file.
    """
    with open(input_filename, 'r', encoding='utf-8') as file:
        dirty_html = file.read()

    cleaned_html = clean_html(dirty_html)

    with open(output_filename, 'w', encoding='utf-8') as file:
        file.write(cleaned_html)

    print(f"Cleaned HTML saved to {output_filename}")


def cli() -> None:
    import argparse

    parser = argparse.ArgumentParser(description="Clean HTML files by removing MS Office comments and XML tags.")
    parser.add_argument('-i', '--input', type=str, required=True, help="Input file to clean.")
    parser.add_argument('-o', '--output', type=str, required=True, help="Output file to save cleaned HTML.")

    args = parser.parse_args()

    main(args.input, args.output)


if __name__ == "__main__":
    cli()
