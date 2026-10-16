import Foundation

/// Gets a token from the GitHub CLI (`gh`), so the app never stores credentials itself.
public enum Credentials {
    /// `GITHUB_TOKEN` (or `GH_TOKEN`) wins when set, which helps scripts and CI; otherwise `gh auth token`.
    public static func token(host: String, environment: [String: String] = ProcessInfo.processInfo.environment) -> String? {
        for key in ["GH_TOKEN", "GITHUB_TOKEN"] {
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
        let data = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        let s = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return p.terminationStatus == 0 && !s.isEmpty ? s : nil
    }
}
