#!/bin/zsh
# Captures the App Store screenshot set from a simulator using the DEBUG launch hooks.
# usage: scripts/appstore-screenshots.sh <simulator-udid> <out-dir> <path/to/PrivateLift.app>
# Build first (derived data outside ~/Documents; iCloud xattrs break codesign there), e.g.
#   xcodebuild -project PrivateLift.xcodeproj -scheme PrivateLift -destination 'generic/platform=iOS Simulator' \
#     -derivedDataPath /tmp/pl-dd CODE_SIGNING_ALLOWED=NO build
# iPhone 18 Pro Max captures 1320x2868 (6.9"); iPad Pro 13-inch captures 2064x2752.
# Output PNGs have an alpha channel; flatten before uploading (sips JPEG round trip).
set -u
D=$1; OUT=$2; APP=$3; BID=Nelson-Computers.PrivateLift
mkdir -p "$OUT"
xcrun simctl boot "$D" 2>/dev/null; xcrun simctl bootstatus "$D" -b >/dev/null 2>&1
xcrun simctl status_bar "$D" override --time 9:41 --batteryState discharging --batteryLevel 100 --wifiBars 3 --cellularBars 4 >/dev/null 2>&1
xcrun simctl uninstall "$D" $BID 2>/dev/null   # fresh store so the demo data seeds
xcrun simctl install "$D" "$APP" || exit 1
xcrun simctl launch --terminate-running-process "$D" $BID -seedScreenshots YES >/dev/null; sleep 6
shot() { # name, then launch args
  local name=$1; shift
  xcrun simctl launch --terminate-running-process "$D" $BID -seedScreenshots YES "$@" >/dev/null
  sleep 5
  xcrun simctl io "$D" screenshot "$OUT/$name.png" >/dev/null 2>&1 && echo "$name"
}
shot 1-dashboard      -screenshotTheme light -initialTab 0 -demoRestTimer YES
shot 2-log-a-set      -screenshotTheme light -initialTab 0 -screenshotScroll log
shot 3-todays-workout -screenshotTheme light -initialTab 0 -screenshotScroll today
shot 4-stats          -screenshotTheme light -initialTab 1
shot 5-history        -screenshotTheme light -initialTab 2
shot 6-dark-mode      -screenshotTheme dark  -initialTab 0 -screenshotScroll plates
