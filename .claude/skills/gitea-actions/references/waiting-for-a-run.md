# Waiting for an Actions run

TLDR: Check the run once right after the push, before any loop. Select it by
full commit SHA, workflow file, and event, never as "the newest run". Parse a
saved response with a probe that fails loudly on anything it does not
understand. Bound the wait by the job's expected duration and keep it
observable. Say you are watching a run only after a probe returned its state.

## Why this exists

On 2026-10-03 an agent opened a pull request on `forgejo.sasu.org` and wrote
"Watching its CI run". Its poll loop printed nothing for ten minutes; the run
had failed after 11 seconds. Four faults combined
(`infra2/agent-docs#280`):

- zsh's `echo "$json"` turned `\n` and `\"` inside JSON strings into raw
  characters, so `jq` failed with a parse error.
- `2>/dev/null` on `jq` hid that error.
- An empty status matched no exit branch, so "no data" looked like "still
  running".
- The first check came only inside a long foreground loop.

## Host facts

Verified on 2026-10-03 with read-only calls.

| Item                   | `forgejo.sasu.org` (Forgejo 15.0.9)                          | `gitea.sasu.org` (Gitea 1.27.3)                                            |
| ---------------------- | ------------------------------------------------------------ | -------------------------------------------------------------------------- |
| List runs              | `GET /repos/{o}/{r}/actions/runs`                            | same                                                                       |
| Filter by commit       | `?head_sha=<full SHA>`; a short SHA matches nothing          | same                                                                       |
| Commit field           | `commit_sha`                                                 | `head_sha`                                                                 |
| Workflow field         | `workflow_id` (`quality.yml`)                                | `path` (`ci.yml@refs/heads/main`)                                          |
| Pending `status`       | `waiting`, `running`, `blocked`                              | `queued`, `waiting`, `in_progress`                                         |
| Terminal `status`      | `success`, `failure`, `cancelled`, `skipped`                 | `completed`; the result is in `conclusion`                                 |
| `conclusion`           | absent                                                       | `success`, `failure`, `cancelled`, `skipped`                               |
| API id vs. display no. | `id` (178) vs. `index_in_repo` (33)                          | `id` (4147) vs. `run_number` (25)                                          |
| One run by API         | `GET …/actions/runs/{id}` — the `id`, not `index_in_repo`    | `GET …/actions/runs/{id}`                                                  |
| Web link (`html_url`)  | `…/actions/runs/{index_in_repo}`                             | `…/actions/runs/{id}`                                                      |
| Job-level status       | `GET …/actions/tasks` (entries carry `run_number`)           | `GET …/actions/runs/{id}/jobs` (`status` + `conclusion`, job `html_url`)   |
| Job log                | `…/actions/runs/{index_in_repo}/jobs/{job}/attempt/{n}/logs` | the failed job's `html_url` from the jobs route; MCP `get_job_log_preview` |

Notes:

- On Gitea, `status: completed` alone is not success. Read `conclusion`.
- On Forgejo, `GET …/actions/runs/33` with the display number returns
  `resource does not exist` — or a different run if that id exists. Use the
  link from `html_url` instead of building one.
- `tea api` exits 0 on an HTTP error; the body is then an error object such
  as `{"message":"resource does not exist",…}`. Only the response shape tells
  you it failed. The probe below checks the shape.
- Forgejo's runs list ignores `limit` unless `page` is also given. Filter by
  `head_sha` instead of paging through recent runs.
- Re-check these facts after an upgrade of either host.

## Steps

1. **Read once, right after the trigger.** Use the host's MCP server first
   (`actions_run_read` with `list_runs`/`get_run` on Gitea). Report the
   timestamp, the run link, and its state. If no run exists yet, say "not
   discovered yet", not "running".
2. **Select one run by identity.** Use the full commit SHA
   (`git rev-parse HEAD`), the workflow file, and the event. Several matches
   (a re-run, two events for one SHA) are a reason to investigate; pin the
   chosen `id` with `RUN_ID`.
3. **Test the parse on one saved response before any loop.** Run
   `ci_run_probe` below on the saved file and read its line. Pass captured
   text to a parser with `printf '%s\n' "$json"` or a file, never with `echo`.
4. **Bound the wait.** Set an overall deadline from the job's expected
   duration (a lint job: a few minutes) and a short discovery deadline.
   Give each request a timeout.
5. **Keep it observable.** Run a loop through the harness's background-task
   facility, if it has one, record its handle and output file, and read the
   result when it ends. Without one, make single probes between short waits:
   no blocking wait over 60 seconds, and an update to the user at least that
   often.
6. **Report the outcome as observed:** success, failure, cancelled, skipped,
   timeout (with the last state and elapsed time), or probe error. For a
   failure, link the failed job and its log. Stopping the observer does not
   authorize cancelling or re-running the remote run.

## The probe

`ci_run_probe` reads one saved runs-list response and prints one line:

```text
<state> id=<API id> number=<display no.> status=<status>[/<conclusion>] url=<html_url>
```

