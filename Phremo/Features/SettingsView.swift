import SwiftUI

// 設定。中身は Web の /settings と同じ4つ＝アカウント情報／本日のAI利用／退会／規約類。
//
// ⚠️ 退会をアプリの中で完結させることは App Store の審査要件（アカウントを作れる
// アプリは、アプリ内で削除もできる必要がある）。Web に飛ばす形は通らない。
struct SettingsView: View {
    let auth: AuthStore

    @State private var user: AccountUser?
    @State private var usage: AiUsage?
    @State private var confirmingDelete = false

    var body: some View {
        NavigationStack {
            List {
                accountSection
                aiUsageSection
                deleteSection
                legalSection
            }
            .navigationTitle("設定")
        }
        .task { await load() }
        .sheet(isPresented: $confirmingDelete) {
            DeleteAccountSheet(auth: auth, email: user?.email ?? "")
        }
    }

    private var accountSection: some View {
        Section("アカウント") {
            HStack(spacing: 12) {
                Text(user?.initial ?? "")
                    .font(.headline)
                    // ⚠️ 地の色を固定しているので文字色も固定する。既定のままだと
                    // ダークモードで白文字になり、薄い地の上で読めなくなる
                    .foregroundStyle(Color(hex: 0x2f2f2f))
                    .frame(width: 48, height: 48)
                    .background(Color(hex: 0xf0ece4), in: Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text(user?.name ?? "読み込み中…").font(.body.weight(.semibold))
                    Text(user?.email ?? "").font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 4)

            Button("ログアウト") { auth.signOut() }
        }
    }

    private var aiUsageSection: some View {
        Section("本日のAI利用") {
            VStack(alignment: .leading, spacing: 12) {
                // 通常は説明文、使えない状態ではその場所がそのまま赤い理由に変わる
                // （説明と理由を並べない）。Web の設定画面と同じ扱い
                if let message = usage?.limitMessage {
                    Text(message).font(.footnote).foregroundStyle(.red)
                } else {
                    Text("単語のAI解析には1日の利用上限があります。毎日0時にリセットされます。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                HStack(spacing: 12) {
                    ProgressView(value: Double(usage?.usedPercent ?? 0), total: 100)
                        .tint((usage?.usedPercent ?? 0) >= 90 ? .red : .primary)
                    Text(usage.map { "\($0.usedPercent)% 使用済み" } ?? "読み込み中…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize()
                }
            }
            .padding(.vertical, 4)
        }
    }

    private var deleteSection: some View {
        Section {
            Button("アカウントを削除", role: .destructive) { confirmingDelete = true }
                .disabled(user == nil)
        } footer: {
            Text("アカウントと、作成したすべてのノート・単語が完全に削除されます。この操作は取り消せません。")
        }
    }

    private var legalSection: some View {
        Section {
            Link("利用規約", destination: AppConfig.baseURL.appending(path: "/terms"))
            Link("プライバシーポリシー", destination: AppConfig.baseURL.appending(path: "/privacy"))
        }
    }

    private func load() async {
        // 片方が落ちても、もう片方は出す。設定画面が丸ごと空になるのを避ける。
        // ⚠️ async let で並行にしない。モデルの Decodable 適合が MainActor 隔離なので
        // （このプロジェクトの既定）、非隔離の文脈からは使えない
        user = try? await APIClient.get("/api/auth/get-session", as: SessionResponse.self).user
        usage = try? await APIClient.get("/api/ai-usage", as: AiUsage.self)
    }
}

// 退会の確認。Web と同じく、自分のメールアドレスを打ってからでないと実行できない
private struct DeleteAccountSheet: View {
    let auth: AuthStore
    let email: String

    @Environment(\.dismiss) private var dismiss
    @State private var typed = ""
    @State private var deleting = false
    @State private var error: String?

    private var matches: Bool {
        typed.trimmingCharacters(in: .whitespaces).lowercased() == email.lowercased()
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("この操作は取り消せません。アカウントと、作成したすべてのノート・単語が完全に削除されます。")
                        .font(.footnote)
                } header: {
                    Text("アカウントの削除（退会）")
                }

                Section {
                    TextField(email, text: $typed)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.emailAddress)
                } footer: {
                    Text("確認のため、ご自身のメールアドレスを入力してください。")
                }

                if let error {
                    Section { Text(error).font(.footnote).foregroundStyle(.red) }
                }

                Section {
                    Button(deleting ? "削除中…" : "アカウントを削除", role: .destructive) {
                        Task { await delete() }
                    }
                    .disabled(!matches || deleting)
                }
            }
            .navigationTitle("退会")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { dismiss() }.disabled(deleting)
                }
            }
        }
    }

    private func delete() async {
        deleting = true
        error = nil
        do {
            try await APIClient.post("/api/auth/delete-user")
            // サーバー側でセッションごと消えている。手元のトークンも捨てて入口へ戻す
            auth.signOut()
            dismiss()
        } catch APIError.api(_, let code) where code == "SESSION_EXPIRED" {
            // Google ログインのユーザーはパスワードを持たないので、better-auth は
            // 「最後のログインから24時間以内」であることだけを条件にしている
            error = "前回のログインから時間が経っているため削除できませんでした。一度ログアウトして入り直してから、もう一度お試しください。"
            deleting = false
        } catch {
            self.error = "削除に失敗しました。時間をおいてもう一度お試しください。"
            deleting = false
        }
    }
}
