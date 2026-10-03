---
name: gitea-actions
description: "Inspect, manage, and administer Gitea Actions on gitea.sasu.org — workflow discovery and disabling, run/job status semantics, cancelling stuck runs, tea CLI coverage, and act_runner registration and deployment — and wait for a CI run on gitea.sasu.org or forgejo.sasu.org with a probe that fails loudly. Use when working with Gitea Actions workflows, runs, jobs, or act_runner instances, when asked to deploy/administer a new runner, or when waiting for, watching, or polling a Gitea or Forgejo Actions run after a push or PR."
compatibility: "Confirmed against Gitea 1.27.0 (gitea.sasu.org). Route/behavior claims here were checked against a version-matched source checkout (gitea.com/gitea/gitea-mirror, tag v1.27.0-dev-153-g...); re-verify against current source if the instance is upgraded. Only references/waiting-for-a-run.md covers Forgejo: its runs-list facts were checked against Forgejo 15.0.9 (forgejo.sasu.org) and Gitea 1.27.3 on 2026-10-03. The rest of this skill makes no Forgejo claims."
---

# Gitea Actions

Work with Gitea Actions on `gitea.sasu.org`: inspecting workflows, runs, and
jobs; disabling dead workflows; cancelling stuck runs; and registering or
administering `act_runner` instances. Several behaviors here are not obvious
from the API surface alone — this skill exists so the next agent doesn't have
to rediscover them by trial and error.

## When to Use

- Inspect workflow files, runs, or jobs for a repository
- Confirm whether a run actually published a build artifact, or download one
- Disable a workflow without deleting it (dead/inherited CI, forks)
- Diagnose a run or job stuck in `queued`/`waiting`
- Wait for the run a push or PR triggered, on Gitea or Forgejo, and report
  its result
- Cancel a stuck run, individually or in bulk
- Check whether an `act_runner` is registered and online for a repo/org/user
- Register a new `act_runner`, rotate its token, or deploy one via Ansible
- Decide whether behavior is really undocumented/unsupported, or just
  unverified — and how to check version-matched source instead of guessing

## Tools, in order of preference

1. Gitea MCP server (`mcp__gitea__actions_run_read`, `actions_run_write`,
   `actions_config_read`, `actions_config_write`, and the general
   `get_repository_tree`/`get_file_contents` tools for workflow files).
   **Caveat:** `actions_run_write`'s `cancel_run` method has been observed to
   error against this instance (Gitea 1.27.0 has no `POST .../cancel` route —
   see below on terminology). Don't trust an MCP tool's advertised method
   name as proof the underlying server route exists; verify or fall back to
   `tea`/REST. See `references/actions-api-gotchas.md`.
2. `tea` CLI: `tea actions runs delete <run-id>` (aliased `cancel`/`remove`/`rm`)
   wraps the same `DELETE .../actions/runs/{run}` endpoint as the REST call
   below — usable and confirmed present in the current `tea` checkout.
3. Gitea REST API via `curl` as a fallback, or when scripting bulk
   operations `tea` doesn't batch for you.

**Terminology note:** Gitea has no separate "cancel a running job" concept
distinct from "delete a run" — `tea`'s `cancel` alias for `runs delete` and
the REST `DELETE .../actions/runs/{run}` endpoint are the same operation.
Both still require the run to already be `Status.IsDone()` (see Common
Workflow 3 below); neither can force-stop a genuinely in-progress run.

Read-only inspection needs no special authorization. Cancelling runs, editing
workflow enable/disable state, or touching `act_runner` registration/tokens
follows this project's normal confirm-before-hard-to-reverse-actions rule —
none of these are silently reversible in the way a local file edit is.

## Common Workflows

### 1) Find and disable a workflow without deleting it

Gitea only picks up `.yaml`/`.yml` files under `.gitea/workflows/` or
`.github/workflows/`. Renaming a file to a non-`.yml`/`.yaml` suffix (e.g.
`build.yml.disabled`) is a git-history-reversible way to stop it firing,
without deleting it — the convention already used in this instance's forked
repos.

