import Foundation

// 接続先。Debug ビルド（Xcode から実行）は dev、Release は本番を見る。
// 認証まわりを触るときに本番へ繋いでしまう事故を、ビルド構成で機械的に防ぐ。
enum AppConfig {
    static let baseURL: URL = {
        #if DEBUG
        return URL(string: "https://eigo-note-dev.nakata-dev.workers.dev")!
        #else
        return URL(string: "https://phremo.com")!
        #endif
    }()

    // ログインの戻り先。ASWebAuthenticationSession はこの host + path への遷移を
    // 横取りしてアプリに URL を渡す。サーバー側の app/ios/auth/callback/page.tsx と
    // 対になっているので、変えるときは両方直すこと。
    // ⚠️ この host は Associated Domains（webcredentials:）にも入っている必要がある
    static var callbackHost: String { baseURL.host()! }
    static let callbackPath = "/ios/auth/callback"

    // ログイン開始 URL。サーバー側の専用ルートで、ブラウザを Google へ
    // リダイレクトする。
    //
    // better-auth の /api/auth/sign-in/social を直接叩かないのは、あれが POST 専用な
    // うえに state 用の Cookie を発行するため。アプリから POST するとその Cookie が
    // アプリ側に入ってしまい、実際にログインするブラウザに届かず照合に失敗する。
    // ログインの開始をブラウザ自身にやらせる必要がある（app/api/ios/login のコメント参照）。
    static var signInURL: URL {
        baseURL.appending(path: "/api/ios/login")
    }
}
