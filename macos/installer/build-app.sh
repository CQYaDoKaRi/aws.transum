#!/bin/bash
# AudioTranscriptionSummary macOS .app バンドル & DMG インストーラー作成スクリプト
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
APP_NAME="AudioTranscriptionSummary"
BUNDLE_ID="com.audiotranscriptionsummary.app"
VERSION="1.0.0"
OUTPUT_DIR="$SCRIPT_DIR/output"
APP_BUNDLE="$OUTPUT_DIR/$APP_NAME.app"
DMG_NAME="${APP_NAME}_${VERSION}.dmg"

echo "=== $APP_NAME macOS インストーラー作成 ==="
echo ""

# 1. リリースビルド
echo "[1/5] リリースビルド中..."
cd "$PROJECT_DIR"
swift build -c release 2>&1 | tail -3
EXECUTABLE="$PROJECT_DIR/.build/release/$APP_NAME"

if [ ! -f "$EXECUTABLE" ]; then
    echo "エラー: ビルド成果物が見つかりません: $EXECUTABLE"
    exit 1
fi
echo "  ビルド完了: $(du -h "$EXECUTABLE" | cut -f1)"

# 2. .app バンドル作成
echo "[2/5] .app バンドル作成中..."
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

# 実行ファイルをコピー
cp "$EXECUTABLE" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"

# Info.plist 作成
cat > "$APP_BUNDLE/Contents/Info.plist" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>$APP_NAME</string>
    <key>CFBundleDisplayName</key>
    <string>Audio Transcription Summary</string>
    <key>CFBundleIdentifier</key>
    <string>$BUNDLE_ID</string>
    <key>CFBundleVersion</key>
    <string>$VERSION</string>
    <key>CFBundleShortVersionString</key>
    <string>$VERSION</string>
    <key>CFBundleExecutable</key>
    <string>$APP_NAME</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSMicrophoneUsageDescription</key>
    <string>音声の録音に使用します</string>
    <key>NSSpeechRecognitionUsageDescription</key>
    <string>音声の文字起こしに使用します</string>
    <key>NSScreenCaptureUsageDescription</key>
    <string>システム音声のキャプチャと画面録画に使用します</string>
    <key>LSApplicationCategoryType</key>
    <string>public.app-category.productivity</string>
</dict>
</plist>
EOF

echo "  .app バンドル作成完了"

# 3. アイコン生成（sips で PNG → icns 変換）
echo "[3/5] アイコン生成中..."
ICONSET_DIR="$OUTPUT_DIR/AppIcon.iconset"
rm -rf "$ICONSET_DIR"
mkdir -p "$ICONSET_DIR"

# Python でアイコン PNG を生成（CoreGraphics 不要、シンプルな方法）
python3 << 'PYEOF'
import struct, zlib, os, sys

def create_png(width, height, pixels):
    """最小限のPNG生成（外部ライブラリ不要）"""
    def chunk(chunk_type, data):
        c = chunk_type + data
        return struct.pack('>I', len(data)) + c + struct.pack('>I', zlib.crc32(c) & 0xffffffff)

    raw = b''
    for y in range(height):
        raw += b'\x00'  # filter: none
        for x in range(width):
            idx = (y * width + x) * 4
            raw += bytes(pixels[idx:idx+4])

    header = b'\x89PNG\r\n\x1a\n'
    ihdr = chunk(b'IHDR', struct.pack('>IIBBBBB', width, height, 8, 6, 0, 0, 0))
    idat = chunk(b'IDAT', zlib.compress(raw, 9))
    iend = chunk(b'IEND', b'')
    return header + ihdr + idat + iend

