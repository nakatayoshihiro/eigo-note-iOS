import Foundation
import SwiftUI

// ノート本文（ProseMirror のドキュメント）を、そのまま SwiftUI で描ける形に読み替える。
//
// ■ なぜ WebView で表示しないのか
// 見た目も選択挙動も Web 依存のままになり、これから足す「書く」機能に何も残らないため。
// 本文の木（Models/NoteDoc.swift）を直接読むので、書くときも同じ木を送り返せる。
//
// ■ 対応している範囲
// Web 側のエディタが使う拡張に合わせてある（app の lib/tiptap-doc.ts が決める）＝
// StarterKit（段落・見出し1〜3・太字・斜体・下線・打ち消し・コード・引用・箇条書き・
// 番号付き・水平線・改行・リンク）＋ タスクリスト ＋ 色 ＋ 文字サイズ。
// 知らない type は落とさず中身だけ拾う（本文が丸ごと消えるより装飾が欠ける方がまし）。
struct NoteBlock: Identifiable {
    let id = UUID()
    let kind: Kind
    let text: AttributedString

    enum Kind: Equatable {
        case paragraph
        case heading(level: Int)
        case bullet(depth: Int)
        case ordered(number: Int, depth: Int)
        case task(done: Bool, depth: Int)
        // リスト項目の2段落目以降。記号は付けず字下げだけ引き継ぐ
        case continuation(depth: Int)
        case quote
        case rule
    }
}

enum NoteBody {
    // 本文に現れる登録済みの単語を塗る。対象は「そのノートから登録した単語」だけで、
    // Web のエディタ（TiptapEditor の buildDecorations）と同じ範囲。
    //
    // 一致の規則も Web の surfaceRegex に合わせる＝大文字小文字を区別する完全一致で、
    // surface が英数字で始まる（終わる）ときだけ、その側に単語境界を要求する。
    // 境界を常に付けないのは "'s" や記号で始まる surface を取りこぼさないため。
    static func highlight(_ blocks: [NoteBlock], words: [Word]) -> [NoteBlock] {
        let patterns = words
            .map(\.surface)
            .filter { !$0.isEmpty }
            .compactMap { surface -> NSRegularExpression? in
                let alnum = CharacterSet.alphanumerics
                // ⚠️ \b は使えない。NSRegularExpression（ICU）の \b は Unicode 基準で、
                // 仮名や漢字も語の文字として数える。一方 Web 側の JS 正規表現（/u 無し）は
                // ASCII 基準なので、「これはgrantです」のような日英混在で結果が食い違う
                // （ICU は境界なしと見て塗らない）。ASCII の境界を先読み・後読みで自分で書く
                let head = surface.unicodeScalars.first.map(alnum.contains) == true ? "(?<![A-Za-z0-9_])" : ""
                let tail = surface.unicodeScalars.last.map(alnum.contains) == true ? "(?![A-Za-z0-9_])" : ""
                return try? NSRegularExpression(
                    pattern: head + NSRegularExpression.escapedPattern(for: surface) + tail
                )
            }
        guard !patterns.isEmpty else { return blocks }

        return blocks.map { block in
            var text = block.text
            let plain = String(text.characters)
            let whole = NSRange(plain.startIndex..., in: plain)

            for pattern in patterns {
                for match in pattern.matches(in: plain, range: whole) {
                    guard let found = Range(match.range, in: plain) else { continue }
                    let start = plain.distance(from: plain.startIndex, to: found.lowerBound)
                    let length = plain.distance(from: found.lowerBound, to: found.upperBound)
                    let lower = text.index(text.startIndex, offsetByCharacters: start)
                    let upper = text.index(lower, offsetByCharacters: length)
                    text[lower..<upper].backgroundColor = marker
                    // ⚠️ 文字色も固定する。Web は乗算で白い紙の上に重ねる前提だが、
                    // iOS はダークモードだと地が黒く、既定の白文字が帯の上で読めなくなる
                    text[lower..<upper].foregroundColor = markerInk
                }
            }
            return NoteBlock(kind: block.kind, text: text)
        }
    }

