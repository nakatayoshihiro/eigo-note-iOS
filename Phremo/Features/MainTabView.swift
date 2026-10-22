import SwiftUI

// ログイン後の入口。Web のサイドバー（すべてのノート / 単語帳 / 復習テスト）に
// 対応するが、復習テストはブラウザ版が Coming Soon なので出していない。
//
// タブの中身がそれぞれ NavigationSplitView なので、iPhone は1カラムのドリルダウン、
// iPad は一覧＋詳細の2カラムになる。
struct MainTabView: View {
    let auth: AuthStore

    // 選んでいるタブはこちらで持つ。SwiftUI 任せにすると、iPhone Duo を開いて
    // 2カラムに切り替わった時に選択が先頭（ノート）へ戻ってしまう
    // （2026-10-22 シミュレータで確認。アプリも scene も作り直されていないのに戻った）
    @State private var selection: Item = .notes

    var body: some View {
        TabView(selection: $selection) {
            Tab("ノート", systemImage: "note.text", value: Item.notes) {
                NoteListView(auth: auth)
            }
            Tab("単語帳", systemImage: "character.book.closed", value: Item.words) {
                WordListView(auth: auth)
            }
            Tab("設定", systemImage: "gearshape", value: Item.settings) {
                SettingsView(auth: auth)
            }
        }
    }

    enum Item: Hashable {
        case notes, words, settings
    }
}
