import Foundation
import Observation

// 本文の保存。エディタ（WebView）から届いたドキュメントをサーバーへ送る。
//
// ■ 方針
// エディタは打鍵が止まってから本文を送ってくる（0.4秒）。こちらはそれを受けて
// PATCH するだけだが、通信中に次の本文が来ることがあるので、**最新の1件だけ**を
// 覚えておいて送り直す。取りこぼしても最後の状態には必ず追いつく。
//
// ■ 中身を読まない
// 受け取るのは JSON の文字列で、アプリはその中を解釈しない（[String: Any] にも
// しない）。長い本文だと変換だけでメインスレッドが止まるうえ、Web 側が付けた
// 未知の属性を落としてしまうため。詳しくは APIClient.patchRawJSON のコメント。
@Observable
final class NoteBodySaver {
    /// 直近の保存が終わった時刻。画面に「保存しました」を出すのに使う
    private(set) var savedAt: Date?
    /// 保存できていない理由。出したままにする（自動保存なので、黙って失敗させない）
    private(set) var failure: String?
    /// 送信中かどうか
    private(set) var isSaving = false

    private let noteId: String
    private var pending: String?
    private var task: Task<Void, Never>?

    init(noteId: String) {
        self.noteId = noteId
    }

    /// エディタから本文が届いた。`document` は JSON の文字列
    func save(document: String) {
        pending = document
        guard task == nil else { return }   // 送信中なら、終わった後に最新を送る
        task = Task { await drain() }
    }

    private func drain() async {
        defer { task = nil }
        while let document = pending {
            pending = nil
            isSaving = true
            do {
                // 本文以外は触らない。タイトルやステッカーは別の経路が持っている
                try await APIClient.patchRawJSON(
                    "/api/notes/\(noteId)",
                    body: "{\"bodyJson\":\(document)}"
                )
                savedAt = Date()
                failure = nil
            } catch APIError.unauthorized {
                failure = "ログインの有効期限が切れました"
            } catch {
                // 次の打鍵で送り直されるので、その間だけ知らせる
                failure = "保存できていません"
            }
            isSaving = false
        }
    }
}