    // Web の --word-marker（globals.css）と同じ色
    private static let marker = Color(hex: 0xffdac0)
    private static let markerInk = Color(hex: 0x2f2f2f)

    /// 本文ドキュメントを行の並びに読み替える
    static func parse(_ doc: NoteDoc) -> [NoteBlock] {
        var blocks: [NoteBlock] = []
        append(doc.content ?? [], depth: 0, into: &blocks)
        return blocks
    }

    /// 旧形式（移行前の HTML）が残っている行のための保険。装飾は諦めて文字だけ見せる。
    ///
    /// 移行スクリプトを流した後に bodyJson が空で来るのは、移行の最中に開いたままだった
    /// 古いタブから保存された行だけ（サーバーはそれを旧形式のまま受ける。app の
    /// lib/note-doc.ts の noteBodyFields を参照）。そのタブが再読み込みされれば直る。
    /// 本文が真っ白に見えるより、素のテキストでも読める方がいい
    static func plainBlocks(fromLegacy body: String) -> [NoteBlock] {
        let broken = body
            .replacingOccurrences(of: "</p>", with: "\n")
            .replacingOccurrences(of: "</li>", with: "\n")
            .replacingOccurrences(of: "<br>", with: "\n")
            .replacingOccurrences(of: "<br/>", with: "\n")
        let plain = broken
            .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .replacingOccurrences(of: "&nbsp;", with: "\u{00A0}")
        return plain
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { NoteBlock(kind: .paragraph, text: AttributedString(String($0))) }
    }

    // MARK: - ブロック

    private static func append(_ nodes: [NoteDoc], depth: Int, into blocks: inout [NoteBlock]) {
        for node in nodes {
            switch node.type {
            case "paragraph":
                add(.paragraph, from: node, into: &blocks)

            case "heading":
                add(.heading(level: node.attrs?.level ?? 1), from: node, into: &blocks)

            case "blockquote":
                // 引用の中は基本が段落。行ごとに引用として描く（縦線は描画側が引く）。
                // 段落以外（水平線・リスト）も入れられるので、それは普通のブロックとして扱う
                for child in node.content ?? [] {
                    if child.type == "paragraph" {
                        add(.quote, from: child, into: &blocks)
                    } else {
                        append([child], depth: depth, into: &blocks)
                    }
                }

            case "horizontalRule":
                blocks.append(NoteBlock(kind: .rule, text: AttributedString()))

            case "codeBlock":
                add(.paragraph, from: node, code: true, into: &blocks)

            case "bulletList", "orderedList", "taskList":
                appendList(node, depth: depth, into: &blocks)

            default:
                // 知らないブロック。中身だけ拾って本文を落とさない
                append(node.content ?? [], depth: depth, into: &blocks)
            }
        }
    }

    private static func appendList(_ list: NoteDoc, depth: Int, into blocks: inout [NoteBlock]) {
        var number = list.attrs?.start ?? 1
        for item in list.content ?? [] {
            var isFirstLine = true
            for child in item.content ?? [] {
                switch child.type {
                case "paragraph":
                    // 項目の1行目だけが記号を持つ。2段落目以降は字下げだけ引き継ぐ
                    let kind: NoteBlock.Kind
                    if !isFirstLine {
                        kind = .continuation(depth: depth)
                    } else if list.type == "taskList" {
                        kind = .task(done: item.attrs?.checked == true, depth: depth)
                    } else if list.type == "orderedList" {
                        kind = .ordered(number: number, depth: depth)
                    } else {
                        kind = .bullet(depth: depth)
                    }
                    add(kind, from: child, into: &blocks)
                    isFirstLine = false

                case "bulletList", "orderedList", "taskList":
                    appendList(child, depth: depth + 1, into: &blocks)

                default:
                    append([child], depth: depth + 1, into: &blocks)
                }
            }
            if list.type == "orderedList" { number += 1 }
        }
    }

    private static func add(
        _ kind: NoteBlock.Kind,
        from node: NoteDoc,
        code: Bool = false,
        into blocks: inout [NoteBlock]
    ) {
        let text = inlineText(of: node, kind: kind, code: code)
        // 空の段落は Web でも1行ぶんの間隔になるので、間隔として残す。
        // ただしリスト項目などの空行は記号だけが並んでしまうので捨てる
        let isBlank = String(text.characters).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        if !isBlank || kind == .paragraph {
            blocks.append(NoteBlock(kind: kind, text: text))
        }
    }

