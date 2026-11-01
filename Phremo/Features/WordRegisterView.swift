import SwiftUI

// 単語の登録画面。本文で選んだ語を AI で解析し、直してから保存する。
// 流れと文言は Web の単語登録モーダル（notes/[id]/NoteEditor.tsx の WordModal）と同じ：
// 開いたら1回だけ解析 → 登録単語・日本語訳・品詞を直せる → 文脈の補足と使われていた文を添えて保存。
// AI が答えられなかった時も、選んだ語を入れておいて手で書けるようにする。
struct WordRegisterView: View {
    let surface: String
    let sentence: String
    let noteId: String
    let noteTitle: String
    var onSaved: (Word) -> Void = { _ in }

    @Environment(\.dismiss) private var dismiss

    @State private var lemma = ""
    @State private var pos = ""
    @State private var translation = ""
    @State private var note = ""
    // nil＝派生語をまだ取得していない（取得するかは任意）
    @State private var relatedForms: [RelatedForm]?

    @State private var started = false
    @State private var loading = true
    @State private var lookupError: String?
    @State private var contextWarning = false
    @State private var saving = false
    @State private var saveError: String?
    // 重複の判定は全ノート横断（Web と同じ）。取れなくても登録は止めない
    @State private var allWords: [Word] = []

    var body: some View {
        NavigationStack {
            Form {
                notices

                Section("登録単語") {
                    TextField(loading ? "解析中…" : "登録単語", text: $lemma)
                        .font(.title3.bold())
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .onChange(of: lemma) { _, value in
                            if value.utf16.count > WordLimits.lemma { lemma = String(value.prefix(WordLimits.lemma)) }
                        }
                }

                Section("日本語訳") {
                    TextField(loading ? "解析中…" : "日本語訳", text: $translation, axis: .vertical)
                        .onChange(of: translation) { _, value in
                            if value.utf16.count > WordLimits.translation {
                                translation = String(value.prefix(WordLimits.translation))
                            }
                        }
                }

                Section("品詞") {
                    PosPicker(selection: $pos)
                }
                // 品詞を変えたら、前の品詞向けに取得した派生語は捨てる（Web と同じ）
                .onChange(of: pos) { _, _ in relatedForms = nil }

                DerivedFormsSection(lemma: lemma, pos: pos, forms: $relatedForms)

                WordContextSection(note: note, sentence: sentence)

                if let saveError {
                    Section {
                        Text(saveError).font(.footnote).foregroundStyle(.red)
                    }
                }
            }
            .disabled(loading)
            .navigationTitle("単語を登録")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if saving {
                        ProgressView()
                    } else {
                        // 品詞が空だとサーバーが invalid_pos で断るので、選ぶまで押せなくする
                        Button("保存") { Task { await save() } }
                            .disabled(loading || lemma.trimmingCharacters(in: .whitespaces).isEmpty || pos.isEmpty)
                    }
                }
            }
        }
        // ⚠️ `.task` を使わないこと。親が作り直されると通信を打ち切る
        // （NoteDetailView.loadIfNeeded のコメント参照）。解析は開いた時に1回だけ
        .onAppear {
            guard !started else { return }
            started = true
            Task { await lookup() }
            Task { allWords = (try? await APIClient.get("/api/words", as: [Word].self)) ?? [] }
        }
    }

    // MARK: - 解析・重複の知らせ

    @ViewBuilder
    private var notices: some View {
        if loading {
            Section {
                HStack(spacing: 10) {
                    ProgressView()
                    Text("AI解析中…").foregroundStyle(.secondary)
                }
            }
        }
        if let lookupError {
            Section {
                Label(lookupError, systemImage: "exclamationmark.triangle")
                    .font(.subheadline)
                    .foregroundStyle(.orange)
            }
        }
        if contextWarning {
            Section {
                Label("元の文が英語として成立していない可能性があります。そのまま登録もできます。", systemImage: "lightbulb")
                    .font(.subheadline)
                    .foregroundStyle(.orange)
            }
        }
        if let duplicate = exactDuplicate {
            Section {
                Label(
                    "「\(duplicate.lemma)」は同じ品詞（\(duplicate.pos)・訳: \(duplicate.translation)）で登録済みです。そのまま登録すると重複します。",
                    systemImage: "exclamationmark.triangle"
                )
                .font(.subheadline)
                .foregroundStyle(.red)
            }
        } else if let first = sameLemmaWords.first {
            let registered = sameLemmaWords.map { "\($0.pos)（訳: \($0.translation)）" }.joined(separator: "、")
            Section {
                Label("「\(first.lemma)」は\(registered)として登録済みです。品詞が違うのでこのまま登録できます。", systemImage: "lightbulb")
                    .font(.subheadline)
                    .foregroundStyle(.orange)
            }
        }
    }

    private var sameLemmaWords: [Word] {
        let key = lemma.trimmingCharacters(in: .whitespaces).lowercased()
        guard !key.isEmpty else { return [] }
        return allWords.filter { $0.lemma.lowercased() == key }
    }

    // 見出し語と品詞が両方一致＝完全な重複。品詞違い（run: 動詞／名詞）は別の単語として扱う
    private var exactDuplicate: Word? {
        sameLemmaWords.first { $0.pos == pos }
    }

    // MARK: - 通信

    private struct LookupResult: Decodable {
        let lemma: String
        let pos: String
        let translation: String
        let note: String
        // 元の文が英語として成立しているか。false のとき警告を出す（登録は止めない）
        let contextIsValid: Bool?
    }

    private func lookup() async {
        defer { loading = false }
        do {
            let result = try await APIClient.post(
                "/api/lookup-word",
                body: ["surface": surface, "sentence": sentence, "noteTitle": noteTitle],
                as: LookupResult.self
            )
            lemma = result.lemma
            pos = result.pos
            translation = result.translation
            note = result.note
            contextWarning = result.contextIsValid == false
        } catch APIError.rejected(let status, let body) {
            keepSelectedWord()
            lookupError = Self.lookupErrorMessage(status: status, body: body)
        } catch {
            keepSelectedWord()
            lookupError = "AI解析に失敗しました。手動で入力してください。"
            print("lookup-word failed: \(error)")
        }
    }

    // AI が答えを返せなかった場合の保険。選んだ文字列は分かっているので空欄にしない
    private func keepSelectedWord() {
        if lemma.isEmpty { lemma = Self.normalizedSelection(surface) }
    }

    private func save() async {
        saving = true
        saveError = nil
        defer { saving = false }
        var body: [String: Any] = [
            "surface": surface,
            "lemma": lemma.trimmingCharacters(in: .whitespaces),
            "pos": pos,
            "translation": translation,
            "note": note,
            "sourceSentence": sentence,
            "sourceNoteId": noteId,
        ]
        // 取得していなければ送らない（null と [] は「未取得」と「見つからなかった」で意味が違う）
        if let relatedForms { body["relatedForms"] = relatedForms.map(\.payload) }
        do {
            let word = try await APIClient.post("/api/words", body: body, as: Word.self)
            onSaved(word)
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
            print("word save failed: \(error)")
        }
    }

    // MARK: - Web から写した規則

    // AI の失敗理由ごとの文言。Web の WordModal と lib/ai-messages.ts（manualInputHint 付き）の写し
    private static func lookupErrorMessage(status: Int, body: Data) -> String {
        let code = ((try? JSONSerialization.jsonObject(with: body)) as? [String: Any])?["error"] as? String
        let hint = "（単語の手動入力は可能です）"
        switch (status, code) {
        case (422, _):
            return "英語の単語として認識できませんでした。綴りを確認してください。"
        case (429, "daily_limit"):
            return "本日のAI解析の利用上限に達しました。0時を過ぎるとまた利用できます\(hint)。"
        case (429, "global_daily_limit"), (503, "ai_disabled"):
            return "AI解析は現在一時的に利用できません。時間をおいてもう一度お試しください\(hint)。"
        case (429, "rate_limit"):
            return "短い時間にAI解析が集中しました。1分ほど待ってからお試しください\(hint)。"
        case (429, _):
            return "アクセスが混み合っています。少し待ってからお試しください。"
        default:
            return "AI解析に失敗しました。手動で入力してください。"
        }
    }

    // AI が解析できなかったときに「登録単語」へ入れる見出し語の整形。
    // Web の normalizeSelectedWord（notes/[id]/NoteEditor.tsx）の写し：
    // 末尾の句読点を落とし、小文字が一つも無ければ小文字にする（"SEEMS" → "seems"）。
    // 活用を基本形に戻すこと（seems → seem）は AI の仕事なので触らない
    static func normalizedSelection(_ surface: String) -> String {
        var text = surface.trimmingCharacters(in: .whitespacesAndNewlines)
        while let last = text.last, ".,!?;:\"”".contains(last) { text.removeLast() }
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.range(of: "[a-z]", options: .regularExpression) != nil ? text : text.lowercased()
    }
}
