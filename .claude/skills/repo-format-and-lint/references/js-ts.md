# JavaScript and TypeScript formatting and linting

Use package-manager scripts and project-local binaries. Do not install global
formatters or linters.

## Discovery

Check for:

- Package managers: `package.json`, `package-lock.json`, `pnpm-lock.yaml`,
  `yarn.lock`, `bun.lockb`
- Formatters: `biome.json`, `biome.jsonc`, `.prettierrc*`, `prettier.config.*`,
  `dprint.json`
- Linters: `eslint.config.*`, `.eslintrc*`, Biome lint settings
- Type checks: `tsconfig.json`, `tsconfig.*.json`, `vue-tsc`, `tsc --noEmit`
- Scripts: `format`, `format:check`, `lint`, `lint:fix`, `check`, `typecheck`,
  `test`

## Preferred commands

Use documented scripts first, for example:

```sh
npm run format
npm run lint
npm run typecheck
```

When no script exists but Biome is configured, prefer:

```sh
npx biome check --write .
npx biome check .
```

When Prettier and ESLint are configured, prefer project scripts. If none exist,
use local binaries with the package manager already used by the repo, for
example:

```sh
npx prettier --write .
npx eslint . --fix
npx eslint .
```

Scope commands to touched files or packages when the project supports it. Avoid
whole-repository formatting churn unless that is the documented convention.

## Import cleanup

Prefer configured tools that understand the language:

- Biome `check --write` for formatting, lint fixes, and import organization
- ESLint autofix when rules are configured for imports or unused variables
- TypeScript compiler checks for unresolved symbols and type errors
- Framework-specific tooling already documented by the project

Do not use text-only scans as the source of truth for unused imports or style
issues. Type-only imports, JSX, decorators, generated files, path aliases, and
framework conventions require language-aware tooling.
