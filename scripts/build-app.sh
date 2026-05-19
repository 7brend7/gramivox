#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="GramiVox"
BUILD_DIR="$ROOT_DIR/.build/debug"
DIST_DIR="$ROOT_DIR/dist"
APP_DIR="$DIST_DIR/$APP_NAME.app"
ICONSET_DIR="$DIST_DIR/AppIcon.iconset"
ICON_PNG="$DIST_DIR/AppIcon1024.png"

mkdir -p "$DIST_DIR"

swift build

rm -rf "$APP_DIR" "$ICONSET_DIR" "$ICON_PNG"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources" "$ICONSET_DIR"

cp "$BUILD_DIR/$APP_NAME" "$APP_DIR/Contents/MacOS/$APP_NAME"
cp "$ROOT_DIR/Resources/Info.plist" "$APP_DIR/Contents/Info.plist"

swift -e '
import AppKit

let size = NSSize(width: 1024, height: 1024)
let image = NSImage(size: size)
image.lockFocus()

let rect = NSRect(origin: .zero, size: size)
NSColor(calibratedRed: 0.10, green: 0.44, blue: 0.96, alpha: 1.0).setFill()
NSBezierPath(roundedRect: rect.insetBy(dx: 56, dy: 56), xRadius: 220, yRadius: 220).fill()

let bubbleRect = NSRect(x: 180, y: 240, width: 664, height: 520)
NSColor.white.setFill()
NSBezierPath(roundedRect: bubbleRect, xRadius: 150, yRadius: 150).fill()

let tail = NSBezierPath()
tail.move(to: NSPoint(x: 320, y: 240))
tail.line(to: NSPoint(x: 245, y: 130))
tail.line(to: NSPoint(x: 410, y: 230))
tail.close()
tail.fill()

let attrs: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: 250, weight: .bold),
    .foregroundColor: NSColor(calibratedRed: 0.10, green: 0.18, blue: 0.35, alpha: 1.0)
]
let text = NSString(string: "Aa")
let textSize = text.size(withAttributes: attrs)
let textRect = NSRect(
    x: bubbleRect.midX - textSize.width / 2,
    y: bubbleRect.midY - textSize.height / 2 + 12,
    width: textSize.width,
    height: textSize.height
)
text.draw(in: textRect, withAttributes: attrs)

image.unlockFocus()

guard
    let tiff = image.tiffRepresentation,
    let rep = NSBitmapImageRep(data: tiff),
    let png = rep.representation(using: .png, properties: [:])
else {
    fatalError("Failed to render icon")
}

try png.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
' "$ICON_PNG"

for size in 16 32 128 256 512; do
  sips -z "$size" "$size" "$ICON_PNG" --out "$ICONSET_DIR/icon_${size}x${size}.png" >/dev/null
  doubled=$(( size * 2 ))
  sips -z "$doubled" "$doubled" "$ICON_PNG" --out "$ICONSET_DIR/icon_${size}x${size}@2x.png" >/dev/null
done

iconutil -c icns "$ICONSET_DIR" -o "$APP_DIR/Contents/Resources/AppIcon.icns"
rm -rf "$ICONSET_DIR" "$ICON_PNG"

codesign --force --deep --sign - "$APP_DIR"

echo "Built $APP_DIR"
