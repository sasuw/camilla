---
name: gitea-ticket-refinement
description: "Use when asked to refine, triage, or groom Gitea tickets — either all tickets labeled state/triage, or one or more specific ticket numbers. Analyzes each ticket and posts the analysis as a comment to prepare it for development; never modifies code or does implementation work in this repo."
---

# gitea-ticket-refinement

Refine Gitea tickets by analyzing them and leaving the analysis as a comment,
so a developer (human or agent) has a clear basis for implementation. This
skill only analyzes and comments — it never edits code, opens branches, or
does implementation work in this repo, regardless of what the analysis
concludes.

## Scope: which tickets

Read the invocation argument (the text after `/gitea-ticket-refinement`) to
decide which tickets to refine:

- **No argument, or "triage"/"all"** — refine every open ticket in the current
  repo (or the repo/org specified by the user) labeled `state/triage`.
- **One or more ticket numbers** (e.g. `42`, `#42`, `42 57 89`, a URL) — refine
  exactly those tickets, regardless of their current label. Do not require
  `state/triage` in this mode; the user is explicitly pointing at a ticket.
- **A repo or org qualifier alongside either of the above** — scope the
  `state/triage` search or the ticket lookup to that repo/org instead of the
  current one.

If neither a `state/triage` scope nor explicit ticket numbers can be
determined from the argument or conversation, ask the user to clarify rather
than guessing.

## Workflow

1. **Identify the target tickets.**
   - Triage-all mode: use `search_issues` (or `list_issues` with a label
     filter) scoped to the target repo/org, filtering for open issues labeled
     `state/triage`.
   - Specific-ticket mode: resolve each given number/URL to its repo and
     issue number with `issue_read`.
2. **For each ticket, read full context** with `issue_read`: description,
   comments, linked issues/PRs, and existing labels. Do not rely on the title
   alone.
3. **Analyze the ticket** as if preparing it for a developer who has not seen
   it before. Cover, as applicable:
   - Problem statement / goal in your own words (confirms you understood it).
   - Relevant code areas or files, found via repo search — reference concrete
     paths (`file:line`) instead of vague pointers.
   - Suggested approach or implementation sketch, including edge cases,
     affected tests, and any migration/config/doc updates likely needed.
   - Open questions or missing information that block a confident
     implementation.
   - Rough complexity/size signal (trivial / small / needs a branch+PR) if
     it's clear from the analysis — this repo's convention only requires a PR
     for more elaborate changes.
   - Do not perform the work: no code edits, no running mutating commands
     against this repo, no opening branches or PRs.
4. **Post the analysis as a new comment** on the ticket via `issue_write`
   (comment). Do not overwrite or delete existing comments or the issue body.
5. **Set the outcome label:**
   - If the analysis leaves no blocking open questions and a developer could
     start immediately: label `state/ok-for-dev`.
   - If there are blocking open questions: label `state/needs-info` instead,
     and make the specific question(s) explicit in the comment.
   - Follow `state/*` label lookup and ID-resolution rules from this
     project's Gitea conventions (see Resources) — labels use numeric IDs,
     not names, and are org-scoped for organization-owned repos but
     repo-scoped for personal `sasu/*` repos; look up the ID for the correct
     scope, don't skip labeling, and don't create a duplicate repo-level
     label on an organization-owned repo.
6. **Report a short summary** to the user: which tickets were refined, which
   ended up `state/ok-for-dev` vs `state/needs-info`, and links to each.

## Guardrails

- Never modify code, config, or docs in this repo as part of refinement.
- Never remove or replace the `state/triage` label with anything other than
  `state/ok-for-dev` or `state/needs-info` based on the analysis outcome.
- If a ticket already has a comment that looks like a prior refinement
  analysis (from you or another agent), re-read it before adding a new one —
  add an updated analysis only if something materially changed; don't spam
  duplicate comments.
- If `issue_read`/`issue_write`/`label_read` calls fail, follow the MCP
  fallback order documented in this project's Gitea conventions (`tea` CLI,
  then REST API) rather than silently skipping the ticket.

## Resources

- `references/gitea-conventions.md` — this project's shared Gitea label IDs,
  lookup procedure, and issue-state process (source of truth; kept in sync
  with `template/snippets/gitea.md`).