```bash
# List workflow files in a repo's default branch
# (via MCP get_repository_tree, or:)
curl -s -H "Authorization: token ${TOKEN}" \
  "https://gitea.sasu.org/api/v1/repos/{owner}/{repo}/contents/.gitea/workflows"
```

Prefer the real per-workflow toggle going forward instead of the rename
trick, since it doesn't touch the file at all:

```bash
curl -X PUT -H "Authorization: token ${TOKEN}" \
  "https://gitea.sasu.org/api/v1/repos/{owner}/{repo}/actions/workflows/{workflow_id}/disable"
# .../enable to re-enable
```

### 2) Check whether a run is actually done

`action_run.status` (the parent run) and each `action_run_job.status` (per
job) are tracked separately and **can disagree**. The scheduler and the
runs-list API key off job-level status, not the parent row — a run that
"looks" cancelled or done at the parent level can still have jobs sitting in
`waiting`/`blocked`. See `references/actions-api-gotchas.md` for the full
status enum and a worked incident where this exact mismatch caused a
supposedly-cleared queue to still be stuck.

```bash
curl -s -H "Authorization: token ${TOKEN}" \
  "https://gitea.sasu.org/api/v1/repos/{owner}/{repo}/actions/runs?status=queued" | jq '.total_count'
```

### 3) Cancel ("delete") a stuck/queued run

In Gitea, "cancel a run" and "delete a run" are the same operation — there
is no `POST .../cancel` route. The real mechanism:

```bash
# via tea (asks for confirmation unless -y/--confirm):
tea actions runs delete <run-id> --repo owner/repo -y
# 'tea actions runs cancel'/'remove'/'rm' are aliases for the same command

# via REST directly:
curl -X DELETE -H "Authorization: token ${TOKEN}" \
  "https://gitea.sasu.org/api/v1/repos/{owner}/{repo}/actions/runs/{run}"
# 204 on success; 400 if the run isn't yet Status.IsDone()
```

Both require the run to already satisfy `IsDone()` (success, failure,
cancelled, or skipped) — they 400 on a genuinely still-queued/running run;
neither can force-stop an in-progress job. There is no bulk-cancel-by-repo
endpoint or `tea` batch mode; script a per-run-ID loop if clearing a
backlog. See `references/actions-api-gotchas.md` for what to do when a run
is stuck queued at the job level and won't satisfy `IsDone()` on its own.

### 4) Check runner registration and diagnose "queued forever"

A run stuck permanently in `queued` with zero registered runners for its
owner scope is the most common root cause of a stuck queue — check this
before assuming a scheduler bug.

```bash
# List runners registered for a repo/org/user scope
curl -s -H "Authorization: token ${TOKEN}" \
  "https://gitea.sasu.org/api/v1/repos/{owner}/{repo}/actions/runners" | jq
curl -s -H "Authorization: token ${TOKEN}" \
  "https://gitea.sasu.org/api/v1/orgs/{org}/actions/runners" | jq
```

Also check the workflow's `runs-on` label actually matches a label a live
runner advertises — a runner registered under a custom label (e.g.
`gitea-actions-group-b`) never picks up jobs requesting `ubuntu-latest`, and
vice versa. See `references/act-runner-deployment.md` for the deployed
runner topology on this instance and how to register a new one.

### 5) Confirm a workflow published an artifact

The v1 artifact-listing endpoints return `"total_count": 0` for anything
uploaded by `upload-artifact@v3`, which is the only protocol Gitea
implements. An empty listing is not a publication failure — do not report
one on that basis.

```bash
# Misleading: returns total_count 0 even for a confirmed v3 upload
curl -s -H "Authorization: token $TOKEN" \
  "https://gitea.sasu.org/api/v1/repos/$OWNER/$REPO/actions/runs/$RUN/artifacts"

# Evidence the upload happened: the job log's upload step
# "Artifact <name> has been successfully uploaded!"

# Download it — WEB route, by artifact name, no /api/v1 prefix
curl -sS -o artifact.zip -H "Authorization: token $TOKEN" \
  "https://gitea.sasu.org/$OWNER/$REPO/actions/runs/$RUN/artifacts/$NAME"
```

