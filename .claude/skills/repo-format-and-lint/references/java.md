# Java formatting and linting

Use project-local Java tooling whenever it exists. Prefer wrapper commands
(`./mvnw`, `./gradlew`) over system `mvn` or `gradle`.

## Discovery

Check for:

- Maven: `pom.xml`, `.mvn/`, `mvnw`
- Gradle: `build.gradle`, `build.gradle.kts`, `settings.gradle`,
  `settings.gradle.kts`, `gradlew`
- Formatting or lint plugins: Spotless, Checkstyle, PMD, SpotBugs, Error Prone,
  formatter plugins, OpenRewrite
- Compiler warnings: Maven compiler plugin, Gradle Java compiler options,
  `-Xlint`, `-Werror`

## Preferred commands

Use the commands the repo documents first. If the project has Spotless, prefer:

| Build tool | Apply formatting | Check formatting |
| ---------- | ---------------- | ---------------- |
| Maven | `./mvnw spotless:apply` or `mvn spotless:apply` | `./mvnw spotless:check` or `mvn spotless:check` |
| Gradle | `./gradlew spotlessApply` | `./gradlew spotlessCheck` |

If Checkstyle, PMD, SpotBugs, Error Prone, are already
configured, run the narrowest relevant command after formatting.

## Import cleanup

Prefer configured Java tooling for import ordering and unused imports:

- Spotless with `removeUnusedImports`
- IDE/LSP organize-imports support if available
- OpenRewrite recipes if already configured
- Compiler or linter checks already wired into Maven or Gradle

Do not write ad-hoc `grep`, `awk`, or Python import scanners for Java unless no
project tool or compiler path is available and the user explicitly accepts the
limitation. Static imports, wildcard imports, same-package classes, nested
classes, annotations, generated sources, and conditional source sets make these
scans easy to get wrong.

## Adding tooling when requested

When the user asks to add formatting enforcement, Spotless is the usual default:

- Use `google-java-format` or the project's existing Java style.
- Enable import ordering and unused-import cleanup when compatible.
- Add an apply command, a check command, and CI enforcement.
- Keep formatting-only commits separate from behavior changes when practical.
