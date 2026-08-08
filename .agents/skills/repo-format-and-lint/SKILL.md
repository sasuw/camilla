---
name: repo-format-and-lint
description: "Use when editing code, cleaning imports, fixing formatting or lint findings, or preparing changes for commit. Discovers and runs the repository configured formatter, linter, import organizer, and check commands instead of ad-hoc parsing."
---

# Repo Format and Lint

Use this skill to keep agent edits aligned with the repository's own formatting,
linting, and import cleanup tooling.

## Workflow

1. Determine the repository root and inspect existing project guidance.
   - Read agent instruction files, README/developer docs, package manager files,
     and CI config for documented format, lint, import cleanup, and test commands.
   - Prefer commands already documented by the project over inferred commands.

2. Discover existing formatter and linter tooling before writing custom checks.
   - Look for ecosystem configuration such as `pom.xml`, `build.gradle`,
     `package.json`, `biome.json`, `.prettierrc`, `eslint.config.*`,
     `pyproject.toml`, `ruff.toml`, `go.mod`, `.clang-format`, `.editorconfig`,
     and CI workflow files.
   - Prefer project-local commands and wrappers: `./mvnw`, `./gradlew`,
     `npm run`, `pnpm`, `yarn`, `npx`, `uv run`, `poetry run`, `make`, or
     checked-in scripts.
   - Do not install global tools or introduce new formatter configuration unless
     the user asks for that setup.

3. Use official tooling instead of brittle text parsing.
   - Do not invent `grep`, `awk`, `sed`, or one-off Python static-analysis scans
     for formatting, import organization, or unused-import cleanup when a project
     formatter, compiler, language server, or linter can do the job.
   - Simple search tools are fine for locating files or symbols; they are not a
     substitute for a formatter, linter, compiler, or static analyzer.

4. Apply the smallest safe automated cleanup.
   - Run the narrowest autofix/format command that covers the touched files or
     module when the tool supports it.
   - Avoid whole-repository formatting churn unless the project convention is to
     format the whole repository or the user explicitly requested it.
   - If no formatter or linter exists, say so and suggest adding one instead of
     silently guessing a style.

5. Verify with check mode.
   - After autofix, run the corresponding non-mutating check command when
     available.
   - For non-trivial code changes, run the repository's relevant tests after
     formatting and linting.
   - If the configured tool fails on pre-existing unrelated issues, report the
     failing scope and keep the user's changes separate from unrelated cleanup.

## Resources

- `references/java.md` covers Maven/Gradle Java formatting and import cleanup.
- `references/js-ts.md` covers JavaScript, TypeScript, JSON, CSS, and Markdown
  formatting and linting.
