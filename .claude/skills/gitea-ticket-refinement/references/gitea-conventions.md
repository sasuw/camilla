### Gitea

- Prefer the Gitea MCP server for issue, PR, and repo operations. Fall back to the `tea` CLI if the MCP server is unavailable; use the HTTP REST API with `curl` only if neither is available.
- Reference the issue number in commit messages, e.g. `Implement issue #5 (short issue title)`.

#### Setting labels on an issue

The `state/*` labels (and `next`) described below are shared workflow labels. Their scope depends on whether the repo belongs to a real Gitea organization or is a personal repository:

- **Organization-owned repositories** (any owner other than `sasu`) — these labels are defined at the **org level**, not per-repo. Gitea supports both scopes, and a repo may have zero repo-scoped labels while still inheriting the full org set. Always check org labels; do not conclude labels "don't exist" from a repo-only lookup.
- **Personal repositories under `sasu/*`** — `sasu` is a personal account, not an organization, so there is no org-label scope to inherit from. Use repository-scoped labels instead: look up and create labels with the repo-scoped tools (`list_repo_labels`, `create_repo_label`). Label IDs here are per-repository — do not assume one `sasu/*` repo's label ID works in another `sasu/*` repo.

The Gitea MCP tools for setting labels (e.g. `issue_write` with `add_labels`/`replace_labels`) take numeric label IDs, not label names, and org and repo labels use separate ID spaces. If you only have a label name (e.g. `state/ok-for-dev`), look up its ID first — do not skip setting labels just because you don't have the ID yet, and do not create a repo-level duplicate of a label that already exists at the org level.

**Prefer the `label_ids.sh --repo owner/repo [label]` script that ships with this skill** for this lookup, in a shell tool call, even when otherwise using the Gitea MCP server for everything else: for an organization-owned repo it fetches and merges both the org's shared labels and the repo's own labels in one call, so there is no need to guess which scope a label lives in or make two separate lookups.

The script lives next to this reference document, at `../scripts/label_ids.sh` relative to this file. Because the skill is deployed into many different projects, **do not call it by a bare relative path** — that resolves against the working directory of whatever project you are in, not against the skill, and fails with `No such file or directory`. Resolve it from this document's own location instead, for example:

```sh
# From the directory holding this reference doc:
../scripts/label_ids.sh --repo infra2/agent-docs state/ok-for-dev
```

Pass several label names to resolve them in one call. One label prints just
its ID (usable in a command substitution); several print `name<TAB>id` rows:

```sh
../scripts/label_ids.sh --repo infra2/agent-docs state/done state/needs-human
```

If you know the deployed skill root (e.g. `~/.claude/skills/gitea-ticket-refinement` or a project's `.agents/skills/gitea-ticket-refinement`), calling `<skill-root>/scripts/label_ids.sh` works equally well. Pass a label name to print just its numeric ID (repo-scoped wins on a name collision); omit it to list every `state/*`/`next` ID found at either scope. For personal repos under `sasu/*` it only reads repo-scoped labels, since `sasu` has no org scope.

Only fall back to raw MCP/`tea`/REST calls if the script itself is unavailable or fails:

1. For organization-owned repos, call `label_read` with method `list_org_labels` (`org`) first to list the org's labels, each with its `id` and `name`. Only fall back to `list_repo_labels` (`owner`, `repo`) for repo-specific labels not part of the shared `state/*`/`next` convention. For personal repos under `sasu/*`, skip straight to `list_repo_labels` (`owner`, `repo`) — there is no org scope to check.
2. Find the entry whose `name` matches the label you want and use its `id` in the `issue_write` call.
3. If the label doesn't exist yet at the relevant scope, create it with `label_write` — `create_org_label` for shared conventions like `state/*` on organization-owned repos, `create_repo_label` for genuinely repo-specific labels or for any label on a personal `sasu/*` repo — then use the `id` from that response.

If neither the script nor the MCP server can supply label IDs, fall back to `tea label list` or the REST API (`GET /orgs/{org}/labels`, `GET /repos/{owner}/{repo}/labels`) instead of leaving the issue unlabeled.

Label IDs are assigned per org (or, for `sasu/*`, per repo) and are neither portable nor stable. Never hardcode or cache them in documentation.

#### Branches and pull requests

- Small issues (only a few changes) can be implemented directly on the main branch; no pull request is needed.
- For more elaborate changes, open a branch: commit the work there, push the branch when ready, and open a pull request.
- The reviewer merges the branch directly if the review result is "pass", and can use `closes #N`/`fixes #N` to close the issue on merge. As the developer, leave closing the issue to the reviewer.

#### Issue states and process

Issues are refined before implementation, tracked with `state/*` labels:

| Label | Meaning | Who acts next |
|---|---|---|
| `state/triage` | New issue, not yet refined | Triager reviews and refines |
| `state/needs-info` | Open questions block refinement | Human answers, then back to refinement |
| `state/ok-for-dev` | Spec is clear and ready to implement | Developer picks it up |

Refinement flow: `state/triage` → `state/ok-for-dev`, with a detour to `state/needs-info` whenever refinement raises blocking questions; return the issue toward `state/ok-for-dev` once they are answered.

Implementation flow:

- Only start implementing an issue once it is labeled `state/ok-for-dev`.
- When starting implementation, move the issue to `state/in-progress`.
- After implementing, move the issue to `state/needs-review` — or directly to `state/done` if the change was trivial (e.g. a simple configuration change).
- If an issue requires work an agent cannot do (e.g. manual testing with a mobile device), move it to `state/needs-human`. Once the human part is done, the human moves it to `state/needs-agent`, and an agent picks it back up (continuing via `state/in-progress`).

Review flow, once an issue reaches `state/needs-review`:

- Reviewer checks the implementation (PR, branch, or main-branch commits) against the issue's requirements.
- Pass → `state/done`, and the PR is merged (or the branch/ticket closed if there was no PR).
- Fail, needs a human decision → `state/needs-human`.
- Fail, agent-fixable → `state/needs-agent`, so implementation can pick it back up.

#### Other Gitea labels

- `next` — the issue should be included in the next milestone or release.
