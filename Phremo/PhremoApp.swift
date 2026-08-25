//
//  PhremoApp.swift
//  Phremo
//
//  Created by 中田 佳宏 on R 8/08/25.
//

import SwiftUI

@main
struct PhremoApp: App {
    @State private var auth = AuthStore()

    var body: some Scene {
        WindowGroup {
            RootView(auth: auth)
        }
    }
}
