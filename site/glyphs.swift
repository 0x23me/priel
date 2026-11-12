// Prints the channel from mac/Resources/AppIcon.png as rows of brightness levels (0 blank, 1 to 8),
// one character per cell, cells 1.85 times as tall as wide, for the page's glyph picture.
//   swift glyphs.swift COLS ROWS > channel.txt
import AppKit

let cols = Int(CommandLine.arguments[1])!, rows = Int(CommandLine.arguments[2])!
let icon = NSImage(contentsOfFile: "../mac/Resources/AppIcon.png")!
let rep = NSBitmapImageRep(data: icon.tiffRepresentation!)!
// The icon's rounded square spans 100 to 924 of 1024; stay inside its corners.
let x0 = 150.0, y0 = 150.0, w = 724.0, h = 724.0
for r in 0..<rows {
    var line = ""
    for c in 0..<cols {
        let x = Int(x0 + (Double(c) + 0.5) * w / Double(cols)), y = Int(y0 + (Double(r) + 0.5) * h / Double(rows))
        let p = rep.colorAt(x: x, y: y)!.usingColorSpace(.sRGB)!
        // Water is bluer than it is red, and its lightness sets the level (the dark banks low, the
        // light middle high); the darker sand along the banks is the dimmest level; the flats stay blank.
        let blue = p.blueComponent - p.redComponent
        if blue > 0.15 {
            line += String(min(8, max(2, 2 + Int((p.brightnessComponent - 0.55) / 0.3 * 6))))
        } else if p.redComponent - p.blueComponent > 0.25 && p.brightnessComponent < 0.8 {
            line += "2"
        } else {
            // The flats: a sparse, steady scatter of the dimmest glyphs, the same on every run.
            var x = UInt32(truncatingIfNeeded: r &* 73_856_093 ^ c &* 19_349_663); x ^= x >> 13; x &*= 0x5bd1_e995; x ^= x >> 15
            line += x % 100 < 20 ? "1" : "0"
        }
    }
    print(line)
}