    // MARK: - 行の中身

    private static func inlineText(of node: NoteDoc, kind: NoteBlock.Kind, code: Bool) -> AttributedString {
        var text = AttributedString()
        for child in node.content ?? [] {
            switch child.type {
            case "text":
                var style = inlineStyle(of: child.marks)
                if code { style.code = true }
                text.append(styled(child.text ?? "", style: style, kind: kind))

            case "hardBreak":
                text.append(AttributedString("\n"))

            default:
                // 知らないインライン（将来の拡張）。中の文字だけ拾う
                text.append(inlineText(of: child, kind: kind, code: code))
            }
        }
        return text
    }

    private static func styled(_ string: String, style: Inline, kind: NoteBlock.Kind) -> AttributedString {
        var piece = AttributedString(string)
        var font = Font.system(size: style.size == "small" ? 12 : style.size == "medium" ? 14 : 16)
        if case .heading(let level) = kind {
            font = .system(size: level == 1 ? 24 : level == 2 ? 20 : 16, weight: level == 3 ? .semibold : .bold)
        } else if style.code {
            font = .system(size: 15, design: .monospaced)
        }
        if style.bold { font = font.bold() }
        if style.italic { font = font.italic() }

        piece.font = font
        if style.underline { piece.underlineStyle = .single }
        if style.strike { piece.strikethroughStyle = .single }
        if let color = style.color { piece.foregroundColor = color }
        if let link = style.link { piece.link = link }
        return piece
    }

    private static func inlineStyle(of marks: [NoteMark]?) -> Inline {
        var style = Inline()
        for mark in marks ?? [] {
            switch mark.type {
            case "bold": style.bold = true
            case "italic": style.italic = true
            case "underline": style.underline = true
            case "strike": style.strike = true
            case "code": style.code = true
            case "link":
                style.underline = true
                style.link = mark.attrs?.href.flatMap(URL.init(string:))
            case "textStyle":
                if let size = mark.attrs?.fontSize, size == "small" || size == "medium" {
                    style.size = size
                }
                if let value = mark.attrs?.color, let color = color(from: value) {
                    style.color = color
                }
            default: break
            }
        }
        return style
    }

    // 色は "#4f46e5" / "rgb(79, 70, 229)" / "var(--surface-medium)" のどれかで入っている
    // （ブラウザが hex を rgb に正規化した行と、CSS 変数のまま保存された行がある）。
    // 読めない形は「色の指定なし」として扱う
    private static func color(from value: String) -> Color? {
        var rgb: (Double, Double, Double)?
        if value.hasPrefix("#") {
            let hex = value.dropFirst()
            if hex.count == 6, let n = UInt32(hex, radix: 16) {
                rgb = (Double((n >> 16) & 0xff), Double((n >> 8) & 0xff), Double(n & 0xff))
            }
        } else if value.lowercased().hasPrefix("rgb") {
            let numbers = value.split(whereSeparator: { !"0123456789".contains($0) }).compactMap { Double($0) }
            if numbers.count >= 3 { rgb = (numbers[0], numbers[1], numbers[2]) }
        }
        guard let (r, g, b) = rgb else { return nil }

        // ⚠️ 本文の既定色（ほぼ黒）は「色を付けた」ではなく「既定のまま」の意味で保存されている。
        // そのまま当てるとダークモードで本文が読めなくなるので、暗い色は既定色に倒す
        let luminance = (0.299 * r + 0.587 * g + 0.114 * b) / 255
        if luminance < 0.25 { return nil }
        return Color(.sRGB, red: r / 255, green: g / 255, blue: b / 255)
    }
}

// 文字にかかっている装飾
private struct Inline {
    var bold = false
    var italic = false
    var underline = false
    var strike = false
    var code = false
    var color: Color?
    var size: String?      // "small" | "medium"（既定は nil ＝ 本文サイズ）
    var link: URL?
}
