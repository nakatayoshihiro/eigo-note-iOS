import Foundation
import Observation

// ノートの保存。エディタ（WebView）から届いた本文とタイトルをサーバーへ送る。
//
// ■ 方針
// エディタは打鍵が止まってから本文・タイトルを送ってくる（0.4秒）。こちらはそれを受けて
// PATCH するだけだが、通信中に次が来ることがあるので、本文・タイトルそれぞれ**最新の1件だけ**を
// 覚えておいて送り直す。取りこぼしても最後の状態には必ず追いつく。
// 両方たまっていれば1回の PATCH にまとめる（Web も本文とタイトルを一緒に送っている）。
// 本文とタイトルで送り手を分けないのは、PATCH が並行して走ると届く順が入れ替わりうるため。
//
// ■ 本文の中身を読まない
// 受け取るのは JSON の文字列で、アプリはその中を解釈しない（[String: Any] にも
// しない）。長い本文だと変換だけでメインスレッドが止まるうえ、Web 側が付けた
// 未知の属性を落としてしまうため。詳しくは APIClient.patchRawJSON のコメント。
@Observable
final class NoteSaver {
    /// 直近の保存が終わった時刻。画面に「保存しました」を出すのに使う
    private(set) var savedAt: Date?
    /// 保存できていない理由。出したままにする（自動保存なので、黙って失敗させない）
    private(set) var failure: String?
    /// 送信中かどうか
    private(set) var isSaving = false

    private let noteId: String
    private var pendingDocument: String?
    private var pendingTitle: String?
    private var task: Task<Void, Never>?

    init(noteId: String) {
        self.noteId = noteId
    }

    /// エディタから本文が届いた。`document` は JSON の文字列
    func save(document: String) {
        pendingDocument = document
        startIfIdle()
    }

    /// エディタからタイトルが届いた
    func save(title: String) {
        pendingTitle = title
        startIfIdle()
    }

    private func startIfIdle() {
        guard task == nil else { return }   // 送信中なら、終わった後に最新を送る
        task = Task { await drain() }
    }

    private func drain() async {
        defer { task = nil }
        while pendingDocument != nil || pendingTitle != nil {
            // 送らなかった方は鍵ごと省く＝サーバー側でその列に触らない
            var fields: [String] = []
            if let title = pendingTitle { fields.append("\"title\":\(Self.quoted(title))") }
            if let document = pendingDocument { fields.append("\"bodyJson\":\(document)") }
            pendingTitle = nil
            pendingDocument = nil
            isSaving = true
            do {
                try await APIClient.patchRawJSON(
                    "/api/notes/\(noteId)",
                    body: "{\(fields.joined(separator: ","))}"
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

    /// 文字列を JSON の文字列リテラルにする。引用符とエスケープは JSONSerialization に任せる
    private static func quoted(_ raw: String) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: raw, options: .fragmentsAllowed),
              let literal = String(data: data, encoding: .utf8) else { return "\"\"" }
        return literal
    }
}