def draw_icon(size):
    pixels = [0] * (size * size * 4)
    cr = int(size * 0.22)

    def in_rounded_rect(x, y, w, h, r):
        if x < r and y < r:
            return (x - r)**2 + (y - r)**2 <= r**2
        if x >= w - r and y < r:
            return (x - (w - r))**2 + (y - r)**2 <= r**2
        if x < r and y >= h - r:
            return (x - r)**2 + (y - (h - r))**2 <= r**2
        if x >= w - r and y >= h - r:
            return (x - (w - r))**2 + (y - (h - r))**2 <= r**2
        return True

    def set_pixel(px, py, r, g, b, a=255):
        if 0 <= px < size and 0 <= py < size:
            idx = (py * size + px) * 4
            # alpha blend
            sa = a / 255.0
            da = pixels[idx+3] / 255.0
            oa = sa + da * (1 - sa)
            if oa > 0:
                pixels[idx] = int((r * sa + pixels[idx] * da * (1 - sa)) / oa)
                pixels[idx+1] = int((g * sa + pixels[idx+1] * da * (1 - sa)) / oa)
                pixels[idx+2] = int((b * sa + pixels[idx+2] * da * (1 - sa)) / oa)
                pixels[idx+3] = int(oa * 255)

    # 背景グラデーション
    for y in range(size):
        for x in range(size):
            if in_rounded_rect(x, y, size, size, cr):
                t = y / size
                r = int(26 + (51 - 26) * t)
                g = int(77 + (140 - 77) * t)
                b = int(191 + (242 - 191) * t)
                set_pixel(x, y, r, g, b)

    # 波形バー
    bar_w = max(2, int(size * 0.035))
    bar_sp = max(1, int(size * 0.023))
    heights = [0.12, 0.20, 0.27, 0.35, 0.31, 0.39, 0.29, 0.23, 0.33, 0.25, 0.18, 0.12]
    total_w = len(heights) * bar_w + (len(heights) - 1) * bar_sp
    sx = (size - total_w) // 2
    cy = int(size * 0.55)
    for i, h_ratio in enumerate(heights):
        bx = sx + i * (bar_w + bar_sp)
        bh = int(size * h_ratio)
        by = cy - bh // 2
        for dy in range(bh):
            for dx in range(bar_w):
                set_pixel(bx + dx, by + dy, 255, 255, 255, 240)

    # ドキュメント（右下）
    dx_start = int(size * 0.62)
    dy_start = int(size * 0.06)
    dw = int(size * 0.28)
    dh = int(size * 0.32)
    for dy in range(dh):
        for dx in range(dw):
            set_pixel(dx_start + dx, dy_start + dy, 255, 255, 255, 230)

    # ドキュメント内の線
    lm = int(dw * 0.12)
    lh = max(1, int(size * 0.012))
    widths = [0.8, 0.65, 0.75, 0.5]
    for i, wr in enumerate(widths):
        ly = dy_start + dh - lm - i * (lh + max(2, int(size * 0.02))) - lh
        lw = int((dw - lm * 2) * wr)
        for dy in range(lh):
            for dx in range(lw):
                set_pixel(dx_start + lm + dx, ly + dy, 38, 102, 217, 180)

    return pixels

output_dir = os.environ.get('ICONSET_DIR', '/tmp/AppIcon.iconset')
sizes = [(16,'16x16'), (32,'16x16@2x'), (32,'32x32'), (64,'32x32@2x'),
         (128,'128x128'), (256,'128x128@2x'), (256,'256x256'),
         (512,'256x256@2x'), (512,'512x512'), (1024,'512x512@2x')]

for sz, name in sizes:
    pixels = draw_icon(sz)
    png = create_png(sz, sz, pixels)
    path = os.path.join(output_dir, f'icon_{name}.png')
    with open(path, 'wb') as f:
        f.write(png)

print(f'  {len(sizes)} サイズのアイコンを生成しました')
PYEOF

# iconutil で .icns に変換
if command -v iconutil &> /dev/null; then
    iconutil -c icns "$ICONSET_DIR" -o "$APP_BUNDLE/Contents/Resources/AppIcon.icns"
    # Info.plist にアイコン参照を追加
    /usr/libexec/PlistBuddy -c "Add :CFBundleIconFile string AppIcon" "$APP_BUNDLE/Contents/Info.plist" 2>/dev/null || \
    /usr/libexec/PlistBuddy -c "Set :CFBundleIconFile AppIcon" "$APP_BUNDLE/Contents/Info.plist"
    echo "  アイコン (.icns) 作成完了"
else
    echo "  警告: iconutil が見つかりません。アイコンなしで続行します"
fi
rm -rf "$ICONSET_DIR"

# 4. DMG 作成
echo "[4/5] DMG インストーラー作成中..."
DMG_PATH="$OUTPUT_DIR/$DMG_NAME"
rm -f "$DMG_PATH"

# 一時ディレクトリに .app と Applications リンクを配置
DMG_STAGING="$OUTPUT_DIR/dmg_staging"
rm -rf "$DMG_STAGING"
mkdir -p "$DMG_STAGING"
cp -R "$APP_BUNDLE" "$DMG_STAGING/"
ln -s /Applications "$DMG_STAGING/Applications"

hdiutil create -volname "$APP_NAME" \
    -srcfolder "$DMG_STAGING" \
    -ov -format UDZO \
    "$DMG_PATH" 2>/dev/null

rm -rf "$DMG_STAGING"
echo "  DMG 作成完了: $(du -h "$DMG_PATH" | cut -f1)"

# 5. 完了
echo ""
echo "[5/5] 完了"
echo "  .app: $APP_BUNDLE"
echo "  DMG:  $DMG_PATH"
echo ""
echo "インストール方法:"
echo "  1. $DMG_NAME をダブルクリックして開く"
echo "  2. AudioTranscriptionSummary.app を Applications フォルダにドラッグ"
echo "  3. Launchpad または Applications フォルダから起動"
