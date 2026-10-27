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
GET    /orgs/{org}/actions/runners/{runner_id}
DELETE /orgs/{org}/actions/runners/{runner_id}
PATCH  /orgs/{org}/actions/runners/{runner_id}

POST   /user/actions/runners/registration-token
GET    /user/actions/runners
GET    /user/actions/runners/{runner_id}
DELETE /user/actions/runners/{runner_id}
PATCH  /user/actions/runners/{runner_id}

POST   /admin/actions/runners/registration-token   (site-admin only)
GET    /admin/actions/runners
GET    /admin/actions/runners/{runner_id}
DELETE /admin/actions/runners/{runner_id}
PATCH  /admin/actions/runners/{runner_id}
```

All paths are relative to `/api/v1`. Each list route takes an optional
`?disabled=true|false` filter. `PATCH` changes only the `disabled` flag; see
"Pausing and resuming a runner" below.

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

## Pausing and resuming a runner

A runner's `disabled` flag stops Gitea from assigning it new jobs while it
stays registered and connected. Use it for maintenance instead of stopping
the runner's service or deleting its registration.

### What pausing does and does not do

- Gitea checks the flag each time the runner asks for a job
  (`services/actions/task.go`, `PickTask`). A paused runner gets no new job.
- A job the runner already took keeps running. Pausing does not cancel it,
  and nothing reports when the runner has finished it: there is no drain
  signal. Check the runs or jobs of the repositories the runner serves if
  the change must wait until the runner is idle.
- Workflows stay enabled. Their jobs stay queued for this runner, or start
  on another online runner in scope that matches their `runs-on:` labels.
- Other runners, including others on the same host, are not affected.
- Resuming (`disabled: false`) lets the runner take queued jobs again.

### API contract

Checked against the vendored Gitea 1.27.3 Swagger
(`data/vendor-docs/gitea/swagger-27.json` in
`infra2/api-external-documentation`) and the version-matched source
(`routers/api/v1/shared/runners.go`, `UpdateRunner`).

| Scope         | Route (relative to `/api/v1`)                       | Operation ID        |
| ------------- | --------------------------------------------------- | ------------------- |
| Instance-wide | `/admin/actions/runners/{runner_id}`                | `updateAdminRunner` |
| Organization  | `/orgs/{org}/actions/runners/{runner_id}`           | `updateOrgRunner`   |
| Repository    | `/repos/{owner}/{repo}/actions/runners/{runner_id}` | `updateRepoRunner`  |
| Token's user  | `/user/actions/runners/{runner_id}`                 | `updateUserRunner`  |

- Request: `PATCH`, `Content-Type: application/json`, body
  `EditActionRunnerOption` with one required boolean: `{"disabled":true}` to
  pause, `{"disabled":false}` to resume. A missing field returns 422. Send a
  JSON boolean, not the string `"true"`.
- Response 200: the `ActionRunner` after the change, the same shape as
  `GET .../actions/runners/{runner_id}`: `id`, `name`, `status`, `busy`,
  `disabled`, `ephemeral`, `labels`.
- The org, repo, and user routes reach only runners registered at exactly
  that scope (a repo route does not reach the org runner serving that
  repo). The admin route reaches every runner. Use the route of the scope
  the runner is registered at.
- 404 means either no such runner or a runner registered at another scope
  (Gitea answers "No permission to access this runner" with 404). List the
  runners at the scope you meant before concluding the ID is wrong.
- 401 or 403: the token lacks the right at that scope. The admin route
  needs a site administrator; the org and repo routes check the token's
  rights over that owner; the user route covers only the token's own
  runners. A permission error never authorizes using another account's
  token: stop and report it.

`status` is `online` or `offline` (no contact for about a minute). `busy`
is `true` when the runner was active in the last few seconds; it is not a
count of running jobs.

### Procedure

1. **Inspect (read-only).** List the runners at the scope and identify the
   runner by name and labels; note its ID.
2. **Get the runner** and record `id`, `name`, `status`, `busy`, and
   `disabled`. If `disabled` already has the target value, there is nothing
   to change; report that.
3. **Authorize.** A live pause or resume changes shared infrastructure.
   Obtain authorization for this runner first, naming host, scope, runner
   ID and name, and the target `disabled` value. Authorization for one
   runner does not cover another.
4. **Change** it with one `PATCH`, through the first tool that can (see
   below). Do not repeat a request whose result is unclear; read first.
5. **Read back** with `GET` on the same scope and ID. The change is done
   only when the response has that `id` and the target `disabled` value.

### Tools, in order

1. **Gitea MCP server.** Discover the host's tools first. The current
   server's Actions tools (`actions_run_*`, `actions_config_*`) have no
   runner list, get, or update method — `actions_config_*` manages secrets
   and variables only. Use a runner method if a newer server exposes one;
   otherwise fall back.
2. **`agent_tea.sh --host gitea.sasu.org api ...`.** It runs `tea api`
   under the agent's own login. Never run bare `tea`: it acts as sasu.
3. **REST** with the host's own agent token, read as the global
   instructions describe.

Before relying on `tea api` flags, read `tea api --help` of the installed
version. The version checked here documents `-X/--method`, `-F/--Field` for
typed fields (`-F disabled=true` sends a JSON boolean; `-f` would send a
string), `-d/--data` for a raw JSON body (not combinable with `-f`/`-F`),
and `-i/--include` to print the HTTP status to stderr. A body without `-X`
defaults to `POST`. `tea api` replaces `{owner}` and `{repo}` in the path
from the current repository context, so write real names.

```bash
scope="orgs/ORG"   # or: admin, repos/OWNER/REPO, user
id=42              # from the list

