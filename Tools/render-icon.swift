#!/usr/bin/env swift
// Renders Traqula's icon assets from code so the mascot can be tweaked and regenerated:
//   swift Tools/render-icon.swift
//
// The mascot is a rounded-square speech bubble with two pill eyes; the bubble's tail is a single fang.

import AppKit
import CoreGraphics
import UniformTypeIdentifiers

let assets = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "Traqula/Resources/Assets.xcassets")

// MARK: - Mascot geometry (100 × 100 design box, y grows downward)

let bubble = CGRect(x: 8, y: 8, width: 84, height: 68)
let bubbleCornerRadius: CGFloat = 20
let eyeSize = CGSize(width: 16, height: 22)
let eyeCenters: [CGPoint] = [CGPoint(x: 38, y: 43), CGPoint(x: 62, y: 43)]

/// The bubble and its fang are one continuous outline, so nothing overlaps and no seam can show.
func mascotBody() -> CGMutablePath {
    let r = bubbleCornerRadius
    let (left, top, right, bottom) = (bubble.minX, bubble.minY, bubble.maxX, bubble.maxY)
    // The fang must start past the bottom-left corner arc (x ≥ left + r), or the arc cannot fit and leaves a kink.
    let fangBase = (left: CGFloat(30), right: CGFloat(48))
    let fangTip = CGPoint(x: 40, y: 93)

    let path = CGMutablePath()
    path.move(to: CGPoint(x: left + r, y: top))
    path.addArc(tangent1End: CGPoint(x: right, y: top), tangent2End: CGPoint(x: right, y: bottom), radius: r)
    path.addArc(tangent1End: CGPoint(x: right, y: bottom), tangent2End: CGPoint(x: left, y: bottom), radius: r)
    // Along the bottom edge, the outline dips into a curved fang: a convex outer edge and a hollowed inner edge,
    // like a canine tooth, hooking slightly toward the center.
    path.addLine(to: CGPoint(x: fangBase.right, y: bottom))
    path.addCurve(to: fangTip, control1: CGPoint(x: 44, y: 82), control2: CGPoint(x: 41, y: 89))
    path.addCurve(to: CGPoint(x: fangBase.left, y: bottom), control1: CGPoint(x: 36, y: 93), control2: CGPoint(x: 30, y: 87))
    path.addArc(tangent1End: CGPoint(x: left, y: bottom), tangent2End: CGPoint(x: left, y: top), radius: r)
    path.addArc(tangent1End: CGPoint(x: left, y: top), tangent2End: CGPoint(x: right, y: top), radius: r)
    path.closeSubpath()
    return path
}

/// Eyes are soft ovals: a little taller than wide, with fully rounded ends, so they never read as a pause button.
/// `emphasis` scales them (width, height) for tiny renderings, where the design-size eyes would be too thin to read.
func mascotEyes(emphasis: CGSize = CGSize(width: 1, height: 1)) -> CGMutablePath {
    let size = CGSize(width: eyeSize.width * emphasis.width, height: eyeSize.height * emphasis.height)
    let path = CGMutablePath()
    for center in eyeCenters {
        let rect = CGRect(x: center.x - size.width / 2, y: center.y - size.height / 2, width: size.width, height: size.height)
        let radius = min(size.width, size.height) * 0.5
        path.addRoundedRect(in: rect, cornerWidth: radius, cornerHeight: radius)
    }
    return path
}

/// Draws the mascot into `frame` (a square, in the receiver's current coordinate system, y downward).
func drawMascot(in context: CGContext, frame: CGRect, body: CGColor, eyes: CGColor?, eyeEmphasis: CGSize = CGSize(width: 1, height: 1)) {
    context.saveGState()
    context.translateBy(x: frame.minX, y: frame.minY)
    context.scaleBy(x: frame.width / 100, y: frame.height / 100)
    if let eyes {
        context.setFillColor(body)
        context.addPath(mascotBody())
        context.fillPath()
        context.setFillColor(eyes)
        context.addPath(mascotEyes(emphasis: eyeEmphasis))
        context.fillPath()
    } else {
        // Template glyph: eyes are cut out so the menu bar shows through them.
        context.setFillColor(body)
        context.addPath(mascotBody())
        context.addPath(mascotEyes(emphasis: eyeEmphasis))
        context.fillPath(using: .evenOdd)
    }
    context.restoreGState()
}

// MARK: - Rendering helpers

