# Security

Review Queue reads your GitHub token from the GitHub CLI (`gh auth token`) or from the
`GH_TOKEN` / `GITHUB_TOKEN` environment variables. It keeps the token in memory only and sends
it only to the GitHub API host you configured (`api.github.com`, or your Enterprise host).
The app makes read-only requests.

If you find a security problem, please do not open a public issue. Use
[GitHub's private vulnerability reporting](https://github.com/sam-cook/review-queue/security/advisories/new)
for this repository instead. You should get a reply within a week.
