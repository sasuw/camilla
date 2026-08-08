---
name: markdown-quality
description: "Lint, format, and link-check Markdown using markdownlint-cli2, Prettier, and lychee. Use when writing or editing Markdown docs, fixing markdown lint findings, checking documentation links, normalizing tables and code fences, or setting up markdown tooling config in a project."
---

# markdown-quality

Lint, format, and link-check Markdown. All tools run through `npx` or a
standalone binary; nothing needs a global install.

## Tools

| Tool              | Job                                                    | Invocation                 |
| ----------------- | ------------------------------------------------------ | -------------------------- |
| Prettier          | Formatting: wrapping, tables, fences, list indentation | `npx -y prettier`          |
| markdownlint-cli2 | Structural linting: headings, fences, bare URLs        | `npx -y markdownlint-cli2` |
| lychee            | Dead link checking, internal and external              | `lychee` (see below)       |

## Order matters

Prettier and markdownlint overlap and will fight each other over list
indentation and emphasis markers. Always run Prettier first, then markdownlint.
The baseline config in `references/configs.md` disables the markdownlint rules
that Prettier already owns, so the two do not contradict each other.

Never run markdownlint `--fix` before Prettier: markdownlint makes edits that
Prettier then reverts, producing churn with no net change.

## Workflow

1. Determine scope. Default to **only the files the current task touched**.
   Whole-repository formatting produces large diffs across files nobody meant to
   change. Format the whole tree only when the user asks for it.

2. Check for existing project config before applying any style.
   - Look for `.markdownlint-cli2.yaml`, `.markdownlint.json`, `.prettierrc*`,
     `.editorconfig`, and any lint targets in CI config.
   - An existing config wins. Do not override a project's chosen style.
   - If no config exists and the user wants one, copy the baseline from
     `references/configs.md` rather than inventing rules.

3. Format.

   ```sh
   npx -y prettier --write <paths>
   ```

   Use `--check` instead of `--write` for a non-mutating verification pass.

4. Lint, with autofix for the mechanical rules.

   ```sh
   npx -y markdownlint-cli2 --fix <globs>
   ```

   Then re-run without `--fix` to see what remains. Findings that survive
   autofix need a human judgement call — most often `MD040` (a code fence with
   no language) and `MD024` (duplicate headings).

5. Link-check when the change touched links, or on request.

   ```sh
   lychee --offline <paths>     # internal links only, fast, no network
   lychee <paths>               # includes external URLs
   ```

   Prefer `--offline` by default. Full external checking reaches the public
   internet, is slow, and produces false positives on rate-limited hosts — run
   it only when the user asks to verify external links.

6. Report what changed. If a tool fails on pre-existing unrelated issues, say so
   and keep those separate from the user's change.

## Glob hazards

`markdownlint-cli2 .` does not mean "this tree" — it is remapped to `*.md` in
the current directory only. Use `"**/*.md"` for a recursive pass, and always
exclude vendored trees:

```sh
npx -y markdownlint-cli2 "**/*.md" "#node_modules" "#.git"
```

Quote every glob. An unquoted `**/*.md` is expanded by the shell rather than the
tool, which changes which files are matched.

## Rules deliberately left off

The baseline disables two rules that otherwise account for the large majority of
findings on existing prose:

- **MD013 (line-length).** Pure preference, and it fires on every long table row
  and URL. Enable it only in a project that has actually committed to a wrap
  width.
- **MD060 (table-column-style).** Cosmetic pipe alignment. Prettier already
  normalizes tables; this rule just disagrees about padding.

Leaving these on buries the structural findings that matter under thousands of
style complaints.

## Fragment files

Files that are intentionally not standalone documents — snippet and partial
templates such as `template/snippets/*.md`, which start at `###` and are
concatenated into a larger document — trip `MD041` (first line should be a
top-level heading). Exclude them by path in the config rather than adding an h1
that would corrupt the assembled output.

## Installing lychee

lychee is a Rust binary and is not available through `npx`. It is optional; the
lint and format steps work without it. If link checking is needed and `lychee`
is not on `PATH`, tell the user rather than installing it unprompted:

```sh
cargo install lychee
```

## Resources

- `references/configs.md` — baseline `.markdownlint-cli2.yaml` and `.prettierrc`
  to copy into a project, with the reasoning behind each setting.
