---
name: zsh-scripting
description: Best practices, pitfalls, and language-level traps for writing, reviewing, or debugging zsh and shell scripts. Covers zsh-vs-bash differences, cross-process quoting, stdin consumption, PATH/dependency traps, failure modes, and testing.
license: MIT
compatibility: Requires zsh (5.x+)
---

# zsh-scripting

Language-level guidance, anti-patterns, and failure modes for writing, reviewing, or debugging zsh scripts across repositories.

> [!IMPORTANT]
> **Tooling Disclaimer**: `shellcheck` only parses Bourne/POSIX/bash syntax. It does not validate zsh scripts. When run against zsh code, `shellcheck` produces false positives (such as SC2004 on zsh array subscript flags like `(Ie)`) while missing critical zsh runtime traps like read-only variable collisions or arithmetic exit code failures under `set -e`. Do not rely on `shellcheck` for zsh validation; use `zsh -n` for syntax checking and consult the traps below.

---

## 1. zsh is not bash

### Reserved variable collisions
- **Trap**: Using variable names like `status`, `path`, `argv`, `options`, `cdpath`, `fignore`, or `mailpath` as local or script variables.
- **Why it fails silently / fatally**: zsh binds these special names to internal shell state. Assigning to `status` fails with `read-only variable: status`. `local path=...` is worse: it shadows the array/scalar pair tied to `$PATH`, so `PATH` is empty for the rest of the function — every command lookup in that scope fails, including indirect ones (e.g. a tool that shells out to a helper binary), with an error that looks unrelated to the shadowing (`exec: "gpg": executable file not found in $PATH`) and gives no hint that a `local` declaration is the cause.
- **Correct form**: Use distinct names for script variables. Knowing the rule is not enough — it is easy to write anyway in a long function — so check for it mechanically rather than by memory:
  ```zsh
  # WRONG
  local status=$?
  local path="/tmp/export"

  # RIGHT
  local exit_code=$?
  local export_dir="/tmp/export"

  # Mechanical check: run before committing, any match is a bug
  grep -nE '\b(local|typeset|declare)\b[^;]*\b(path|status|argv|options|cdpath|fignore|mailpath)\b' script.zsh
  ```

### `$0` inside a function is the function name, not the script
- **Trap**: Using `$0` inside a function body (e.g. in a `usage()` helper) to print the script's own name or path.
- **Why it fails silently**: zsh enables `FUNCTION_ARGZERO` by default, so `$0` inside a function resolves to the *function's* name, not the script's. bash prints the script path here, so this is a genuine zsh-vs-bash difference. The output still looks plausible, which is what makes it easy to ship unnoticed.
  ```zsh
  #!/usr/bin/env zsh
  usage() { print "Usage: $0 [-h]" }
  usage
  ```
  ```
  $ ./argzero.zsh
  Usage: usage [-h]        # wanted: Usage: ./argzero.zsh
  ```
- **Correct form**: Capture the name at file scope, outside any function, and reference that variable instead of `$0` inside the function:
  ```zsh
  SCRIPT_NAME="${0:t}"           # or "$0" for the full path
  usage() { print "Usage: ${SCRIPT_NAME} [-h]" }
  ```

### `set -e` and arithmetic evaluation
- **Trap**: Using `(( x++ ))` or `(( count++ ))` to increment counters when `set -e` is active.
- **Why it fails silently**: In zsh (and bash), `(( expr ))` returns exit status 1 if `expr` evaluates to 0. When `x=0`, post-increment `(( x++ ))` evaluates to 0 *before* incrementing. Under `set -e`, an exit code of 1 aborts the script immediately with no error message.
- **Correct form**: Guard arithmetic increments or use explicit assignment.
  ```zsh
  set -euo pipefail

  # WRONG - aborts immediately when count is 0
  (( count++ ))

  # RIGHT - guarded arithmetic or explicit math
  (( count++ )) || true
  # OR
  count=$(( count + 1 ))
  ```

