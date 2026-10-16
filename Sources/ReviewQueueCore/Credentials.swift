import Foundation

/// Gets a token from the GitHub CLI (`gh`), so the app never stores credentials itself.
public enum Credentials {
    /// An environment token wins when set, as with `gh` itself: `GH_TOKEN` / `GITHUB_TOKEN` for
    /// github.com, `GH_ENTERPRISE_TOKEN` / `GITHUB_ENTERPRISE_TOKEN` for any other host.
    /// Otherwise `gh auth token`.
    public static func token(host: String, environment: [String: String] = ProcessInfo.processInfo.environment) -> String? {
        let keys = host == Settings.defaultHost ? ["GH_TOKEN", "GITHUB_TOKEN"] : ["GH_ENTERPRISE_TOKEN", "GITHUB_ENTERPRISE_TOKEN"]
        for key in keys {
            if let t = environment[key]?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty { return t }
        }
        return run(["gh", "auth", "token", "--hostname", host])
    }

    /// Apps started from Finder get a minimal PATH; add the usual Homebrew and MacPorts locations.
    public static var searchPath: String {
        let extra = ["/opt/homebrew/bin", "/usr/local/bin", "/opt/local/bin", "/usr/bin", "/bin"]
        return (extra + [ProcessInfo.processInfo.environment["PATH"] ?? ""]).joined(separator: ":")
    }

    static func run(_ args: [String]) -> String? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        p.arguments = args
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = searchPath
        p.environment = env
        let out = Pipe()
        p.standardOutput = out
        p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { return nil }
        // A hung `gh` (for example waiting on a keychain prompt) must not hang the app.
        let killer = DispatchWorkItem { if p.isRunning { p.terminate() } }
        DispatchQueue.global().asyncAfter(deadline: .now() + 10, execute: killer)
        let data = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        killer.cancel()
        let s = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return p.terminationStatus == 0 && !s.isEmpty ? s : nil
    }
}
