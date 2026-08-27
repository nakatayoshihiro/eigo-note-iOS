#!/usr/bin/env python3
"""Web のステッカー（tsx）を iOS のアセットカタログ（svg）に写す。

絵の正は Web 側 `app/components/stickers/Sticker*.tsx`。あちらは Figma の書き出しを
scripts/gen-sticker.py で tsx にしたもので、viewBox は全種 100x100 に正規化されている。
iOS 側で描き直すと2つの絵が育ってしまうので、ここでは tsx から svg を機械的に起こす。

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


def to_svg(tsx: str) -> str:
    body = tsx[tsx.index("<svg"): tsx.rindex("</svg>") + len("</svg>")]

    # JSX 固有の書き方を素の SVG に戻す。
    # id は React の useId() で描画ごとに一意にしていた（同じ絵を一覧に何枚も
    # 並べると重複するため）。svg ファイルは1枚で完結するので固定名でよい
    body = re.sub(r"id=\{`\$\{uid\}-([a-z0-9]+)`\}", r'id="m-\1"', body)
    body = re.sub(r"=\{`url\(#\$\{uid\}-([a-z0-9]+)\)`\}", r'="url(#m-\1)"', body)
    body = body.replace('style={{ maskType: "alpha" }}', 'style="mask-type:alpha"')

    # 呼び出し側で当てていた属性を落とす（className は CSS 用、aria-hidden は HTML 用）
    body = re.sub(r"\s*className=\{className\}", "", body)
    body = re.sub(r'\s*aria-hidden="true"', "", body)

    # 親要素いっぱいに描く指定は HTML 用。アセットカタログは実寸を要るので
    # viewBox と同じ 100x100 にする
    body = body.replace('width="100%"', 'width="100"').replace('height="100%"', 'height="100"')

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
