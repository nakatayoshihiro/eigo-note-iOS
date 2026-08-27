import SwiftUI

struct WordListView: View {
    let auth: AuthStore

    @State private var words: [Word] = []
    @State private var phase: Phase = .loading
    @State private var query = ""
    @State private var selectedPos: String?
    // 選択は Word ではなく id で持つ。引っ張って更新したあとも選択が生き残る
    @State private var selectedID: Word.ID?

    enum Phase {
        case loading
        case loaded
        case failed(String)
    }

    // 絞り込みは Web（words/page.tsx）と同じ＝品詞 ＋ 検索。
    // ノートでの絞り込みはノート名が /api/words に載っていないので今回は入れない
    private var filtered: [Word] {
        words.filter { word in
            (selectedPos == nil || word.pos == selectedPos) && word.matches(query)
        }
    }

    private var isFiltering: Bool {
        selectedPos != nil || !query.isEmpty
    }

    var body: some View {
        NavigationSplitView {
            content
                .navigationTitle("単語帳")
                .searchable(text: $query, prompt: "単語・訳・派生語")
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) { posMenu }
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

    private var posMenu: some View {
        Menu {
            Picker("品詞", selection: $selectedPos) {
                Text("すべての品詞").tag(String?.none)
                ForEach(Pos.all, id: \.self) { pos in
                    Text(pos).tag(String?.some(pos))
                }
            }
        } label: {
            Label(
                selectedPos ?? "品詞",
                systemImage: selectedPos == nil
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
            if isFiltering {
                ContentUnavailableView.search
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
            phase = .loaded
        } catch APIError.unauthorized {
            auth.handleUnauthorized()
        } catch {
            phase = .failed("通信に失敗しました。電波状況を確認してもう一度お試しください。")
            print("word list load failed: \(error)")
        }
    }
}
