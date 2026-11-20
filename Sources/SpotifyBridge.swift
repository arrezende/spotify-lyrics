import Foundation

/// Talks to the Spotify desktop app through AppleScript.
/// No OAuth needed, just the Automation permission (System Settings › Privacy › Automation).
enum SpotifyBridge {
    private static let fieldSeparator = "\u{241F}"

    static func snapshot() -> SpotifySnapshot? {
        let script = """
        tell application "Spotify"
            if it is running then
                set t to name of current track
                set a to artist of current track
                set al to album of current track
                set s to (get player state) as string
                set p to ((player position) as integer)
                set d to ((duration of current track) as integer) / 1000
                return t & "\(fieldSeparator)" & a & "\(fieldSeparator)" & al & "\(fieldSeparator)" & s & "\(fieldSeparator)" & (p as string) & "\(fieldSeparator)" & (d as string)
            end if
        end tell
        """
        guard let raw = run(script) else { return nil }
        let parts = raw.components(separatedBy: fieldSeparator)
        guard parts.count >= 6 else { return nil }

        let title = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return nil }

        return SpotifySnapshot(
            title: title,
            artist: parts[1].trimmingCharacters(in: .whitespacesAndNewlines),
            album: parts[2].trimmingCharacters(in: .whitespacesAndNewlines),
            playing: parts[3].contains("playing"),
            position: number(parts[4]),
            duration: number(parts[5])
        )
    }

    enum Transport: String {
        case playPause = "playpause"
        case next = "next track"
        case previous = "previous track"
    }

    /// Sends a transport command to Spotify. Returns false if osascript failed.
    static func send(_ transport: Transport) -> Bool {
        run("tell application \"Spotify\" to \(transport.rawValue)") != nil
    }

    /// AppleScript renders numbers with the system locale, so "219,36" is possible.
    private static func number(_ raw: String) -> Double {
        let cleaned = raw
            .replacingOccurrences(of: ",", with: ".")
            .filter { $0.isNumber || $0 == "." || $0 == "-" }
        return Double(cleaned) ?? 0
    }

    private static func run(_ script: String) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]
        let outPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = Pipe()
        do {
            try process.run()
        } catch {
            return nil
        }
        let data = outPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
