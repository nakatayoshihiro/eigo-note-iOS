import SwiftUI

struct NoteListView: View {
    let auth: AuthStore

    @State private var notes: [Note] = []
    @State private var phase: Phase = .loading
    // 選択はノートそのものではなく id で持つ。引っ張って更新しても選択が生き残る
    @State private var selectedID: Note.ID?
    // 作ったばかりのノート。開いた時にタイトルへカーソルを置くのに使う
    @State private var newNoteID: Note.ID?
    @State private var creating = false
    // 削除の確認を出しているノート
    @State private var deleting: Note?
    @State private var alert: AlertContent?

    struct AlertContent {
        let title: String
        let message: String
    }

    enum Phase {
        case loading
        case loaded
        case failed(String)
    }

    var body: some View {
        // NavigationSplitView をルートにすると、iPhone では1カラムのドリルダウン、
        // iPad ではサイドバー＋詳細に自動で変形する。size class の分岐を自分で
        // 書かなくて済む（Web 版のサイドバー常設レイアウトに近い形が iPad で出る）
        NavigationSplitView {
            content
                .navigationTitle("ノート")
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        Button("新規ノート", systemImage: "square.and.pencil") {
                            Task { await create() }
                        }
                        .disabled(creating)
                    }
                }
        } detail: {
            // iPad は右列に本文（横向きなら一覧と並ぶ）。iPhone では画面が畳まれ、
            // 行をタップすると本文が push される
            if let note = notes.first(where: { $0.id == selectedID }) {
                NoteDetailView(
                    note: note,
                    focusTitle: note.id == newNoteID,
                    onTitleChange: { rename(note.id, to: $0) },
                    onWordAdded: { addWordCount(to: note.id) }
                )
            } else {
                ContentUnavailableView("ノートを選んでください", systemImage: "note.text")
            }
        }
        .task { await load() }
        // 作ったノートから離れたら、次に開いた時はもうタイトルへ飛ばさない
        .onChange(of: selectedID) { _, id in
            if id != newNoteID { newNoteID = nil }
        }
        .alert(
            alert?.title ?? "",
            isPresented: Binding(get: { alert != nil }, set: { if !$0 { alert = nil } }),
            presenting: alert
        ) { _ in
            Button("OK") {}
        } message: { alert in
            Text(alert.message)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch phase {
        case .loading:
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)

        case .failed(let message):
            ContentUnavailableView {
                Label("読み込めませんでした", systemImage: "exclamationmark.triangle")
            } description: {
                Text(message)
            } actions: {
                Button("再試行") { Task { await load() } }
            }

        case .loaded where notes.isEmpty:
            ContentUnavailableView {
                Label("ノートがありません", systemImage: "note.text")
            } description: {
                Text("最初のノートを作りましょう。")
            } actions: {
                Button("ノートを作成") { Task { await create() } }
                    .disabled(creating)
            }

        case .loaded:
            List(notes, selection: $selectedID) { note in
                row(for: note)
                    // ⚠️ role: .destructive にしないこと。押した瞬間に行が消える動きになり、
                    // 確認でキャンセルすると行が戻ってくる（削除は確認の後で行う）
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button("削除", systemImage: "trash") { deleting = note }
                            .tint(.red)
                    }
                    .contextMenu {
                        Button("削除", systemImage: "trash", role: .destructive) { deleting = note }
                    }
                    // 確認は行ごとに付ける。一覧全体に付けると、吹き出しの矢印が
                    // スワイプした行ではなく画面の別の場所を指してしまう
                    .confirmationDialog(
                        "ノートを削除しますか？",
                        isPresented: Binding(
                            get: { deleting?.id == note.id },
                            set: { if !$0 { deleting = nil } }
                        ),
                        titleVisibility: .visible
                    ) {
                        // 単語を残すか一緒に消すかは、Web の削除ダイアログのチェックと同じ選択肢。
                        // 単語が無いノートでは選択肢自体を出さない（迷わせるだけなので）
                        if note.wordCount > 0 {
                            Button("ノートだけ削除（単語は残す）", role: .destructive) {
                                Task { await delete(note, withWords: false) }
                            }
                            Button("単語\(note.wordCount)語も一緒に削除", role: .destructive) {
                                Task { await delete(note, withWords: true) }
                            }
                        } else {
                            Button("削除", role: .destructive) {
                                Task { await delete(note, withWords: false) }
                            }
                        }
                    } message: {
                        Text(note.wordCount > 0
                            ? "このノートの単語\(note.wordCount)語は、単語帳に残すか一緒に削除するかを選べます。この操作は取り消せません。"
                            : "この操作は取り消せません。")
                    }
            }
            .refreshable { await load() }
        }
    }

    private func row(for note: Note) -> some View {
        HStack(spacing: 12) {
            Image(Sticker.forNote(id: note.id, saved: note.sticker).imageName)
                .resizable()
                .scaledToFit()
                // 大きさ・傾きは Web のリスト表示（app/(app)/page.tsx）に合わせた。
                // 影は付けない（Web もリストとピッカーだけ影なし）
                .frame(width: 50, height: 50)
                .rotationEffect(.degrees(16))
            VStack(alignment: .leading, spacing: 4) {
                Text(note.displayTitle).font(.body).lineLimit(1)
                Text("\(note.wordCount) 語 ・ \(note.lastViewedAt.formatted(.relative(presentation: .named)))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    // Web と同じく、空のノートを作ってすぐ開く（タイトルも本文もノートの画面で書く）
    private func create() async {
        guard !creating else { return }   // 連打で何件も作らない
        creating = true
        defer { creating = false }
        do {
            let note = try await APIClient.post(
                "/api/notes",
                body: ["title": "", "body": ""],
                as: Note.self
            )
            // 新規作成は明示的な操作なので、Web と同じく先頭に出す
            notes.insert(note, at: 0)
            phase = .loaded
            newNoteID = note.id
            selectedID = note.id
        } catch APIError.unauthorized {
            auth.handleUnauthorized()
        } catch APIError.rejected(_, let body) {
            alert = AlertContent(
                title: "ノートを作成できませんでした",
                message: QuotaMessage.from(body) ?? "もう一度お試しください。"
            )
        } catch {
            alert = AlertContent(
                title: "ノートを作成できませんでした",
                message: "通信に失敗しました。電波状況を確認してもう一度お試しください。"
            )
            print("note create failed: \(error)")
        }
    }

    // 単語も消す時だけ ?words=delete を付ける。付けなければ単語は単語帳に残る
    // （サーバー側でノート名を単語の補足に書き足す。app/api/notes/[id]/route.ts）
    private func delete(_ note: Note, withWords: Bool) async {
        do {
            try await APIClient.delete(
                "/api/notes/\(note.id)",
                query: withWords ? [URLQueryItem(name: "words", value: "delete")] : []
            )
            notes.removeAll { $0.id == note.id }
            if selectedID == note.id { selectedID = nil }
        } catch APIError.unauthorized {
            auth.handleUnauthorized()
        } catch {
            alert = AlertContent(
                title: "削除できませんでした",
                message: "通信に失敗しました。電波状況を確認してもう一度お試しください。"
            )
            print("note delete failed: \(error)")
        }
    }

    private func rename(_ id: Note.ID, to title: String) {
        guard let index = notes.firstIndex(where: { $0.id == id }) else { return }
        notes[index].title = title
    }

    private func addWordCount(to id: Note.ID) {
        guard let index = notes.firstIndex(where: { $0.id == id }) else { return }
        notes[index].wordCount += 1
    }

    private func load() async {
        do {
            let response = try await APIClient.get("/api/notes", as: NoteListResponse.self)
            notes = response.items
            phase = .loaded
        } catch APIError.unauthorized {
            // トークンが失効している。ログイン画面に戻す
            auth.handleUnauthorized()
        } catch {
            phase = .failed("通信に失敗しました。電波状況を確認してもう一度お試しください。")
            print("note list load failed: \(error)")
        }
    }
}
