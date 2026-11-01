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
//   → JS   window.phremoEditor.setDoc(doc) / .setTitle(title) / .focusTitle() / .focus()
//          / .wordSelection() / .collapseSelection() / .format(command, value) / .blur()
//   ← JS   { type: "ready" | "update" | "title" | "format", ... }
struct NoteEditorWebView: UIViewRepresentable {
    /// 本文。サーバーから来た JSON の**文字列**をそのまま渡す（型に変換しない）
    let document: String?
    /// タイトル。本文と同じく最初の1回だけ渡す（以降はエディタが持つ）
    let title: String
    /// 本文で塗る単語。同じく JSON の文字列
    let words: String?
    /// 開いたらタイトルにカーソルを置く（作ったばかりのノート）
    var focusTitle = false
    /// 本文が変わった。渡すのは JSON の**文字列**。
    /// ⚠️ ここで Swift の型に変換しないこと。5.7万字のノートだと変換だけで
    /// メインスレッドが数百 ms 止まり、それが入力とカーソル移動の遅れになる
    /// （実機で確認。2026-09-02）。サーバーへはこの文字列のまま送る
    var onChange: (String) -> Void = { _ in }
    /// タイトルが変わった
    var onTitleChange: (String) -> Void = { _ in }
    /// 書式バーの「単語登録」が押された。選択中の語と、それが使われていた文を渡す
    var onRegisterWord: (_ surface: String, _ sentence: String) -> Void = { _, _ in }
    /// エディタが使えるようになった
    var onReady: () -> Void = {}

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> EditorWebView {
        let config = WKWebViewConfiguration()
        config.userContentController.add(context.coordinator, name: "phremo")
        // キーボードを出すのにタップ以外の操作を要求しない（focus() を効かせるため）
        config.preferences.javaScriptCanOpenWindowsAutomatically = false

        let webView = EditorWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.onRegisterWord = { [weak webView, coordinator = context.coordinator] in
            guard let webView else { return }
            coordinator.registerWord(in: webView)
        }
        webView.installFormattingBar()
        // ⚠️ isOpaque = false（背景の透過）にしないこと。合成の速い経路から外れて
        // スクロールと描画が目に見えて重くなる。背景はページ側の CSS で塗る
        // 端末に任せる。自前でスクロールを持つと、キーボードが出た時の追従を
        // 二重に管理することになる（WebView 実装の最大の落とし穴がここ）
        webView.scrollView.keyboardDismissMode = .interactive
        // 下の safe area（ホームインジケータ）のぶんを空ける。
        // ⚠️ 上には効いていない。SwiftUI が WebView の frame をナビバーの下から
        // 始めているので safeAreaInsets.top は 0（実機で計測。2026-09-04）。
        // 「本文の1行目がバーに潜る」の原因はここではなく setDoc のスクロールだった
        webView.scrollView.contentInsetAdjustmentBehavior = .always

        guard let url = Bundle.main.url(forResource: "editor", withExtension: "html") else {
            assertionFailure("editor.html が見つからない（npm run build:editor を流したか）")
            return webView
        }
        webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        return webView
    }

    func updateUIView(_ webView: EditorWebView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.sync(with: webView)
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        var parent: NoteEditorWebView
        private var isReady = false
        private var sentDoc = false

        init(parent: NoteEditorWebView) {
            self.parent = parent
        }

        private var sentWords: String?

        /// 届いたものをエディタへ渡す。本文は最初の1回だけ（以降はエディタが持つ）、
        /// 単語は変わるたびに渡し直す
        func sync(with webView: WKWebView) {
            guard isReady else { return }
            if !sentDoc, let document = parent.document {
                sentDoc = true
                webView.evaluateJavaScript("window.phremoEditor.setTitle(\(quoted(parent.title)))")
                webView.evaluateJavaScript("window.phremoEditor.setDoc(\(quoted(document)))")
                if parent.focusTitle {
                    // 先に WebView を入力の受け手にしておく。iPad の2カラムでは、一覧の側の
                    // ボタンで作ったあと WebView が受け手になっておらず、JS の focus() が
                    // 無視されてタイトルにカーソルが入らなかった（2026-10-31、シミュレータで確認）
                    webView.becomeFirstResponder()
                    webView.evaluateJavaScript("window.phremoEditor.focusTitle()")
                }
            }
            if let words = parent.words, words != sentWords {
                sentWords = words
                webView.evaluateJavaScript("window.phremoEditor.setWords(\(quoted(words)))")
            }
        }

        /// JSON を JS の文字列リテラルとして渡す。JSONSerialization に文字列を
        /// 1つだけ書かせて、引用符とエスケープを任せる（自前で組むと壊れる）
        private func quoted(_ raw: String) -> String {
            guard let data = try? JSONSerialization.data(withJSONObject: raw, options: .fragmentsAllowed),
                  let literal = String(data: data, encoding: .utf8) else { return "\"\"" }
            return literal
        }

        /// 選択中の語と文をエディタから受け取り、登録画面へ渡す
        func registerWord(in webView: WKWebView) {
            webView.evaluateJavaScript("window.phremoEditor.wordSelection()") { [weak self] result, _ in
                guard let self,
                      let json = result as? String, !json.isEmpty,
                      let selection = try? JSONDecoder().decode(WordSelection.self, from: Data(json.utf8))
                else { return }
                // 選択を残すと、登録画面を閉じた後に選択の編集メニューが出直す
                webView.evaluateJavaScript("window.phremoEditor.collapseSelection()")
                self.parent.onRegisterWord(selection.surface, selection.sentence)
            }
        }

        private struct WordSelection: Decodable {
            let surface: String
            let sentence: String
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
                parent.onReady()
                if let webView = message.webView { sync(with: webView) }

            case "error":
                // 黙って壊れないように残す（画面には出さない）
                print("editor js error: \(body["message"] ?? "")")

            case "update":
                guard let document = body["doc"] as? String else { return }
                parent.onChange(document)

            case "title":
                guard let title = body["title"] as? String else { return }
                parent.onTitleChange(title)

            case "format":
                // 書式バーの押下状態
                (message.webView as? EditorWebView)?.formatting.update(from: body)

            default:
                break
            }
        }

    }
}

