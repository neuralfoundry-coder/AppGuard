#!/bin/zsh
launchctl bootout gui/$(id -u)/com.local.appguard 2>/dev/null || true
rm -f ~/Library/LaunchAgents/com.local.appguard.plist ~/.local/bin/appguard
rm -rf /Volumes/BuildSpace/appguard
echo "제거 완료"
