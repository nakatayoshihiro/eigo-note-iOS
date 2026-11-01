import SwiftUI

// 単語の登録画面（WordRegisterView）と編集画面（WordEditView）で共有する部品。
// Web の WordPanelFields.tsx / DerivedFormsSection.tsx に当たる。

// MARK: - 品詞の選択

struct PosPicker: View {
    @Binding var selection: String

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Pos.all, id: \.self) { item in
                    Button { selection = item } label: {
                        PosBadge(pos: item)
                            .overlay(
                                Capsule().strokeBorder(Pos.color(for: item).text, lineWidth: selection == item ? 1.5 : 0)
                            )
                            .opacity(selection.isEmpty || selection == item ? 1 : 0.4)
                            .padding(.vertical, 4)
                    }
                    // Form の行の中で、ボタンごとに別々に押せるようにする
                    .buttonStyle(.borderless)
                    .accessibilityAddTraits(selection == item ? .isSelected : [])
                }
            }
        }
    }
}

// MARK: - 派生語

enum DerivedForms {
    private struct Response: Decodable {
        let forms: [RelatedForm]
    }

    /// 派生語を AI に聞く。失敗した時は画面に出す文言を返す。
    /// 文言は Web の DerivedFormsSection と lib/ai-messages.ts（手入力の案内なし）の写し
    static func fetch(lemma: String, pos: String) async -> Result<[RelatedForm], DerivedFormsError> {
        do {
            let response = try await APIClient.post(
                "/api/lookup-derivatives",
                body: ["lemma": lemma.trimmingCharacters(in: .whitespaces), "pos": pos],
                as: Response.self
            )
            return .success(response.forms)
        } catch APIError.rejected(_, let body) {
            let code = ((try? JSONSerialization.jsonObject(with: body)) as? [String: Any])?["error"] as? String
            switch code {
            case "daily_limit":
                return .failure(.init(message: "本日のAI解析の利用上限に達しました。0時を過ぎるとまた利用できます。"))
            case "rate_limit":
                return .failure(.init(message: "短い時間にAI解析が集中しました。1分ほど待ってからお試しください。"))
            case "global_daily_limit", "ai_disabled":
                return .failure(.init(message: "AI解析は現在一時的に利用できません。時間をおいてもう一度お試しください。"))
            default:
                return .failure(.generic)
            }
        } catch {
            print("lookup-derivatives failed: \(error)")
            return .failure(.generic)
        }
    }
}

struct DerivedFormsError: Error {
    let message: String
    static let generic = DerivedFormsError(message: "派生語の取得に失敗しました。時間をおいてもう一度お試しください。")
}

/// 取得した派生語の並び。品詞を色分けした「品詞 : 英語形」（Web の DerivedFormsSection と同じ）
struct DerivedFormsList: View {
    let forms: [RelatedForm]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(forms, id: \.self) { form in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    PosBadge(pos: form.pos)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(form.form).font(.body.weight(.semibold))
                        if !form.translation.isEmpty {
                            Text(form.translation).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }
}

/// フォームの「派生語」欄。未取得なら取得ボタン、取得後は一覧と「再生成」。
/// 派生語を持たない品詞（前置詞・接続詞・句動詞）と、見出し語が空の間は出さない。
/// `forms` は nil＝まだ取得していない／[]＝取得したが見つからなかった、の2状態（Word.relatedForms と同じ）
struct DerivedFormsSection: View {
    let lemma: String
    let pos: String
    @Binding var forms: [RelatedForm]?

    @State private var busy = false
    @State private var error: String?

    var body: some View {
        if Pos.hasDerivatives(pos), !lemma.trimmingCharacters(in: .whitespaces).isEmpty {
            Section {
                if busy {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("派生語を取得中…").foregroundStyle(.secondary)
                    }
                } else if let forms {
                    if forms.isEmpty {
                        Text("派生語は見つかりませんでした").foregroundStyle(.secondary)
                    } else {
                        DerivedFormsList(forms: forms)
                    }
                } else {
                    Button("派生語を登録") { Task { await generate() } }
                }
                if let error {
                    Text(error).font(.footnote).foregroundStyle(.red)
                }
            } header: {
                HStack {
                    Text("派生語")
                    Spacer()
                    if forms != nil && !busy {
                        Button("再生成", systemImage: "arrow.clockwise") { Task { await generate() } }
                            .font(.caption)
                            .textCase(nil)
                    }
                }
            }
        }
    }

    private func generate() async {
        busy = true
        error = nil
        defer { busy = false }
        switch await DerivedForms.fetch(lemma: lemma, pos: pos) {
        case .success(let result): forms = result
        case .failure(let failure): error = failure.message
        }
    }
}

// MARK: - 文脈

/// 文脈の補足（AI が書いた説明）と、使われていた文。どちらも読むだけ（Web の ContextCard と同じ）
struct WordContextSection: View {
    let note: String
    let sentence: String

    // 補足は「ニュアンス＋形の説明」を改行で連結した文字列（Word.noteLines と同じ割り方）
    private var noteLines: [String] {
        note.split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    var body: some View {
        if !noteLines.isEmpty || !sentence.isEmpty {
            Section("文脈") {
                if !noteLines.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(Array(noteLines.enumerated()), id: \.offset) { _, line in
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Text("・")
                                Text(line)
                            }
                        }
                    }
                    .font(.subheadline)
                }
                if !sentence.isEmpty {
                    Label {
                        Text(sentence)
                    } icon: {
                        Image(systemName: "quote.opening")
                    }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                }
            }
        }
    }
}
