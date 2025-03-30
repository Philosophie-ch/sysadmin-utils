import time
from typing import Tuple
import aiohttp
import asyncio
import csv

TIMEOUT = 1000  # Adjust for performance
CONCURRENCY = 100  # Adjust for performance
MAX_REDIRECTS = 20  # Prevent infinite loops

type TRawUrl = str
type TScheme = str
type TUrl = str
type TStatus = str
type TErrorType = str
type TError = str

type UrlReport = Tuple[TRawUrl, TScheme, TUrl, TStatus, TErrorType, TError]

CSV_HEADER = ["url", "scheme", "url_stripped", "status", "error_type", "error"]


async def check_url(session, raw_url: str, check_philch: bool) -> UrlReport:
    """Check if a URL is broken, ignoring redirects"""
    try:

        url = raw_url

        if (
            raw_url.startswith("data:")
            or raw_url.startswith("mailto:")
            or raw_url.startswith("tel:")
            or raw_url.startswith("javascript:")
            or raw_url.startswith("ftp:")
            or raw_url.startswith("file:")
        ):
            scheme_url = raw_url.split(":")
            return raw_url, scheme_url[0], scheme_url[1], "Skipped", "Scheme", ""

        elif raw_url.startswith("data_link"):
            return raw_url, "data", "", "Skipped", "DataLink", ""

        elif raw_url.startswith("/"):
            url = f"https://www.philosophie.ch{raw_url}"
            if url.startswith("https://www.philosophie.ch/profil/"):
                return raw_url, "", url, "Skipped", "PhilosophieCH-Profile", "To check against existing profiles"
            elif not url.startswith("https://www.philosophie.ch/profil/") and not check_philch:
                return (
                    raw_url,
                    "",
                    url,
                    "Skipped",
                    "PhilosophieCH",
                    "To check independently, else we get 'too many requests'",
                )

        elif "philosophie.ch" in raw_url and not check_philch:
            return (
                raw_url,
                "",
                "",
                "Skipped",
                "PhilosophieCH",
                "To check independently, else we get 'too many requests'",
            )

        elif raw_url.startswith("#"):
            return raw_url, "", "", "Skipped", "Anchor", ""

        if not url.startswith("http"):
            return raw_url, "Unknown", "", "Skipped", "UnknownScheme", ""

        async with session.get(url, timeout=TIMEOUT, max_redirects=MAX_REDIRECTS, allow_redirects=True) as response:

            if 400 <= response.status < 600:
                return (
                    raw_url,
                    "",
                    "",
                    "NonSuccessCode",
                    f"{response.status}",
                    f"Code {response.status}: {response.reason}",
                )
            return raw_url, "", "", "OK", "", ""

    except aiohttp.TooManyRedirects:
        print(f"🟠 Too many redirects: {raw_url}")
        return raw_url, "", "", "Error", "TooManyRedirects", f"Error: Too many redirects (max: {MAX_REDIRECTS})"

    except Exception as e:
        print(f"❌ Error for [[ {raw_url} ]] ::: {e.__class__.__name__}: {str(e)}")
        return raw_url, "", "", "Unhandled Error", f"{e.__class__.__name__}", f"Error: {e.__class__.__name__}: {str(e)}"


async def check_all_urls(urls, check_philch, throttle):
    """Check all URLs asynchronously"""
    broken_urls = []
    connector = aiohttp.TCPConnector(limit_per_host=CONCURRENCY)

    if not check_philch:
        async with aiohttp.ClientSession(connector=connector) as session:
            tasks = [check_url(session, url) for url in urls]
            results = await asyncio.gather(*tasks)
            broken_urls = tuple(r for r in results if r is not None)
    else:
        # throttle requests to avoid "too many requests" error
        async with aiohttp.ClientSession(connector=connector) as session:
            for url in urls:
                report = await check_url(session, url, check_philch)
                broken_urls.append(report)
                await asyncio.sleep(throttle)

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


def main(file: str, output: str, check_philch: bool, throttle: float):
    start_time = time.time()
    print(f"{start_time=}")

    urls = read_urls_from_file(file)
    print(f"Checking {len(urls)} URLs...")

    broken_urls = asyncio.run(check_all_urls(urls, check_philch, throttle))
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

    parser.add_argument(
        "-p",
        "--philch",
        required=False,
        default=False,
        help="Check only philosophie.ch URLs",
    )

    parser.add_argument(
        "-t",
        "--throttle",
        required=False,
        default=0.1,
        help="Throttle requests to avoid 'too many requests' error, when checking philosophie.ch URLs",
    )

    args = parser.parse_args()

    return main(file=args.file, output=args.output, check_philch=args.philch, throttle=args.throttle)


if __name__ == "__main__":
    cli()