| Exit | Line / meaning                                                                                                                                              |
| ---: | ----------------------------------------------------------------------------------------------------------------------------------------------------------- |
|    0 | `success …`                                                                                                                                                 |
|    1 | `failure …`, `cancelled …`, or `skipped …`                                                                                                                  |
|    2 | probe error: empty or malformed body, unexpected shape, malformed run record, selected run without id/number/`html_url`, ambiguous match, unsupported state |
|    3 | `pending …`                                                                                                                                                 |
|    4 | `none` — no matching run yet                                                                                                                                |

jq's diagnostics stay on stderr. The code runs in Bash 3.2+ and zsh and
needs `jq` 1.6+. It avoids the name `status`, which zsh reserves.

<!-- ci-run-probe:begin -->

```sh
# ci_run_probe FILE SHA WORKFLOW [EVENT [RUN_ID]]
ci_run_probe() {
  local probe_line
  probe_line=$(jq -rs --arg sha "$2" --arg wf "$3" --arg ev "${4:-}" --arg id "${5:-}" '
    if length != 1 then error("expected 1 JSON document, got \(length)") else .[0] end
    | if type == "object" and (.workflow_runs | type) == "array" then .workflow_runs
      else error("unexpected response: \(tostring | .[0:200])") end
    | map(if type == "object"
            and ((.commit_sha // .head_sha) | type) == "string"
            and ((.workflow_id // .path) | type) == "string"
            and (.event | type) == "string"
          then . else error("malformed run record: \(tojson | .[0:200])") end)
    | [.[] | select(((.commit_sha // .head_sha) == $sha)
        and (((.workflow_id // .path // "") | sub("@.*$"; "")) == $wf)
        and ($ev == "" or .event == $ev)
        and ($id == "" or (.id | tostring) == $id))]
    | if length == 0 then "none"
      elif length > 1 then error("ambiguous: \(length) runs match, ids \(map(.id))")
      else .[0] as $run
        | if ($run.id | type) == "number"
            and (($run.index_in_repo // $run.run_number) | type) == "number"
            and ($run.html_url | type) == "string" and $run.html_url != ""
          then . else error("run lacks id, number, or html_url: \($run | tojson | .[0:200])") end
        | $run.status as $s
        | ($run.conclusion // "") as $c
        | (if ($s | type) != "string" then error("status is \($s | tojson)")
           elif $s == "completed" then $c
           else $s end) as $r
        | (if any(("waiting", "blocked", "running", "queued", "in_progress"); . == $r) then "pending"
           elif any(("success", "failure", "cancelled", "skipped"); . == $r) then $r
           else error("unsupported state: status=\($s | tojson) conclusion=\($c | tojson)") end)
        | "\(.) id=\($run.id) number=\($run.index_in_repo // $run.run_number)"
          + " status=\($s)\(if $c == "" then "" else "/" + $c end) url=\($run.html_url)"
      end' "$1") || {
    printf 'probe error: jq failed on %s\n' "$1" >&2
    return 2
  }
  printf '%s\n' "$probe_line"
  case $probe_line in
    success\ *) return 0 ;;
    failure\ * | cancelled\ * | skipped\ *) return 1 ;;
    pending\ *) return 3 ;;
    none) return 4 ;;
    *) printf 'probe error: unexpected line\n' >&2; return 2 ;;
  esac
}
```

<!-- ci-run-probe:end -->

### One check

Set the inputs, fetch into a file, check the fetch, then probe. For
`gitea.sasu.org`, drop `--host forgejo.sasu.org`. Use `agent_tea.sh`, never
bare `tea`. `timeout` is GNU coreutils (`gtimeout` on macOS with Homebrew
coreutils).

```sh
S=${SCRATCH:-$(mktemp -d)}   # session scratchpad, if the harness gives one
REPO=forks/cli-agent-orchestrator WF=quality.yml EV=pull_request RUN_ID=
SHA=$(git rev-parse HEAD)

probe_once() {
  timeout 30 agent_tea.sh --host forgejo.sasu.org api \
    "/repos/$REPO/actions/runs?head_sha=$SHA" \
    </dev/null >"$S/runs.json" 2>"$S/runs.err" || {
    printf 'fetch failed (rc=%s); stderr in %s\n' "$?" "$S/runs.err" >&2
    return 2   # do not parse a partial body
  }
  printf '%s ' "$(date -u +%H:%M:%SZ)"
  ci_run_probe "$S/runs.json" "$SHA" "$WF" "$EV" "$RUN_ID"
}

probe_once; echo "rc=$?"
```

Expected output for the incident run:

```text
11:41:05Z failure id=178 number=33 status=failure url=https://forgejo.sasu.org/forks/cli-agent-orchestrator/actions/runs/33
rc=1
```

### Bounded wait

Run this through the harness's background-task facility, with its output in
a file you read. It ends on any result except `pending` and `none`, on the
discovery deadline, and on the overall deadline.

```sh
start=$(date +%s)
discover_by=$((start + 120)) deadline=$((start + 600))   # from expected duration
while :; do
  probe_once; rc=$?
  now=$(date +%s)
  case $rc in
    3) ;;
    4) [ "$now" -lt "$discover_by" ] || { echo "no run after $((now - start))s"; exit 4; } ;;
    *) exit "$rc" ;;
  esac
  [ "$now" -lt "$deadline" ] || { echo "timeout after $((now - start))s"; exit 124; }
  sleep 20
done
```

The last line before `timeout` is the last observed state. A timeout says
nothing about the run's result; report it as a timeout.
