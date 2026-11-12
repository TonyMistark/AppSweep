#!/bin/zsh
# AppSweep.app 构建脚本
# 用法：./make-app.sh [输出目录，默认 ./dist]
# 版本号：优先环境变量 AS_VERSION，否则取最近 git tag

set -euo pipefail
cd "$(dirname "$0")"

OUT_DIR="${1:-dist}"
APP_NAME="AppSweep"
BUNDLE_ID="cn.appsweep.app"
VERSION="${AS_VERSION:-$(git describe --tags --abbrev=0 2>/dev/null | sed 's/^v//' || true)}"
VERSION="${VERSION:-0.1.0}"

echo "── 1/4 release 编译…"
swift build -c release --disable-sandbox --product AppSweep
BIN=".build/release/$APP_NAME"

echo "── 2/4 组装 $APP_NAME.app…"
APP="$OUT_DIR/$APP_NAME.app"
mkdir -p "$OUT_DIR"
: > "$OUT_DIR/.metadata_never_index"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/$APP_NAME"

ICON="Assets/AppIcon.icns"
if [[ -f "$ICON" ]]; then
    cp "$ICON" "$APP/Contents/Resources/"
fi

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>            <string>$APP_NAME</string>
    <key>CFBundleDisplayName</key>     <string>$APP_NAME</string>
    <key>CFBundleIdentifier</key>      <string>$BUNDLE_ID</string>
    <key>CFBundleVersion</key>         <string>$VERSION</string>
    <key>CFBundleShortVersionString</key> <string>$VERSION</string>
    <key>CFBundlePackageType</key>     <string>APPL</string>
    <key>CFBundleExecutable</key>      <string>$APP_NAME</string>
    <key>LSMinimumSystemVersion</key>  <string>13.0</string>
    <key>LSApplicationCategoryType</key> <string>public.app-category.utilities</string>
    <key>NSHighResolutionCapable</key> <true/>
    <key>NSSupportsAutomaticTermination</key> <false/>
    <key>NSSupportsSuddenTermination</key>   <false/>
    <key>NSAppleEventsUsageDescription</key>
    <string>AppSweep 需要控制 Finder 以将文件移到废纸篓</string>
</dict>
</plist>
PLIST

if [[ -f "$ICON" ]]; then
    /usr/libexec/PlistBuddy -c "Add :CFBundleIconFile string AppIcon" "$APP/Contents/Info.plist" >/dev/null
fi

echo "── 3/4 签名…"
IDENTITY="${AS_SIGN_IDENTITY:-}"
if [[ -z "$IDENTITY" ]]; then
    IDENTITY=$(security find-identity -v -p codesigning | grep -oE '"[^"]+"' | head -1 | tr -d '"') || true
fi
ENTITLEMENTS=$(mktemp)
cat > "$ENTITLEMENTS" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
    <key>com.apple.security.automation.apple-events</key><true/>
</dict></plist>
EOF
if [[ -n "$IDENTITY" && "$IDENTITY" != "-" ]]; then
    codesign --force --options runtime --entitlements "$ENTITLEMENTS" --sign "$IDENTITY" "$APP"
    echo "   已用 $IDENTITY 签名"
else
    codesign --force --entitlements "$ENTITLEMENTS" --sign - "$APP"
    echo "   ad-hoc 签名"
fi
rm -f "$ENTITLEMENTS"

echo "── 4/4 校验…"
codesign --verify --verbose "$APP" 2>&1 | tail -1
spctl --assess --type execute "$APP" 2>&1 || true

# DMG：Release 附件名 appsweep-<版本>.dmg，UpdateChecker 按这个名字认附件
DMG="$OUT_DIR/appsweep-$VERSION.dmg"
rm -f "$DMG"
hdiutil create -volname "$APP_NAME $VERSION" -srcfolder "$APP" -ov -format UDZO "$DMG" >/dev/null
echo "   DMG：$DMG"

echo ""
echo "✓ 完成：$APP（版本 $VERSION）"
echo "  DMG：$DMG"
