import SwiftUI

// ⚠️ スパイク（2026-09-02）。WebView に載せた Tiptap を実機で確かめるためだけの画面。
// 見るのは3点だけ：
//   1. 日本語入力（変換・確定）が壊れないか
//   2. キーボードが出た時にカーソルが隠れないか、打鍵にスクロールが追従するか
//   3. 編集できるようになるまで何秒か
// 2026-09-02 から保存もする（本文だけ）。判断が付いたらこのファイルごと消して、
// ノート画面そのものを WebView に置き換える。
struct EditorSpike: View {
    let note: Note
    let doc: NoteDoc

    init(note: Note, doc: NoteDoc) {
        self.note = note
        self.doc = doc
        _saver = State(initialValue: NoteBodySaver(noteId: note.id))
    }

    @Environment(\.dismiss) private var dismiss
    @State private var readyMs: Int?
    @State private var changes = 0
    @State private var saver: NoteBodySaver
    @State private var booted = false
    @State private var mode = "full"
    @State private var jsError: String?

    var body: some View {
        NavigationStack {
            NoteEditorWebView(
                doc: doc,
                mode: mode,
                onChange: { document in
                    changes += 1
                    saver.save(document: document)
                },
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
        if let failure = saver.failure { return failure }
        guard let readyMs else {
            return booted ? "HTML は読めた／エディタが起動しない" : "起動中…"
        }
        if saver.isSaving { return "保存中…" }
        if saver.savedAt != nil { return "保存しました ・ 変更 \(changes) 回" }
        return "起動 \(readyMs)ms ・ 変更 \(changes) 回"
    }
}
