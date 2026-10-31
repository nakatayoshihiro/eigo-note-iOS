import Foundation

// サーバーが上限で断った時（429）の本文を、画面に出す文言へ変える。
// Web の lib/create-quota.ts（createQuotaMessage）と lib/storage-quota.ts
// （storageQuotaMessage）の写し。**文言を変えるときは両方そろえること。**
enum QuotaMessage {
    private static let labels = ["note": "ノート", "word": "単語"]

    static func from(_ body: Data) -> String? {
        guard let e = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any],
              let error = e["error"] as? String else { return nil }

        if error == "storage_quota",
           let limit = e["limitMb"] as? NSNumber, let used = e["usedMb"] as? NSNumber {
            // NSNumber の文字列化は JS のテンプレートと同じ形になる（50 / 12.3）
            return "保存できる容量の上限（\(limit)MB）に達しました。現在 \(used)MB 使用中です。不要なノートや単語を削除してください"
        }

        guard let resource = e["resource"] as? String, let label = labels[resource] else { return nil }
        if error == "quota_exceeded", let limit = e["limit"] as? NSNumber {
            let count = NumberFormatter.localizedString(from: limit, number: .decimal)
            return "\(label)は\(count)件までです。不要な\(label)を削除してからお試しください"
        }
        if error == "create_rate_limit" {
            return "短い時間に\(label)を作りすぎました。少し待ってからお試しください"
        }
        return nil
    }
}
