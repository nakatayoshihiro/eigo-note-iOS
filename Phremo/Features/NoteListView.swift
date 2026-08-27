import SwiftUI

struct NoteListView: View {
    let auth: AuthStore

    @State private var notes: [Note] = []
    @State private var phase: Phase = .loading
    // 選択はノートそのものではなく id で持つ。引っ張って更新しても選択が生き残る
    @State private var selectedID: Note.ID?

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
        } detail: {
            // iPad は右列に本文（横向きなら一覧と並ぶ）。iPhone では画面が畳まれ、
            // 行をタップすると本文が push される
            if let note = notes.first(where: { $0.id == selectedID }) {
                NoteDetailView(note: note)
            } else {
                ContentUnavailableView("ノートを選んでください", systemImage: "note.text")
            }
        }
        .task { await load() }
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
            ContentUnavailableView(
                "ノートがありません",
                systemImage: "note.text",
                description: Text("ブラウザ版でノートを作ると、ここに表示されます。")
            )

        case .loaded:
            List(notes, selection: $selectedID) { note in
                row(for: note)
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
