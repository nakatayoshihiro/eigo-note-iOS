import Foundation

enum APIError: Error {
    case unauthorized          // 401。トークンが無効か期限切れ
    case server(status: Int)
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
