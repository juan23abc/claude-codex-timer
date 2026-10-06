import Foundation

// Small bounded VT screen for Claude's /usage view. Cursor moves and erases matter:
// stripping ANSI codes would concatenate old reset times with subsequent updates.
struct TerminalScreen {
    private let width = 100, height = 32
    private var cells = Array(repeating: Array(repeating: " " as Unicode.Scalar, count: 100), count: 32)
    private var row = 0, column = 0, savedRow = 0, savedColumn = 0
    private var scrollTop = 0, scrollBottom = 31
    private var mode = 0 // text, escape, CSI, OSC, OSC escape, charset
    private var sequence = ""
    private var pending = Data()
    var text: String { cells.map { String(String.UnicodeScalarView($0)).trimmingCharacters(in: .whitespaces) }.joined(separator: "\n") }

    mutating func feed(_ data: Data) {
        pending.append(data)
        var count = pending.count
        var decoded: String?
        for suffix in 0...min(3, count) {
            if let value = String(data: pending.prefix(count - suffix), encoding: .utf8) {
                decoded = value; count -= suffix; break
            }
        }
        guard let decoded else { pending.removeAll(); return }
        pending.removeFirst(count)
        for char in decoded.unicodeScalars {
            switch mode {
            case 1:
                mode = 0
                switch char {
                case "[": mode = 2; sequence = ""
                case "]", "P", "^", "_": mode = 3
                case "(", ")": mode = 5
                case "7": savedRow = row; savedColumn = column
                case "8": row = savedRow; column = savedColumn
                case "D": lineFeed()
                case "E": column = 0; lineFeed()
                case "c": clear()
                default: break
                }
            case 2:
                if (0x40...0x7e).contains(char.value) { csi(char); mode = 0 }
                else if sequence.count < 128 { sequence.unicodeScalars.append(char) }
                else { mode = 0 }
            case 3:
                if char.value == 7 { mode = 0 }
                else if char.value == 27 { mode = 4 }
            case 4: mode = char == "\\" ? 0 : 3
            case 5: mode = 0
            default:
                switch char.value {
                case 27: mode = 1
                case 13: column = 0
                case 10: lineFeed()
                case 8: column = max(0, column - 1)
                case 9: column = min(width - 1, (column / 8 + 1) * 8)
                case 0...31, 127: break
                default:
                    if column >= width { column = 0; lineFeed() }
                    cells[row][column] = char; column += 1
                }
            }
        }
    }

    private mutating func clear() {
        cells = Array(repeating: Array(repeating: " ", count: width), count: height)
        row = 0; column = 0; scrollTop = 0; scrollBottom = height - 1
    }
    private mutating func lineFeed() {
        if row == scrollBottom { cells.remove(at: scrollTop); cells.insert(Array(repeating: " ", count: width), at: scrollBottom) }
        else { row = min(height - 1, row + 1) }
    }
    private mutating func csi(_ command: Unicode.Scalar) {
        if sequence.hasPrefix("?") {
            if sequence == "?1049", command == "h" || command == "l" { clear() }
            return
        }
        let args = sequence.split(separator: ";", omittingEmptySubsequences: false).map { Int($0) ?? 0 }
        let n = max(1, args.first ?? 1)
        switch command {
        case "A": row = max(0, row - n)
        case "B": row = min(height - 1, row + n)
        case "C": column = min(width - 1, column + n)
        case "D": column = max(0, column - n)
        case "E": row = min(height - 1, row + n); column = 0
        case "F": row = max(0, row - n); column = 0
        case "G", "`": column = min(width - 1, n - 1)
        case "d": row = min(height - 1, n - 1)
        case "H", "f": row = min(height - 1, n - 1); column = min(width - 1, max(1, args.count > 1 ? args[1] : 1) - 1)
        case "J":
            let kind = args.first ?? 0
            for y in 0..<height { for x in 0..<width {
                if kind == 2 || kind == 3 || (kind == 0 && (y > row || (y == row && x >= column))) || (kind == 1 && (y < row || (y == row && x <= column))) { cells[y][x] = " " }
            } }
        case "K":
            for x in 0..<width {
                let kind = args.first ?? 0
                if kind == 2 || (kind == 0 && x >= column) || (kind == 1 && x <= column) { cells[row][x] = " " }
            }
        case "X": for x in min(column, width - 1)..<min(width, column + n) { cells[row][x] = " " }
        case "P":
            let x = min(column, width - 1), count = min(n, width - min(column, width - 1))
            cells[row].removeSubrange(x..<(x + count)); cells[row].append(contentsOf: Array(repeating: " ", count: count))
        case "s": savedRow = row; savedColumn = column
        case "u": row = savedRow; column = savedColumn
        case "r":
            scrollTop = min(height - 1, n - 1)
            scrollBottom = min(height - 1, max(scrollTop, (args.count > 1 && args[1] > 0 ? args[1] : height) - 1))
            row = 0; column = 0
        default: break // colors, cursor visibility, terminal queries
        }
    }
}
