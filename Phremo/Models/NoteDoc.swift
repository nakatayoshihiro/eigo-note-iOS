import Foundation

// ノート本文（ProseMirror のドキュメント）。サーバーが `bodyJson` として返す木で、
// Web 側の定義は app の lib/note-doc.ts、形を決める拡張は lib/tiptap-doc.ts にある。
//
// ■ なぜ HTML ではなくこれを読むのか
// 本文の正が 2026-09-01 に HTML から JSON になった。HTML を Swift で組み立て直さずに
// 済むので、これから足す「書く」機能でも同じ木をそのまま送り返せる。
//
// ■ 未知のノード・マークについて
// 知らない type は落とさず中身だけ拾う（NoteBody.parse）。Web 側に拡張が増えたときに
// 本文が丸ごと消えるより、装飾が付かないだけの方がましなため。
struct NoteDoc: Decodable, Hashable {
    let type: String
    let content: [NoteDoc]?
    let text: String?
    let marks: [NoteMark]?
    let attrs: NoteAttrs?
}

struct NoteMark: Decodable, Hashable {
    let type: String
    let attrs: NoteAttrs?
}

// ノードとマークの属性をまとめて1つで受ける。使う場所ごとに現れる鍵が違う
// （heading は level、taskItem は checked、link は href、textStyle は color と fontSize）。
// 知らない鍵は Decodable が黙って捨てる
struct NoteAttrs: Decodable, Hashable {
    let level: Int?
    let checked: Bool?
    let start: Int?
    let color: String?
    let fontSize: String?
    let href: String?
}