# 1-2: inspect (read-only)
agent_tea.sh --host gitea.sasu.org api "$scope/actions/runners" \
  | jq '.runners[] | {id, name, status, busy, disabled, labels: [.labels[].name]}'
agent_tea.sh --host gitea.sasu.org api "$scope/actions/runners/$id" \
  | jq '{id, name, status, busy, disabled}'

# 4: pause (after authorization); use disabled=false to resume
agent_tea.sh --host gitea.sasu.org api -i -X PATCH -F disabled=true \
  "$scope/actions/runners/$id"
echo "rc=$?"

# 5: read back the same ID and value
agent_tea.sh --host gitea.sasu.org api "$scope/actions/runners/$id" \
  | jq -e --argjson id "$id" '.id == $id and .disabled == true'
```

The wrapper exits 7 on 401 and 8 on 403, but `tea api` exits 0 on other
HTTP errors such as 404 or 422 and prints the error body. So a zero exit
does not show success: read the status line from `-i` (expect 200) and rely
on the read-back.

REST fallback, same steps:

```bash
base="https://gitea.sasu.org/api/v1"
curl -sS -o runner.json -w '%{http_code}\n' -X PATCH \
  -H "Authorization: token ${TOKEN}" -H "Content-Type: application/json" \
  -d '{"disabled":true}' "$base/$scope/actions/runners/$id"   # expect 200
curl -sS -H "Authorization: token ${TOKEN}" "$base/$scope/actions/runners/$id" \
  | jq -e --argjson id "$id" '.id == $id and .disabled == true'
```

This runner administration guidance covers Gitea only; it makes no claim
about Forgejo.

## Diagnosing "queued forever, no runner picks it up"

This is the most common act_runner-related failure mode. Check, in order:

1. **Does any runner exist at all for this scope?** `GET .../actions/runners`
   at the repo/org/user scope the queued run's repo belongs to. Zero rows
   means no runner has ever registered there — the run will never execute
   until one does, regardless of how long it waits.
2. **Is a registered runner online?** Check `status` (`online` or
   `offline`) in the runner list response (or `last_online` in the
   underlying `action_runner` table if you have DB access) — a runner that
   registered once but is no longer running looks identical to "queued
   forever" from the workflow's perspective. `busy` only means recent
   activity; a busy runner still takes the next job when it asks.
3. **Is the online runner paused?** `disabled: true` means it is connected
   but gets no new jobs (see "Pausing and resuming a runner"). It differs
   from offline (no contact) and from a label mismatch (step 4): the runner
   is up and its labels may match. Resume it only with authorization.
4. **Does the workflow's `runs-on:` label match a label any online, enabled
   runner actually advertises?** A mismatch (e.g. workflow requests
   `ubuntu-latest`, only a `gitea-actions-group-b`-labeled runner exists) is
   silent — the run just queues forever with no error surfaced to the user.
5. Only after ruling out 1–4 should you suspect a scheduler bug or a stuck
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
(`~/Projects/gitea.com/gitea/gitea-mirror`, after confirming its
tag matches the live instance's `/api/v1/version`) — particularly
`models/actions/task.go` (`CreateTaskForRunner`, job-selection logic) and
`routers/api/v1/{repo,org,user,admin}/...` plus `routers/api/v1/shared/runners.go`
for the registration/list/delete handlers — rather than assuming GitHub's
documented behavior carries over unchanged.
