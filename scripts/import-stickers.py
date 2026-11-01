#!/usr/bin/env python3
"""Web のステッカー（tsx）を iOS のアセットカタログ（svg）に写す。

絵の正は Web 側 `app/components/stickers/Sticker*.tsx`。あちらは Figma の書き出しを
scripts/gen-sticker.py で tsx にしたもので、viewBox は全種共通の正方形（2026-09-06 から
104x104。以前は 100x100）。iOS 側で描き直すと2つの絵が育ってしまうので、ここでは
tsx から svg を機械的に起こす。

    python3 scripts/import-stickers.py

絵を差し替えたら Web 側を直してから、これを流し直す。
"""

import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
WEB = ROOT.parent / "app" / "app" / "components" / "stickers"
OUT = ROOT / "Phremo" / "Assets.xcassets" / "Stickers"

NAMES = [
    "business", "diary", "diamond", "interview",
    "listening", "speaking", "test", "travel",
]


# SVG の仕様そのものがキャメルケースの属性。これ以外のキャメルケースは React の
# 書き方（strokeWidth など）なので、ハイフン区切りに戻す
SVG_CAMEL = {
    "viewBox", "preserveAspectRatio",
    "maskUnits", "maskContentUnits", "clipPathUnits",
    "gradientUnits", "gradientTransform", "patternUnits", "patternTransform",
}


def to_svg(tsx: str) -> str:
    # 2回以上使う d はコンポーネントの外に定数として括り出されている
    # （gen-sticker.py。白フチは「マスク」「白い塗り」「外側の線」で同じ形を3回使う）
    consts = dict(re.findall(r'^const (\w+) =\s*"([^"]*)";', tsx, re.M))

    body = tsx[tsx.index("<svg"): tsx.rindex("</svg>") + len("</svg>")]

    body = re.sub(
        r"d=\{(\w+)\}",
        lambda m: f'd="{consts[m.group(1)]}"',
        body,
    )

    # JSX 固有の書き方を素の SVG に戻す。
    # id は React の useId() で描画ごとに一意にしていた（同じ絵を一覧に何枚も
    # 並べると重複するため）。svg ファイルは1枚で完結するので固定名でよい
    body = re.sub(r"id=\{`\$\{uid\}-([a-z0-9]+)`\}", r'id="m-\1"', body)
    body = re.sub(r"=\{`url\(#\$\{uid\}-([a-z0-9]+)\)`\}", r'="url(#m-\1)"', body)
    body = body.replace('style={{ maskType: "alpha" }}', 'style="mask-type:alpha"')

    # 呼び出し側で当てていた属性を落とす（className は CSS 用、aria-hidden は HTML 用）
    body = re.sub(r"\s*className=\{className\}", "", body)
    body = re.sub(r'\s*aria-hidden="true"', "", body)

    body = re.sub(
        r"(\s)([a-z]+[A-Z][A-Za-z]*)=",
        lambda m: m.group(1)
        + (m.group(2) if m.group(2) in SVG_CAMEL else re.sub(r"[A-Z]", lambda c: "-" + c.group().lower(), m.group(2)))
        + "=",
        body,
    )

    # 親要素いっぱいに描く指定は HTML 用。アセットカタログは実寸を要るので
    # viewBox と同じ大きさにする
    size = re.search(r'viewBox="0 0 (\d+) \1"', body)
    if not size:
        raise SystemExit("viewBox が正方形の 0 0 N N になっていません")
    body = body.replace('width="100%"', f'width="{size[1]}"').replace('height="100%"', f'height="{size[1]}"')

    leftover = re.findall(r"\{[^}]*\}", body)
    if leftover:
        raise SystemExit(f"JSX の式が残っています: {leftover[:3]}")

    return re.sub(r"\n\s+", "\n  ", body).strip() + "\n"


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    (OUT / "Contents.json").write_text(
        json.dumps({"info": {"author": "xcode", "version": 1}}, indent=2) + "\n"
    )

    for name in NAMES:
        source = WEB / f"Sticker{name.capitalize()}.tsx"
        asset = OUT / f"sticker-{name}.imageset"
        asset.mkdir(exist_ok=True)
        (asset / f"sticker-{name}.svg").write_text(to_svg(source.read_text()))
        (asset / "Contents.json").write_text(
            json.dumps(
                {
                    "images": [{"filename": f"sticker-{name}.svg", "idiom": "universal"}],
                    "info": {"author": "xcode", "version": 1},
                    # 拡大しても粗くならないようベクタのまま保持する。
                    # original = 色を持った絵として扱う（テンプレート化して単色に
                    # されると、白フチも含めて全部潰れる）
                    "properties": {
                        "preserves-vector-representation": True,
                        "template-rendering-intent": "original",
                    },
                },
                indent=2,
            )
            + "\n"
        )
        print(f"{source.name} → {asset.name}")


if __name__ == "__main__":
    main()
