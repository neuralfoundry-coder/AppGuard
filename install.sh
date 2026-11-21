#!/bin/zsh
# AppGuard 빌드 + 설치 + LaunchAgent 등록
set -e
SRC="$(cd "$(dirname "$0")" && pwd)"
BUILD=/Volumes/BuildSpace/appguard           # 전역 빌드 정책: 빌드 산출물은 BuildSpace
BIN=$HOME/.local/bin/appguard
PLIST=$HOME/Library/LaunchAgents/com.local.appguard.plist
LABEL=com.local.appguard

[ -d /Volumes/BuildSpace ] || { echo "BuildSpace 미마운트: diskutil mount BuildSpace"; exit 1; }
mkdir -p "$BUILD" "$HOME/.local/bin" "$HOME/Library/LaunchAgents"
swiftc -O -o "$BUILD/appguard" "$SRC/AppGuard.swift"
cp "$BUILD/appguard" "$BIN"

cat > "$PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>$LABEL</string>
  <key>ProgramArguments</key><array><string>$BIN</string></array>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><true/>
  <key>LimitLoadToSessionType</key><string>Aqua</string>
</dict></plist>
EOF

launchctl bootout gui/$(id -u)/$LABEL 2>/dev/null || true
launchctl bootstrap gui/$(id -u) "$PLIST"
echo "설치 완료. 제거: $SRC/uninstall.sh"
