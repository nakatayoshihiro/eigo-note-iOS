import SwiftUI

// ログイン後の入口。Web のサイドバー（すべてのノート / 単語帳 / 復習テスト）に
// 対応するが、復習テストはブラウザ版が Coming Soon なので今は2つだけ。
//
// タブの中身がそれぞれ NavigationSplitView なので、iPhone は1カラムのドリルダウン、
// iPad は一覧＋詳細の2カラムになる。
struct MainTabView: View {
    let auth: AuthStore

    var body: some View {
        TabView {
            Tab("ノート", systemImage: "note.text") {
                NoteListView(auth: auth)
            }
            Tab("単語帳", systemImage: "character.book.closed") {
                WordListView(auth: auth)
            }
        }
    }
}
