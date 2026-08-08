---
name: bash-scripting
description: "Write, review, debug, and port Bash scripts that must run under Bash 3.2 on macOS and remain portable across macOS and Linux. Covers Bash-version restrictions, BSD-vs-GNU command differences, safe shell patterns, portability checks, and testing."
license: "MIT"
compatibility: "Requires Bash 3.2 or newer on macOS or Linux"
---

# bash-scripting

Write Bash scripts against the Bash 3.2 language level and the common macOS/Linux
command-line environment. Treat macOS's system `/bin/bash` and BSD userland as
first-class targets, even when developing on Linux with newer Bash and GNU tools.

> [!IMPORTANT]
> Passing `bash -n` or ShellCheck under a newer Bash does not prove Bash 3.2
> compatibility. Neither tool prevents Bash 4+ features, and ShellCheck does not
> detect every GNU-versus-BSD utility difference. Test with macOS `/bin/bash` and
> the system utilities whenever possible.

## 1. Establish the portability baseline

1. Inspect the repository's existing shebang, style, formatter, linter, and test
   commands before editing.
2. Preserve the existing shell dialect. Use Bash only when the script declares
   Bash; do not make `/bin/sh` scripts depend on Bash syntax.
3. For new Bash scripts, use a single-argument shebang and put shell options in
   the body:

   ```bash
   #!/usr/bin/env bash

   set -o pipefail
   ```

   Do not use `#!/usr/bin/env -S bash ...`; macOS versions differ in `env -S`
   support.
4. Set Bash 3.2 as the feature ceiling. Do not assume Homebrew, MacPorts, GNU
   coreutils, or a newer Bash unless the project explicitly declares them as
   dependencies.
5. Prefer one implementation that works on both macOS and Linux. Branch on the
   operating system only when the native interfaces genuinely differ.

## 2. Stay within Bash 3.2

Avoid newer Bash syntax even if it works locally:

| Avoid | Bash 3.2-compatible form |
| --- | --- |
| Associative arrays (`declare -A`) | Indexed arrays, `case`, or explicit records |
| `mapfile` / `readarray` | `while IFS= read -r line` |
| `${value,,}` / `${value^^}` | `printf '%s' "$value" \| tr '[:upper:]' '[:lower:]'` and the inverse |
| `[[ -v name ]]` | `[[ ${name+x} == x ]]` |
| Namerefs (`declare -n`) | Pass values explicitly or print a function result |
| `&>>file` | `>>file 2>&1` |
| `command \|& consumer` | `command 2>&1 \| consumer` |
| `wait -n`, `coproc`, or `globstar` | Use explicit PIDs, ordinary jobs, or `find` |
| Negative array indices | Calculate a non-negative index |
| `${value@Q}` and other `@` transforms | Use explicit destination-specific escaping |

Use indexed arrays carefully:

```bash
items=()
items[${#items[@]}]=$new_item

for item in "${items[@]}"; do
  printf '%s\n' "$item"
done
```

Under Bash 3.2, `set -u` has surprising behavior around empty arrays and unset
values. Guard optional variables with `${name-}` or `${name:-default}`, and test
empty-array paths on the target Bash.

For regular expressions, store the expression in a variable and leave the
right-hand side unquoted. Quoting the right-hand side of `=~` has
version-sensitive semantics:

```bash
integer_pattern='^[0-9]+$'
if [[ $value =~ $integer_pattern ]]; then
  printf '%s\n' "integer"
fi
```

## 3. Avoid shell failure traps

Quote expansions unless splitting or globbing is intentional. Preserve argument
boundaries with `"$@"`, and use `printf` instead of `echo -e`.

Separate declarations from commands whose status matters:

```bash
# Wrong: local masks the command substitution's exit status.
local result=$(generate_result)

# Right
local result
result=$(generate_result) || return
```

Do not rely blindly on `set -e`. Its behavior changes in conditionals, command
substitutions, pipelines, and subshells. Handle expected failures explicitly:

