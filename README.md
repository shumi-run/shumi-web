# Shumi website

The static site serves the installer at `https://shumi.run/install.sh`, Shumi TUI bundles under `/releases/`, and plugin downloads under `/plugins/`. The archive files are GitHub Release assets. Git tracks their public paths, versioned asset URLs and SHA-256 digests in [release-assets.tsv](release-assets.tsv).

## Deploy to GitHub Pages

In the shumi-web repository, set **Settings → Pages → Build and deployment → Source** to **GitHub Actions**. Set the custom domain to `shumi.run` there. The Pages workflow runs on pushes to `main` and can also be run manually.

The workflow downloads every pinned archive from [Shumi Web Releases](https://github.com/shumi-run/shumi-web/releases) and verifies its SHA-256 before deploying. Publish the assets before merging changes to the website. Keep old manifest entries and release assets available so cached installer pointers and pinned CI downloads still work.

The release scripts and preview use Python 3.11 or later. To preview with archives staged locally, run `python3 scripts/release-assets.py build _site --local-assets .` from this checkout. Use a fresh output directory on each run. Omit `--local-assets .` to check the published GitHub downloads.

## Stage a TUI release

1. On each platform you’re releasing for, run `./scripts/build-release.sh` in the shumi-tui checkout for the release. It prints the path to the archive in `target/dist/`. Use neutral archive ownership metadata for public bundles.
2. Attach the finalized archives to a tagged release in `shumi-run/shumi-web`.
3. In shumi-web, run `sh scripts/stage-release.sh /path/to/shumi-tui-VERSION-TARGET.tar.gz RELEASE_TAG` on the exact archive uploaded. This pins the asset and updates the target’s version and SHA-256 pointer under `releases/`. The local archive copy is ignored by Git.
4. Update the homepage’s platform list when adding a platform. Commit the updated pointer and manifest together.

The installer selects the archive for the current platform. Each target has its own pointer, so shipping a release for one platform leaves the other platforms on their existing versions until their builds are ready.

## Stage a plugin release

Build the archives in the shumi-plugins checkout. Attach each per-plugin source and binary archive to a tagged release in `shumi-run/shumi-web`. Stage the exact source archive with `sh scripts/stage-plugin-release.sh /path/to/PLUGIN-VERSION-source.tar.gz RELEASE_TAG`. Stage the Linux binary with `sh scripts/stage-plugin-release.sh /path/to/PLUGIN-VERSION-linux-x86_64.tar.gz RELEASE_TAG MINIMUM_SHUMI_VERSION`.

Add the generated links to the matching card in `plugins/index.html` and commit it with the updated manifest. The binary link carries the plugin API version, the minimum core version and the SHA-256 digest. Put newer links first for the website and retain older links so Shumi TUI can select a compatible release.