### Reading stdin into a variable
- **Trap**: Writing `$(<&0)` to capture standard input.
- **Why it fails silently**: `$(<&0)` attempts to execute a command named `<&0` or invoke a subshell command substitution incorrectly.
- **Correct form**: Use `IFS= read -rd '' var` to slurp stdin into a variable using builtins only. Note that `read` returns exit code 1 upon reaching EOF, so guard it under `set -e`.
  ```zsh
  # WRONG
  payload="$(<&0)"

  # RIGHT
  IFS= read -rd '' payload || true
  ```

### Fatal globbing by default
- **Trap**: Running file operations with globs where zero files might match, e.g., `rm -f *.bak`.
- **Why it fails silently / fatally**: Unlike bash (which leaves unmatched globs as literal strings), zsh raises `zsh: no matches found: *.bak` and aborts command execution unless `null_glob` is enabled. This is the second case (with `set -e` + arithmetic above) where bash intuition actively misleads: bash's default lets the pattern pass through unchanged, zsh's default aborts.
- **Correct form**: Enable `null_glob` before un-guaranteed globs, or use zsh glob qualifiers `(N)`.
  ```zsh
  # WRONG - aborts script if no .bak files exist
  rm -f *.bak

  # RIGHT - set option in script header or scope
  setopt null_glob
  rm -f *.bak

  # RIGHT - explicit null-glob qualifier (N)
  rm -f *.bak(N)
  ```

### Globs inside remote commands expand locally, not on the remote host
- **Trap**: Writing `ssh host 'rm /some/dir/*.bak'` (or building the command string without the outer quotes) and expecting the glob to match files on the remote host.
- **Why it fails silently / fatally**: A glob is expanded by whichever shell parses it first. If it isn't fully inside quotes that reach `ssh` as one argument, the *local* shell expands it against the *local* filesystem before `ssh` ever runs — and by the "fatal globbing by default" trap above, a local no-match aborts the whole command, even if matching files exist on the remote host. One failing pattern in a multi-pattern command aborts all of it, so a second pattern that would have matched remotely is never attempted either.
- **Correct form**: Keep the whole remote command in one quoted string, and prefer `find` (which does its own matching on the remote host) over a bare glob for remote cleanup — list with `-print` before adding `-delete` as a reviewable dry run.
  ```zsh
  # WRONG - if the surrounding quotes are dropped or the glob leaks out, the
  # local shell expands (or aborts on) *.bak.* against the local filesystem
  ssh host 'rm /etc/app/*.bak.* /etc/other/*.bak.*'

  # RIGHT - find matches remotely; no local glob expansion possible
  ssh host 'find /etc/app /etc/other -maxdepth 1 -type f -name "*.bak.*" -print -delete'
  ```