```bash
if ! output=$(perform_check); then
  printf 'Error: check failed\n' >&2
  exit 1
fi
```

Remember that arithmetic commands return failure when the expression evaluates
to zero. Under `set -e`, avoid unguarded post-increment:

```bash
# Wrong when count starts at zero
((count++))

# Safe
count=$((count + 1))
```

Avoid pipelines when a loop must update variables in the current shell because
the loop normally runs in a subshell:

```bash
count=0
while IFS= read -r line; do
  count=$((count + 1))
done < "$input_file"
```

Command substitution removes trailing newlines. Use a file or a streaming
interface when trailing newlines are meaningful.

## 4. Account for BSD and GNU utility differences

Do not use these Linux/GNU-specific forms without a portable fallback:

- `readlink -f` or `realpath`
- `sed -i` without accounting for incompatible BSD/GNU arguments
- `date -d`, `stat -c`, `find -printf`, `grep -P`, or `sort -V`
- `xargs -r`, `timeout`, `sha256sum`, or `base64 -w`
- `cp -a`, `install -D`, `du -b`, or negative counts such as `head -n -1`
- Linux-only paths such as `/proc`, `/sys`, or `/run`

Resolve the script directory without `readlink -f`:

```bash
script_dir=$(
  CDPATH= cd -P "$(dirname "$0")" &&
    pwd
) || exit 1
```

Avoid non-portable in-place `sed` flags. Write a temporary file beside the
destination and replace it only after success:

```bash
temp_file=$(mktemp "${config_file}.tmp.XXXXXX") || exit 1

cleanup() {
  rm -f "$temp_file"
}
trap cleanup EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

# Preserve the destination mode before redirecting into the temporary file.
cp -p "$config_file" "$temp_file" || exit 1
if sed 's/old/new/g' "$config_file" > "$temp_file"; then
  mv "$temp_file" "$config_file"
else
  exit 1
fi
```

Always give `mktemp` a template ending in at least six `X` characters. Do not
use GNU-only `mktemp` flags such as `--suffix`.

Use portable search and batch forms:

```bash
grep -E 'extended-regexp' "$input_file"
find "$root_dir" -type f -name '*.tmp' -exec rm -f '{}' \;
```

When exact bytes matter, avoid here-strings because they append a newline:

```bash
encoded=$(printf '%s' "$token" | base64 | tr -d '\n')
```

Provide explicit dependency fallbacks when command names differ:

```bash
sha256_file() {
  if command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$1" | awk '{print $1}'
  elif command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
  else
    printf 'Error: no SHA-256 utility found\n' >&2
    return 1
  fi
}
```

If an OS-specific branch is unavoidable, reject unknown systems clearly:

```bash
case $(uname -s) in
  Darwin) platform=macos ;;
  Linux) platform=linux ;;
  *)
    printf 'Error: unsupported operating system\n' >&2
    exit 1
    ;;
esac
```

## 5. Build safe command-line interfaces

Use Bash's `getopts` for short options. For long options, use an explicit
`case` loop instead of assuming GNU `getopt`:

```bash
dry_run=false
output_file=

while (($# > 0)); do
  case $1 in
    -n | --dry-run)
      dry_run=true
      shift
      ;;
    -o | --output)
      (($# >= 2)) || {
        printf 'Error: %s requires a value\n' "$1" >&2
        exit 2
      }
      output_file=$2
      shift 2
      ;;
    --output=*)
      output_file=${1#*=}
      shift
      ;;
    --)
      shift
      break
      ;;
    -*)
      printf 'Error: unknown option: %s\n' "$1" >&2
      exit 2
      ;;
    *)
      break
      ;;
  esac
done
```

For scripts that change state, provide `-h`/`--help` and, when meaningful,
`-n`/`--dry-run`. Make dry-run output show the resolved operation without
performing it, but do not treat a successful dry run as proof that the real
operation will succeed.