func makeContext(size: Int) -> CGContext {
    let context = CGContext(
        data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    // Flip so the design math can use y-down coordinates.
    context.translateBy(x: 0, y: CGFloat(size))
    context.scaleBy(x: 1, y: -1)
    return context
}

func writePNG(_ context: CGContext, to url: URL) {
    let image = context.makeImage()!
    let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(destination, image, nil)
    CGImageDestinationFinalize(destination)
}

func color(_ hex: UInt32, alpha: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

func writeJSON(_ object: Any, to url: URL) throws {
    try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]).write(to: url)
}

// MARK: - App icon

func drawAppIcon(size: Int) -> CGContext {
    let context = makeContext(size: size)
    let scale = CGFloat(size) / 1024
    context.scaleBy(x: scale, y: scale)

    // macOS icon plate: an 824 pt rounded square centered on the 1024 pt canvas.
    let plate = CGRect(x: 100, y: 100, width: 824, height: 824)
    let platePath = CGPath(roundedRect: plate, cornerWidth: 185, cornerHeight: 185, transform: nil)
    context.saveGState()
    context.addPath(platePath)
    context.clip()
    let gradient = CGGradient(
        colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
        colors: [color(0xD6F0FF), color(0x8CCBFF), color(0x4A90E2)] as CFArray,
        locations: [0, 0.55, 1]
    )!
    context.drawLinearGradient(gradient, start: CGPoint(x: plate.minX, y: plate.minY), end: CGPoint(x: plate.maxX, y: plate.maxY), options: [])
    context.restoreGState()

    // Soft shadow under the mascot, then the mascot itself.
    let mascotFrame = CGRect(x: 232, y: 206, width: 560, height: 560)
    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -14 ), blur: 36, color: color(0x1E3A8A, alpha: 0.4))
    drawMascot(in: context, frame: mascotFrame, body: color(0xFFFFFF), eyes: nil)
    context.restoreGState()
    drawMascot(in: context, frame: mascotFrame, body: color(0xFFFFFF), eyes: color(0x14213D))
    return context
}

let appIconSet = assets.appending(path: "AppIcon.appiconset")
try FileManager.default.createDirectory(at: appIconSet, withIntermediateDirectories: true)
var appIconImages: [[String: String]] = []
for (points, scales) in [(16, [1, 2]), (32, [1, 2]), (128, [1, 2]), (256, [1, 2]), (512, [1, 2])] {
    for scale in scales {
        let filename = "icon_\(points)x\(points)@\(scale)x.png"
        writePNG(drawAppIcon(size: points * scale), to: appIconSet.appending(path: filename))
        appIconImages.append(["filename": filename, "idiom": "mac", "scale": "\(scale)x", "size": "\(points)x\(points)"])
    }
}
try writeJSON(["images": appIconImages, "info": ["author": "xcode", "version": 1]], to: appIconSet.appending(path: "Contents.json"))

// MARK: - Menu bar glyph (template silhouette with the eyes cut out)

let imageSet = assets.appending(path: "MenuBarIcon.imageset")
try FileManager.default.createDirectory(at: imageSet, withIntermediateDirectories: true)
var menuBarImages: [[String: String]] = []
for scale in [1, 2, 3] {
    let points = 18
    let size = points * scale
    let context = makeContext(size: size)
    // Taller, slightly wider eyes so the cut-outs read at menu bar size.
    drawMascot(in: context, frame: CGRect(x: 0, y: 0, width: size, height: size), body: color(0x000000), eyes: nil,
               eyeEmphasis: CGSize(width: 1.15, height: 1.15))
    let filename = "MenuBarIcon@\(scale)x.png"
    writePNG(context, to: imageSet.appending(path: filename))
    menuBarImages.append(["filename": filename, "idiom": "universal", "scale": "\(scale)x"])
}
try writeJSON([
    "images": menuBarImages,
    "info": ["author": "xcode", "version": 1],
    "properties": ["template-rendering-intent": "template"],
], to: imageSet.appending(path: "Contents.json"))

try writeJSON(["info": ["author": "xcode", "version": 1]], to: assets.appending(path: "Contents.json"))

// MARK: - README logo

let docsImages = assets.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appending(path: "docs/images")
try FileManager.default.createDirectory(at: docsImages, withIntermediateDirectories: true)
writePNG(drawAppIcon(size: 512), to: docsImages.appending(path: "logo.png"))
print("Rendered icons into \(assets.path)")
