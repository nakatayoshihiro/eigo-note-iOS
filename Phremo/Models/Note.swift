import Foundation

// GET /api/notes のレスポンス。サーバー側は { items, nextCursor } を返す
// （app/api/notes/route.ts）。nextCursor はページング用で、今は一覧の初回表示しか
// 使っていないが、あとで無限スクロールを足すときにここが要る。
struct NoteListResponse: Decodable {
    let items: [Note]
    let nextCursor: String?
}

struct Note: Identifiable, Decodable, Hashable {
    let id: String
    let title: String
    // 本文の正は bodyJson。body は検索と一覧プレビューのためのプレーンテキストで、
    // 一覧（GET /api/notes）はこちらしか返さない。bodyJson が入るのは
    // 1件取得（GET /api/notes/{id}）だけ
    let body: String
    let bodyJson: NoteDoc?
    // ノートのステッカー絵文字。null のときはサーバー側が id から決定的に算出する
    // 旧挙動のフォールバックがあるので、アプリ側でも代替を出す
    let sticker: String?
    let lastViewedAt: Date
    let wordCount: Int

    // サーバーは単語数を `_count: { words: N }` という入れ子で返す。
    // アプリ側でその形を引きずりたくないので、ここで平らにする
    private enum CodingKeys: String, CodingKey {
        case id, title, body, bodyJson, sticker, lastViewedAt
        case count = "_count"
    }

    private struct Count: Decodable {
        let words: Int
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        body = try container.decode(String.self, forKey: .body)
        // 本文の木が読めなくてもノート自体は開けるようにする（body のテキストは出せる）
        bodyJson = try? container.decodeIfPresent(NoteDoc.self, forKey: .bodyJson)
        sticker = try container.decodeIfPresent(String.self, forKey: .sticker)
        lastViewedAt = try container.decode(Date.self, forKey: .lastViewedAt)
        wordCount = try container.decodeIfPresent(Count.self, forKey: .count)?.words ?? 0
    }

    // 一覧に出す見出し。サーバー側は title の既定値が空文字なので、
    // 無題のノートがのっぺらぼうにならないよう代替を置く
    var displayTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "無題のノート" : title
    }
}
