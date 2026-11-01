import SwiftUI

// 単語の詳細。並びは Web の単語パネル閲覧モード（words/page.tsx）と同じ＝
// 見出し → 日本語訳 → 派生語 → 文脈の補足 → 使われていた文 → 削除。
// 右上の「編集」で編集画面（WordEditView）を開く。発音はまだブラウザ版のみ。
struct WordDetailView: View {
    let word: Word
    /// 書き換えた（編集・派生語の取得）。一覧の単語を差し替える
    var onUpdated: (Word) -> Void = { _ in }
    /// 削除した。一覧から外す
    var onDeleted: () -> Void = {}

    @State private var editing = false
    @State private var confirmingDelete = false
    @State private var deleting = false
    @State private var generating = false
    @State private var actionError: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                header

                section("日本語訳") {
                    Text(word.translation)
                        .font(.title3)
                        .textSelection(.enabled)
                }

                derivedForms

                if !word.noteLines.isEmpty || !word.sourceSentence.isEmpty {
                    contextCard
                }

                if let actionError {
                    Text(actionError).font(.footnote).foregroundStyle(.red)
                }

                // 削除は閲覧の最下部（Web の単語パネルと同じ位置）
                Button(deleting ? "削除中…" : "この単語を削除", role: .destructive) {
                    confirmingDelete = true
                }
                .font(.body.bold())
                .disabled(deleting)
                .frame(maxWidth: .infinity)
                .padding(.top, 8)
                .confirmationDialog(
                    "「\(word.lemma)」を削除しますか？",
                    isPresented: $confirmingDelete,
                    titleVisibility: .visible
                ) {
                    Button("削除", role: .destructive) { Task { await delete() } }
                } message: {
                    Text("この操作は取り消せません。")
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle(word.lemma)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("編集") { editing = true }
            }
        }
        .sheet(isPresented: $editing) {
            WordEditView(word: word, onSaved: onUpdated)
        }
        // 別の単語に切り替わったら（iPad の右カラム）、前の単語の失敗表示は持ち越さない
        .onChange(of: word.id) { _, _ in actionError = nil }
    }

    // 派生語。未取得なら閲覧のままここから取得し、そのまま保存する（Web と同じ。
    // 編集画面に入らずに済む）。派生語を持たない品詞では、取得済みのものがある時だけ出す
    @ViewBuilder
    private var derivedForms: some View {
        let forms = word.relatedForms
        if !(forms ?? []).isEmpty || Pos.hasDerivatives(word.pos) {
            section("派生語") {
                if let forms, !forms.isEmpty {
                    DerivedFormsList(forms: forms)
                } else if forms != nil {
                    Text("派生語は見つかりませんでした").foregroundStyle(.secondary)
                } else if generating {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("派生語を取得中…").foregroundStyle(.secondary)
                    }
                } else {
                    Button("派生語を登録") { Task { await generateDerivedForms() } }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                }
            }
        }
    }

    private func generateDerivedForms() async {
        generating = true
        actionError = nil
        defer { generating = false }
        switch await DerivedForms.fetch(lemma: word.lemma, pos: word.pos) {
        case .success(let forms):
            do {
                let updated = try await APIClient.patch(
                    "/api/words/\(word.id)",
                    body: ["relatedForms": forms.map(\.payload)],
                    as: Word.self
                )
                onUpdated(updated)
            } catch {
                actionError = "派生語を保存できませんでした。もう一度お試しください"
                print("related forms save failed: \(error)")
            }
        case .failure(let failure):
            actionError = failure.message
        }
    }

    private func delete() async {
        deleting = true
        actionError = nil
        defer { deleting = false }
        do {
            try await APIClient.delete("/api/words/\(word.id)")
            onDeleted()
        } catch {
            actionError = "削除に失敗しました。もう一度お試しください"
            print("word delete failed: \(error)")
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            PosBadge(pos: word.pos)
            Text(word.lemma)
                .font(.largeTitle.bold())
                .textSelection(.enabled)
            Text("登録日 \(word.createdAt.formatted(date: .abbreviated, time: .omitted))")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // Web と同じく補足と出典文はひとまとまりの薄いカードに入れる
    private var contextCard: some View {
        VStack(alignment: .leading, spacing: 20) {
            if !word.noteLines.isEmpty {
                labeled("文脈の補足", systemImage: "lightbulb") {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(Array(word.noteLines.enumerated()), id: \.offset) { _, line in
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Text("・")
                                Text(line)
                            }
                        }
                    }
                }
            }
            if !word.sourceSentence.isEmpty {
                labeled("使われていた文", systemImage: "quote.opening") {
                    Text(word.sourceSentence).textSelection(.enabled)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16))
    }

    private func section(_ label: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            content()
        }
    }

    private func labeled(
        _ label: String,
        systemImage: String,
        @ViewBuilder content: () -> some View
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(label, systemImage: systemImage)
                .font(.caption)
                .foregroundStyle(.secondary)
            content()
        }
    }
}
