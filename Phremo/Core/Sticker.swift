import Foundation

// ノートのステッカー。Web の lib/sticker.ts と同じ規則で決める。
//
// 保存値は絵文字からイラストのキー（"travel" など）に移行済みで、絵文字時代の行も
// まだ残っている。Web は「STICKER_SET に無い値は null と同じ扱いで ID から決定的に
// 算出する」形にしているので、こちらも同じにする。ハッシュまで合わせてあるので、
// 同じノートには Web と同じ絵が出る。
enum Sticker: String, CaseIterable {
    case business, diary, diamond, interview, listening, speaking, test, travel

    static func forNote(id: String, saved: String?) -> Sticker {
        if let saved, let known = Sticker(rawValue: saved) { return known }
        return allCases[hash(id) % allCases.count]
    }

    // ⚠️ 暫定。Web はイラスト8種（app/components/stickers/）だが iOS には絵がまだ無いので
    // SF Symbol で代用している。絵をアセットカタログに入れたらここを差し替える
    var symbol: String {
        switch self {
        case .business: "briefcase.fill"
        case .diary: "book.closed.fill"
        case .diamond: "diamond.fill"
        case .interview: "person.2.fill"
        case .listening: "headphones"
        case .speaking: "bubble.left.and.bubble.right.fill"
        case .test: "checkmark.square.fill"
        case .travel: "airplane"
        }
    }

    // lib/sticker.ts の hashString と同じ計算。JS の `h = (h << 5) - h + code; h |= 0`
    // ＝ 32bit で丸めながら回すので、Int32 のオーバーフロー演算子で同じ値にする
    private static func hash(_ text: String) -> Int {
        var h: Int32 = 0
        for unit in text.utf16 {
            h = (h << 5) &- h &+ Int32(unit)
        }
        // Int32.min を abs すると Swift は落ちるので、Int に広げてから絶対値を取る
        return abs(Int(h))
    }
}
