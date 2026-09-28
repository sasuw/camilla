# act_runner: registration and administration

Covers registering, diagnosing, and deploying `act_runner` instances for
Gitea Actions on `gitea.sasu.org`. Confirmed against Gitea 1.27.0 via a
version-matched source checkout (`gitea.com/gitea/gitea-mirror`,
tag `v1.27.0-dev-153-g...`).

## Scope model: repo, org, user, and admin/global

`act_runner` registration is scoped to exactly one of: a single repo, an
org, a user (personal account), or the whole instance (admin/global). The
REST API has a parallel route family at each scope
(`routers/api/v1/{repo,org,user,admin}/...`), all backed by the same
`shared.GetRegistrationToken`/runner-list/get/delete/update handlers:

```text
POST   /repos/{owner}/{repo}/actions/runners/registration-token
GET    /repos/{owner}/{repo}/actions/runners
GET    /repos/{owner}/{repo}/actions/runners/{runner_id}
DELETE /repos/{owner}/{repo}/actions/runners/{runner_id}
PATCH  /repos/{owner}/{repo}/actions/runners/{runner_id}

POST   /orgs/{org}/actions/runners/registration-token
GET    /orgs/{org}/actions/runners
...

POST   /user/actions/runners/registration-token
GET    /user/actions/runners
...

POST   /admin/actions/runners/registration-token   (site-admin only)
GET    /admin/actions/runners
DELETE /admin/actions/runners/{runner_id}
```

**Job-selection model is owner_id-scoped, not repo-content-scoped.** An
org-level or user-level runner has _every_ Actions-enabled repo under that
owner evaluated against it for queued jobs — not just the repos it's
intended to serve. A registered custom label (see below) prevents the
runner from _executing_ jobs outside its intended scope, but does not
reduce what gets evaluated. Registering at the narrower scope (one runner
per repo) is the only mechanism that closes this fully; treat the
broader-scope tradeoff as a deliberate choice to weigh, not a default.

A separate org needs its own runner registration even if another runner
already serves a "similar" repo elsewhere — Gitea's `CreateTaskForRunner`
(`models/actions/task.go`) never evaluates a runner outside its own
registered owner scope, regardless of label overlap.

## Labels: never register the bare stock labels unless you mean to

Register runners under a custom label (e.g. `gitea-actions-group-b`) that
workflows opt into explicitly via `runs-on:`, rather than the bare
`ubuntu-latest`/`macos-latest` GitHub-compatible labels — unless you
specifically intend the runner to pick up _every_ workflow at its owner
scope that requests that stock label. Registering under a custom label
also means workflows still requesting `ubuntu-latest` will queue forever
until their `runs-on:` is updated to match — this is expected, not a bug,
and is a common cause of "why is this run still queued" after a runner is
freshly deployed.

Do not register a label for a platform the runner can't actually provide
(e.g. `macos-latest` on a Linux-only host) — an unfulfillable label should
stay unregistered, not registered-but-perpetually-unmatched.

## Registering a new runner

1. Generate a registration token at the intended scope (see routes above;
   the web UI equivalents are under that repo/org/user's Settings → Actions
   → Runners page, or the instance admin panel for global scope).
2. Store the token via this project's secrets flow (gopass, human-run
   insert; Ansible reads it with `no_log: true`) — never commit it, never
   paste it into a workflow file or issue comment.
3. Run `act_runner register` (interactively or via `--no-interactive` with
   `--instance`, `--token`, `--name`, `--labels` flags) pointed at the
   Gitea instance URL, or let the deployment tooling do this as part of
   first start (see `config.yaml`'s `runner.registration_token` /
   pre-registered `.runner` file handling, if your deployment mechanism
   supports it).
4. Choose Docker vs. host (direct) execution mode. Docker mode is generally
   preferred — it isolates job containers from the host and supports
   Docker-in-workflow features (service containers, `docker compose`
   inside a job) that host-execution mode cannot provide.
5. Prove the runner before pointing any real repo at it: dispatch a
   disposable, secret-free smoke workflow requesting the runner's exact
   label and confirm it completes. Do this independently for each runner
   instance in a multi-scope deployment — a shared deployment mechanism
   does not mean shared proof of working state.

## Diagnosing "queued forever, no runner picks it up"

This is the most common act_runner-related failure mode. Check, in order:

1. **Does any runner exist at all for this scope?** `GET .../actions/runners`
   at the repo/org/user scope the queued run's repo belongs to. Zero rows
   means no runner has ever registered there — the run will never execute
   until one does, regardless of how long it waits.
2. **Is a registered runner online?** Check `last_online`/`last_active` in
   the runner list response (or the underlying `action_runner` table if you
   have DB access) — a runner that registered once but is no longer running
   looks identical to "queued forever" from the workflow's perspective.
3. **Does the workflow's `runs-on:` label match a label any online runner
   actually advertises?** A mismatch (e.g. workflow requests
   `ubuntu-latest`, only a `gitea-actions-group-b`-labeled runner exists) is
   silent — the run just queues forever with no error surfaced to the user.
4. Only after ruling out 1–3 should you suspect a scheduler bug or a stuck
   job-level status row — see `references/actions-api-gotchas.md` for the
   run-vs-job status mismatch trap, which produces a superficially similar
   symptom (run "won't clear") but with a different root cause and fix.

## Token rotation

Resetting/regenerating a registration token does **not** un-register or
disconnect a runner already running under the old token — the old token
simply becomes invalid for any _future_ registration attempt. If you need
to force an existing runner to re-register (e.g. after a suspected token
leak), you must also restart that runner process/container after rotating
the token, not just rotate the token alone.

## Deploying via Ansible (this instance's pattern)

On `gitea.sasu.org`, `act_runner` instances are deployed as Ansible-managed,
version-pinned systemd services running Docker containers (not raw host
execution), one dedicated service account per registered scope. If deploying
a new instance here, look for the current playbook and group_vars under
`infra/configs-ansible` (`playbooks/services/configure_gitea_act_runner.yml`
and `group_vars/gitea_actions_runners.yml` as of the last deployment) rather
than hand-rolling a new mechanism — extend the existing per-scope instance
list pattern for a new scope rather than duplicating the playbook.

Operational runbook for the currently deployed instances (read-only checks,
change steps, token rotation, rollback, monitoring/alerting, known gaps) is
maintained in `infra2/agent-devop`'s `runbooks/` directory — check there for
the current live topology, host, and scopes before assuming any specific
host/label/scope combination is still accurate; deployments are added and
changed over time and this skill does not track that state itself.

Pin the runner image and the job image to specific tags (never `latest`),
and set `force_pull: true` in `config.yaml` so a version bump actually takes
effect on the next playbook run rather than silently reusing a cached image.

## Verifying instead of guessing

Runner-registration and job-scheduling behavior is exactly the kind of
thing that's easy to get subtly wrong by analogy with GitHub Actions (whose
self-hosted-runner model differs in scope semantics). When behavior is
ambiguous, check the version-matched Gitea source
(`/home/sasu/Projects/gitea.com/gitea/gitea-mirror`, after confirming its
tag matches the live instance's `/api/v1/version`) — particularly
`models/actions/task.go` (`CreateTaskForRunner`, job-selection logic) and
`routers/api/v1/{repo,org,user,admin}/...` plus `routers/api/v1/shared/runners.go`
for the registration/list/delete handlers — rather than assuming GitHub's
documented behavior carries over unchanged.
