import Foundation

/// Minimal ANSI/VT100 terminal-grid renderer — a direct port of
/// `os-menu/ansi-grid.js`.
///
/// Claude Code's TUI positions text with absolute cursor moves (CUP
/// `\u{1b}[r;cH`, CHA `\u{1b}[cG`) rather than plain newlines/spaces — e.g.
/// two-column layouts like "Favorite model: Sonnet 5   Total tokens: 23.7m"
/// are drawn by jumping the cursor to column 42 and writing "Total tokens:"
/// there. A regex that just strips ANSI codes collapses that gap and runs
/// words together ("Favoritemodel:...Totaltokens:"). Tracking a real cursor
/// position and placing each character into a sparse grid reconstructs the
/// intended spacing regardless of how the TUI chose to move the cursor.
///
/// ## Why UTF-16 code units, not `Character`
/// The obvious Swift spelling — iterate `Array(raw)` — is wrong here, and
/// wrong in a way that stays hidden until a specific CLI trips it. Swift's
/// `Character` is an extended grapheme cluster, and **CRLF is a single
/// grapheme cluster**: `Array("a\r\nb")` has three elements, the middle one
/// being `"\r\n"`. A `ch == "\n"` test therefore never fires on CRLF output,
/// the cursor never advances a row, and the pair gets written into the grid as
/// if it were a printable character. Cursor's TUI emits CRLF; Claude's does
/// not, which is why this only ever showed up on one provider.
///
/// Iterating UTF-16 code units matches what the JavaScript original does
/// (`raw[i]` indexes UTF-16), which keeps column arithmetic identical even for
/// astral-plane characters, where each surrogate half occupies its own column
/// in both implementations and is reassembled on the way out.
public enum AnsiGrid {

    // UTF-16 code unit constants, named so the state machine below reads.
    private static let esc: UInt16 = 0x1B
    private static let bel: UInt16 = 0x07
    private static let lbracket: UInt16 = 0x5B   // [
    private static let rbracket: UInt16 = 0x5D   // ]
    private static let backslash: UInt16 = 0x5C
    private static let semicolon: UInt16 = 0x3B
    private static let question: UInt16 = 0x3F
    private static let at: UInt16 = 0x40
    private static let lf: UInt16 = 0x0A
    private static let cr: UInt16 = 0x0D

    private static func isDigit(_ u: UInt16) -> Bool { u >= 0x30 && u <= 0x39 }
    private static func isAlpha(_ u: UInt16) -> Bool {
        (u >= 0x41 && u <= 0x5A) || (u >= 0x61 && u <= 0x7A)
    }

    /// Replays `raw`'s cursor movement against a virtual grid and returns the
    /// rendered lines, trailing whitespace trimmed.
    public static func toLines(_ raw: String) -> [String] {
        let units = Array(raw.utf16)
        var grid: [Int: [Int: UInt16]] = [:]
        var row = 0
        var col = 0
        var maxRow = 0

        func clearLine(_ r: Int, from lower: Int?, to upper: Int?) {
            guard let line = grid[r] else { return }
            var updated = line
            for c in line.keys {
                let aboveLower = lower.map { c >= $0 } ?? true
                let belowUpper = upper.map { c <= $0 } ?? true
                if aboveLower && belowUpper { updated.removeValue(forKey: c) }
            }
            grid[r] = updated
        }

        var i = 0
        let n = units.count
        while i < n {
            let u = units[i]

            if u == esc {
                if let csi = matchCSI(units, at: i) {
                    i = csi.end
                    // Private-mode toggles (`\u{1b}[?25l` etc.) have no text effect.
                    if csi.params.first == question { continue }

                    let nums: [Int?] = parseParams(csi.params)
                    let p1 = nums.count > 0 ? nums[0] : nil
                    let p2 = nums.count > 1 ? nums[1] : nil

                    switch csi.final {
                    case 0x48, 0x66:            // H, f — cursor position
                        row = max(0, (p1 ?? 1) - 1)
                        col = max(0, (p2 ?? 1) - 1)
                    case 0x47:                  // G — cursor horizontal absolute
                        col = max(0, (p1 ?? 1) - 1)
                    case 0x64:                  // d — line position absolute
                        row = max(0, (p1 ?? 1) - 1)
                    case 0x43:                  // C — cursor forward
                        col += p1 ?? 1
                    case 0x44:                  // D — cursor back
                        col = max(0, col - (p1 ?? 1))
                    case 0x41:                  // A — cursor up
                        row = max(0, row - (p1 ?? 1))
                    case 0x42:                  // B — cursor down
                        row += p1 ?? 1
                    case 0x4B:                  // K — erase in line
                        switch p1 ?? 0 {
                        case 0: clearLine(row, from: col, to: nil)
                        case 1: clearLine(row, from: nil, to: col)
                        case 2: grid[row] = [:]
                        default: break
                        }
                    case 0x4A:                  // J — erase in display
                        switch p1 ?? 0 {
                        case 2, 3:
                            grid.removeAll()
                        case 0:
                            for r in grid.keys where r > row { grid.removeValue(forKey: r) }
                            clearLine(row, from: col, to: nil)
                        case 1:
                            for r in grid.keys where r < row { grid.removeValue(forKey: r) }
                            clearLine(row, from: nil, to: col)
                        default:
                            break
                        }
                    default:
                        // m, l, h, q, r, c … — colour/mode changes and queries,
                        // no cursor or text effect, so nothing to replay.
                        break
                    }
                    maxRow = max(maxRow, row)
                    continue
                }

                if let oscEnd = matchOSC(units, at: i) {
                    i = oscEnd
                    continue
                }

                // Any other two-unit escape (`ESC 7`, `ESC 8`, charset selects,
                // and — importantly — a CSI this parser didn't recognise, whose
                // remaining bytes then land in the grid as literal text, exactly
                // as they do in the JS original).
                if i + 1 < n {
                    i += 2
                    continue
                }
                i += 1
                continue
            }

            if u == lf {
                row += 1
                col = 0
                maxRow = max(maxRow, row)
                i += 1
                continue
            }
            if u == cr {
                col = 0
                i += 1
                continue
            }

            grid[row, default: [:]][col] = u
            col += 1
            maxRow = max(maxRow, row)
            i += 1
        }

        var lines: [String] = []
        lines.reserveCapacity(maxRow + 1)
        for r in 0...max(maxRow, 0) {
            guard let line = grid[r], !line.isEmpty else {
                lines.append("")
                continue
            }
            let width = (line.keys.max() ?? -1) + 1
            var buf = [UInt16](repeating: 0x20, count: width)   // space-filled
            for (c, unit) in line where c >= 0 && c < width {
                buf[c] = unit
            }
            var rendered = String(decoding: buf, as: UTF16.self)
            // `.replace(/\s+$/, "")` — trailing whitespace only.
            while let last = rendered.last, last.isWhitespace { rendered.removeLast() }
            lines.append(rendered)
        }
        return lines
    }

