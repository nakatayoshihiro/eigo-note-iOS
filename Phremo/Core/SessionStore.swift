import Foundation
import Security

// セッショントークンの保管庫。Keychain を使う。
//
// UserDefaults ではなく Keychain を使うのは、UserDefaults がバックアップや
// ファイルとして平文で読み出せてしまうため。トークンはそれ自体がログイン状態
// そのものなので、パスワードと同じ扱いにする。
//
// kSecAttrAccessibleAfterFirstUnlock は「再起動後、一度でもロック解除されていれば
// 読める」。端末ロック中でも読めるので、将来バックグラウンドで同期する時に効く。
// 逆に .whenUnlocked にするとロック中の処理が全部失敗する。
enum SessionStore {
    private static let service = "com.phremo.Phremo.session"
    private static let account = "sessionToken"

    private static var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    static func save(_ token: String) {
        guard let data = token.data(using: .utf8) else { return }
        // 上書きのために一度消す。SecItemUpdate でも良いが、
        // 「無ければ追加・あれば更新」の分岐を持たずに済むぶん事故が少ない
        SecItemDelete(baseQuery as CFDictionary)

        var query = baseQuery
        query[kSecValueData as String] = data
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock

        let status = SecItemAdd(query as CFDictionary, nil)
        if status != errSecSuccess {
            // 保存に失敗するとログイン状態が保てない。原因究明のために残す
            // （トークン本体は絶対にログに出さない）
            print("SessionStore.save failed: OSStatus \(status)")
        }
    }

    static func read() -> String? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func clear() {
        SecItemDelete(baseQuery as CFDictionary)
    }
}
