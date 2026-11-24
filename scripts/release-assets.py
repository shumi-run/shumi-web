"""Record versioned GitHub Release assets and assemble the public Pages artifact."""

import argparse
import fcntl
import hashlib
from html.parser import HTMLParser
from pathlib import Path
import re
import shutil
import subprocess
import sys
from tempfile import TemporaryDirectory


ROOT = Path(__file__).resolve().parent.parent
MANIFEST = ROOT / "release-assets.tsv"
ARCHIVE_PATH = re.compile(r"(?:releases|plugins/[a-z0-9-]+)/[a-z0-9][a-z0-9._-]*\.tar\.gz")
DIGEST = re.compile(r"[0-9a-f]{64}")
RELEASE_TAG = re.compile(r"[A-Za-z0-9][A-Za-z0-9._-]*")


def asset_url(path, tag):
    if not ARCHIVE_PATH.fullmatch(path) or not RELEASE_TAG.fullmatch(tag) or tag == "latest":
        raise ValueError(f"Expected a versioned release tag and a valid archive path: {tag}, {path}")
    return f"https://github.com/shumi-run/shumi-web/releases/download/{tag}/{Path(path).name}"


def load_manifest():
    assets = {}
    for number, row in enumerate(MANIFEST.read_text().splitlines(), 1):
        fields = row.split("\t")
        if len(fields) != 3 or len(fields[2].rsplit("/", 2)) != 3:
            raise ValueError(f"Invalid entry in {MANIFEST.name} on line {number}")
        path, checksum, url = fields
        _, tag, _ = url.rsplit("/", 2)
        if not DIGEST.fullmatch(checksum) or url != asset_url(path, tag) or path in assets:
            raise ValueError(f"Invalid or duplicate entry in {MANIFEST.name} on line {number}")
        assets[path] = (checksum, url)
    return assets


def checksum(path):
    with path.open("rb") as source:
        return hashlib.file_digest(source, "sha256").hexdigest()


def record(path, tag, archive):
    url = asset_url(path, tag)
    digest = checksum(archive)
    with MANIFEST.open("a") as manifest:
        fcntl.flock(manifest, fcntl.LOCK_EX)
        existing = load_manifest().get(path)
        if existing == (digest, url):
            return
        if existing is not None:
            raise ValueError(f"Release asset is already pinned with different metadata: {path}")
        manifest.write(f"{path}\t{digest}\t{url}\n")


class CatalogDownloads(HTMLParser):
    def __init__(self):
        super().__init__()
        self.downloads = {}

    def handle_starttag(self, tag, attrs):
        attrs = dict(attrs)
        if tag == "a" and "download" in attrs and "href" in attrs:
            self.downloads[f"plugins/{attrs['href']}"] = attrs.get("data-sha256")


def check_site_metadata(assets, pointers):
    catalog = CatalogDownloads()
    catalog.feed((ROOT / "plugins/index.html").read_text())
    expected = catalog.downloads
    for pointer in pointers:
        version, digest = pointer.read_text().splitlines()
        expected[f"releases/shumi-tui-{version}-{pointer.stem}.tar.gz"] = digest
    for path, digest in expected.items():
        if path not in assets:
            raise ValueError(f"Download is missing from {MANIFEST.name}: {path}")
        if digest is not None and assets[path][0] != digest:
            raise ValueError(f"Site checksum does not match {MANIFEST.name}: {path}")


def build(output, local_assets):
    assets = load_manifest()
    pointers = sorted((ROOT / "releases").glob("*.txt"))
    check_site_metadata(assets, pointers)
    if output.exists():
        raise ValueError(f"Choose a new output directory: {output}")

    with TemporaryDirectory(dir=output.parent, prefix=".pages-") as temp:
        site = Path(temp) / "site"
        site.mkdir()
        for directory in ("plugins", "releases"):
            (site / directory).mkdir()
        for path in (
            ".nojekyll", "index.html", "styles.css", "demo.js", "install.sh",
            "plugins/index.html", "plugins/catalog.js",
        ):
            shutil.copyfile(ROOT / path, site / path)
        shutil.copytree(ROOT / "assets", site / "assets")
        for pointer in pointers:
            shutil.copyfile(pointer, site / "releases" / pointer.name)
        for path, (digest, url) in assets.items():
            destination = site / path
            destination.parent.mkdir(parents=True, exist_ok=True)
            if local_assets is None:
                subprocess.run(
                    [
                        "curl", "--fail", "--silent", "--show-error", "--location",
                        "--proto", "=https", "--proto-redir", "=https", "--retry", "3",
                        "--output", str(destination), url,
                    ],
                    check=True,
                )
            else:
                shutil.copyfile(local_assets / path, destination)
            if checksum(destination) != digest:
                raise ValueError(f"Release asset checksum mismatch: {path}")
        site.rename(output)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    build_args = commands.add_parser("build")
    build_args.add_argument("output", type=Path)
    build_args.add_argument("--local-assets", type=Path, help="Use local archives for a preview")
    record_args = commands.add_parser("record")
    record_args.add_argument("path")
    record_args.add_argument("tag")
    record_args.add_argument("archive", type=Path)
    args = parser.parse_args()
    try:
        if args.command == "build":
            build(args.output, args.local_assets)
        else:
            record(args.path, args.tag, args.archive)
    except (ValueError, OSError, subprocess.CalledProcessError) as error:
        print(f"Release assets: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
