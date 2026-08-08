---
trigger: always_on
description: "Always-on instructions for Antigravity"
---
# Project Instructions

## Project overview

<!-- One paragraph: what this project does and its primary tech stack. -->

## Repository structure

<!-- Key directories and what they contain. -->

```
src/        # application source
tests/      # test suite
docs/       # documentation
```

## Development workflow

<!-- How to build, run, and test the project. -->

```sh
# Install dependencies
# npm install / pip install -r requirements.txt / ...

# Run tests
# npm test / pytest / ...
```

## Code conventions

<!-- Language, formatting, naming rules that matter most. -->

- Language/runtime version: <!-- e.g. Node 22, Python 3.12 -->
- Formatter: <!-- e.g. prettier, black -->
- Key rules: <!-- e.g. no default exports, snake_case functions -->

## Project-specific guidance


### Shell

- Bash and zsh are equally acceptable.
- Preserve an existing script's shell language, dialect, and shebang.
- For new scripts, use the shell language already used by most of the repository unless project requirements give a reason to choose another.
- Use `set -euo pipefail` for Bash scripts unless the script intentionally handles unset values or non-zero statuses.
- All shell scripts intended to be run directly should have `-h`/`--help` usage output.
- Add a `-n`/`--dry-run` option for scripts making permanent changes to the system, other systems, or transmitting data over the network.
- Use snake_case for shell script file names.
- Use snake_case for function names in shell scripts.
- Keep scripts compatible with typical default installations of modern macOS, Linux (especially Debian-based), and FreeBSD.
- Quote variable expansions unless word splitting is explicitly required.
- Use `shellcheck` and `bash -n` to validate Bash scripts. `shellcheck` does not support zsh.
- Use `zsh -n` to check zsh syntax. Use a repository-configured zsh formatter or linter when available.
- Use `shfmt` only for shell dialects it supports, not for zsh.
- Do not hardcode home directory paths (e.g. `/Users/<user>`, `/home/<user>`). Prefer `$HOME`; use `~` only where `$HOME` does not work (e.g. `.gitconfig`). Only fall back to a hardcoded home directory path if neither is possible.
- Do not use `path` or `status` as variable names in zsh scripts.
- Scripts compute their own `SCRIPT_DIR` / `REPO_ROOT` with a shell-appropriate mechanism, such as `$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)` in Bash or `${0:A:h}` in zsh.
- Shared logic lives in lib files (e.g., `homebin/ssh-key-scan-lib.sh`) that are `source`d by consumers — not copied
- Errors go to stderr via a dedicated error function (e.g., `ssh_key_scan_err()`)
- Dependencies are checked with `require_command` / `ensure_*_commands` at startup


### Markdown and Documentation

- Keep headings hierarchical and use descriptive link text.
- Update nearby documentation when behavior, commands, or configuration paths change.
- Prefer concise examples that can be copied and run as written.
- Check rendered tables and lists when making structural documentation changes.


## Agent guidance

<!-- What the agent should and should not do autonomously. -->

- Prefer editing existing files over creating new ones.
- After any non-trivial change: run the repository's configured linter, compile, and run the test suite
