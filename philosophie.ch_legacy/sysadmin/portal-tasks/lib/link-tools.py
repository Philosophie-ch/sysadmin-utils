import time
from typing import Tuple
import aiohttp
import asyncio
import csv

TIMEOUT = 1000  # Adjust for performance
CONCURRENCY = 100  # Adjust for performance
MAX_REDIRECTS = 20  # Prevent infinite loops

type TUrl = str
type TStatus = str
type TErrorType = str
type TError = str

type UrlReport = Tuple[
    TUrl,
    TStatus,
    TErrorType,
    TError
]

CSV_HEADER = ["url", "status", "error_type", "error"]

async def check_url(session, raw_url: str) -> UrlReport:
    """Check if a URL is broken, ignoring redirects"""
    try:

        url = raw_url

        if raw_url.startswith("data:") or raw_url.startswith("mailto:") or raw_url.startswith("tel:") or raw_url.startswith("javascript:") or raw_url.startswith("ftp:") or raw_url.startswith("data_link"):
            return raw_url, "Skipped", "URLScheme", ""

        elif raw_url.startswith("/"):
            url = f"https://www.philosophie.ch{raw_url}"

        elif raw_url.startswith("#"):
            return raw_url, "Skipped", "SkippedAnchor", ""

        if not url.startswith("http"):
            return raw_url, "Skipped", "URLScheme", ""

        async with session.get(url, timeout=TIMEOUT, max_redirects=MAX_REDIRECTS, allow_redirects=True) as response:

            if 400 <= response.status < 600:
                return raw_url, "NonSuccessCode", f"{response.status}", f"Code {response.status}: {response.reason}"
            return raw_url, "OK", "", ""

    except aiohttp.TooManyRedirects:
        print(f"🟠 Too many redirects: {raw_url}")
        return raw_url, "Error", "TooManyRedirects", f"Error: Too many redirects (max: {MAX_REDIRECTS})"

    except Exception as e:
        print(f"❌ Error for [[ {raw_url} ]] ::: {e.__class__.__name__}: {str(e)}")
        return raw_url, "Unhandled Error", f"{e.__class__.__name__}", f"Error: {e.__class__.__name__}: {str(e)}"


async def check_all_urls(urls):
    """Check all URLs asynchronously"""
    broken_urls = []
    connector = aiohttp.TCPConnector(limit_per_host=CONCURRENCY)
    
    async with aiohttp.ClientSession(connector=connector) as session:
        tasks = [check_url(session, url) for url in urls]
        results = await asyncio.gather(*tasks)
        broken_urls = tuple(r for r in results if r is not None)

    return broken_urls


def read_urls_from_file(file_path):
    """Read URLs from a file"""
    with open(file_path, "r", encoding="utf-8") as file:
        return {line.strip() for line in file if line.strip()}  # Keep unique URLs
        

def save_broken_urls(broken_urls, output_file):
    """Save broken URLs to a CSV file"""
    with open(output_file, "w", newline="", encoding="utf-8", errors="ignore") as file:
        writer = csv.writer(file)
        writer.writerow(CSV_HEADER)
        writer.writerows(broken_urls)


def main(
    file: str,
    output: str,
):
    start_time = time.time()
    print(f"{start_time=}")

    urls = read_urls_from_file(file)
    print(f"Checking {len(urls)} URLs...")

    broken_urls = asyncio.run(check_all_urls(urls))
    print(f"\n✅ Done! Processed {len(broken_urls)} links.")

    save_broken_urls(broken_urls, output)
    print(f"💾 Saved links to {output}")

    end_time = time.time()
    print(f"{end_time=}")
    print(f"Total time: {end_time - start_time:.2f} seconds")
    

def cli():
    import argparse

    parser = argparse.ArgumentParser(description="Check URLs for broken links")

    parser.add_argument(
        "-f",
        "--file",
        type=str,
        required=True,
        help="Path to the file containing URLs to check",
    )

    parser.add_argument(
        "-o",
        "--output",
        type=str,
        required=True,
        help="Path to the output CSV file",
    )

    args = parser.parse_args()

    return main(args.file, args.output)




if __name__ == "__main__":
    cli()