Use `command -v` for dependency checks. Report missing dependencies before
starting mutations.

### Separators: never NUL, never a raw control byte

When joining fields into a single string (a composite key, a serialized
record), do not use a NUL byte as the separator, and never write any control
byte *literally* into the source.

NUL cannot survive a process boundary: `execve(2)` arguments and the
environment are NUL-terminated C strings, so the value is truncated rather
than passed. `env X="$(printf 'a\0b')" sh -c 'echo ${#X}'` prints `1`, not
`3` — silently.

Writing the byte literally is the more damaging half. A raw `0x00` makes
`file(1)` report the source as `data`, so `grep` treats it as binary and
prints nothing at all — no error, just a silent wrong answer. Exact-match
edits fail too, since the byte is invisible in normal output. A literal
`0x1F` breaks tooling the same way.

Use `0x1F` between fields and a newline between records, always written as an
escape and extracted to a named constant:

```bash
readonly KEY_SEP=$'\x1f'
key="${source_id}${KEY_SEP}${name}"
```

`find -print0 | xargs -0` remains correct — it stays inside a pipe and never
crosses an argv/env boundary. When searching for a control character, name it
by escape (`grep -P '\x1f'`, `tr -dc '\000' <file | wc -c`, `cat -A`) rather
than pasting the byte into the pattern.

See `skills/zsh-scripting/SKILL.md` §2 for the full rationale and examples.

## 6. Handle temporary files and cleanup safely

Use a dedicated, positively identified temporary directory and quote it during
cleanup:

```bash
task_temp_dir=$(mktemp -d "${TMPDIR:-/tmp}/tool-name.XXXXXX") || exit 1

cleanup() {
  if [[ -n ${task_temp_dir:-} && -d $task_temp_dir ]]; then
    rm -rf "$task_temp_dir"
  fi
}
trap cleanup EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM
```

Do not construct destructive targets from unresolved variables, broad globs, or
unvalidated user input. Perform authoritative external mutations before local
bookkeeping, and handle non-critical follow-up failures explicitly.

## 7. Validate portability

Run the repository's configured checks first, then perform all relevant checks
below:

1. Run `bash -n path/to/script.sh`.
2. Run ShellCheck with Bash parsing, for example
   `shellcheck -x --shell=bash path/to/script.sh`.
3. Search manually for Bash 4+ features and the GNU-only commands listed above.
4. Run help, invalid-option, missing-argument, empty-input, whitespace, glob,
   and failure-path tests.
5. On macOS, run the script explicitly with `/bin/bash` and confirm
   `/bin/bash --version` reports 3.2.
6. Test against macOS system utilities with a minimal system `PATH` when the
   script is intended to have no third-party dependencies:

   ```bash
   env PATH=/usr/bin:/bin:/usr/sbin:/sbin /bin/bash path/to/script.sh --help
   ```

7. Test on Linux as well; portability defects can exist in either direction.

Do not use `BASH_COMPAT=3.2` as proof of compatibility. On newer Bash it changes
selected runtime semantics, but it does not reject newer syntax or builtins.

## 8. Pre-commit checklist

1. Confirm the shebang invokes Bash without non-portable shebang arguments.
2. Confirm every language feature exists in Bash 3.2.
3. Confirm external command flags work with both BSD and GNU implementations.
4. Confirm paths do not assume Linux-only filesystems.
5. Confirm expansions, arrays, and `"$@"` preserve spaces and glob characters.
6. Confirm temporary-file cleanup cannot target a broad or empty path.
7. Confirm `-h`/`--help` and `-n`/`--dry-run` follow repository conventions.
8. Confirm syntax, lint, and tests pass under an actual macOS Bash 3.2 runtime.
9. Confirm no NUL is used as a field separator and no raw control byte is written literally into the source: `tr -dc '\000\037' <script.sh | wc -c` must print `0`.
