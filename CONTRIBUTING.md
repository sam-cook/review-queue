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
- Title them as a [Conventional Commit](https://www.conventionalcommits.org), because the
  squash-merge commit message decides the next version and the changelog:

  | Title | Release |
  | --- | --- |
  | `fix: show re-review requests after a force-push` | patch (1.0.**1**) |
  | `feat: show team review requests` | minor (1.**1**.0) |
  | `feat!: drop macOS 14` (or a `BREAKING CHANGE:` footer) | major (**2**.0.0) |
  | `docs:`, `chore:`, `ci:`, `test:`, `refactor:` | no release |

  A check on each PR enforces this.
- CI runs the tests and builds the app on macOS.

## Releasing (maintainers)

Releases are automatic, through [release-please](https://github.com/googleapis/release-please):

1. Each push to `main` updates a pull request named **chore(main): release x.y.z**. It bumps
   `VERSION` and adds the new entries to `CHANGELOG.md`.
2. Merge that pull request when you want to release. release-please tags `vx.y.z` and
   publishes the GitHub release, and the Release workflow builds the app and attaches
   `ReviewQueue-x.y.z.zip`.
3. To rebuild the zip for an existing release, run the Release workflow by hand with the tag.

One-time setup:

- In the repository settings, under **Actions → General → Workflow permissions**, allow
  GitHub Actions to create and approve pull requests.
- Optional: add a fine-grained token with *Contents* and *Pull requests* write access as the
  `RELEASE_PLEASE_TOKEN` secret. Pull requests opened with the default token do not trigger
  CI, so without it the release PR shows no checks.
- After the first release (v1.0.0), delete `"release-as": "1.0.0"` from
  `release-please-config.json`, or every later release PR will propose 1.0.0 again.
