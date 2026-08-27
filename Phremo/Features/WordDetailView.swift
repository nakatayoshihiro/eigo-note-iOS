import SwiftUI

// 単語の詳細。並びは Web の単語パネル閲覧モード（words/page.tsx）と同じ＝
// 見出し → 日本語訳 → 派生語 → 文脈の補足 → 使われていた文。
// 今は読み取り専用（編集・削除・発音はブラウザ版のみ）。
struct WordDetailView: View {
    let word: Word

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                header

                section("日本語訳") {
                    Text(word.translation)
                        .font(.title3)
                        .textSelection(.enabled)
                }

                if let forms = word.relatedForms, !forms.isEmpty {
                    section("派生語") {
                        VStack(alignment: .leading, spacing: 10) {
                            ForEach(forms, id: \.self) { form in
                                HStack(alignment: .firstTextBaseline, spacing: 8) {
                                    PosBadge(pos: form.pos)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(form.form).font(.body.weight(.semibold))
                                        Text(form.translation)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    }
                }

                if !word.noteLines.isEmpty || !word.sourceSentence.isEmpty {
                    contextCard
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle(word.lemma)
        .navigationBarTitleDisplayMode(.inline)
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
