import SwiftUI
import Observation

// キーボードのすぐ上に出す書式バー。Web の選択ツールバー（TiptapEditor.tsx の BubbleMenu）に当たる。
//
// ■ なぜキーボードの上か
// Web で、タッチ端末に画面下部固定のバーを試して却下された（2026-07-20）。iPhone では
// キーボードに同化した形でないと成立しない、という判断。Notion のアプリも同じ置き方をしている。
// WebView 標準の「∧ ∨ ✓」のバーをこれに差し替える（EditorWebView.installFormattingBar）。
//
// ■ 押下状態
// エディタがカーソル位置の書式を { type: "format" } で送ってくる（変わった時だけ）。
// ボタンを押すと window.phremoEditor.format(...) を呼ぶ。中身は Web のツールバーと同じ操作。

/// カーソル位置の書式。エディタから届く
@Observable
final class FormattingState {
    var inBody = false
    var hasSelection = false
    var selectionTooLong = false   // 単語として登録できない長さの選択
    var bold = false
    var italic = false
    var underline = false
    var heading = 0          // 0 = 見出しではない
    var fontSize: String?    // nil = 大（既定）
    var colorIndex = -1      // TextColor.palette の番号。-1 = 未指定・パレット外
    var list: String?        // "bulletList" | "orderedList" | "taskList"

    func update(from message: [String: Any]) {
        inBody = message["inBody"] as? Bool ?? false
        hasSelection = message["hasSelection"] as? Bool ?? false
        selectionTooLong = message["selectionTooLong"] as? Bool ?? false
        bold = message["bold"] as? Bool ?? false
        italic = message["italic"] as? Bool ?? false
        underline = message["underline"] as? Bool ?? false
        heading = message["heading"] as? Int ?? 0
        fontSize = message["fontSize"] as? String
        colorIndex = message["colorIndex"] as? Int ?? -1
        list = message["list"] as? String
    }
}

enum FormatCommand {
    case bold, italic, underline
    case heading(Int)
    case fontSize(String?)   // nil = 大
    case color(Int?)         // nil = 解除
    case list(String)

    /// エディタに渡す JS。値は JSON の形で書く（文字列の引用符を自前で組まない）
    var script: String {
        switch self {
        case .bold: return "window.phremoEditor.format('bold')"
        case .italic: return "window.phremoEditor.format('italic')"
        case .underline: return "window.phremoEditor.format('underline')"
        case .heading(let level): return "window.phremoEditor.format('heading\(level)')"
        case .fontSize(let size): return "window.phremoEditor.format('fontSize', \(size.map { "'\($0)'" } ?? "null"))"
        case .color(let index): return "window.phremoEditor.format('color', \(index ?? -1))"
        case .list(let name): return "window.phremoEditor.format('\(name)')"
        }
    }
}

/// 文字色のパレット。lib/tiptap-colors.ts の TEXT_COLORS と**同じ並び**（JS へは番号で渡す）
enum TextColor {
    static let palette: [(label: String, color: UIColor)] = [
        ("黒", UIColor(Color(hex: 0x2f2f2f))),
        ("グレー", UIColor(Color(hex: 0x767676))),
        ("ローズ", UIColor(Color(hex: 0xbb3369))),
        ("オレンジ", UIColor(Color(hex: 0xc2410c))),
        ("グリーン", UIColor(Color(hex: 0x1f7a45))),
        ("ティール", UIColor(Color(hex: 0x00727a))),
        ("ブルー", UIColor(Color(hex: 0x2367c0))),
    ]

    /// メニューに出す色見本。メニューは画像を単色に塗り替えるので、元の色のまま描かせる
    static func swatch(_ color: UIColor) -> UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: 20, height: 20)).image { _ in
            color.setFill()
            UIBezierPath(ovalIn: CGRect(x: 1, y: 1, width: 18, height: 18)).fill()
        }
        .withRenderingMode(.alwaysOriginal)
    }
}

