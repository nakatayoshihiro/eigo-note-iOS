import SwiftUI

struct WordListView: View {
    let auth: AuthStore

    @State private var words: [Word] = []
    // 絞り込みの選択肢を作るためだけに引く。単語には sourceNoteId しか入っていないので、
    // ノート名を出すには一覧が要る
    @State private var notes: [Note] = []
    @State private var phase: Phase = .loading
    @State private var query = ""
    @State private var selectedPos: String?
    @State private var selectedNoteID: String?
    // 選択は Word ではなく id で持つ。引っ張って更新したあとも選択が生き残る
    @State private var selectedID: Word.ID?

    enum Phase {
        case loading
        case loaded
        case failed(String)
    }

    // 絞り込みは Web（words/page.tsx）と同じ＝ノート ＋ 品詞 ＋ 検索
    private var filtered: [Word] {
        words.filter { word in
            (selectedNoteID == nil || word.sourceNoteId == selectedNoteID)
                && (selectedPos == nil || word.pos == selectedPos)
                && word.matches(query)
        }
    }

    private var isFiltering: Bool {
        selectedNoteID != nil || selectedPos != nil || !query.isEmpty
    }

    var body: some View {
        NavigationSplitView {
            content
                .navigationTitle("単語帳")
                // 何で絞り込んでいるかを画面に出す。アイコンの塗りつぶしだけだと、
                // 絞り込んだまま忘れて「単語が減った」と見える
                .navigationSubtitle(filterSummary)
                .searchable(text: $query, prompt: "単語・訳・派生語")
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) { filterMenu }
                }
        } detail: {
            // iPad は右カラムに詳細（Web の単語パネルと同じ位置関係）。
            // iPhone では画面が畳まれ、行をタップすると詳細が push される
            if let word = words.first(where: { $0.id == selectedID }) {
                WordDetailView(word: word)
            } else {
                ContentUnavailableView("単語を選んでください", systemImage: "character.book.closed")
            }
        }
        .task { await load() }
    }

    // 絞り込みの要約。何も掛かっていなければ空（サブタイトルは出ない）
    private var filterSummary: String {
        [notes.first { $0.id == selectedNoteID }?.displayTitle, selectedPos]
            .compactMap { $0 }
            .joined(separator: " ・ ")
    }

    private var filterMenu: some View {
        Menu {
            // ノートは削除されると単語側の sourceNoteId が null になる（Web と同じ挙動）。
            // 消えたノートで絞り込む手段は持たせない＝選択肢は今あるノートだけ
            // 入れ子のメニューにはならず、その場に並ぶ。見出しを付けないと
            // ノートの一覧と品詞の一覧が地続きに見える
            Section("ノート") {
                Picker("ノート", selection: $selectedNoteID) {
                    Text("すべてのノート").tag(String?.none)
                    ForEach(notes) { note in
                        Text(note.displayTitle).tag(String?.some(note.id))
                    }
                }
            }
            Section("品詞") {
                Picker("品詞", selection: $selectedPos) {
                    Text("すべての品詞").tag(String?.none)
                    ForEach(Pos.all, id: \.self) { pos in
                        Text(pos).tag(String?.some(pos))
                    }
                }
            }
            if selectedNoteID != nil || selectedPos != nil {
                Section {
                    Button("絞り込みを解除", systemImage: "xmark") {
                        selectedNoteID = nil
                        selectedPos = nil
                    }
                }
            }
        } label: {
            Label(
                "絞り込み",
                systemImage: selectedNoteID == nil && selectedPos == nil
                    ? "line.3.horizontal.decrease.circle"
                    : "line.3.horizontal.decrease.circle.fill"
            )
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

        case .loaded where filtered.isEmpty:
            // 「1件も無い」と「絞り込んだ結果0件」は原因が違うので文言を分ける
            if !query.isEmpty {
                ContentUnavailableView.search
            } else if isFiltering {
                ContentUnavailableView(
                    "条件に一致する単語がありません",
                    systemImage: "line.3.horizontal.decrease.circle",
                    description: Text("絞り込みを変えてみてください。")
                )
            } else {
                ContentUnavailableView(
                    "単語がありません",
                    systemImage: "character.book.closed",
                    description: Text("ノートで単語を登録すると、ここに表示されます。")
                )
            }

        case .loaded:
            List(filtered, selection: $selectedID) { word in
                row(for: word)
            }
            .refreshable { await load() }
        }
    }

    private func row(for word: Word) -> some View {
        HStack(spacing: 12) {
            PosBadge(pos: word.pos)
            VStack(alignment: .leading, spacing: 4) {
                Text(word.lemma).font(.body.weight(.semibold)).lineLimit(1)
                Text(word.translation).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
        }
        .padding(.vertical, 4)
    }

    private func load() async {
        do {
            // サーバー側は createdAt の降順で返す（新しい単語が上）
            words = try await APIClient.get("/api/words", as: [Word].self)
            // ノート一覧は絞り込みの選択肢用。取れなくても単語は出す
            notes = (try? await APIClient.get("/api/notes", as: NoteListResponse.self))?.items ?? []
            phase = .loaded
        } catch APIError.unauthorized {
            auth.handleUnauthorized()
        } catch {
            phase = .failed("通信に失敗しました。電波状況を確認してもう一度お試しください。")
            print("word list load failed: \(error)")
        }
    }
}