### Declare associative arrays with their initializer combined
- **Trap**: Splitting an associative array declaration into `typeset -A M` followed by a separate `M=( [key]=value )` assignment.
- **Why it fails silently**: `zsh -n` parses without executing, so at the point it parses the assignment line, the earlier `typeset -A` has not "taken effect" yet. The subscript is then read as an arithmetic expression and the parse fails — even though the script runs correctly, since by runtime the array *is* declared:
  ```zsh
  #!/usr/bin/env zsh
  typeset -A M
  M=(
    [/a/b]=30
  )
  print "runtime ok: ${M[/a/b]}"
  ```
  ```
  $ zsh -n assoc.zsh
  assoc.zsh:3: bad math expression: operand expected at `/a/b'
  $ ./assoc.zsh
  runtime ok: 30
  ```
  This is not about slashes in the key — a plain key fails the same way, with a different message (`bad subscript for direct array assignment`). See also the `zsh -n` caveat in the pre-commit checklist below.
- **Correct form**: Combine the declaration and the initializer in one statement. This passes both `zsh -n` and runtime, and keeps the readable `[key]=value` subscript syntax:
  ```zsh
  # WRONG - passes at runtime but fails zsh -n
  typeset -A M
  M=( [/a/b]=30 )

  # RIGHT - passes both zsh -n and runtime
  typeset -A M=( [/a/b]=30 )
  ```

### 1-based array indexing and membership lookup
- **Trap**: Assuming 0-based array indexing or using loops to check array membership.
- **Why it fails silently**: zsh arrays are 1-indexed (`$arr[1]` is the first element, `$arr[0]` is empty).
- **Correct form**: Use 1-based indices and zsh subscript flag `(Ie)` for exact element membership checks.
  ```zsh
  typeset -a items=(alpha beta gamma)

  # 1-based indexing
  first_item="$items[1]"  # "alpha"

  # Membership check: returns index (1..N) if found, 0 if missing
  if (( ${items[(Ie)beta]} > 0 )); then
    echo "Found beta at index ${items[(Ie)beta]}"
  fi
  ```

---

## 2. Quoting across process boundaries

### Single-level quoting rule
- **Trap**: Nesting quotes across multiple execution boundaries (e.g. local script → `ssh` → remote shell → `psql`).
- **Why it fails silently**: Each shell layer strips one level of quotes and evaluates special characters. Variable interpolations like PostgreSQL `:'var'` or shell variables silently degrade to literal strings or empty values across three layers of quoting.
- **Correct form**: Never nest more than one level of quoting. Construct the payload in the destination shell, or pass data strictly via standard input.
  ```zsh
  # WRONG - nested quoting across ssh into remote psql degrades variables silently
  ssh remote_host "psql -U dbuser -c \"SELECT * FROM users WHERE name = ':'var'\";\""

  # RIGHT - stream payload via stdin to avoid remote quoting layers
  cat <<'SQL' | ssh -n remote_host "psql -U dbuser -f -"
  SELECT * FROM users WHERE name = 'alice';
  SQL
  ```

### Target language escaping
- **Trap**: Using shell escaping functions (`${(q)var}` or `printf %q`) to escape values destined for non-shell execution targets (SQL, JSON, YAML).
- **Why it fails silently**: Escaping rules belong strictly to the *destination* engine. PostgreSQL string literals require doubled single quotes (`''`), whereas bash backslash escapes (`\'`) cause SQL syntax errors or data corruption.
- **Correct form**: Pass parameters safely via SQL parameterization/stdin or target-specific formatters (`jq`, `yq`).

### Separators: never NUL, never a raw control byte
- **Trap**: Joining fields with a NUL byte (`\0`) because it cannot occur in the data, and writing that byte *literally* into the source.
- **Why it fails silently**: Two separate failures, both silent.
  - **NUL cannot cross a process boundary.** `execve(2)` arguments and the environment are NUL-terminated C strings, so a NUL truncates the value rather than being carried as data — `env X="$(printf 'a\0b')" sh -c 'echo ${#X}'` prints `1`, not `3`. It survives only in a pure pipe/redirect path. No error is raised; the data is just gone.
  - **A raw control byte in source breaks your tooling.** A literal `0x00` makes `file(1)` classify the source as `data`, so `grep` treats it as binary and prints *nothing* — no error, no warning, just a silent wrong answer that reads as "this code doesn't exist". Exact-match edits also fail, because the byte is invisible in normal output. A literal `0x1F` causes the same tooling failures.
- **Correct form**: Pick a separator that cannot appear in the data — `0x1F` (unit separator) between fields, `0x0A` (newline) between records — and **always write it as an escape, never as a literal byte**. Extract it to a named constant so it appears once.
  ```zsh
  # WRONG - NUL as separator, truncates across any argv/env boundary
  key="${source_id}"$'\0'"${name}"

  # WRONG - correct byte, but pasted literally into the source (breaks grep)
  # key="${source_id}<a literal 0x1f here>${name}"

  # RIGHT - unit separator, written as an escape
  readonly KEY_SEP=$'\x1f'
  key="${source_id}${KEY_SEP}${name}"

  # RIGHT - splitting fields back apart
  while IFS= read -r -d $'\x1f' field; do
    printf 'field=[%s]\n' "$field"
  done
  ```
