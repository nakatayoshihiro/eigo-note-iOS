import Foundation
import SwiftUI

// ノート本文（Tiptap が吐く HTML）を、そのまま SwiftUI で描ける形に読み替える。
//
// ■ なぜ WebView で表示しないのか
// 本文は将来 ProseMirror JSON に移行する予定（書く機能の前提）。その時に差し替わるのは
// ここの読み取り部分だけで、下の NoteBlock と描画側はそのまま使える。WebView に逃がすと
// 見た目も選択挙動も Web 依存のままになり、移行しても何も残らない。
//
// ■ 対応している範囲
// Web 側のエディタ（app/components/TiptapEditor.tsx）が使う拡張に合わせてある＝
// StarterKit（段落・見出し1〜3・太字・斜体・打ち消し・コード・引用・箇条書き・番号付き・
// 水平線・改行・リンク）＋ タスクリスト ＋ 色（span[style]）＋ 文字サイズ（span[data-size]）。
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
    static func parse(html: String) -> [NoteBlock] {
        // XMLParser に通すための下ごしらえ。Tiptap の出力は HTML なので、閉じない要素と
        // HTML 固有の実体参照だけ直せば XML として読める（&amp; &lt; &gt; は XML と共通）
        var xml = html
            .replacingOccurrences(of: "<br>", with: "<br/>")
            .replacingOccurrences(of: "<hr>", with: "<hr/>")
            .replacingOccurrences(of: "&nbsp;", with: "\u{00A0}")
        xml = xml.replacingOccurrences(
            of: "<img([^>]*[^/])?>", with: "<img$1/>", options: .regularExpression
        )
        xml = xml.replacingOccurrences(
            of: "<input([^>]*[^/])?>", with: "<input$1/>", options: .regularExpression
        )

        let parser = XMLParser(data: Data("<body>\(xml)</body>".utf8))
        let delegate = NoteBodyBuilder()
        parser.delegate = delegate
        guard parser.parse() else {
            // 読めなかったときは黙って空にせず、タグを落とした素のテキストを見せる。
            // 本文が消えたように見えるのが一番困る
            let plain = html.replacingOccurrences(
                of: "<[^>]+>", with: "", options: .regularExpression
            )
            return [NoteBlock(kind: .paragraph, text: AttributedString(plain))]
        }
        return delegate.finish()
    }
}

// 文字にかかっている装飾。開始タグで積み、終了タグで戻す
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

private final class NoteBodyBuilder: NSObject, XMLParserDelegate {
    private var blocks: [NoteBlock] = []
    private var inline: [Inline] = [Inline()]
    private var lists: [(ordered: Bool, task: Bool, counter: Int)] = []

    private var kind: NoteBlock.Kind?
    private var text = AttributedString()
    // <li> の中にいる間だけ深さを覚えておく。項目が複数段落のとき、2段落目以降を
    // 同じ字下げで続けるために要る
    private var itemDepth: Int?
    // タスク項目のチェックボックスは <label><input>…</label> で書き出される。
    // 中身は飾りなので丸ごと読み飛ばす
    private var skipping = 0

    func finish() -> [NoteBlock] {
        flush()
        return blocks
    }

    func parser(
        _ parser: XMLParser,
        didStartElement element: String,
        namespaceURI: String?,
        qualifiedName: String?,
        attributes: [String: String] = [:]
    ) {
        if skipping > 0 { skipping += 1; return }

        switch element {
        case "label", "input":
            skipping = 1

        case "ul", "ol":
            lists.append((ordered: element == "ol", task: attributes["data-type"] == "taskList", counter: 0))

        case "li":
            flush()
            let depth = max(lists.count - 1, 0)
            itemDepth = depth
            if var list = lists.last {
                if list.task {
                    kind = .task(done: attributes["data-checked"] == "true", depth: depth)
                } else if list.ordered {
                    list.counter += 1
                    lists[lists.count - 1] = list
                    kind = .ordered(number: list.counter, depth: depth)
                } else {
                    kind = .bullet(depth: depth)
                }
            } else {
                kind = .bullet(depth: 0)
            }

        case "p":
            // リスト項目の中身は <li><p>…</p></li> の形で来る。最初の段落は項目そのもの
            // なので新しい行にしない（2つ目以降は同じ字下げの段落として続ける）
            if kind == nil {
                flush(startingFrom: itemDepth.map { .continuation(depth: $0) } ?? .paragraph)
            } else if !text.characters.isEmpty {
                flush(startingFrom: kind)
            }

        case "h1", "h2", "h3":
            flush()
            kind = .heading(level: Int(element.dropFirst()) ?? 1)

        case "blockquote":
            flush()
            kind = .quote

        case "hr":
            flush()
            blocks.append(NoteBlock(kind: .rule, text: AttributedString()))

        case "br":
            text.append(AttributedString("\n"))

        case "div":
            break   // タスク項目の入れ物。中の <p> が本体

        default:
            inline.append(mark(element, attributes: attributes, from: inline[inline.count - 1]))
        }
    }

    func parser(
        _ parser: XMLParser,
        didEndElement element: String,
        namespaceURI: String?,
        qualifiedName: String?
    ) {
        if skipping > 0 { skipping -= 1; return }

        switch element {
        case "ul", "ol":
            flush()
            if !lists.isEmpty { lists.removeLast() }
        case "li":
            flush()
            itemDepth = nil
        case "p", "h1", "h2", "h3", "blockquote":
            flush()
        case "hr", "br", "div", "label", "input":
            break
        default:
            if inline.count > 1 { inline.removeLast() }
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        guard skipping == 0 else { return }
        if kind == nil { kind = .paragraph }

        var piece = AttributedString(string)
        let style = inline[inline.count - 1]
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
        text.append(piece)
    }

    // 開いている行を確定する。`startingFrom` を渡すと、同じ種類の行を続けて開き直す
    private func flush(startingFrom next: NoteBlock.Kind? = nil) {
        if let kind {
            let trimmed = String(text.characters).trimmingCharacters(in: .whitespacesAndNewlines)
            // 空の段落は Web でも1行ぶんの間隔になるので、間隔として残す。
            // ただしリスト項目の空行は記号だけが並んでしまうので捨てる
            if !trimmed.isEmpty || kind == .paragraph {  // 空行の扱い
                blocks.append(NoteBlock(kind: kind, text: text))
            }
        }
        text = AttributedString()
        kind = next
    }

    private func mark(_ element: String, attributes: [String: String], from parent: Inline) -> Inline {
        var style = parent
        switch element {
        case "strong", "b": style.bold = true
        case "em", "i": style.italic = true
        case "u": style.underline = true
        case "s", "del", "strike": style.strike = true
        case "code": style.code = true
        case "a":
            style.underline = true
            style.link = attributes["href"].flatMap(URL.init(string:))
        case "span":
            if let size = attributes["data-size"], size == "small" || size == "medium" {
                style.size = size
            }
            if let color = attributes["style"].flatMap(Self.color(fromStyle:)) {
                style.color = color
            }
        default: break
        }
        return style
    }

    // style="color: #4f46e5" / "color: rgb(79, 70, 229)" の両方が来る
    // （ブラウザが hex を rgb に正規化して保存された行がある）
    private static func color(fromStyle style: String) -> Color? {
        guard let range = style.range(of: "color:", options: .caseInsensitive) else { return nil }
        let value = style[range.upperBound...]
            .prefix { $0 != ";" }
            .trimmingCharacters(in: .whitespaces)

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
