import Foundation

do {
    try await CLI().run(arguments: Array(CommandLine.arguments.dropFirst()))
} catch let error as CLIError {
    fputs("opentype: \(error.message)\n", stderr)
    Foundation.exit(Int32(error.exitCode))
} catch {
    fputs("opentype: \(error.localizedDescription)\n", stderr)
    Foundation.exit(1)
}

private struct CLI {
    func run(arguments: [String]) async throws {
        var parser = ArgumentParser(arguments: arguments)
        let command = parser.next() ?? "help"

        switch command {
        case "help", "-h", "--help":
            print(Self.help)
        case "status":
            let config = try DeveloperInterfaceConfig.load()
            print(config.enabled ? "enabled 127.0.0.1:\(config.port)" : "disabled")
        case "record":
            let options = try SessionOptions(parser: &parser)
            try await OpenTypeLauncher.launchIfNeeded()
            let client = try HTTPClient(config: .load())
            let session = try await client.createSession(options: options)
            _ = try await client.startRecording(sessionID: session.id)
            fputs("Recording. Press Return to stop.\n", stderr)
            _ = readLine()
            let result = try await client.stopRecording(sessionID: session.id)
            print(options.json ? result.encodedJSON() : result.text)
        case "transcribe":
            let options = try SessionOptions(parser: &parser, requiresAudio: true)
            try await OpenTypeLauncher.launchIfNeeded()
            let client = try HTTPClient(config: .load())
            let session = try await client.createSession(options: options)
            let result = try await client.submitAudio(sessionID: session.id, audioURL: try options.requiredAudioURL())
            print(options.json ? result.encodedJSON() : result.text)
        case "create":
            let options = try SessionOptions(parser: &parser)
            try await OpenTypeLauncher.launchIfNeeded()
            let session = try await HTTPClient(config: .load()).createSession(options: options)
            print(session.encodedJSON())
        case "start":
            let sessionID = try parser.requiredUUID(name: "session id")
            try await OpenTypeLauncher.launchIfNeeded()
            let session = try await HTTPClient(config: .load()).startRecording(sessionID: sessionID)
            print(session.encodedJSON())
        case "stop":
            let sessionID = try parser.requiredUUID(name: "session id")
            let result = try await HTTPClient(config: .load()).stopRecording(sessionID: sessionID)
            print(result.encodedJSON())
        case "cancel":
            let sessionID = try parser.requiredUUID(name: "session id")
            let session = try await HTTPClient(config: .load()).cancel(sessionID: sessionID)
            print(session?.encodedJSON() ?? "{}")
        case "events":
            let sessionID = try parser.requiredUUID(name: "session id")
            try await HTTPClient(config: .load()).streamEvents(sessionID: sessionID)
        default:
            throw CLIError("unknown command: \(command)")
        }
    }

    private static let help = """
    Usage:
      opentype status
      opentype record [--mode direct|processed|command] [--language auto|zh|en|ja|ko|yue] [--screen-context on|off] [--json]
      opentype transcribe --audio path.wav [--mode direct|processed|command] [--language auto|zh|en|ja|ko|yue] [--screen-context on|off] [--json]
      opentype create [--mode direct|processed|command] [--language auto|zh|en|ja|ko|yue] [--screen-context on|off]
      opentype start <session-id>
      opentype stop <session-id>
      opentype cancel <session-id>
      opentype events <session-id>
    """
}
