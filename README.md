# Review Queue

A small macOS menu bar app that shows which of your teammates' pull requests on
GitHub need **your** review right now. It works with github.com and with GitHub Enterprise Server.

It watches the PRs of the teammates you pick, works out where each one is in the
review cycle, and only puts a PR in front of you when the next move is yours —
including when someone pushes new commits after you left comments, and when
reviewers leave feedback on your own PRs.

## What it shows

Click the icon in the menu bar to open the panel. PRs are grouped by what you
need to do:

### Needs your review

| Situation | Label | Section |
| --- | --- | --- |
| A review was requested from you directly (from anyone, not only teammates) | Review requested | Needs you |
| The author re-requested your review | Re-review requested | Needs you |
| New commits or a force-push landed after your review or comment | New commits | Needs you |
| The author commented after your review or comment | Author replied | Needs you |
| A teammate's PR from the last 7 days that you have not reviewed | Not reviewed | Needs you |
| You reviewed and nothing has happened since | Waiting on author | Waiting |
| Someone else requested changes and the author has not pushed since | Changes requested | Waiting |
| You approved it, or it is a draft | — | Hidden |
| Someone else approved it and you were never involved | — | Hidden |

### Your PRs

Your own open PRs (drafts included) appear when they have feedback you have not
addressed:

| Situation | Label |
| --- | --- |
| A person requested changes after your last push | Changes requested |
| Review threads are unresolved and the last reply is not yours | *N* unresolved |
| A reviewer commented after your last push or comment | New comments |

Comments only count when they come from someone who reviewed the PR or was asked
to, so status comments from bots and service accounts are ignored.

- Approvals from bots (GitHub Apps and other `Bot` accounts) do not count as approvals.
- If someone else approved a PR you reviewed or commented on, it stays in the list
  with an **Approved** pill (it may merge soon), plus an **N open** pill when your
  review threads are still unresolved.
- PRs you have reviewed or commented on are tracked at any age and from any author (not only
  teammates), so a PR comes back when it gets new commits or replies after your involvement.
- Each row shows the author, a CI dot (green passed, orange running, red failed),
  the repository and number, and when the PR was opened.

### Menu bar icon and notifications

- The badge shows how many PRs need you, counting both reviews to do and your PRs with feedback.
- The badge turns **red** when a PR newly needs you. Opening the panel clears it.
- A macOS notification is posted for each new event (for example "New commits ·
  alice"). Click it to open the PR.

### Dismissing PRs

- Hover a PR and click **×** to dismiss it until something changes. It comes back
  if it needs you for a new reason (new commits, a reply, a review request).
- Right-click a PR for **Always Hide This PR**, **Copy Link** and **Open in Browser**.
- Dismissed PRs are listed in the collapsed **Dismissed** section, where you can
  restore them.

## Requirements

- macOS 14 (Sonoma) or later, Apple silicon or Intel.
- Xcode Command Line Tools, for `swiftc`: `xcode-select --install`
- The GitHub CLI, logged in to GitHub Enterprise:

  ```sh
  brew install gh
  gh auth login
  ```

## Install

```sh
git clone https://github.com/sam-cook/review-queue.git
cd review-queue
./build.sh
```

`build.sh` compiles the app, installs it to `~/Applications/Review Queue.app` and
starts it. Run it again after pulling changes.

Building on your own Mac avoids the Gatekeeper warning that a downloaded,
unsigned app would trigger.

## First run

1. Click the pull-request icon in the menu bar.
2. Add the GitHub usernames of the teammates whose PRs you review, pressing
   Return after each. Each name is checked against GitHub.
3. Allow notifications when macOS asks.
4. Optional: turn on **Launch at login** in the panel footer.

Edit the team at any time with the people icon in the panel header.

## How it works

- One Swift file (`ReviewQueue.swift`) using SwiftUI's `MenuBarExtra`. No
  dependencies, no server.
- It gets a token by running `gh auth token --hostname github.com` and calls the
  GitHub GraphQL API directly. The token is not stored by the app.
- It refreshes every 5 minutes, after your Mac wakes, and on demand (⌘R).
- It only reads from GitHub. It never comments, approves or changes anything.
- Your team, dismissed PRs and seen state are stored locally in macOS user
  defaults (`io.github.sam-cook.review-queue`).

## Configuration

These settings are constants at the top of `ReviewQueue.swift`. Change them and
run `./build.sh` again:

| Constant | Default | Meaning |
| --- | --- | --- |
| `windowDays` | `7` | How far back to look for unreviewed teammate PRs |
| `refreshInterval` | `300` seconds | How often to refresh |

### GitHub Enterprise Server

The app uses github.com by default. To use a GitHub Enterprise Server instead, log in with
`gh auth login --hostname <your-ghe-host>`, then:

```sh
defaults write io.github.sam-cook.review-queue host <your-ghe-host>
```

Restart the app afterwards.

## Known limits

- A review requested from a GitHub **team** you belong to is not shown as
  "Review requested". A teammate's PR still shows as "Not reviewed".
- "Author replied" only counts comments by the PR author.
- Each search returns at most 40 PRs.
- One refresh costs at most about 210 GraphQL points (usually far fewer), out of the
  5,000 per hour that github.com gives you (shared with `gh` and other tools). If the limit is reached, the app
  pauses for 10 minutes and says so in the panel.

## Troubleshooting

| Problem | Fix |
| --- | --- |
| "No GitHub token" in the panel | Run `gh auth login` |
| No icon in the menu bar | Check that it is running: `pgrep -x ReviewQueue`. On a full menu bar, icons can be hidden behind the notch. |
| No notifications | System Settings → Notifications → Review Queue |

For a quick check without the UI, print what the app sees:

```sh
"$HOME/Applications/Review Queue.app/Contents/MacOS/ReviewQueue" --dump
```

## Uninstall

```sh
pkill -x ReviewQueue
rm -rf "$HOME/Applications/Review Queue.app"
defaults delete io.github.sam-cook.review-queue
```

Turn off **Launch at login** before you uninstall, or remove the app from
System Settings → General → Login Items.
