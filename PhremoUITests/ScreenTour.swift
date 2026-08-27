import XCTest

// 画面を順に開いてスクリーンショットを残すだけのテスト。
//
// ■ 何のためにあるか
// 変更のたびに「単語帳タブを開いて、単語を1件タップして…」と人手で操作するのを無くす。
// 落ちずに一通り開けること自体が回帰テストになり、撮った画像で見た目も確認できる。
//
// ■ 前提
// **シミュレータにログイン済みのセッションが要る**（Keychain に残っていれば足りる）。
// ログイン画面で止まった場合は、そのスクリーンショットが残るので原因が分かる。
//
//     xcodebuild test -project Phremo.xcodeproj -scheme Phremo \
//       -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
//       -resultBundlePath /tmp/tour.xcresult
//
// 画像の取り出しは scripts/screens.sh を使う。
final class ScreenTour: XCTestCase {
    override func setUp() {
        continueAfterFailure = true   // 途中で開けない画面があっても最後まで撮る
    }

    @MainActor
    func testTour() {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 10))

        shoot(app, "01-notes")

        // ノートを1件開く（本文・ハイライト）
        if app.collectionViews.cells.firstMatch.waitForExistence(timeout: 10) {
            app.collectionViews.cells.element(boundBy: min(4, app.collectionViews.cells.count - 1)).tap()
            shoot(app, "02-note-body")
            back(app)
        }

        tab(app, "単語帳")
        shoot(app, "03-words")

        // 絞り込み（ノートで絞ると、何で絞っているかが副題に出る）
        let filter = app.buttons["絞り込み"]
        if filter.waitForExistence(timeout: 5) {
            filter.tap()
            shoot(app, "03b-filter-menu")
            // メニューは入れ子にならず、ノートも品詞もその場に並ぶ
            let item = app.buttons["the Office フレーズ"]
            if item.waitForExistence(timeout: 3) {
                item.tap()
                shoot(app, "03c-filtered")
            }
        }

        // 単語を1件開く（詳細・派生語）
        if app.collectionViews.cells.firstMatch.waitForExistence(timeout: 10) {
            app.collectionViews.cells.firstMatch.tap()
            shoot(app, "04-word-detail")
            back(app)
        }

        tab(app, "設定")
        shoot(app, "05-settings")
    }

    // タブは iOS 26 の浮いたタブバー。
    // ⚠️ firstMatch が要る。iPad では同じラベルのボタンが入れ子で2つ見え
    // （_UIFloatingTabBarItemCell の中に Button）、そのままだと
    // 「Multiple matching elements」で落ちる
    private func tab(_ app: XCUIApplication, _ name: String) {
        let inTabBar = app.tabBars.buttons[name].firstMatch
        let button = inTabBar.exists ? inTabBar : app.buttons[name].firstMatch
        if button.waitForExistence(timeout: 5) { button.tap() }
    }

    // iPhone は push なので戻るボタン。iPad の2カラムでは戻る必要が無い
    private func back(_ app: XCUIApplication) {
        let backButton = app.navigationBars.buttons.firstMatch
        if backButton.exists && backButton.isHittable { backButton.tap() }
    }

    private func shoot(_ app: XCUIApplication, _ name: String) {
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways   // 成功したテストでも残す（既定は失敗時のみ）
        add(shot)
    }
}
