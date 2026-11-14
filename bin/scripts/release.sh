#!/usr/bin/env bash

# Prepare and publish a Camilla release through GitHub Actions.
set -euo pipefail

readonly repository='sasuw/camilla'
readonly release_branch='master'

dry_run=false

usage() {
  cat <<'EOF'
Usage: bin/scripts/release.sh [--dry-run] VERSION

Prepares VERSION and publishes it through the GitHub Actions release workflow.
VERSION must be a semantic version without a leading "v", for example 1.0.2.

Before a release, add the release notes for the new version to CHANGELOG.md,
commit all other release content, and start from a clean working tree on the
master branch. The script updates the package and executable versions, commits
and tags the result, and pushes the tag. GitHub Actions builds the native x64
Linux, macOS, and Windows archives and attaches them to the GitHub release.

Options:
  -n, --dry-run  Check code and release metadata locally. Temporarily bumps
                  versions to verify the tagged source, then restores them;
                  does not commit, tag, or push.
  -h, --help     Show this help text.
EOF
}

die() {
  printf 'Error: %s\n' "$*" >&2
  exit 1
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || die "Required command not found: $1"
}

while (($# > 0)); do
  case "$1" in
    -n|--dry-run)
      dry_run=true
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    --)
      shift
      break
      ;;
    -*)
      die "Unknown option: $1"
      ;;
    *)
      break
      ;;
  esac
  shift
done

(($# == 1)) || {
  usage >&2
  exit 1
}

version="$1"
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.-]+)?(\+[0-9A-Za-z.-]+)?$ ]] || \
  die 'VERSION must be a semantic version without a leading v.'

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repository_dir="$(cd -- "$script_dir/../.." && pwd)"
cd "$repository_dir"

for command in dart gh git yq; do
  require_command "$command"
done

[[ "$(git rev-parse --show-toplevel)" == "$repository_dir" ]] || \
  die 'Run the script from the camilla repository.'

if ! "$dry_run"; then
  [[ "$(git branch --show-current)" == "$release_branch" ]] || \
    die "Releases must be made from the $release_branch branch."

  origin_push_url="$(git remote get-url --push origin)"
  origin_normalized="${origin_push_url%.git}"
  case "$origin_normalized" in
    git@github.com:sasuw/camilla|https://github.com/sasuw/camilla|ssh://git@github.com/sasuw/camilla)
      ;;
    *)
      die "origin must push to github.com/$repository, not $origin_push_url"
      ;;
  esac
fi

[[ -z "$(git status --porcelain)" ]] || \
  die 'The working tree must be clean before preparing a release.'

current_version="$(yq -r '.version' pubspec.yaml)"
[[ "$current_version" != 'null' && -n "$current_version" ]] || \
  die 'Could not read version from pubspec.yaml.'
[[ "$current_version" != "$version" ]] || \
  die "pubspec.yaml already has version $version."

notes_file="$(mktemp)"
pubspec_backup="$(mktemp)"
camilla_backup="$(mktemp)"
restore_files=false
cleanup() {
  rm -f "$notes_file"
  if "$restore_files"; then
    cp "$pubspec_backup" pubspec.yaml
    cp "$camilla_backup" bin/camilla.dart
  fi
  rm -f "$pubspec_backup" "$camilla_backup"
}
trap cleanup EXIT

cp pubspec.yaml "$pubspec_backup"
cp bin/camilla.dart "$camilla_backup"

if ! awk -v version="$version" '
  found && /^## / {
    exit
  }
  $0 ~ "^## " version "([,[:space:]]|$)" {
    found = 1
  }
  found {
    if ($0 == "") {
      blank_lines++
      next
    }
    while (blank_lines > 0) {
      print ""
      blank_lines--
    }
    print
  }
  END {
    exit !found
  }
' CHANGELOG.md > "$notes_file"; then
  die "CHANGELOG.md needs a heading for version $version."
fi

dart pub get
dart format --set-exit-if-changed bin lib test
dart analyze
dart test
git diff --quiet || die 'Release verification modified tracked files.'

if ! "$dry_run"; then
  git fetch --quiet origin "$release_branch" --tags
  [[ "$(git rev-parse HEAD)" == "$(git rev-parse "origin/$release_branch")" ]] || \
    die "Local $release_branch is not synchronized with origin/$release_branch."
  git show-ref --verify --quiet "refs/tags/v$version" && die "Tag v$version already exists."
  gh release view "v$version" --repo "$repository" >/dev/null 2>&1 && \
    die "GitHub release v$version already exists."
fi

restore_files=true
perl -0pi -e "s/^version: .*\$/version: $version/m" pubspec.yaml
perl -0pi -e "s/(defaultValue: ')[^']+(')/\${1}$version\${2}/" bin/camilla.dart
grep -Fq "defaultValue: '$version'" bin/camilla.dart || \
  die 'Could not update the executable version.'
dart pub get
dart format --set-exit-if-changed bin lib test
dart analyze
dart test
git diff --check

if "$dry_run"; then
  printf 'Dry run complete: no tracked files, tags, or GitHub releases were changed.\n'
  exit 0
fi

restore_files=false
git add pubspec.yaml bin/camilla.dart
git commit -m "Prepare release v$version"
git push origin "HEAD:refs/heads/$release_branch"
git tag -a "v$version" -m "Release v$version"
git push origin "refs/tags/v$version"

printf 'Pushed v%s. GitHub Actions is building and publishing the release.\n' "$version"
printf 'Monitor it at https://github.com/%s/actions\n' "$repository"