- **Exception**: `find -print0 | xargs -0` (and `read -d ''` paired with it) is correct and idiomatic. It stays inside a pipe, never crossing an argv/env boundary, and the NUL is written as an escape rather than embedded in source. This rule does not forbid it.
- **Corollary**: When *searching* for a control character, name it by escape rather than pasting it — `grep -P '\x1f' file`, `tr -dc '\000' <file | wc -c`, `cat -A file`. Pasting the byte into a search pattern reproduces the problem in the search itself.

---

## 3. stdin discipline

### `ssh` consumes stdin
- **Trap**: Invoking `ssh` inside a loop reading lines from stdin or before an interactive prompt.
- **Why it fails silently**: `ssh` by default reads from standard input to forward it to the remote process. Running `ssh` inside a `while read line` loop causes `ssh` to drain all remaining lines from stdin on the first iteration, silently terminating the loop prematurely.
- **Rule**: **Always pass `-n` to `ssh` unless you are deliberately piping data into it.**
  ```zsh
  # WRONG - ssh eats remaining lines from stdin
  while IFS= read -r host; do
    ssh "$host" "uptime"
  done < hosts.txt

  # RIGHT - -n prevents stdin consumption
  while IFS= read -r host; do
    ssh -n "$host" "uptime"
  done < hosts.txt
  ```

### Here-strings (`<<<`) vs `printf`
- **Trap**: Using here-strings (`<<< "$secret"`) to pass exact bytes, tokens, hashes, or passwords to commands.
- **Why it fails silently**: Here-strings automatically append a trailing newline (`\n`). When computing hashes (`sha256sum`), encoding tokens (`base64`), or piping passwords, the extra newline alters the byte payload.
- **Correct form**: Use `printf '%s'` when exact byte length matters.
  ```zsh
  # WRONG - appends newline, altering hash
  sha256=$(sha256sum <<< "$secret")

  # RIGHT - exact byte stream without trailing newline
  sha256=$(printf '%s' "$secret" | sha256sum)
  ```

### Quoted (`<<'EOF'`) vs Unquoted (`<<EOF`) heredocs
- **Rule**:
  - Use **quoted heredoc (`<<'EOF'`)** when passing scripts/payloads to remote shells or `ssh`, preventing local variable expansion.
  - Use **unquoted heredoc (`<<EOF`)** only when you intentionally want local variable substitution prior to sending.

---

## 4. PATH and dependencies

### zsh startup file PATH resets
- **Trap**: Exporting `PATH="/custom/bin:$PATH"` in a parent script and expecting child `#!/usr/bin/env zsh` scripts to inherit it.
- **Why it fails silently**: Non-interactive zsh instances source system and user startup files (`/etc/zshrc`, `~/.zshenv`), which frequently re-initialize or re-order `PATH`.
- **Correct form**: Always set required `PATH` entries inside the zsh script itself or verify executable availability during preflight checks.

### Indirect process dependency lookups
- **Trap**: Pinning a top-level tool via absolute path (e.g. `/usr/bin/gopass`) without checking its sub-dependencies.
- **Why it fails silently**: Tools like `gopass` invoke child binaries (e.g. `gpg`) via `$PATH` search. Pinning `gopass` succeeds initially, but runtime operations crash when `gopass` cannot locate `gpg` in the subshell `PATH`.
- **Correct form**: Preflight-check both the top-level binary and all indirect child binaries.
  ```zsh
  # Dependency preflight check
  for cmd in gopass gpg psql ssh; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
      echo "Error: required dependency '$cmd' not found in PATH." >&2
      exit 1
    fi
  done
  ```

---

## 5. Failure modes and testing

### `--dry-run` limitation
- **Trap**: Relying on a clean `--dry-run` execution as proof of script correctness.
- **Why it fails silently**: `--dry-run` guards branch around mutating statements, leaving actual API payload syntax, database schema compatibility, remote permissions, and file system write access untested. A green dry run is **not** evidence of working code.
- **Correct form**: Test mutating scripts against an isolated test harness (e.g. a container running `sshd`, systemd, or PostgreSQL).

