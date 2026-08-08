# Project Instructions

## Project overview

camilla is a Dart command-line program that recursively scans a static website
for lowercase `.html` files and writes a `sitemap.xml`. It supports a
top-level-directory multilingual layout and can be compiled as a standalone
executable.

## Repository structure

```text
bin/camilla.dart              # CLI entry point and sitemap generation
bin/scripts/create_test_site.sh # Manual-test fixture generator
lib/fileHandler.dart           # Filesystem traversal and relative paths
test/camilla_test.dart         # Dart test suite
deploy/deployLocal.sh          # Local build and install helper
```

## Development workflow

Use the Dart SDK and run commands from the repository root:

```sh
dart pub get
dart format bin lib test
dart analyze
dart test
```

Run from source with `dart run bin/camilla.dart -b https://example.com`.
Compile a standalone executable with
`dart compile exe bin/camilla.dart -o bin/camilla`.

`dart analyze` currently reports pre-existing findings: its configuration still
references the removed `pedantic` package, and the CLI and test contain two
warnings. Do not treat those as introduced by unrelated changes; report any new
findings separately.

## Code conventions

- The package declares Dart SDK `>=2.12.0`; preserve null-safe Dart code.
- Use `dart format` for changed Dart files.
- Preserve established names such as `fileHandler.dart` and existing CLI option
  spellings: `--baseUrl`/`-b`, `--baseDirContainsLanguageDirs`/`-l`, and
  `--version`/`-v`.
- Keep filesystem behaviour explicit: only lowercase `.html` files are
  included, and multilingual mode treats every top-level directory as a
  language directory.

## Agent guidance

- Edit `.agent-docs/template.md`, not generated instruction files. Deploy the
  template with `adm docs deploy .` when the instruction files must be updated.
- Run the relevant Dart formatter, analyzer, and tests after non-trivial
  changes.
- Update `README.md` when command-line behaviour, supported layouts, or build
  commands change.
