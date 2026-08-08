# camilla

camilla creates a `sitemap.xml` file for a static HTML website. It can be
compiled into a standalone executable for Linux, macOS, or Windows.

## Install

Download an archive for the latest release from the
[releases page](https://github.com/sasuw/camilla/releases). Extract it and run
the `camilla` executable from a terminal. To make it available system-wide,
place it in a directory on your `PATH`, such as `/usr/local/bin` on Linux or
macOS.

## Create a sitemap

Run camilla from the root directory of the static site. The command scans that
directory recursively for files whose names end in lowercase `.html` or `.htm` and
overwrites `sitemap.xml` in the current directory.

`--baseUrl` (or `-b`) is required because sitemap locations must be absolute:

```sh
camilla --baseUrl https://example.com
```

Do not include a trailing slash in the base URL. camilla adds one before each
page path. Sitemap URLs always use `/` as their path separator, including when
camilla runs on Windows.

The output contains one `url` entry per HTML file, with its relative path and
the file's last-modified date:

```xml
<?xml version="1.0"?>
<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">
  <url>
    <loc>https://example.com/about.html</loc>
    <lastmod>2026-08-08</lastmod>
  </url>
</urlset>
```

## Create a multilingual sitemap

Use `--baseDirContainsLanguageDirs` (or `-l`) when every top-level directory in
the site is a language directory and they share the same page paths:

```text
site/
├── de/
│   └── index.html
├── en/
│   └── index.html
└── fi/
    └── index.html
```

```sh
camilla -b https://example.com -l
```

camilla treats every top-level directory as a language code. Keep assets and
other non-language directories outside this site root. It does not check that a
corresponding page exists in each language directory, so use this option only
when their page structures are identical. It adds `xhtml:link` alternate
references for language-specific pages; pages directly in the site root have no
alternates. See [Google's guidance for localized pages](https://support.google.com/webmasters/answer/189077?hl=en).

## Develop

camilla is a Dart package. Install a supported Dart SDK, then fetch dependencies
and format, analyze, and test from the repository root:

```sh
dart pub get
dart format bin lib test
dart analyze
dart test
```

Run the program from source with Dart's package runner:

```sh
dart run bin/camilla.dart -b https://example.com
```

Compile a standalone executable with:

```sh
dart compile exe bin/camilla.dart -o bin/camilla
```

For manual testing, `bin/scripts/create_test_site.sh` creates a sample static
site in `camilla_test/` below the current directory.

## Release

Add release notes for the new version to `CHANGELOG.md`, commit all intended
changes, then run the release script from a clean `master` branch:

```sh
bin/scripts/release.sh 1.0.2
```

It checks the Dart code, updates the package and executable versions, commits
and tags the release as `v1.0.2`, and pushes it to GitHub. GitHub Actions then
builds native x64 archives for Linux, macOS, and Windows and publishes them on
the GitHub release. Use `--dry-run` to validate the release metadata and Dart
code without changing Git or GitHub.

The macOS executable is not code-signed. Users may need to approve it in
Gatekeeper before first use.

## Contribute

Open an issue before starting a substantial change so it can be aligned with
the project goals. Contributions are welcome as issues, testing, or code.

## License

camilla is distributed under the MIT License. See [LICENSE](LICENSE).
