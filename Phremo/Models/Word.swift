import Foundation

// GET /api/words のレスポンス（app/api/words/route.ts）。
// ノートと違ってページングは無く、Word の配列がそのまま返る。
struct Word: Identifiable, Decodable, Hashable {
    let id: String
    let lemma: String
    let surface: String
    let pos: String
    let translation: String
    let note: String
    let sourceSentence: String
    let sourceNoteId: String?
    let createdAt: Date
    let reviewCount: Int
    let rememberedCount: Int
    // null = まだ取得していない / [] = 取得したが見つからなかった、の2状態がある。
    // Web 側（words/page.tsx）もこの区別で表示を変えている
    let relatedForms: [RelatedForm]?

    // 補足は「ニュアンス＋形の説明」を改行で連結した文字列（lookup-word の出力形）。
    // Web は NoteBullets で行ごとの箇条書きにしているので、こちらも行に割る
    var noteLines: [String] {
        note.split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    // 検索の当たり判定。Web（words/page.tsx の filteredWords）と同じ対象に揃える＝
    // 見出し語・本文中の形・訳・品詞・派生語（綴りと訳）。
    // ⚠️ 派生語の「品詞」は対象にしない。「副詞」で検索したときに副詞の派生語を持つ
    // 単語まで並び、品詞フィルタの結果とずれるため
    func matches(_ query: String) -> Bool {
        let q = query.lowercased()
        if q.isEmpty { return true }
        if lemma.lowercased().contains(q) { return true }
        if surface.lowercased().contains(q) { return true }
        if translation.lowercased().contains(q) { return true }
        if pos.lowercased().contains(q) { return true }
        return (relatedForms ?? []).contains {
            $0.form.lowercased().contains(q) || $0.translation.lowercased().contains(q)
        }
    }
}

// 派生語。DB では Json 列なので、API 側は form と pos しか型検証していない
// （lib/word-limits.ts）。translation が欠けた行が来ても落ちないようにしておく
struct RelatedForm: Decodable, Hashable {
    let pos: String
    let form: String
    let translation: String

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        pos = (try? container.decode(String.self, forKey: .pos)) ?? ""
        form = (try? container.decode(String.self, forKey: .form)) ?? ""
        translation = (try? container.decode(String.self, forKey: .translation)) ?? ""
    }

    private enum CodingKeys: String, CodingKey {
        case pos, form, translation
    }
}
