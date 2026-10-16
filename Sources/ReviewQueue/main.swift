import AppKit
import ReviewQueueCore
import SwiftUI

let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
let settings = Settings(defaults: .standard)
let client = GitHubClient(settings: settings) { Credentials.token(host: settings.host) }

let usage = """
Review Queue \(version): a menu bar app for the pull requests that need your review.

Usage: ReviewQueue [option]
  (no option)            run the menu bar app
  --demo                 run the menu bar app with made-up data (no GitHub access)
  --dump                 print what the app would show, then exit
  --snapshot FILE [--dark] [--demo]
                         render the panel to a PNG, then exit
  --version              print the version
  --help                 print this help

Settings (defaults write \(Bundle.main.bundleIdentifier ?? "io.github.sam-cook.review-queue") KEY VALUE):
  host             github.com (default) or a GitHub Enterprise Server host
  windowDays       how far back to look for unreviewed teammate PRs (default 7)
  refreshInterval  seconds between refreshes (default 300, minimum 60)
"""

let args = Array(CommandLine.arguments.dropFirst())
let demo = args.contains("--demo")

struct ReviewQueueApp: App {
    @StateObject var store: Store

    init() {
        let s = demo
            ? Store(settings: settings, client: client, persistence: Persistence(UserDefaults(suiteName: "review-queue-demo")!),
                    notifier: nil, autoRefresh: false)
            : Store(settings: settings, client: client)
        if demo { s.team = ["jonas", "mira", "aiko", "sol"]; s.show(Demo.prs()) }
        _store = StateObject(wrappedValue: s)
    }

    var body: some Scene {
        MenuBarExtra {
            Panel(store: store)
        } label: {
            Image(nsImage: store.icon)
        }
        .menuBarExtraStyle(.window)
    }
}

/// Prints the queue, one PR per line: reason, approved, own open threads, author, repo#number, title.
func dump() async -> Int32 {
    do {
        let (viewer, prs) = try await client.fetchQueue(team: Persistence().loadTeam())
        print("Signed in to \(settings.host) as \(viewer). \(prs.count) PRs.")
        for p in prs {
            print(p.label.padding(toLength: 20, withPad: " ", startingAt: 0), p.othersApproved ? "approved" : "        ",
                  "open:\(p.myOpenThreads)", p.author, "\(p.repo)#\(p.number)", p.title)
        }
        return 0
    } catch {
        FileHandle.standardError.write(Data("error: \(error.localizedDescription)\n".utf8))
        return 1
    }
}

@MainActor
func snapshot(to path: String, dark: Bool) async -> Int32 {
    let store = Store(settings: settings, client: client, persistence: Persistence(UserDefaults(suiteName: "review-queue-snapshot")!),
                      notifier: nil, autoRefresh: false)
    if demo {
        store.team = ["jonas", "mira", "aiko", "sol"]
        store.show(Demo.prs())
    } else {
        do { store.show(try await client.fetchQueue(team: Persistence().loadTeam()).prs) }
        catch { FileHandle.standardError.write(Data("error: \(error.localizedDescription)\n".utf8)); return 1 }
    }
    if let first = store.needsMe.first { store.newKeys = [first.key] }
    let view = Panel(store: store, snapshot: true)
        .background(dark ? Color(white: 0.16) : Color(white: 0.97))
        .environment(\.colorScheme, dark ? .dark : .light)
    let r = ImageRenderer(content: view)
    r.scale = 2
    guard let img = r.nsImage, let tiff = img.tiffRepresentation,
          let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) else { return 1 }
    do { try png.write(to: URL(fileURLWithPath: path)) } catch { return 1 }
    print("Wrote \(path)")
    return 0
}

func runAndExit(_ work: @escaping @MainActor () async -> Int32) -> Never {
    _ = NSApplication.shared
    Task { @MainActor in exit(await work()) }
    RunLoop.main.run()
    exit(0)
}

if args.contains("--help") || args.contains("-h") { print(usage); exit(0) }
if args.contains("--version") { print(version); exit(0) }
if args.contains("--dump") { runAndExit { await dump() } }
if let i = args.firstIndex(of: "--snapshot") {
    guard i + 1 < args.count, !args[i + 1].hasPrefix("--") else { print(usage); exit(2) }
    let path = args[i + 1], dark = args.contains("--dark")
    runAndExit { await snapshot(to: path, dark: dark) }
}
if let unknown = args.first(where: { $0.hasPrefix("-") && $0 != "--demo" && !$0.hasPrefix("-NS") && !$0.hasPrefix("-Apple") }) {
    FileHandle.standardError.write(Data("Unknown option \(unknown)\n\n\(usage)\n".utf8))
    exit(2)
}

ReviewQueueApp.main()
