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
    /// 開いたらタイトルにカーソルを置く（作ったばかりのノート）
    var focusTitle = false
    /// タイトルが変わった。一覧の行とナビゲーションバーの見出しを追従させるのに使う
    var onTitleChange: (String) -> Void = { _ in }
    /// 単語を登録した。一覧の語数（削除の確認で単語の扱いを聞くかの判断にも使う）を追従させる
    var onWordAdded: () -> Void = {}

    @State private var document: String?
    @State private var title: String?
    @State private var words: String?
    @State private var loadFailed = false
    @State private var saver: NoteSaver
    // 登録画面に渡す、本文で選んだ語と文
    @State private var registering: WordDraft?

    struct WordDraft: Identifiable {
        let id = UUID()
        let surface: String
        let sentence: String
    }

    init(
        note: Note,
        focusTitle: Bool = false,
        onTitleChange: @escaping (String) -> Void = { _ in },
        onWordAdded: @escaping () -> Void = {}
    ) {
        self.note = note
        self.focusTitle = focusTitle
        self.onTitleChange = onTitleChange
        self.onWordAdded = onWordAdded
        _saver = State(initialValue: NoteSaver(noteId: note.id))
    }

    var body: some View {
        Group {
            if let document {
                NoteEditorWebView(
                    document: document,
                    title: title ?? note.title,
                    words: words,
                    focusTitle: focusTitle,
                    onChange: { saver.save(document: $0) },
                    onTitleChange: {
                        // 単語登録で AI に渡すノート名にも使うので手元でも持つ
                        // （エディタへは最初の1回しか送らないので、ここで変えても送り返さない）
                        title = $0
                        saver.save(title: $0)
                        onTitleChange($0)
                    },
                    onRegisterWord: { registering = WordDraft(surface: $0, sentence: $1) }
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
        .sheet(item: $registering) { draft in
            WordRegisterView(
                surface: draft.surface,
                sentence: draft.sentence,
                noteId: note.id,
                noteTitle: title ?? note.title,
                onSaved: { _ in
                    onWordAdded()
                    // 塗りを取り直す（新しい語にも印が付く）
                    Task { await loadWords() }
                }
            )
        }
        .onAppear { loadIfNeeded() }
        // iPad は詳細のビューが作り直されず中身だけ差し替わるので、
        // ノートが変わったら取り直す
        .onChange(of: note.id) { _, _ in
            document = nil
            title = nil
            words = nil
            loadFailed = false
            saver = NoteSaver(noteId: note.id)
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
            // 本文は文字列のまま抜き出す。タイトルも一覧の値ではなくこちらを使う
            // （一覧を読んだ後に Web で変えられていても、開いた時点の最新を出す）
            let fields = APIClient.fields(["bodyJson", "title"], of: json)
            title = fields["title"].flatMap { try? JSONDecoder().decode(String.self, from: Data($0.utf8)) }
            document = fields["bodyJson"] ?? "{\"type\":\"doc\",\"content\":[{\"type\":\"paragraph\"}]}"
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
