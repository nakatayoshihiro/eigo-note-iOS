import SwiftUI

// ノート1件の表示。読み取り専用（編集はブラウザ版）。
// 本文の読み替えは Core/NoteBody.swift。
struct NoteDetailView: View {
    let note: Note

    private var blocks: [NoteBlock] { NoteBody.parse(html: note.body) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header
                ForEach(blocks) { block in
                    row(for: block)
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        // タイトルは本文の先頭に大きく出しているので、バーには入れない
        // （入れると同じ名前が上下に二重に並ぶ）
        .navigationBarTitleDisplayMode(.inline)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                Text(note.displayTitle)
                    .font(.system(size: 28, weight: .bold))
                    .textSelection(.enabled)
                Spacer(minLength: 12)
                Image(Sticker.forNote(id: note.id, saved: note.sticker).imageName)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 48, height: 48)
                    .rotationEffect(.degrees(12))
            }
            Text("\(note.wordCount) 語 ・ \(note.lastViewedAt.formatted(.relative(presentation: .named)))")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.bottom, 16)
    }

    @ViewBuilder
    private func row(for block: NoteBlock) -> some View {
        switch block.kind {
        case .rule:
            Divider().padding(.vertical, 12)

        case .heading:
            Text(block.text)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 16)
                .padding(.bottom, 6)

        case .continuation(let depth):
            Text(block.text)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, CGFloat(depth) * 20 + 20)
                .padding(.vertical, 3)

        case .paragraph:
            Text(block.text)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                // 空段落は Web でも1行ぶんの間隔になる。高さを持たせないと間隔が消える
                .frame(minHeight: block.text.characters.isEmpty ? 12 : 0)
                .padding(.vertical, 4)

        case .quote:
            HStack(spacing: 12) {
                Rectangle().fill(.secondary.opacity(0.4)).frame(width: 3)
                Text(block.text).foregroundStyle(.secondary).textSelection(.enabled)
            }
            .padding(.vertical, 4)

        case .bullet(let depth):
            marker("・", depth: depth, text: block.text)

        case .ordered(let number, let depth):
            marker("\(number).", depth: depth, text: block.text)

        case .task(let done, let depth):
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: done ? "checkmark.square.fill" : "square")
                    .foregroundStyle(done ? Color.accentColor : .secondary)
                Text(block.text)
                    .strikethrough(done, color: .secondary)
                    .foregroundStyle(done ? .secondary : .primary)
                    .textSelection(.enabled)
            }
            .padding(.leading, CGFloat(depth) * 20)
            .padding(.vertical, 3)
        }
    }

    private func marker(_ symbol: String, depth: Int, text: AttributedString) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(symbol).foregroundStyle(.secondary).monospacedDigit()
            Text(text).textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.leading, CGFloat(depth) * 20)
        .padding(.vertical, 3)
    }
}
