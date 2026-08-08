---
name: gitea-ticket-implementation
description: "Use when asked to implement one or more specific Gitea tickets, given as explicit numbers (e.g. \"implement #33, #34 and #35\"). Implements each ticket in order, commits after each one individually, labels it state/needs-review (or state/done if trivial), and posts a comment describing the implementation. Never used for triage or bulk state/triage sweeps — see gitea-ticket-refinement for that."
---

# gitea-ticket-implementation

Implement one or more specific, already-refined Gitea tickets, one at a time,
in the order given. Each ticket gets its own commit, its own outcome label,
and its own implementation-summary comment — never batch multiple tickets
into a single commit or a single comment.

## Scope: which tickets

Read the invocation argument (the text after `/gitea-ticket-implementation`,
or the user's request) to decide which tickets to implement:

- **One or more explicit ticket numbers** (e.g. `42`, `#42`, `42 57 89`, a
  URL) — implement exactly those tickets, in the order listed. Order matters:
  finish and commit one before starting the next, since later tickets may
  depend on earlier ones.
- **No explicit ticket numbers** — do not guess which tickets to implement.
  Ask the user to clarify. This skill never scans for `state/ok-for-dev` or
  any other label on its own initiative.
- **A repo or org qualifier alongside ticket numbers** — scope the lookup to
  that repo/org instead of the current one.

This skill is for implementation only. It does not triage, refine, or
comment-analyze tickets that haven't been implemented yet — use
`gitea-ticket-refinement` for that instead.

## Workflow

Repeat this full cycle for each ticket, in the given order, before moving to
the next one:

1. **Read full context** with `issue_read`: description, comments (including
   any prior refinement analysis), linked issues/PRs, and existing labels.
   Do not rely on the title alone.
2. **Move the ticket to `state/in-progress`** before starting work, per this
   project's Gitea conventions (see Resources).
3. **Implement the change** in this repo:
   - Follow existing structures and conventions in the affected code; prefer
     editing existing files over creating new ones.
   - Decide branch vs. direct-to-main per this project's branch/PR
     conventions (see Resources): small issues may go directly on the main
     branch, more elaborate changes get their own branch (push + PR once
     ready, but leave closing the issue to the reviewer).
   - Run the project's test suite (or the relevant subset) after the change,
     per this project's normal definition of done.
4. **Commit the implementation for this ticket only.** Do not fold multiple
   tickets' changes into one commit, even if they touch overlapping files —
   commit ticket N's work before starting ticket N+1. Reference the issue
   number in the commit message (e.g. `Implement issue #42 (short title)`),
   per this project's Gitea conventions.
5. **Set the outcome label:**
   - `state/needs-review` — the normal outcome once implementation and tests
     are done.
   - `state/done` instead, only if the change was trivial (e.g. a simple
     configuration change) per this project's Gitea conventions.
   - Look up the numeric label ID via `label_read` — org-scoped first for
     organization-owned repos, repo-scoped for personal `sasu/*` repos —
     rather than skipping the label; see Resources for the lookup procedure
     and current ID table.
6. **Post a comment describing the implementation** via `issue_write`
   (comment), covering:
   - What was changed and where (concrete `file:line` references), in your
     own words.
   - How it was verified (tests run, manual check performed).
   - Branch/PR link, if one was opened.
   - Any follow-up or deviation from the original refinement analysis worth
     flagging to the reviewer.
   Do not overwrite or delete existing comments or the issue body.
7. Only after the commit, label, and comment for this ticket are done, move
   on to the next ticket in the list.

After all tickets are processed, **report a short summary** to the user:
which tickets were implemented, their resulting commits, resulting labels,
and links to each ticket.

## Guardrails

- Never combine two tickets' changes into a single commit, label update, or
  comment — one full cycle (implement → commit → label → comment) per ticket
  before starting the next.
- Never skip straight to `state/done` unless the change is genuinely trivial;
  default to `state/needs-review`.
- Never move a ticket to `state/in-progress` without intending to finish that
  cycle before moving to the next ticket.
- If a ticket turns out to be unclear or missing information once you read
  it, stop and flag it to the user (or set `state/needs-info` with a comment
  explaining the blocking question) rather than guessing at the intended
  behavior.
- If `issue_read`/`issue_write`/`label_read` calls fail, follow the MCP
  fallback order documented in this project's Gitea conventions (`tea` CLI,
  then REST API) rather than silently skipping the ticket.
- Do not push to remote or open PRs beyond what this project's normal
  workflow calls for without following the usual confirmation expectations
  for hard-to-reverse actions.

## Resources

- `../gitea-ticket-refinement/references/gitea-conventions.md` — this
  project's shared Gitea label IDs, lookup procedure, branch/PR conventions,
  and issue-state process (source of truth; kept in sync with
  `template/snippets/gitea.md`). Read this before setting labels or deciding
  branch vs. direct-to-main.