### State mutation ordering
- **Trap**: Modifying local state or files *before* executing remote or external state changes.
- **Why it fails silently**: If the remote command fails halfway through, local state is left out of sync with remote reality.
- **Correct form**: Perform authoritative remote state mutations first (e.g. `ALTER ROLE ...`). If remote execution succeeds, proceed to local state updates.

### Truncated diagnostics hide the real error
- **Trap**: Capturing a subprocess's stderr for a diagnostic and printing only the first line (e.g. `${err%%$'\n'*}`), on the assumption that the first line is the message.
- **Why it fails silently**: Some tools (e.g. `gopass`) emit a leading blank line before the actual error text. Truncating to the first line then prints an empty string, so a real, specific failure reason (e.g. a missing `gpg` binary) is thrown away and the operator sees a blank diagnostic with no way to tell what went wrong.
- **Correct form**: Print the subprocess's stderr in full when reporting a failure; do not assume the first line is the message.
  ```zsh
  # WRONG - assumes the first line is the message; can print nothing useful
  echo "operation FAILED: ${err%%$'\n'*}" >&2

  # RIGHT - preserve the full diagnostic
  echo "operation FAILED:" >&2
  print -r -- "$err" >&2
  ```

### Non-fatal operations post-irreversible actions
- **Trap**: Running post-mutation tasks (e.g. logging a newly rotated credential to a secondary store) under strict `set -e` without failure handling.
- **Why it fails silently / fatally**: If credential rotation succeeds on the target database, but recording the event in a secondary log fails, `set -e` aborts the script immediately, losing the newly generated credential output.
- **Correct form**: Collect and log post-mutation failures explicitly instead of allowing `set -e` to abort the script.
  ```zsh
  # Perform authoritative change
  rotate_remote_database_password "$new_password"

  # Post-change non-fatal recording
  if ! record_audit_log "$username"; then
    echo "WARNING: Failed to record audit log entry, but password was rotated successfully." >&2
  fi
  ```

---

## 6. Pre-commit Checklist

Run this fast checklist before committing any zsh script:

1. **Syntax check**: `zsh -n path/to/script.sh` passes cleanly. Necessary but not sufficient: a split associative-array declaration (`typeset -A M` followed by a separate `M=( [k]=v )`) fails `zsh -n` while running correctly — see "Declare associative arrays with their initializer combined" above. If `zsh -n` fails, investigate before "fixing" what may be working code.
2. **Help flag**: `path/to/script.sh -h` / `path/to/script.sh --help` returns usage instructions and exits 0.
3. **Dry run flag**: `path/to/script.sh -n` / `path/to/script.sh --dry-run` executes safely without side effects.
4. **`ssh` calls**: Every `ssh` call has `-n` unless stdin is explicitly piped into it.
5. **Quoting**: No nested quotes across `ssh`, `psql`, or remote execution boundaries. Any glob inside an `ssh` command string is quoted as part of that string and intended for the remote shell, not the local one.
6. **Reserved variables**: Run `grep -nE '\b(local|typeset|declare)\b[^;]*\b(path|status|argv|options|cdpath|fignore|mailpath)\b' script.zsh` — any hit is a bug, even if the variable name convention is already documented elsewhere.
7. **Arithmetic under `set -e`**: Every `(( ... ))` increment is guarded (e.g. `(( count++ )) || true`).
8. **Dependencies**: Preflight check verifies all direct and child binaries (e.g. `gopass`, `gpg`).
9. **Diagnostics**: Failure messages print the subprocess's full stderr, not just its first line.
10. **Separators**: No NUL used as a field separator, and no raw control byte written literally into the source. Run `tr -dc '\000\037' <script.zsh | wc -c` — anything but `0` is a bug. Use `$'\x1f'` between fields, newline between records; `find -print0 | xargs -0` is the allowed exception.
