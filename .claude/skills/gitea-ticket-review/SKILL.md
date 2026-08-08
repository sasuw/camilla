---
name: gitea-ticket-review
description: "Use when asked to review one or more specific Gitea tickets, given as explicit numbers (e.g. \"review ticket #15\" or \"review #33, #34\"). Reviews the ticket's implementation (branch, PR, or direct main-branch commits), then labels it state/done, state/needs-human, or state/needs-agent, and either merges/requests-changes on its PR or comments and closes the ticket directly. Never used for implementing or refining tickets — see gitea-ticket-implementation and gitea-ticket-refinement for those."
---

# gitea-ticket-review

Review one or more specific, already-implemented Gitea tickets, one at a
time, in the order given. Each ticket gets its own review comment, its own
outcome label, and — depending on where the work lives — its own PR
decision or its own close/merge action. Never batch multiple tickets into a
single review comment or a single merge.

## Scope: which tickets

Read the invocation argument (the text after `/gitea-ticket-review`, or the
user's request) to decide which tickets to review:

- **One or more explicit ticket numbers** (e.g. `42`, `#42`, `42 57 89`, a
  URL) — review exactly those tickets, in the order listed.
- **No explicit ticket numbers** — do not guess which tickets to review. Ask
  the user to clarify. This skill never scans for `state/needs-review` or
  any other label on its own initiative.
- **A repo or org qualifier alongside ticket numbers** — scope the lookup to
  that repo/org instead of the current one.

This skill is for review only. It does not implement or refine tickets —
use `gitea-ticket-implementation` or `gitea-ticket-refinement` for that
instead.

## Workflow

Repeat this full cycle for each ticket, in the given order, before moving to
the next one:

1. **Read full context** with `issue_read`: description, comments (including
   any prior implementation summary), linked issues/PRs, and existing
   labels. Do not rely on the title alone.
2. **Determine where the implementation lives:**
   - **Open PR linked to the ticket** — use `pull_request_read` (`get`,
     `get_diff`, `get_files`) to review the changes.
   - **Branch without a PR** — use `git`/`list_branches` + `list_commits` (or
     the Gitea MCP repo tools) to find the branch and review its commits
     against the default branch.
   - **Directly on the main branch** — review the relevant commit(s)
     referencing this ticket (`list_commits`, `get_commit`).
   If none of these can be found, stop and flag it to the user rather than
   guessing which changes belong to the ticket.
3. **Review the implementation** against the ticket's requirements and this
   project's normal definition of done:
   - Does the change actually address the ticket's problem statement/goal?
   - Correctness: read the diff, check for bugs, missed edge cases, or
     regressions.
   - Tests: were they run (per any implementation comment) and do they cover
     the change? Re-run the project's test suite yourself if you can do so
     safely (see this project's `CLAUDE.md`/test instructions).
   - Conventions: does it follow existing structures, this project's
     coding/documentation conventions, and (for commits) the issue-reference
     convention in commit messages?
   - Note concrete `file:line` references for anything you flag, in your own
     words.
4. **Decide the review outcome:**
   - **Pass** — the implementation is correct, tested, and ready → outcome
     label `state/done`.
   - **Fail, needs a human decision** — e.g. a design/product tradeoff, an
     ambiguous requirement, something outside what an agent should decide
     alone → outcome label `state/needs-human`.
   - **Fail, no human needed** — a concrete, agent-fixable problem (bug,
     missing test, convention violation) → outcome label `state/needs-agent`.
5. **Act according to where the implementation lives:**
   - **PR exists:**
     - Pass → merge the PR with `pull_request_write` (`method: "merge"`),
       letting `closes #N`/`fixes #N` (already in the PR body, per this
       project's conventions) close the ticket. Prefer the project's normal
       merge style; do not force-merge over failing checks without flagging
       it to the user first.
     - Fail (either label) → request changes via
       `pull_request_review_write` (`method: "create"`, `state:
       "REQUEST_CHANGES"`) with a body explaining what's wrong and why, plus
       inline `comments` for specific `file:line` issues where useful. Leave
       the PR open; do not close or merge it.
   - **Branch without a PR:**
     - Post the review result as a comment on the ticket via `issue_write`
       (comment), covering what was reviewed and why it passed/failed.
     - Set the outcome label (`state/done`, `state/needs-human`, or
       `state/needs-agent`).
     - Pass (`state/done`) → merge the branch to the main branch yourself
       (following this project's normal merge conventions), then close the
       ticket via `issue_write` (`state: "closed"`).
     - Fail (`state/needs-human` or `state/needs-agent`) → leave the ticket
       open and do not merge the branch; the fix/decision still needs to
       happen before this work is done.
   - **Directly on main branch (no branch/PR):**
     - Post the review result as a comment on the ticket via `issue_write`
       (comment).
     - Set the outcome label (`state/done`, `state/needs-human`, or
       `state/needs-agent`).
     - Pass (`state/done`) → close the ticket via `issue_write`
       (`state: "closed"`). No branch or merge operations apply here.
     - Fail (`state/needs-human` or `state/needs-agent`) → leave the ticket
       open; the change is already on main, but the ticket isn't done until
       the flagged problem is addressed.
   - Look up the numeric label ID via `label_read` — org-scoped first for
     organization-owned repos, repo-scoped for personal `sasu/*` repos —
     rather than skipping the label; see Resources for the lookup procedure
     and current ID table.
6. Only after the comment/PR-decision, label, and close/merge for this
   ticket are done, move on to the next ticket in the list.

After all tickets are processed, **report a short summary** to the user:
which tickets were reviewed, their pass/fail outcome, resulting labels, and
what action was taken (merged, changes requested, or closed), with links to
each ticket/PR.

## Guardrails

- Never combine two tickets' reviews into a single comment, PR decision, or
  merge — one full cycle (review → decide → act → label) per ticket before
  starting the next.
- Never merge a PR or a branch to main without having actually reviewed the
  diff/commits — do not rubber-stamp based on the implementation comment
  alone.
- Never mark `state/done` if you have any doubt the change is correct or
  fully tested; prefer `state/needs-human` or `state/needs-agent` instead.
- Use `state/needs-human` only for cases that genuinely need a human
  decision (ambiguity, tradeoffs, manual verification); default to
  `state/needs-agent` for concrete, fixable problems so the fix loop can
  continue without a human in it.
- When a branch (with or without a PR) is merged to main as part of this
  review, only do so after the outcome label and review comment are already
  posted — do not merge first and label after.
- If `issue_read`/`issue_write`/`label_read`/`pull_request_read`/
  `pull_request_write`/`pull_request_review_write` calls fail, follow the
  MCP fallback order documented in this project's Gitea conventions (`tea`
  CLI, then REST API) rather than silently skipping the ticket.
- Do not force-merge over failing CI checks, delete branches beyond this
  project's normal conventions, or take other hard-to-reverse actions
  without the usual confirmation expectations for such actions.

## Resources

- `../gitea-ticket-refinement/references/gitea-conventions.md` — this
  project's shared Gitea label IDs, lookup procedure, branch/PR conventions,
  and issue-state process (source of truth; kept in sync with
  `template/snippets/gitea.md`). Read this before setting labels or deciding
  how to merge/close.
