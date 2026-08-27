import Foundation

// GET /api/auth/get-session（better-auth）。bearer を付けて叩くと、
// ブラウザの Cookie と同じようにセッションとユーザーが返る
struct SessionResponse: Decodable {
    let user: AccountUser
}

struct AccountUser: Decodable {
    let id: String
    let name: String
    let email: String
    let image: String?

    // 頭文字。画像を出さない代わりの丸バッジに使う（Web の設定画面と同じ作り）
    var initial: String {
        let source = name.trimmingCharacters(in: .whitespaces).isEmpty ? email : name
        return source.first.map(String.init)?.uppercased() ?? "?"
    }
}

// GET /api/ai-usage。金額は返らず、自分の使用率（%）と、使えない理由だけが来る
struct AiUsage: Decodable {
    let usedPercent: Int
    let limitedBy: String?      // "disabled" | "global" | "user" | nil

    // 文言は Web の lib/ai-messages.ts と揃える（同じ状況で違う言い方をしない）
    var limitMessage: String? {
        switch limitedBy {
        case "user":
            "本日のAI解析の利用上限に達しました。0時を過ぎるとまた利用できます。"
        case "global", "disabled":
            "AI解析は現在一時的に利用できません。時間をおいてもう一度お試しください。"
        default:
            nil
        }
    }
}
