import SwiftUI
import WebKit

// 本文エディタ。Web と同じ Tiptap を WKWebView に載せて動かす。
//
// ■ なぜ WebView なのか（2026-09-02 決定）
// Web と iOS で最初から同機能を出す方針のため。エディタの挙動（リストの Enter・
// 貼り付けの整形・undo・色・文字サイズ）を2実装で同じに保ち続けるのは1人では持てない。
// Notion と Atlassian が同じ構成（器はネイティブ、エディタだけ Web）を採っており、
// Tiptap 公式も ProseMirror は DOM 依存なので WebView に載せるのが現状の解としている。
//
// ■ 中身
// `Resources/editor.html` は Web リポジトリの `editor-webview/` を Vite で1ファイルに
// 固めたもの（`npm run build:editor` で書き出してここへコピーする）。外部リクエストが
// 無いのでオフラインで開ける。**このファイルを手で編集しないこと**（次のビルドで消える）。
//
// ■ やり取り
//   → JS   window.phremoEditor.setDoc(doc) / .focus()
//   ← JS   { type: "ready" | "update" | "selection", ... }
struct NoteEditorWebView: UIViewRepresentable {
    let doc: NoteDoc?
    /// 計測モード（スパイク）。"full" / "small" / "plain"
    var mode: String = "full"
    /// 本文が変わった。渡すのは JSON の**文字列**。
    /// ⚠️ ここで Swift の型に変換しないこと。5.7万字のノートだと変換だけで
    /// メインスレッドが数百 ms 止まり、それが入力とカーソル移動の遅れになる
    /// （実機で確認。2026-09-02）。サーバーへはこの文字列のまま送る
    var onChange: (String) -> Void = { _ in }
    /// 起動にかかった時間（スパイクの計測用）
    var onReady: (Int) -> Void = { _ in }
    /// HTML までは動いた（切り分け用）
    var onBoot: () -> Void = {}
    /// JS の実行時エラー（切り分け用）
    var onError: (String) -> Void = { _ in }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.userContentController.add(context.coordinator, name: "phremo")
        // キーボードを出すのにタップ以外の操作を要求しない（focus() を効かせるため）
        config.preferences.javaScriptCanOpenWindowsAutomatically = false

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        // ⚠️ isOpaque = false（背景の透過）にしないこと。合成の速い経路から外れて
        // スクロールと描画が目に見えて重くなる。背景はページ側の CSS で塗る
        // 端末に任せる。自前でスクロールを持つと、キーボードが出た時の追従を
        // 二重に管理することになる（WebView 実装の最大の落とし穴がここ）
        webView.scrollView.keyboardDismissMode = .interactive

        guard let url = Bundle.main.url(forResource: "editor", withExtension: "html") else {
            assertionFailure("editor.html が見つからない（npm run build:editor を流したか）")
            return webView
        }
        webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.sendDocIfReady(to: webView)
        context.coordinator.applyMode(to: webView, mode: mode)
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        var parent: NoteEditorWebView
        private var isReady = false
        private var sentDoc = false

        init(parent: NoteEditorWebView) {
            self.parent = parent
        }

        private var appliedMode = "full"

        func applyMode(to webView: WKWebView, mode: String) {
            guard isReady, mode != appliedMode else { return }
            appliedMode = mode
            webView.evaluateJavaScript("window.phremoEditor.setMode('\(mode)')")
        }

        func sendDocIfReady(to webView: WKWebView) {
            guard isReady, !sentDoc, let doc = parent.doc else { return }
            guard let data = try? JSONEncoder().encode(doc),
                  let json = String(data: data, encoding: .utf8) else { return }
            sentDoc = true
            webView.evaluateJavaScript("window.phremoEditor.setDoc(\(json))")
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            // ready は JS から来る。ここでは何もしない（描画完了 ≠ エディタ生成完了）
        }

        func userContentController(
            _ controller: WKUserContentController,
            didReceive message: WKScriptMessage
        ) {
            guard let body = message.body as? [String: Any],
                  let type = body["type"] as? String else { return }

            switch type {
            case "ready":
                isReady = true
                parent.onReady(body["ms"] as? Int ?? -1)
                if let webView = message.webView { sendDocIfReady(to: webView) }

            case "boot":
                parent.onBoot()

            case "error":
                parent.onError(body["message"] as? String ?? "不明なエラー")

            case "update":
                guard let document = body["doc"] as? String else { return }
                parent.onChange(document)

            default:
                break
            }
        }
    }
}
