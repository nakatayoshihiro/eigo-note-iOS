import Foundation

enum APIError: Error {
    case unauthorized          // 401。トークンが無効か期限切れ
    case server(status: Int)
    // better-auth はエラーの理由を本文の code で返す（例: SESSION_EXPIRED）。
    // 状態によって出し分ける必要があるので、ステータスだけでなく code も持つ
    case api(status: Int, code: String?)
    case invalidResponse
}

// サーバーとのやり取り。全リクエストに Authorization: Bearer を付ける。
enum APIClient {
    // Cookie を明示的に無効にした専用セッションを使う。
    //
    // 既定の URLSession は Set-Cookie を勝手に保存して次から送ってしまう。
    // 一度でも Cookie で通ってしまうと「bearer が壊れていても動いてしまう」状態に
    // なり、本番で初回起動時だけ落ちる、という形で表面化する。ここで塞いでおけば
    // アプリは常に bearer だけで認証していることが保証される。
    static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.httpCookieAcceptPolicy = .never
        config.httpShouldSetCookies = false
        config.httpCookieStorage = nil
        return URLSession(configuration: config)
    }()

    // Prisma は DateTime を "2026-08-25T16:12:01.123Z" のようにミリ秒付きで返す。
    // JSONDecoder の .iso8601 は小数秒を受け付けず落ちるので、自前で組む。
    //
    // ISO8601DateFormatter ではなく Date.ISO8601FormatStyle を使うのは、前者が
    // class（非 Sendable）で、Swift 6 だと @Sendable クロージャに閉じ込められない
    // ため。FormatStyle は値型なので安全に持ち回せる。
    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        let withFraction = Date.ISO8601FormatStyle(includingFractionalSeconds: true)
        let withoutFraction = Date.ISO8601FormatStyle(includingFractionalSeconds: false)

        decoder.dateDecodingStrategy = .custom { decoder in
            let text = try decoder.singleValueContainer().decode(String.self)
            if let date = try? withFraction.parse(text) { return date }
            // 小数秒が無い値も来うる（ミリ秒がちょうど 0 のとき等）
            if let date = try? withoutFraction.parse(text) { return date }
            throw DecodingError.dataCorrupted(
                .init(codingPath: decoder.codingPath, debugDescription: "日付として読めません: \(text)")
            )
        }
        return decoder
    }()

    // ⚠️ クエリは path に混ぜず query で渡すこと。URL.appending(path:) は渡された文字列を
    // まるごと1つのパス要素として扱うので、"?" が %3F にエスケープされる
    // （"/api/words?noteId=x" → "/api/words%3FnoteId=x"）。404 になるだけで例外は出ず、
    // 「取得できないが画面は動く」という気づきにくい壊れ方をする
    // 本文を送らない POST（退会など）。返ってきた本文は使わないので捨てる
    static func post(_ path: String, body: [String: Any] = [:]) async throws {
        guard let token = SessionStore.read() else { throw APIError.unauthorized }

        var request = URLRequest(url: AppConfig.baseURL.appending(path: path))
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw APIError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            let code = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            throw APIError.api(status: http.statusCode, code: code?["code"] as? String)
        }
    }

    // 中身を読まずに JSON をそのまま受け取る。エディタへ渡す本文と単語に使う。
    //
    // ⚠️ Swift の型にしないのは、（1）長い本文だと変換だけでメインスレッドが止まる
    // （2）Web 側が付けた未知の属性を落としてしまう、の2つの理由から。
    // アプリは本文の中身を解釈しないので、文字列のまま WebView へ渡せばよい。
    static func getRawJSON(_ path: String, query: [URLQueryItem] = []) async throws -> String {
        guard let token = SessionStore.read() else { throw APIError.unauthorized }

        var components = URLComponents(
            url: AppConfig.baseURL.appending(path: path),
            resolvingAgainstBaseURL: false
        )
        if !query.isEmpty { components?.queryItems = query }
        guard let url = components?.url else { throw APIError.invalidResponse }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw APIError.invalidResponse }
        if http.statusCode == 401 { throw APIError.unauthorized }
        guard (200..<300).contains(http.statusCode) else {
            throw APIError.server(status: http.statusCode)
        }
        guard let text = String(data: data, encoding: .utf8) else { throw APIError.invalidResponse }
        return text
    }

    /// 応答の JSON から、鍵ひとつぶんを**文字列のまま**取り出す。
    /// ノート1件の応答から本文（bodyJson）だけを抜くのに使う
    static func field(_ name: String, of json: String) -> String? {
        guard let data = json.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let value = object[name], !(value is NSNull),
              let out = try? JSONSerialization.data(withJSONObject: value, options: .fragmentsAllowed)
        else { return nil }
        return String(data: out, encoding: .utf8)
    }

    // 本文の保存。JSON を組み立て直さず、渡された文字列をそのまま本文として送る。
    //
    // ⚠️ ここで `[String: Any]` を経由しないこと。5.7万字のノートだと、その変換だけで
    // メインスレッドが数百 ms 止まる（実機で確認済み。2026-09-02）。エディタから来る
    // ドキュメントはアプリが中身を読む必要が無いので、文字列のまま素通しでよい。
    // 未知の属性を落とさない、という意味でもこの経路が正しい。
    static func patchRawJSON(_ path: String, body: String) async throws {
        guard let token = SessionStore.read() else { throw APIError.unauthorized }

        var request = URLRequest(url: AppConfig.baseURL.appending(path: path))
        request.httpMethod = "PATCH"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data(body.utf8)

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw APIError.invalidResponse }
        if http.statusCode == 401 { throw APIError.unauthorized }
        guard (200..<300).contains(http.statusCode) else {
            let code = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            throw APIError.api(status: http.statusCode, code: code?["error"] as? String)
        }
    }

    static func get<T: Decodable>(
        _ path: String,
        query: [URLQueryItem] = [],
        as type: T.Type
    ) async throws -> T {
        guard let token = SessionStore.read() else { throw APIError.unauthorized }

        var components = URLComponents(
            url: AppConfig.baseURL.appending(path: path),
            resolvingAgainstBaseURL: false
        )
        if !query.isEmpty { components?.queryItems = query }
        guard let url = components?.url else { throw APIError.invalidResponse }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw APIError.invalidResponse }

        // 401 はトークンが死んだということ。呼び出し側でサインアウトに倒す
        if http.statusCode == 401 { throw APIError.unauthorized }
        guard (200..<300).contains(http.statusCode) else {
            throw APIError.server(status: http.statusCode)
        }

        return try decoder.decode(T.self, from: data)
    }
}
