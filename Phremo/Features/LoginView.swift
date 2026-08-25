import AuthenticationServices
import SwiftUI

struct LoginView: View {
    let auth: AuthStore

    // SwiftUI が用意している ASWebAuthenticationSession のラッパー。
    // 自前で presentationAnchor を実装する必要がない
    @Environment(\.webAuthenticationSession) private var webAuthenticationSession

    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            VStack(spacing: 12) {
                Text("phremo")
                    .font(.system(size: 34, weight: .bold))
                Text("フレーズをメモして覚える、\nあなた専用の英語学習ノート。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            Spacer()

            VStack(spacing: 16) {
                Button {
                    Task { await auth.signIn(using: webAuthenticationSession) }
                } label: {
                    HStack(spacing: 8) {
                        if auth.isSigningIn {
                            ProgressView().tint(.white)
                        }
                        Text(auth.isSigningIn ? "ログイン中…" : "Google でログイン")
                            .font(.headline)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                }
                .buttonStyle(.borderedProminent)
                .disabled(auth.isSigningIn)

                if let message = auth.errorMessage {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 40)
        }
        // iPad やランドスケープで間延びしないよう、内容の幅を抑える
        .frame(maxWidth: 420)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
