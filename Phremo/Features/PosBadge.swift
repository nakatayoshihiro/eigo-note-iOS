import SwiftUI

// 品詞ピル。色は Web の lib/pos.ts（Figma PartOfSpeechBadge 881:6161）と同じ値。
// 変えるときは両方直すこと。
enum Pos {
    // 単語登録で使う品詞の全種類（lib/pos.ts の POS_TYPES と同順）
    static let all = ["名詞", "動詞", "形容詞", "副詞", "前置詞", "接続詞", "句動詞"]

    private static let colors: [String: (bg: Color, text: Color)] = [
        "名詞": (Color(hex: 0xf2f0fe), Color(hex: 0x5a42f3)),
        "動詞": (Color(hex: 0xe4f6eb), Color(hex: 0x2d9559)),
        "形容詞": (Color(hex: 0xfdf0e7), Color(hex: 0xf98e42)),
        "副詞": (Color(hex: 0xffebf3), Color(hex: 0xe83480)),
        "前置詞": (Color(hex: 0xddebfd), Color(hex: 0x1e8ee3)),
        "接続詞": (Color(hex: 0xfff7e8), Color(hex: 0xec9a2f)),
        "句動詞": (Color(hex: 0xedfafb), Color(hex: 0x008c94)),
    ]

    static func color(for pos: String) -> (bg: Color, text: Color) {
        colors[pos] ?? (Color(hex: 0xf0f0f3), Color(hex: 0x767676))
    }
}

struct PosBadge: View {
    let pos: String
    // Web は淡い地に濃い文字。ダークモードでその地色をそのまま置くと白い札が
    // 浮くので、文字色を薄く敷いた地に置き換える（色の見分けは保ったまま）
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        if !pos.isEmpty {
            let c = Pos.color(for: pos)
            Text(pos)
                .font(.caption2.bold())
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(scheme == .dark ? c.text.opacity(0.22) : c.bg, in: Capsule())
                .foregroundStyle(c.text)
        }
    }
}

extension Color {
    // Web から色を写すときに 16進をそのまま書けるようにする
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xff) / 255,
            green: Double((hex >> 8) & 0xff) / 255,
            blue: Double(hex & 0xff) / 255
        )
    }
}
