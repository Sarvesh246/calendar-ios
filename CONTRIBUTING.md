# Contributing

## Setup

```bash
npm install     # also installs the git hooks (husky)
```

## Before you push

```bash
npm run typecheck && npm run lint && npm run format:check
```

The pre-commit hook runs ESLint and Prettier on staged files and scans the staged diff for secrets. CI runs the same checks. The native build runs only on macOS runners.

## Commits

[Conventional Commits](https://www.conventionalcommits.org/), enforced by `commitlint`:

```
<type>(<optional scope>): <what changed, imperative, lower case>
```

Types: `feat`, `fix`, `perf`, `refactor`, `style`, `test`, `docs`, `build`, `ci`, `chore`, `revert`.
Examples: `feat(nav): add liquid glass tab capsule`, `fix(live-activity): keep the widget extension when re-signing`.

## Things that are easy to break

- Re-signing must keep `DatebookWidgets.appex` and the App Group `group.com.sarveshjagtap.datebook`.
- The wrapper is identified by the `DatebookNativeApp` user-agent marker. The web app depends on it; do not change it without changing the web repo.
- Do not commit `.env` files, signing material (`*.p12`, `*.p8`, `*.mobileprovision`) or notes with credentials. They are ignored; keep them outside the repo folder.

## Reporting security issues

See [SECURITY.md](SECURITY.md).