If you suspect a listing is wrong, check a run you know published as a
control; if that one also lists zero, the listing is the problem. See
`references/actions-api-gotchas.md` for the hardcoded `FinalizedArtifactsV4`
filter that causes this.

### 6) Wait for a run on Gitea or Forgejo

Check once right after the push, before any loop, and report the state you
saw. Select the run by full commit SHA, workflow file, and event — never as
the first entry of the latest runs. Parse a saved response with
`ci_run_probe`, which exits non-zero on an empty, malformed, ambiguous, or
unknown response instead of treating it as "still running".

The hosts differ. Forgejo 15 reports the result in `status`; Gitea 1.27
reports `status: completed` and the result in `conclusion`. Forgejo's API
takes the run `id`, while its web links use `index_in_repo`. `tea api` exits
0 on an HTTP error.

```bash
probe_once; echo "rc=$?"   # 0 success, 1 failure/cancelled/skipped, 2 probe error, 3 pending, 4 none yet
```

The probe, the host table, the one-check and bounded-wait commands, and the
incident behind them: `references/waiting-for-a-run.md`. Do not cancel or
re-run a remote run only because your wait ended.

### 7) Verify instead of guessing at API/CLI behavior

When Gitea API or CLI behavior is ambiguous, undocumented, or a plausible
route/flag 404s, check version-matched source rather than guessing:

```bash
# Confirm the live instance's version
curl -s https://gitea.sasu.org/api/v1/version

# Find/confirm a matching tag in the local checkout, then grep the real source
cd "$HOME/Projects/gitea.com/gitea/gitea-mirror"
git describe --tags --always
grep -rn "actions/runs/{run}\|actions/runners" routers/api/v1/api.go
```

`gitea.com/gitea/gitea-mirror` tracks upstream `main` and is the
version-matched checkout for this instance; most other `gitea.com/gitea/*`
checkouts under `~/Projects/gitea.com/gitea/` are stale snapshots —
verify the tag before trusting one. `tea` CLI source is at
`~/Projects/gitea.com/gitea/tea`.

## Guardrails

- Never say you are watching or waiting for a run before a probe returned
  its state. A probe that cannot parse its input is an error, not "pending".

- Never read an empty artifact listing as proof a run failed to publish.
  The v1 endpoints filter out every `upload-artifact@v3` artifact, and v3 is
  what Gitea supports. Check the job log's upload line, or download by name
  via the web route, before reporting a packaging or publication failure.
- Never guess an API route from GitHub Actions' equivalent REST API without
  checking Gitea's own source — GitHub's actions API and Gitea's diverge
  (e.g. no `/cancel`, different runner-scope endpoints).
- Don't conclude an operation is "impossible via API" from one 404 — check
  version-matched source before falling back to a direct DB write. A DB
  write that only touches `action_run` and not `action_run_job` looks
  successful but leaves the job-level state (and therefore the scheduler)
  still stuck.
- Registering, deploying, or reconfiguring an `act_runner`, and rotating its
  registration token, are hard-to-reverse, shared-infrastructure changes —
  confirm before acting, same as any other production change in this
  project.
- Do not register a runner under the bare `ubuntu-latest`/`macos-latest`
  labels unless that is genuinely intended — an org/user-scoped runner
  registered under a stock label has every Actions-enabled repo under that
  owner's queued jobs evaluated against it, not just the repos it's meant
  to serve. Prefer a custom label repos opt into explicitly.
- Never commit a runner registration token to git; store it in gopass and
  inject it via Ansible `no_log: true`, per this project's secrets model.

## References

- `references/actions-api-gotchas.md` — run/job status enum, the run
  vs. job status-mismatch trap, the real cancel/delete mechanism,
  `tea` CLI's actual command coverage, and why artifact listings come back
  empty for v3 uploads (plus the web route that does return them).
- `references/waiting-for-a-run.md` — waiting for a run on Gitea or
  Forgejo: per-host field and identifier table, the copyable `ci_run_probe`
  with its exit codes, a one-check command, and a bounded background wait.
- `references/act-runner-deployment.md` — registering, deploying, and
  administering `act_runner`: registration-token flow, repo/org/user/admin
  scope, Docker vs. host execution mode, and this instance's deployed
  topology.
