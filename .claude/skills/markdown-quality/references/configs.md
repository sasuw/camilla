# Baseline Markdown configs

Copy these into a project root when it has no markdown tooling config yet. They
are tuned so Prettier and markdownlint do not contradict each other, and so the
signal-to-noise ratio stays usable on documentation that predates the tooling.

## `.prettierrc`

```json
{
  "proseWrap": "preserve",
  "overrides": [
    {
      "files": "*.md",
      "options": {
        "tabWidth": 2
      }
    }
  ]
}
```

`proseWrap: "preserve"` is the important setting. The alternatives both cause
problems on an existing repository:

- `"always"` reflows every paragraph to the print width, rewriting essentially
  every documentation file the first time it runs.
- `"never"` joins each paragraph onto one long line, which makes git diffs
  useless — a one-word edit shows as a whole-paragraph change.

`"preserve"` keeps existing line breaks and still fixes tables, code fences, and
list indentation.

## `.markdownlint-cli2.yaml`

```yaml
config:
  # Prettier owns these; enabling them makes the two tools fight.
  MD004: false # ul-style
  MD007: false # ul-indent
  MD013: false # line-length — see SKILL.md
  MD060: false # table-column-style — Prettier normalizes tables

  # Duplicate headings are legitimate under different parents
  # (e.g. repeated "Usage" sections).
  MD024:
    siblings_only: true

  # Allow inline HTML that Markdown cannot express.
  MD033:
    allowed_elements:
      - br
      - details
      - summary
      - kbd

globs:
  - "**/*.md"

ignores:
  - "node_modules"
  - ".git"
  # Snippet fragments are concatenated into larger documents and
  # intentionally start at a non-h1 heading level.
  - "template/snippets/*.md"
```

### Notes on specific rules

**MD024 `siblings_only`.** Without this, a document with `## Usage` under two
different top-level sections is flagged. Sibling-only scoping catches the real
case (the same heading twice in one section) and ignores the false one.

**MD033 `allowed_elements`.** Markdown has no syntax for line breaks inside a
table cell, collapsible sections, or keyboard keys. These four elements cover
the common needs; add to the list rather than disabling MD033 entirely, which
would let arbitrary HTML through.

**MD040 is intentionally left on.** A code fence with no language loses syntax
highlighting everywhere the document renders. It is not autofixable — the tool
cannot guess the language — so it will produce findings that need a human to
resolve. That is the intended behaviour.

**MD041 stays on, with fragments excluded by path.** Rather than disabling the
rule globally, the `ignores` entry exempts only the files that are genuinely not
standalone documents. Extend that list for a project's own fragment locations.

## Adopting this on an existing repository

Run the tooling once and commit the mechanical result as its own commit, before
any content change, so the formatting churn does not hide real edits in review:

```sh
npx -y prettier --write "**/*.md"
npx -y markdownlint-cli2 --fix "**/*.md"
```

Then re-run the linter without `--fix` and work through what remains by hand.
On a large documentation tree, consider doing this per-directory instead of all
at once.
