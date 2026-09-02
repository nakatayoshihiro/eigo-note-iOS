import SwiftUI

// ノート1件の画面。本文の表示と編集をまとめて WebView（Tiptap）が受け持つ。
//
// ■ なぜ表示までここに寄せたか
// Web と同じ機能を出す方針のため、編集は WebView に載せた（[[ios-editor-architecture]]）。
// 表示だけネイティブに残すと、同じ本文が2つの描画で出て、フォント・行間・選択の挙動が
// 食い違う。だから読みも WebView に寄せている。
//
// ■ 本文は文字列のまま運ぶ
// サーバーから来た JSON を Swift の型に変換しない。長い本文だと変換だけで画面が止まり、
// Web 側が付けた未知の属性も落ちるため（APIClient.getRawJSON のコメント参照）。
struct NoteDetailView: View {
    let note: Note

    @State private var document: String?
    @State private var words: String?
    @State private var loadFailed = false
    @State private var saver: NoteBodySaver

    init(note: Note) {
        self.note = note
        _saver = State(initialValue: NoteBodySaver(noteId: note.id))
    }

    var body: some View {
        Group {
            if let document {
                NoteEditorWebView(
                    document: document,
                    words: words,
                    onChange: { saver.save(document: $0) }
                )
            } else if loadFailed {
                ContentUnavailableView(
                    "本文を読み込めませんでした",
                    systemImage: "exclamationmark.triangle",
                    description: Text("通信を確認して、開き直してください。")
                )
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .ignoresSafeArea(.container, edges: .bottom)
        .navigationTitle(note.displayTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                // 自動保存なので、失敗を黙って飲み込まない（Web と同じ扱い）
                if let failure = saver.failure {
                    Text(failure).font(.caption).foregroundStyle(.red)
                } else {
                    Image(Sticker.forNote(id: note.id, saved: note.sticker).imageName)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 28, height: 28)
                        .rotationEffect(.degrees(12))
                }
            }
        }
        .onAppear { loadIfNeeded() }
        // iPad は詳細のビューが作り直されず中身だけ差し替わるので、
        // ノートが変わったら取り直す
        .onChange(of: note.id) { _, _ in
            document = nil
            words = nil
            loadFailed = false
            saver = NoteBodySaver(noteId: note.id)
            loadIfNeeded()
        }
    }

    // ⚠️ `.task(id:)` を使わないこと。ビューが作り直されると通信を打ち切るため、
    // 一覧が更新されるたびに取得が巻き添えで死ぬ（-999 cancelled。2026-09-01 に実機で発生）
    private func loadIfNeeded() {
        if document == nil && !loadFailed { Task { await loadBody() } }
        if words == nil { Task { await loadWords() } }
    }

    private func loadBody() async {
        do {
            let json = try await APIClient.getRawJSON("/api/notes/\(note.id)")
            // 本文だけを文字列のまま抜き出す
            document = APIClient.field("bodyJson", of: json) ?? "{\"type\":\"doc\",\"content\":[{\"type\":\"paragraph\"}]}"
        } catch {
            loadFailed = true
            print("note body load failed: \(error)")
        }
    }

    private func loadWords() async {
        do {
            words = try await APIClient.getRawJSON(
                "/api/words",
                query: [URLQueryItem(name: "noteId", value: note.id)]
            )
        } catch {
            // 塗りが無くても本文は読める。ここで画面を止めない
            print("note words load failed: \(error)")
        }
    }
}
