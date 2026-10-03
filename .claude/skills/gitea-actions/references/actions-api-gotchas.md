# Gitea Actions: status semantics, cancellation, and CLI coverage

Confirmed against Gitea 1.27.0 (`gitea.sasu.org`), checked against a
version-matched source checkout: `~/Projects/gitea.com/gitea/gitea-mirror`
(tag `v1.27.0-dev-153-g...`, tracks upstream `main`). Re-verify against
current source if the instance is upgraded — do not assume these routes are
stable across major versions without checking.

## Status enum

`models/actions/status.go` defines one `Status` type shared by
`ActionRun`, `ActionRunJob`, `ActionTask`, and `ActionTaskStep`:

| Value | Name        | `IsDone()` |
| ----: | ----------- | ---------- |
|     0 | `unknown`   | no         |
|     1 | `success`   | yes        |
|     2 | `failure`   | yes        |
|     3 | `cancelled` | yes        |
|     4 | `skipped`   | yes        |
|     5 | `waiting`   | no         |
|     6 | `running`   | no         |
|     7 | `blocked`   | no         |

`IsDone()` is `true` only for `success`, `failure`, `cancelled`, `skipped`.
A run/job showing `waiting`, `running`, or `blocked` is **not** done — this
matters directly for the `DELETE` run endpoint below.

Do not assume raw DB values from memory or from a different Gitea version —
confirm against this file in a version-matched checkout before treating any
status number as ground truth. A prior investigation on this instance
initially misread `3` (cancelled) and `5` (waiting/queued) backwards,
overstating a queue backlog by roughly two orders of magnitude before the
mistake was caught.

## Run status and job status are separate, and can disagree

`action_run.status` (the parent run) and each `action_run_job.status` (one
row per job in that run) are stored and updated independently. The
scheduler and the runs-list API read **job-level** status to decide whether
work is outstanding, not just the parent row.

Concretely: a database fix that only does
`UPDATE action_run SET status = <done> WHERE ...` can make the parent row
look finished while its `action_run_job` rows are still `waiting` (5) or
`blocked` (7) — the run is still genuinely stuck, and the API keeps
reporting it as queued, even though `action_run.status` says otherwise.

This exact failure happened during a real incident on this instance
(`infra2/agent-devop#27`/`#28`): a first-pass SQL update on `action_run`
only looked complete; verification caught that `action_run_job` rows for
the same runs were still stuck, because the job table is what the
scheduler and API actually key off. The correct fix used the real API
endpoint below, whose cascade cleans up both tables correctly.

**Rule of thumb:** when asked "is this run really done," check job-level
state (`action_run_job`, or the job status embedded in the API's run/job
representation), not just the run's own `status` field.

## Cancelling a queued/stuck run

There is **no `/cancel` endpoint** in Gitea 1.27.0. A `POST
.../runs/{run}/cancel` is a plausible guess (it mirrors GitHub's Actions
API) but 404s — do not conclude from this 404 alone that no cancellation
mechanism exists at all.

The real, confirmed mechanism (`routers/api/v1/repo/action.go`,
`DeleteActionRun`):

```text
DELETE /api/v1/repos/{owner}/{repo}/actions/runs/{run}
```

- Returns `204 No Content` on success.
- Returns `400` if `!run.Status.IsDone()` — i.e. the run must already be in
  `success`, `failure`, `cancelled`, or `skipped` state. It cannot force-stop
  a run that is genuinely still `waiting`/`running`/`blocked`.
- On success, its `DeleteRun` service call cascades to remove the
  corresponding `action_run_job` rows too — this is the correct single
  operation, not a two-step fix.

There is no bulk-cancel-by-repo endpoint; iterate one `DELETE` call per run
ID if clearing a backlog. Query `action_run`/the runs-list API first to get
an exact candidate set (e.g. `status=queued`) before iterating, and do a
dry run (print the IDs) before actually deleting when acting on more than a
handful.

**If a run needs clearing but isn't `IsDone()` yet** (still `waiting` at
the job level, no runner ever picks it up): there is no clean API path to
force a queued-but-unstarted run straight to a done state. Treat a direct
DB write as a last resort, and if used, update **both** `action_run.status`
and every corresponding `action_run_job.status` in the same transaction —
never the parent table alone — then re-verify via the job-level query
below before calling the cancellation done.

```sql
-- Read-only: get the exact queued/waiting backlog before acting
SELECT id, repo_id, status FROM action_run WHERE status = 5;
SELECT id, run_id, status FROM action_run_job WHERE status IN (5, 7);
```

## `tea` CLI coverage

Source: `~/Projects/gitea.com/gitea/tea`, `cmd/actions/`.

As of the checked-out version, `tea actions` has subcommands for:

