import SwiftUI

// ログイン状態で画面を出し分けるだけの入口。
struct RootView: View {
    let auth: AuthStore

    var body: some View {
        Group {
            switch auth.state {
            case .restoring:
                // Keychain を読むだけなので一瞬。ここでロゴを出すと逆にちらつく
                ProgressView()
            case .signedOut:
                LoginView(auth: auth)
            case .signedIn:
                NoteListView(auth: auth)
            }
        }
        .task { auth.restore() }
    }
}
