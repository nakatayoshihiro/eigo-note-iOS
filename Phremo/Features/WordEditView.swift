import SwiftUI

// 単語の編集画面。Web の単語パネルの編集モード（words/page.tsx の WordPanel）と同じ欄＝
// 登録単語・日本語訳・品詞・派生語を直せる。文脈の補足と使われていた文は読むだけ。
// 変更が無い間は保存できず、変更したまま閉じようとしたら破棄の確認を挟む（Web と同じ）。
struct WordEditView: View {
    let word: Word
    var onSaved: (Word) -> Void = { _ in }

    @Environment(\.dismiss) private var dismiss

    @State private var lemma: String
    @State private var translation: String
    @State private var pos: String
    @State private var relatedForms: [RelatedForm]?

    @State private var saving = false
    @State private var saveError: String?
    @State private var confirmingDiscard = false

    init(word: Word, onSaved: @escaping (Word) -> Void = { _ in }) {
        self.word = word
        self.onSaved = onSaved
        _lemma = State(initialValue: word.lemma)
        _translation = State(initialValue: word.translation)
        _pos = State(initialValue: word.pos)
        _relatedForms = State(initialValue: word.relatedForms)
    }

    private var dirty: Bool {
        lemma != word.lemma || translation != word.translation || pos != word.pos
            || relatedForms != word.relatedForms
    }

    private var lemmaIsEmpty: Bool {
        lemma.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("登録単語", text: $lemma)
                        .font(.title3.bold())
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .onChange(of: lemma) { _, value in
                            if value.utf16.count > WordLimits.lemma { lemma = String(value.prefix(WordLimits.lemma)) }
                        }
                } header: {
                    Text("登録単語")
                } footer: {
                    if lemmaIsEmpty {
                        Text("登録単語を入力してください").foregroundStyle(.red)
                    }
                }

                Section("日本語訳") {
                    TextField("日本語訳", text: $translation, axis: .vertical)
                        .onChange(of: translation) { _, value in
                            if value.utf16.count > WordLimits.translation {
                                translation = String(value.prefix(WordLimits.translation))
                            }
                        }
                }

                Section("品詞") {
                    PosPicker(selection: $pos)
                }
                // 品詞を変えたら、前の品詞向けの派生語は捨てる（Web と同じ）
                .onChange(of: pos) { _, _ in relatedForms = nil }

                DerivedFormsSection(lemma: lemma, pos: pos, forms: $relatedForms)

                WordContextSection(note: word.note, sentence: word.sourceSentence)

                if let saveError {
                    Section {
                        Text(saveError).font(.footnote).foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("単語の編集")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") {
                        if dirty { confirmingDiscard = true } else { dismiss() }
                    }
                    .confirmationDialog(
                        "変更を破棄しますか？",
                        isPresented: $confirmingDiscard,
                        titleVisibility: .visible
                    ) {
                        Button("変更を破棄", role: .destructive) { dismiss() }
                        Button("編集に戻る", role: .cancel) {}
                    } message: {
                        Text("編集をやめると変更内容は破棄されます。")
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if saving {
                        ProgressView()
                    } else {
                        Button("保存") { Task { await save() } }
                            .disabled(!dirty || lemmaIsEmpty)
                    }
                }
            }
        }
        // 変更したまま下へ引いて閉じると、書いた分が黙って消える
        .interactiveDismissDisabled(dirty)
    }

    private func save() async {
        saving = true
        saveError = nil
        defer { saving = false }
        var body: [String: Any] = [
            "lemma": lemma.trimmingCharacters(in: .whitespaces),
            "translation": translation,
            "pos": pos,
        ]
        // nil は送らない。サーバーは null を「触らない」として扱うので、送っても意味が無い
        if let relatedForms { body["relatedForms"] = relatedForms.map(\.payload) }
        do {
            let updated = try await APIClient.patch("/api/words/\(word.id)", body: body, as: Word.self)
            onSaved(updated)
            dismiss()
        } catch APIError.rejected(_, let body) {
            // 保存できていないので閉じない。入力はそのまま残す
            saveError = WordLimits.validationMessage(from: body)
                ?? QuotaMessage.from(body)
                ?? "保存に失敗しました。もう一度お試しください"
        } catch APIError.unauthorized {
            saveError = "ログインの有効期限が切れました。ログインし直してください"
        } catch {
            saveError = "保存に失敗しました。もう一度お試しください"
            print("word update failed: \(error)")
        }
    }
}
