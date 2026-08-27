import SwiftUI

// ログアウト。タブが増えたのでどのタブからでも出せるよう部品にした
struct SignOutButton: View {
    let auth: AuthStore

    var body: some View {
        Button("ログアウト", systemImage: "rectangle.portrait.and.arrow.right") {
            auth.signOut()
        }
    }
}
