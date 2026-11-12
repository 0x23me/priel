import Foundation

/// Commands that need root, run through the system's administrator prompt.
enum Admin {
    /// Runs args as root, the password dialog saying why. Returns what went wrong, or nil when it
    /// worked or the owner cancelled.
    static func run(_ args: [String], why: String) async -> String? {
        let shell = args.map { "'" + $0.replacingOccurrences(of: "'", with: "'\\''") + "'" }.joined(separator: " ")
        // Without a prompt of its own, the dialog says osascript wants to make changes.
        let literal = [shell, why].map { $0.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", "do shell script \"\(literal[0])\" with prompt \"\(literal[1])\" with administrator privileges"]
        let stderr = Pipe()
        process.standardError = stderr
        process.standardOutput = FileHandle.nullDevice
        return await withCheckedContinuation { done in
            process.terminationHandler = { process in
                let text = String(decoding: stderr.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
                // osascript says "0:123: execution error: <what the command printed> (1)"; -128 is Cancel.
                if process.terminationStatus == 0 || text.contains("(-128)") { return done.resume(returning: nil) }
                let message = text.components(separatedBy: "execution error: ").last ?? text
                done.resume(returning: message.replacingOccurrences(of: #"\s*\(-?\d+\)\s*$"#, with: "", options: .regularExpression))
            }
            do { try process.run() } catch { done.resume(returning: error.localizedDescription) }
        }
    }
}
