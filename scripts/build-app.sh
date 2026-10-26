#!/bin/zsh
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="Claude Narrator.app"
APP_DIR="$PROJECT_ROOT/dist/$APP_NAME"
EXPECTED_APP_DIR="$PROJECT_ROOT/dist/Claude Narrator.app"

if [[ "$APP_DIR" != "$EXPECTED_APP_DIR" ]]; then
  print -u2 "Unexpected app path: $APP_DIR"
  exit 1
fi

swift build -c release --package-path "$PROJECT_ROOT"

if [[ -e "$APP_DIR" ]]; then
  rm -rf "$APP_DIR"
fi
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
cp "$PROJECT_ROOT/.build/release/ClaudeNarrator" "$APP_DIR/Contents/MacOS/ClaudeNarrator"
cp "$PROJECT_ROOT/Resources/Info.plist" "$APP_DIR/Contents/Info.plist"
cp "$PROJECT_ROOT/Resources/AppIcon.icns" "$APP_DIR/Contents/Resources/AppIcon.icns"
codesign --force --deep --sign - "$APP_DIR"

print "$APP_DIR"
