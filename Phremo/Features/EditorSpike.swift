import SwiftUI

// ⚠️ スパイク（2026-09-02）。WebView に載せた Tiptap を実機で確かめるためだけの画面。
// 見るのは3点だけ：
//   1. 日本語入力（変換・確定）が壊れないか
//   2. キーボードが出た時にカーソルが隠れないか、打鍵にスクロールが追従するか
//   3. 編集できるようになるまで何秒か
// 保存はしない（読み込んで触るだけ）。判断が付いたらこのファイルごと消すか、
// 本採用してノート画面そのものに置き換える。
struct EditorSpike: View {
    let note: Note
    let doc: NoteDoc

    @Environment(\.dismiss) private var dismiss
    @State private var readyMs: Int?
    @State private var changes = 0
    @State private var booted = false
    @State private var mode = "full"
    @State private var jsError: String?

    var body: some View {
        NavigationStack {
            NoteEditorWebView(
                doc: doc,
                mode: mode,
                onChange: { changes += 1 },
                onReady: { readyMs = $0 },
                onBoot: { booted = true },
                onError: { jsError = $0 }
            )
            .ignoresSafeArea(.container, edges: .bottom)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("閉じる") { dismiss() }
                }
                // 計測モードの切り替え。HTML 側のボタンだと自動操作が届かないので
                // ネイティブ側に置く（スパイクの間だけ）
                ToolbarItem(placement: .topBarTrailing) {
                    HStack {
                        Button("短") { mode = "small" }
                        Button("素") { mode = "plain" }
                        Button("全") { mode = "full" }
                    }
                }
                // キーボードが出ると下のバーは隠れる。測るための数字なので上に置く
                ToolbarItem(placement: .principal) {
                    Text(status).font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
    }

    private var status: String {
        if let jsError { return "JS エラー: \(jsError)" }
        guard let readyMs else {
            return booted ? "HTML は読めた／エディタが起動しない" : "起動中…"
        }
        return "起動 \(readyMs)ms ・ 変更 \(changes) 回 ・ 保存はしません"
    }
}