- `runs` (alias `run`) — `list` (default), `view`/`show`/`get` (run detail,
  `--jobs` for the jobs table), `logs`, and `delete` (aliases `cancel`,
  `remove`, `rm`; `cmd/actions/runs/delete.go`). **`delete` and `cancel` are
  the same command** — Gitea has no separate "stop a running job" verb
  distinct from "delete the run," and both map to the identical
  `DeleteRepoActionRun` SDK call, i.e. the same
  `DELETE /api/v1/repos/{owner}/{repo}/actions/runs/{run}` route documented
  above (same `IsDone()` precondition, same 400 if the run isn't done yet).
  Prompts for confirmation unless invoked with `-y`/`--confirm`.
- `secrets` — list/create/delete.
- `variables` — list/set/delete.
- `workflows` (alias `workflow`) — **list only**
  (`cmd/actions/workflows.go`); no CLI subcommand for enable/disable or
  manual dispatch. Use the REST endpoints in the main `SKILL.md`
  (`PUT .../workflows/{workflow_id}/{disable,enable}`,
  `POST .../workflows/{workflow_id}/dispatches`) for those.

If a `tea actions` subcommand you expect doesn't exist, don't assume it's
merely restricted or requires different flags — grep the actual `cmd/actions/`
tree in the checkout to confirm before falling back to the REST API. This
exact mistake happened once already on this instance: an agent assumed no
cancel path existed at all (both an MCP tool call and a guessed
`/cancel` REST URL had failed) and fell back to a raw SQL `UPDATE`, when
the correct fix was simply the real `DELETE` route/`tea actions runs
delete` — see the incident recap above.

## Workflow file discovery

Gitea only picks up workflow files under `.gitea/workflows/` or
`.github/workflows/` with a `.yaml`/`.yml` extension (confirmed against
`docs/versioned_docs/version-1.27/usage/actions/quickstart.md` in the
`gitea.com/gitea/docs` checkout). Any other extension (e.g. renaming to
`build.yml.disabled`) is invisible to the workflow trigger scanner — a
valid, git-history-reversible way to disable a workflow without deleting
it. The real per-workflow API toggle
(`PUT .../actions/workflows/{workflow_id}/{disable,enable}`) is generally
preferable going forward since it needs no file change at all; see the main
`SKILL.md` for the exact call.

## Artifact listing returns nothing for v3-protocol uploads

Both artifact-listing endpoints report `"total_count": 0` for artifacts
uploaded by `upload-artifact@v3`, even when the upload succeeded, the
artifact is `upload-confirmed`, unexpired, and downloadable:

```text
GET /api/v1/repos/{owner}/{repo}/actions/runs/{run}/artifacts
GET /api/v1/repos/{owner}/{repo}/actions/artifacts
```

An empty listing is therefore **not** evidence that a workflow failed to
publish. Do not report a packaging or publication failure on this basis.

**Why.** Both handlers hardcode `FinalizedArtifactsV4: true`
(`routers/api/v1/repo/action.go`, `GetArtifactsOfRun` and `GetArtifacts`).
In `FindArtifactsOptions.ToConds()` (`models/actions/artifact.go`) that flag
adds two conditions:

```go
cond = cond.And(builder.Eq{"status": ArtifactStatusUploadConfirmed}.Or(builder.Eq{"status": ArtifactStatusExpired}))
cond = cond.And(builder.Like{"content_encoding", "%/%"})
```

The second one is the filter that bites. Per the field comment on
`ActionArtifact.ContentEncodingOrType`, `content_encoding` holds:

- empty or null — legacy (v3) uncompressed content
- `gzip` — v3 gzip-compressed content
- a MIME type such as `application/zip` — v4

Only a MIME type contains `/`, so `LIKE '%/%'` matches v4 uploads only.
Every v3 artifact is excluded from both listings by construction. This is a
filter, not a bug in the upload, and no query parameter turns it off.

This matters here because Gitea only implements the v3 artifact protocol:
`upload-artifact@v4` aborts against Gitea with `GHESNotSupportedError`, so
repositories on this instance deliberately pin the v3 line — which is
exactly the case the listing API cannot see.

**Confirming an upload actually happened.** Read the job log for the
upload step; a successful v3 upload prints:

```text
Artifact <name> has been successfully uploaded!
```

**Downloading a v3 artifact.** Use the _web_ route, which takes the
artifact **name** rather than a numeric id, and works for v3 artifacts
because it filters on status only
(`ListUploadedArtifactsMetaByRunAttempt`, no `content_encoding` condition):

```text
GET /{owner}/{repo}/actions/runs/{run}/artifacts/{artifact_name}
```

Registered at `routers/web/web.go:1560` (`actions.ArtifactsDownloadView`).
Note the path has no `/api/v1` prefix. Authenticate with the usual
`Authorization: token <token>` header; it returns `200` with
`application/zip`:

```sh
curl -sS -o artifact.zip \
  -H "Authorization: token $TOKEN" \
  "https://gitea.sasu.org/{owner}/{repo}/actions/runs/{run}/artifacts/{name}"
```

Verified on `wortx/website` run 3939: the v1 endpoints returned
`total_count: 0` while this route returned a 155,934-byte zip containing the
expected package and its `.sha256` sidecar. The same run's full-gate
predecessor (run 3938) also listed zero artifacts despite publishing, which
is a useful control — if a known-good run also lists zero, the listing is
the problem, not the run.

The numeric-id endpoints (`GET/DELETE .../actions/artifacts/{artifact_id}`,
`.../{artifact_id}/zip`) are not usable for v3 artifacts either, since the
only way to discover an id is the listing that omits them.
