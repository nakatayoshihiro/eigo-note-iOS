import AuthenticationServices
import Foundation
import SwiftUI

// ログイン状態。アプリ全体で1つ持ち、画面はこれを見て出し分ける。
@MainActor
@Observable
final class AuthStore {
    enum State {
        case restoring   // 起動直後、Keychain を見に行っている最中
        case signedOut
        case signedIn
    }

    private(set) var state: State = .restoring
    private(set) var errorMessage: String?
    private(set) var isSigningIn = false

    // 起動時に Keychain を見るだけ。ここではサーバーに問い合わせない。
    // 「トークンがあるのに実は失効している」場合は最初の API 呼び出しが 401 を
    // 返すので、そこでサインアウトに倒す（起動を1往復ぶん速くするため）
    func restore() {
        state = SessionStore.read() == nil ? .signedOut : .signedIn
    }

    // ログイン。SwiftUI の webAuthenticationSession を画面から渡してもらう。
    //
    // 流れは lib/auth.ts と app/api/ios/handoff/route.ts のコメントを参照。要点は
    // 「ブラウザ内で完結する Google ログインの結果を、使い捨てトークン経由で
    // アプリに引き渡す」こと。
    func signIn(using webAuth: WebAuthenticationSession) async {
        guard !isSigningIn else { return }
        isSigningIn = true
        errorMessage = nil
        defer { isSigningIn = false }

        do {
            // ブラウザが /ios/auth/callback に到達した時点で iOS が横取りし、
            // その URL がここに返ってくる（Associated Domains の webcredentials で
            // ドメイン所有が検証される）
            let callbackURL = try await webAuth.authenticate(
                using: AppConfig.signInURL,
                callback: .https(host: AppConfig.callbackHost, path: AppConfig.callbackPath),
                additionalHeaderFields: [:]
            )

            let items = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false)?.queryItems
            if let error = items?.first(where: { $0.name == "error" })?.value {
                throw SignInError.server(error)
            }
            guard let oneTimeToken = items?.first(where: { $0.name == "token" })?.value else {
                throw SignInError.missingToken
            }

            let sessionToken = try await exchange(oneTimeToken: oneTimeToken)
            SessionStore.save(sessionToken)
            state = .signedIn
        } catch is CancellationError {
            // ユーザーが自分で閉じた場合はエラー表示しない
        } catch let error as ASWebAuthenticationSessionError where error.code == .canceledLogin {
            // 同上（キャンセルは失敗ではない）
        } catch {
            errorMessage = "ログインできませんでした。通信環境を確認して、もう一度お試しください。"
            print("signIn failed: \(error)")
        }
    }

    // 使い捨てトークンを本物のセッショントークンに引き換える。
    // 本体はレスポンスボディではなく set-auth-token ヘッダーで返ってくる
    // （better-auth の bearer プラグインが付ける）。
    private func exchange(oneTimeToken: String) async throws -> String {
        var request = URLRequest(
            url: AppConfig.baseURL.appending(path: "/api/auth/one-time-token/verify")
        )
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["token": oneTimeToken])

        let (_, response) = try await APIClient.session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw SignInError.missingToken }
        guard http.statusCode == 200 else { throw SignInError.exchangeFailed(status: http.statusCode) }
        guard let token = http.value(forHTTPHeaderField: "set-auth-token") else {
            throw SignInError.missingToken
        }
        return token
    }

    func signOut() {
        SessionStore.clear()
        state = .signedOut
        errorMessage = nil
    }

    // API が 401 を返したとき用。トークンが失効しているのでログイン画面に戻す
    func handleUnauthorized() {
        guard state == .signedIn else { return }
        signOut()
    }

    enum SignInError: Error {
        case missingToken
        case exchangeFailed(status: Int)
        case server(String)
    }
}

extension AuthStore.State: Equatable {}
