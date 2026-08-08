---
name: update-agent-docs
description: "Use when agent instruction docs (AGENTS.md, CLAUDE.md, copilot-instructions.md, always-on.md) have drifted apart within a project because each agent only updates its own file. Reconciles them by merging differing content into the project's .agent-docs/template.md source of truth, then re-deploys all docs from it so they match again."
---

# update-agent-docs

Agent instruction files (`AGENTS.md`, `CLAUDE.md`,
`.github/copilot-instructions.md`, `.agents/rules/always-on.md`) are all
rendered from one project-local source, `.agent-docs/template.md`. Drift
happens when an agent edits its own deployed file directly instead of the
template — the next `deploy`/`refresh` then either overwrites that edit or
reports a conflict and leaves it alone. This skill reconciles the files back
into one source and re-deploys.

Never hand-copy text between the deployed files. The template is always the
single source of truth; edits belong there, and the deployed files are
regenerated from it.

## Workflow

1. **Inventory the current state.**
   ```sh
   adm docs list .
   ```
   Files reported `managed current` match the template already — nothing to
   merge for those. `managed modified` or `custom` files carry drift and need
   review. `missing` files just need a normal deploy at the end, no merge.

   If `.agent-docs/template.md` does not exist yet in this project, there is
   no merge target. Ask the user whether to scaffold one now
   (`adm docs init .`, which creates the template from the repo default and
   deploys) before continuing, or treat one of the existing deployed files as
   the seed.

2. **Diff each deployed file against the template.**
   Read `.agent-docs/template.md` and each `managed modified`/`custom` file
   reported in step 1 (`AGENTS.md`, `CLAUDE.md`,
   `.github/copilot-instructions.md`, `.agents/rules/always-on.md`). Use
   `diff` or read both and compare manually for a clear picture of what each
   agent added or changed that the others don't have.
   ```sh
   diff .agent-docs/template.md CLAUDE.md
   ```
   Note that the deployed files are supersets of the template in one
   respect: `deploy-agent-docs.sh` renders a per-language snippet block
   (see step 4) into a `<!-- agent-docs snippets:start/end -->` region and a
   language-specific `<!-- AGENT_DOCS_LANGUAGE_SNIPPETS -->` marker in the
   template. That block is expected divergence, not drift — do not merge
   snippet content back into the template body; handle snippets separately
   in step 4.

3. **Merge genuine drift into the template.**
   For every other difference — a new section one agent added, a corrected
   command, an updated convention — decide where it belongs in
   `.agent-docs/template.md` and edit the template there, not any of the
   deployed files. If two files disagree (e.g. CLAUDE.md and AGENTS.md
   document conflicting test commands), reconcile the conflict with the user
   rather than picking one arbitrarily, unless the correct answer is obvious
   from the repo state (e.g. one command no longer exists).

4. **Reconcile snippets alongside the template.**
   Snippets are shared reference blocks (language/tool conventions) that
   `deploy-agent-docs.sh` injects into the rendered docs; they live outside
   the template file itself, in `template/snippets/*.md` (or wherever
   `AGENT_DOCS_SNIPPET_DIR` points), not inline in the deployed docs. List
   what's available and compare against what the project's deploy has been
   including:
   ```sh
   adm docs list-snippets
   cat .agent-docs/snippets   # project's persisted selection, if present
   ```
   If a deployed file has snippet-block content that doesn't match any
   existing snippet file (an agent hand-wrote a language/tool section
   directly into e.g. CLAUDE.md instead of using a snippet), treat that as
   drift too: either it belongs in the template body proper (project-specific,
   not reusable), or — if it looks like reusable per-language/tool guidance
   another project could also use — propose extracting it as a new snippet
   file under `template/snippets/` and ask the user before adding one (new
   snippets are a repo-wide addition, not a project-local change). Do not
   silently invent new snippet files.

5. **Clear the deployed files.**
   ```sh
   adm docs clear .
   ```
   By default this only removes files that are unmodified since their last
   known deployment, and leaves `custom`/edited files alone (so if step 3
   fully captured the drift into the template, the files it leaves behind
   are stale and about to be regenerated identically). If `clear` reports
   conflicts for files you've already merged into the template, that's
   expected — `deploy` in the next step will report and refresh them.

6. **Redeploy from the reconciled template.**
   ```sh
   adm docs deploy .
   ```
   Pass `--snippet a,b,c` or `-i/--interactive` if step 4 changed which
   snippets this project should include; otherwise the project's persisted
   `.agent-docs/snippets` selection (if any) is reused automatically, merged
   with auto-detected language snippets.

7. **Verify.**
   ```sh
   adm docs list .
   ```
   Every file should now report `managed current`. Read one or two of the
   regenerated files to confirm the merged content landed where expected.
   Do not run any repository-internal test suite after updating these
   documents: generated agent instructions are not part of the normal code
   base. This `adm docs list` check is the required verification.

8. **Commit.**
   Stage `.agent-docs/template.md` and the regenerated instruction files
   together as one change (plus any new file under `template/snippets/` if
   step 4 added one), per the repo's normal commit conventions.

## Notes

- This workflow is project-local. Global docs (`adm docs list -g` /
  `adm docs deploy -g`) follow the same merge-then-redeploy shape but merge
  into `template/agent-instructions-global.md` in the agent-docs repo itself,
  not a project's `.agent-docs/template.md`.
- If `adm docs clear .` or `adm docs deploy .` reports persistent conflicts
  after the merge, re-check step 2 — a file with content not yet reflected
  in the template will keep showing as `custom`/`modified` since the tool
  can't tell a merged edit from an unmerged one.
