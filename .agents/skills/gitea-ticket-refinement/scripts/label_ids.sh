#!/usr/bin/env bash
# Look up Gitea workflow-label IDs without hardcoding organization-specific values.
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: label_ids.sh <org> [label...]
       label_ids.sh --repo <owner>/<repo> [label...]

List the current IDs for state/* and next labels for a repository in one
call. For --repo OWNER/REPO where OWNER is an organization, this reads both
the org-level shared labels (state/*, next; these are almost always what you
want) and any repo-specific labels, and merges them - no separate org lookup
needed. For --repo sasu/REPO, sasu is a personal account with no org scope,
so only repo-level labels are read. Passing an organization name directly
(no --repo) lists only that org's shared labels, without merging in any
single repo's repo-specific labels.

With a single label argument, print only that numeric ID to stdout, which
is suitable for command substitution. With several label arguments, print
one "name<TAB>id" row per label instead, so the IDs stay distinguishable.
Any label that does not exist is a fatal error. If the same label name
exists at both org and repo scope, the repo-scoped ID wins, since Gitea
lets a repo-scoped label shadow an org one.

Options:
  -r, --repo OWNER/REPO  Read this repository's labels (merged with its org's
                         shared labels unless OWNER is sasu)
  -h, --help             Show this help

Environment:
  GITEA_HOST             Gitea base URL for REST fallback (default: https://gitea.sasu.org)
  GITEA_ACCESS_TOKEN     Access token for REST fallback

The tea CLI is used for repository-scoped lookups when available. Organization
labels are read from the Gitea REST API because tea has no organization-label
endpoint.
USAGE
}

fail() {
  printf 'label_ids: %s\n' "$*" >&2
  exit 1
}

repo=""
scope=""
labels=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help)
      usage
      exit 0
      ;;
    -r|--repo)
      [[ $# -ge 2 ]] || fail "$1 requires OWNER/REPO."
      [[ -z "$repo" ]] || fail "--repo may only be specified once."
      [[ -z "$scope" ]] || fail "do not provide an organization with --repo."
      repo="$2"
      shift 2
      ;;
    -*)
      fail "unknown option: $1"
      ;;
    *)
      if [[ -n "$repo" ]]; then
        labels+=("$1")
      elif [[ -z "$scope" ]]; then
        scope="$1"
      else
        labels+=("$1")
      fi
      shift
      ;;
  esac
done

command -v jq >/dev/null 2>&1 || fail "jq is required."

owner=""
if [[ -n "$repo" ]]; then
  [[ "$repo" == */* && "$repo" != /* && "$repo" != */ ]] || fail "--repo must be OWNER/REPO."
  scope="$repo"
  scope_type="repo"
  owner="${repo%%/*}"
else
  [[ -n "$scope" ]] || fail "provide an organization or --repo OWNER/REPO."
  [[ "$scope" != "sasu" ]] || fail "sasu is a personal account; use --repo sasu/REPO."
  scope_type="org"
fi

workflow_labels='["state/triage", "state/needs-info", "state/ok-for-dev", "state/in-progress", "state/needs-review", "state/needs-human", "state/needs-agent", "state/done", "next"]'

fetch_repo_labels() {
  if command -v tea >/dev/null 2>&1; then
    tea labels list --repo "$scope" --output json --limit 100
    return
  fi

  command -v curl >/dev/null 2>&1 || fail "curl is required when tea is unavailable."
  [[ -n "${GITEA_ACCESS_TOKEN:-}" ]] || fail "GITEA_ACCESS_TOKEN is required for the REST API fallback."

  local host="${GITEA_HOST:-https://gitea.sasu.org}"
  host="${host%/}"
  curl --fail --silent --show-error \
    --header "Authorization: token $GITEA_ACCESS_TOKEN" \
    "$host/api/v1/repos/$scope/labels?limit=100"
}

fetch_org_labels() {
  local org="$1"
  command -v curl >/dev/null 2>&1 || fail "curl is required for organization label lookups."
  [[ -n "${GITEA_ACCESS_TOKEN:-}" ]] || fail "GITEA_ACCESS_TOKEN is required for the REST API fallback."

  local host="${GITEA_HOST:-https://gitea.sasu.org}"
  host="${host%/}"
  curl --fail --silent --show-error \
    --header "Authorization: token $GITEA_ACCESS_TOKEN" \
    "$host/api/v1/orgs/$org/labels?limit=100"
}

if [[ "$scope_type" == "repo" ]]; then
  repo_labels_json="$(fetch_repo_labels)" || fail "could not retrieve labels for repo '$scope'."
  jq -e 'type == "array"' >/dev/null <<<"$repo_labels_json" || fail "Gitea returned invalid label data for repo '$scope'."
  # The tea CLI reports the numeric label ID as a string in "index"; the REST
  # API uses a numeric "id". Normalize to "id" so both sources merge and
  # print identically - otherwise every tea-sourced label yields a null ID.
  repo_labels_json="$(jq '[.[] | . + {id: (.id // (.index | tonumber?))}]' <<<"$repo_labels_json")" \
    || fail "could not normalize label data for repo '$scope'."
  jq -e 'all(.[]; .id != null)' >/dev/null <<<"$repo_labels_json" \
    || fail "Gitea returned labels without a usable numeric ID for repo '$scope'."

  if [[ "$owner" == "sasu" ]]; then
    labels_json="$repo_labels_json"
  else
    org_labels_json="$(fetch_org_labels "$owner")" || fail "could not retrieve labels for org '$owner'."
    jq -e 'type == "array"' >/dev/null <<<"$org_labels_json" || fail "Gitea returned invalid label data for org '$owner'."
    # Merge repo labels first (so a repo-scoped label wins on a name
    # collision with an org label of the same name), then append any org
    # labels whose name isn't already present.
    labels_json="$(jq -s '.[0] as $repo_labels | .[1] as $org_labels
      | $repo_labels + [$org_labels[] | select(.name as $n | ($repo_labels | map(.name) | index($n)) | not)]' \
      <<<"$repo_labels_json"$'\n'"$org_labels_json")"
  fi
else
  labels_json="$(fetch_org_labels "$scope")" || fail "could not retrieve labels for org '$scope'."
  jq -e 'type == "array"' >/dev/null <<<"$labels_json" || fail "Gitea returned invalid label data."
fi

if [[ ${#labels[@]} -gt 0 ]]; then
  # A single label prints just its ID, so the common case stays usable in a
  # command substitution. Several labels print "name<TAB>id" rows instead,
  # since a bare list of numbers would be ambiguous.
  for label in "${labels[@]}"; do
    id="$(jq -r --arg label "$label" 'first(.[] | select(.name == $label) | .id) // empty' <<<"$labels_json")"
    [[ -n "$id" ]] || fail "label '$label' does not exist at $scope_type scope '$scope'."
    if [[ ${#labels[@]} -eq 1 ]]; then
      printf '%s\n' "$id"
    else
      printf '%s\t%s\n' "$label" "$id"
    fi
  done
  exit 0
fi

jq -r --argjson wanted "$workflow_labels" '
  $wanted[] as $name
  | .[] | select(.name == $name)
  | "\(.name)\t\(.id)"
' <<<"$labels_json"
