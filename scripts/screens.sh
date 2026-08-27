#!/bin/bash
# 画面を一通り開いてスクリーンショットを撮る。人手でタップして回らないための道具。
#
#   scripts/screens.sh                        # iPhone 17 Pro
#   scripts/screens.sh "iPad Pro 11-inch (M5)"
#
# 出力: /tmp/phremo-screens/<名前>.png（実行のたびに作り直す）
# ⚠️ 対象のシミュレータにログイン済みのセッションが要る。無ければログイン画面が撮れる。
set -uo pipefail

DEVICE="${1:-iPhone 17 Pro}"
OUT="/tmp/phremo-screens"
RESULT="$(mktemp -d)/tour.xcresult"

cd "$(dirname "$0")/.."

# ⚠️ 失敗しても止めない。落ちた時こそ、その時の画面と失敗理由を見たい
# （xcresult には失敗時の UI ツリーと録画も入る）
STATUS=0
xcodebuild test \
  -project Phremo.xcodeproj \
  -scheme Phremo \
  -destination "platform=iOS Simulator,name=$DEVICE" \
  -resultBundlePath "$RESULT" \
  -quiet || STATUS=$?

rm -rf "$OUT" && mkdir -p "$OUT"
xcrun xcresulttool export attachments --path "$RESULT" --output-path "$OUT" >/dev/null

# 取り出した画像は UUID 名なので、テスト側で付けた名前に戻す
python3 - "$OUT" <<'PY'
import json, re, sys
from pathlib import Path

out = Path(sys.argv[1])
manifest = json.loads((out / "manifest.json").read_text())
for entry in manifest:
    for attachment in entry.get("attachments", []):
        name = attachment.get("suggestedHumanReadableName") or attachment["exportedFileName"]
        clean = re.sub(r"_\d+_[0-9A-F-]{36}", "", name)
        source = out / attachment["exportedFileName"]
        if source.exists():
            source.rename(out / clean)
(out / "manifest.json").unlink()
PY

echo "→ $OUT"
ls "$OUT"
if [ "$STATUS" -ne 0 ]; then
  echo "⚠️ テストは失敗しています（終了コード $STATUS）。理由は上の 'Complete Issue Description.txt'"
fi
exit "$STATUS"
