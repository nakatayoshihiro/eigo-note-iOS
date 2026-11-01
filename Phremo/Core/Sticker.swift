import Foundation

// ノートのステッカー。Web の lib/sticker.ts と同じ規則で決める。
//
// DB には必ず名前（"travel" など）が入っている（null・絵文字の行は 2026-11-01 に
// Web の scripts/backfill-note-sticker.ts で埋め、API も null を拒む）。
// それでも知らない名前は来る：Web が先にステッカーを足すと、このアプリが更新される
// まではその名前を知らない（ノート作成時にサーバーがランダムに付けるので、
// このアプリで作ったノートにも付く）。そのときは ID から決定的に既存の1枚を選ぶ。
// 空欄にすると壊れて見えるので、別の絵で代わりに出す方を選んでいる（2026-11-01 判断）。
// ハッシュは Web と同じ計算。
enum Sticker: String, CaseIterable {
    case business, diary, diamond, interview, listening, speaking, test, travel

    static func forNote(id: String, saved: String?) -> Sticker {
        if let saved, let known = Sticker(rawValue: saved) { return known }
        return allCases[hash(id) % allCases.count]
    }

    // 絵は Assets.xcassets/Stickers/。Web の tsx から scripts/import-stickers.py で
    // 起こしたものなので、描き直すときは Web 側を直してスクリプトを流す
    var imageName: String { "sticker-\(rawValue)" }

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
