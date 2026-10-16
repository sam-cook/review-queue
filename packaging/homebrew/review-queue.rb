# Homebrew cask for Review Queue. The Release workflow fills in the version and checksum and
# pushes the result to github.com/sam-cook/homebrew-tap; edit this template, not the copy there.
cask "review-queue" do
  version "__VERSION__"
  sha256 "__SHA256__"

  url "https://github.com/sam-cook/review-queue/releases/download/v#{version}/ReviewQueue-#{version}.zip"
  name "Review Queue"
  desc "Menu bar app for the GitHub pull requests that need your review"
  homepage "https://github.com/sam-cook/review-queue"

  livecheck do
    url :url
    strategy :github_latest
  end

  depends_on formula: "gh"
  depends_on macos: :sonoma

  app "Review Queue.app"

  # The app is ad-hoc signed, not notarised: clear the quarantine flag before Homebrew moves it,
  # so it opens without a Gatekeeper prompt. Only possible in a third-party tap; homebrew/cask
  # requires notarisation.
  preflight_steps do
    run "/usr/bin/xattr",
        args:           ["-dr", "com.apple.quarantine", "Review Queue.app"],
        chdir:          ".",
        writable_paths: ["Review Queue.app"]
  end

  uninstall quit:       "io.github.sam-cook.review-queue",
            login_item: "Review Queue"

  zap trash: "~/Library/Preferences/io.github.sam-cook.review-queue.plist"

  caveats <<~EOS
    Review Queue reads your GitHub login from the GitHub CLI. If you have not logged in yet:
      gh auth login
  EOS
end