    /// `/[─│╭╰╮╯━┃┏┗┓┛█▌▛▜▝▞▟▐▙▚▔░▒▓]/g` from the JS original. All BMP, so a
    /// UTF-16 unit set is a faithful representation.
    private static let boxUnits: Set<UInt16> = Set(
        "─│╭╰╮╯━┃┏┗┓┛█▌▛▜▝▞▟▐▙▚▔░▒▓".utf16)

    public static func stripBoxChars(_ s: String) -> String {
        String(decoding: Array(s.utf16).filter { !boxUnits.contains($0) }, as: UTF16.self)
    }

    // MARK: - Escape-sequence matching
    //
    // Hand-rolled rather than NSRegularExpression: this runs over every unit of
    // a multi-hundred-KB capture, and the JS version's `lastIndex`-anchored
    // regexes are trivial state machines that cost far less inline.

    private struct CSIMatch {
        var params: [UInt16]
        var final: UInt16
        var end: Int
    }

    private static func parseParams(_ params: [UInt16]) -> [Int?] {
        guard !params.isEmpty else { return [] }
        var out: [Int?] = []
        var current = ""
        for u in params {
            if u == semicolon {
                out.append(current.isEmpty ? nil : Int(current))
                current = ""
            } else if let scalar = Unicode.Scalar(u) {
                current.unicodeScalars.append(scalar)
            }
        }
        out.append(current.isEmpty ? nil : Int(current))
        return out
    }

    /// `/\x1b\[([0-9;?]*)([a-zA-Z@])/y`
    private static func matchCSI(_ units: [UInt16], at start: Int) -> CSIMatch? {
        var i = start
        guard i < units.count, units[i] == esc else { return nil }
        i += 1
        guard i < units.count, units[i] == lbracket else { return nil }
        i += 1
        var params: [UInt16] = []
        while i < units.count,
              isDigit(units[i]) || units[i] == semicolon || units[i] == question {
            params.append(units[i])
            i += 1
        }
        guard i < units.count else { return nil }
        let final = units[i]
        guard isAlpha(final) || final == at else { return nil }
        return CSIMatch(params: params, final: final, end: i + 1)
    }

    /// `/\x1b\][^\x07\x1b]*(?:\x07|\x1b\\)/y`
    private static func matchOSC(_ units: [UInt16], at start: Int) -> Int? {
        var i = start
        guard i < units.count, units[i] == esc else { return nil }
        i += 1
        guard i < units.count, units[i] == rbracket else { return nil }
        i += 1
        while i < units.count, units[i] != bel, units[i] != esc {
            i += 1
        }
        guard i < units.count else { return nil }
        if units[i] == bel { return i + 1 }
        // ESC \ (String Terminator)
        if i + 1 < units.count, units[i + 1] == backslash { return i + 2 }
        return nil
    }
}
