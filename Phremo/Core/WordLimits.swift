import Foundation

// 単語1件あたりの入力上限と、上限で断られた時（400）の文言。
// Web の lib/word-limits.ts（WORD_LIMITS / wordValidationMessage）の写し。
// **値や文言を変えるときは両方そろえること。**
enum WordLimits {
    static let lemma = 100
    static let translation = 500

    private static let fieldLabels = [
        "lemma": "登録単語",
        "surface": "選択した語",
        "translation": "日本語訳",
        "note": "文脈の補足",
        "sourceSentence": "使われていた文",
    ]

    static func validationMessage(from body: Data) -> String? {
        guard let e = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any],
              let error = e["error"] as? String else { return nil }
        if error == "too_long", let field = e["field"] as? String, let label = fieldLabels[field],
           let max = e["max"] as? NSNumber {
            return "\(label)は\(max)文字までです"
        }
        if error == "invalid_pos" { return "品詞の値が正しくありません" }
        if error == "invalid_related_forms" { return "派生語の値が正しくありません" }
        return nil
    }
}