// 本文エディタの WKWebView。キーボードのすぐ上に書式バー（FormattingBar）を出す。
// 標準の「∧ ∨ ✓」のバーと差し替える。
//
// 単語登録は書式バーの先頭だけに置く（選択時の編集メニューには足さない。2026-10-31
// ユーザー判断＝選択中はキーボードと一緒にバーが必ず見えているので、2か所に出す意味が無い）
final class EditorWebView: WKWebView {
    var onRegisterWord: () -> Void = {}
    /// カーソル位置の書式。エディタから届き、書式バーの押下状態になる
    let formatting = FormattingState()

    // MARK: - 書式バー

    private lazy var formattingHost: UIHostingController<FormattingBar> = {
        let host = UIHostingController(rootView: FormattingBar(
            state: formatting,
            onFormat: { [weak self] command in self?.evaluateJavaScript(command.script) },
            onRegisterWord: { [weak self] in self?.onRegisterWord() },
            onDismissKeyboard: { [weak self] in self?.evaluateJavaScript("window.phremoEditor.blur()") }
        ))
        // キーボードの上に置く部品なので、画面の安全領域を自分で避けない
        host.safeAreaRegions = []
        host.view.backgroundColor = .clear
        host.view.frame = CGRect(x: 0, y: 0, width: 0, height: 56)
        host.view.autoresizingMask = [.flexibleWidth]
        return host
    }()

    /// キーボードの上に出す部品（入力中の部品が inputAccessoryView として返す）
    fileprivate var formattingBar: UIView { formattingHost.view }

    /// WebView 標準の「∧ ∨ ✓」のバーを書式バーに差し替える。
    ///
    /// ⚠️ WKWebView には差し替えの公開 API が無い。キーボードを出しているのは WebView の
    /// 中の部品（クラス名が WKContent で始まる）なので、その部品だけを「inputAccessoryView を
    /// 書式バーで返す」派生クラスに付け替える。WebKit を使うアプリで広く使われている手で、
    /// 非公開のメソッドは呼んでいない。中の部品が見つからなければ何もしない（標準のバーのまま）
    func installFormattingBar() {
        // iPad では iOS 標準のショートカットバー（画面のキーボードの上段。物理キーボード時は画面下）に、
        // WebView が右側の群として B I U と「フォーマット」（iOS の書式パネル）を並べる。書式の操作は
        // 書式バーに一本化する（2026-11-01 ユーザー判断）。標準のボタンは WebView 自身の処理を通り
        // Tiptap のコマンドを通らないので、結果が書式バーと揃う保証も無い。
        // 左側の群（カット・コピー・取り消す・やり直す・ペースト）は書式ではないので残す
        inputAssistantItem.trailingBarButtonGroups = []

        guard let content = scrollView.subviews.first(where: {
            NSStringFromClass(type(of: $0)).hasPrefix("WKContent")
        }) else {
            print("formatting bar: content view not found")
            return
        }
        let base: AnyClass = type(of: content)
        let name = "Phremo_\(NSStringFromClass(base))"
        if NSClassFromString(name) == nil, let subclass = objc_allocateClassPair(base, name, 0) {
            let getter: @convention(block) (UIView) -> UIView? = { view in
                // 自分を抱えている EditorWebView を遡って探し、その書式バーを返す
                nonisolated(unsafe) var bar: UIView?
                MainActor.assumeIsolated {
                    var current: UIView? = view.superview
                    while let candidate = current {
                        if let webView = candidate as? EditorWebView {
                            bar = webView.formattingBar
                            break
                        }
                        current = candidate.superview
                    }
                }
                return bar
            }
            let selector = #selector(getter: UIResponder.inputAccessoryView)
            if let method = class_getInstanceMethod(base, selector) {
                class_addMethod(subclass, selector, imp_implementationWithBlock(getter), method_getTypeEncoding(method))
            }
            objc_registerClassPair(subclass)
        }
        if let subclass = NSClassFromString(name) {
            object_setClass(content, subclass)
        }
    }
}
