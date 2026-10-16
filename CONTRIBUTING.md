# Contributing

Thanks for helping. Bug reports, rule suggestions and pull requests are all welcome.

## Before you start

- For a bug, open an issue with what you expected, what happened, and the output of
  `ReviewQueue --dump` (remove anything private).
- For a change to *which PRs show and why*, open an issue first. The rules are the product,
  so it helps to agree on them before code.

## Setup

macOS 14 or later and the Xcode Command Line Tools (`xcode-select --install`). Xcode works too.

```sh
make test   # Swift Testing suites; must pass
make demo   # the app with made-up data, no GitHub needed
```

## Where things go

- **Rules** (which PRs show, with which label) live in `Sources/ReviewQueueCore/Classifier.swift`.
  Every rule change needs a test in `Tests/ReviewQueueCoreTests/ClassifierTests.swift`; the
  `Node` builder makes a PR fixture in a few lines.
- **The query** lives in `Queries.swift`. Keep the cost of one refresh at about 210 GraphQL
  points or less (check with `rateLimit(dryRun: true) { cost }` in the GraphQL explorer).
- **UI** lives in `Sources/ReviewQueue/Views/`. If it changes how the panel looks, run
  `make screenshots` and commit the new images.

## Pull requests

- Keep them small and focused, and describe the user-visible change.
- Add an entry under "Unreleased" in [CHANGELOG.md](CHANGELOG.md).
- CI runs the tests and builds the app on macOS.

## Releasing (maintainers)

1. Update `VERSION` and move the CHANGELOG entries under the new version.
2. Commit, then tag and push: `git tag v$(cat VERSION) && git push --tags`.
3. The release workflow tests, builds, and publishes the zip.
