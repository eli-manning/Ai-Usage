import Foundation
import UsageCore

// Dev harness: parse a captured screen and print the result as JSON, so the
// Swift parsers can be diffed against os-menu's JS originals byte for byte.
// Not shipped in the app bundle; see `make verify`.
let args = CommandLine.arguments
guard args.count >= 3 else {
    FileHandle.standardError.write(Data("usage: parsecheck <usage|stats|agy|codex|cursor> <file>\n".utf8))
    exit(2)
}
let raw = (try? String(contentsOfFile: args[2], encoding: .utf8)) ?? ""
let encoder = JSONEncoder()
encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

func emit<T: Encodable>(_ v: T) {
    if let d = try? encoder.encode(v) { print(String(decoding: d, as: UTF8.self)) }
}

switch args[1] {
case "usage": emit(UsageParser.parseUsage(raw))
case "stats": emit(UsageParser.parseStats(raw))
case "agy": emit(ProviderParsers.parseAgy(raw))
case "codex": emit(ProviderParsers.parseCodex(raw))
case "cursor": emit(ProviderParsers.parseCursor(raw))
case "lines": UsageParser.toCleanLines(raw).forEach { print($0) }
case "rawlines": AnsiGrid.toLines(raw).enumerated().forEach { print("[\($0.offset)]|\($0.element)|") }
default: exit(2)
}