struct FormattingBar: View {
    let state: FormattingState
    var onFormat: (FormatCommand) -> Void
    var onRegisterWord: () -> Void
    var onDismissKeyboard: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 2) {
                    // Web のツールバーと同じく、選択中は先頭に「単語登録」
                    if state.inBody && state.hasSelection {
                        Button(action: onRegisterWord) {
                            Label("単語登録", systemImage: "sparkles")
                                .font(.subheadline.bold())
                        }
                        .buttonStyle(.borderedProminent)
                        .buttonBorderShape(.capsule)
                        .tint(Color(hex: 0x2f2f2f))
                        // Web と同じく、登録できない長さの選択では押せなくする
                        .disabled(state.selectionTooLong)
                        .accessibilityHint(state.selectionTooLong ? "選択範囲が長すぎます（200文字まで）" : "")
                        .padding(.trailing, 6)
                    }
                    textMenu
                    colorMenu
                    separator
                    toggle("太字", systemImage: "bold", isOn: state.bold) { onFormat(.bold) }
                    toggle("斜体", systemImage: "italic", isOn: state.italic) { onFormat(.italic) }
                    toggle("下線", systemImage: "underline", isOn: state.underline) { onFormat(.underline) }
                    separator
                    toggle("箇条書き", systemImage: "list.bullet", isOn: state.list == "bulletList") {
                        onFormat(.list("bulletList"))
                    }
                    toggle("番号付きリスト", systemImage: "list.number", isOn: state.list == "orderedList") {
                        onFormat(.list("orderedList"))
                    }
                    toggle("チェックリスト", systemImage: "checklist", isOn: state.list == "taskList") {
                        onFormat(.list("taskList"))
                    }
                }
                .padding(.horizontal, 10)
                // タイトル欄にいる間は本文の書式を変えられない。ボタンの色を自分で
                // 指定しているので、無効の見た目（薄く）も自分で付ける
                .disabled(!state.inBody)
                .opacity(state.inBody ? 1 : 0.35)
            }

            Divider().frame(height: 24)

            Button(action: onDismissKeyboard) {
                Image(systemName: "keyboard.chevron.compact.down")
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("キーボードを閉じる")
        }
        .frame(height: 48)
        .tint(Color(.label))
        .glassEffect(.regular, in: .capsule)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
    }

    private var separator: some View {
        Divider().frame(height: 20).padding(.horizontal, 6)
    }

    private func toggle(_ label: String, systemImage: String, isOn: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.body.weight(.medium))
                .frame(width: 36, height: 36)
                .foregroundStyle(isOn ? Color(.systemBackground) : Color(.label))
                .background(isOn ? Color(.label) : .clear, in: RoundedRectangle(cornerRadius: 8))
        }
        .accessibilityLabel(label)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }

    // 見出しと本文サイズ（Web の Text メニューと同じ並び。見出しとサイズは排他）
    private var textMenu: some View {
        Menu {
            Section("見出し") {
                check("H1 見出し (大)", isOn: state.heading == 1) { onFormat(.heading(1)) }
                check("H2 見出し (中)", isOn: state.heading == 2) { onFormat(.heading(2)) }
            }
            Section("本文") {
                check("小", isOn: state.heading == 0 && state.fontSize == "small") { onFormat(.fontSize("small")) }
                check("中", isOn: state.heading == 0 && state.fontSize == "medium") { onFormat(.fontSize("medium")) }
                check("大", isOn: state.heading == 0 && state.fontSize == nil) { onFormat(.fontSize(nil)) }
            }
        } label: {
            HStack(spacing: 2) {
                Image(systemName: "textformat.size")
                Image(systemName: "chevron.down").font(.caption2.weight(.bold))
            }
            .frame(height: 36)
            .padding(.horizontal, 6)
        }
        .accessibilityLabel("文字の大きさ")
    }

    private var colorMenu: some View {
        Menu {
            ForEach(Array(TextColor.palette.enumerated()), id: \.offset) { index, entry in
                Button {
                    onFormat(.color(index))
                } label: {
                    Label {
                        Text(entry.label)
                    } icon: {
                        Image(uiImage: TextColor.swatch(entry.color))
                    }
                }
            }
            Button("色を解除", systemImage: "xmark") { onFormat(.color(nil)) }
        } label: {
            HStack(spacing: 2) {
                Circle()
                    .fill(Color(state.colorIndex >= 0 ? TextColor.palette[state.colorIndex].color : TextColor.palette[0].color))
                    .overlay(Circle().strokeBorder(Color(.separator)))
                    .frame(width: 20, height: 20)
                Image(systemName: "chevron.down").font(.caption2.weight(.bold))
            }
            .frame(height: 36)
            .padding(.horizontal, 6)
        }
        .accessibilityLabel("文字色")
    }

    private func check(_ title: String, isOn: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            if isOn {
                Label(title, systemImage: "checkmark")
            } else {
                Text(title)
            }
        }
    }
}
