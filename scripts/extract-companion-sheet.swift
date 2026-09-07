import AppKit
import Foundation
import ImageIO
import UniformTypeIdentifiers

struct ThemeSpec {
    let id: String
    let source: String
}

let arguments = CommandLine.arguments
guard arguments.count == 4, let topInset = Double(arguments[3]) else {
    fputs("usage: extract-companion-sheet.swift <source.jpg> <output-directory> <top-inset-pixels>\n", stderr)
    exit(2)
}

let sourceURL = URL(fileURLWithPath: arguments[1])
let outputURL = URL(fileURLWithPath: arguments[2], isDirectory: true)
let assetPrefix = outputURL.lastPathComponent.lowercased()
let paleArtworkThreshold = assetPrefix == "belle" ? 0.03 : 0.06
let edgeArtworkThreshold = assetPrefix == "belle" ? 0.04 : 0.18
let sourceImage = NSImage(contentsOf: sourceURL)!
var sourceRect = NSRect(origin: .zero, size: sourceImage.size)
let sourceRep = NSBitmapImageRep(data: sourceImage.tiffRepresentation!)!
let sourceCG = sourceRep.cgImage!
let width = sourceCG.width
let height = sourceCG.height
let columns = 8
let rows = 9
let leftInset = CGFloat(width) * 0.109
let topInset = CGFloat(topInset)
let rightInset = assetPrefix == "belle" ? 100.0 : 0.0
let cellWidth = (CGFloat(width) - leftInset - rightInset) / CGFloat(columns)
let cellHeight = (CGFloat(height) - topInset - CGFloat(height) * 0.025) / CGFloat(rows)
// Keep each crop inside its row so neighboring review-sheet rows never become
// runtime frames. The source sheets already leave enough room for the action
// marks inside the row itself.
let cropWidth = min(118.0, cellWidth - 12.0)
// Keep the crop inside the illustrated row so review-sheet dividers cannot
// become runtime pixels.
let rowInset = height > 800 ? -12.0 : 10.0
let cropHeight = max(56.0, min(104.0, cellHeight - rowInset))

func rgbaContext(width: Int, height: Int) -> CGContext {
    CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
              space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
}

func transparent(_ image: CGImage) -> CGImage {
    let context = rgbaContext(width: image.width, height: image.height)
    context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
    guard let data = context.data?.assumingMemoryBound(to: UInt8.self) else { return image }
    let pixelCount = image.width * image.height
    let background = SIMD3<Int>(Int(data[0]), Int(data[1]), Int(data[2]))
    var visited = Array(repeating: false, count: pixelCount)
    var queue: [(Int, Int)] = []
    func enqueue(_ x: Int, _ y: Int) {
        guard x >= 0, y >= 0, x < image.width, y < image.height else { return }
        let index = y * image.width + x
        guard !visited[index] else { return }
        visited[index] = true
        queue.append((x, y))
    }
    for x in 0..<image.width { enqueue(x, 0); enqueue(x, image.height - 1) }
    for y in 0..<image.height { enqueue(0, y); enqueue(image.width - 1, y) }
    var cursor = 0
    while cursor < queue.count {
        let (x, y) = queue[cursor]; cursor += 1
        let index = (y * image.width + x) * 4
        let color = SIMD3<Int>(Int(data[index]), Int(data[index + 1]), Int(data[index + 2]))
        let distance = abs(color.x - background.x) + abs(color.y - background.y) + abs(color.z - background.z)
        let maximum = max(color.x, max(color.y, color.z))
        let minimum = min(color.x, min(color.y, color.z))
        let saturation = maximum > 0 ? Double(maximum - minimum) / Double(maximum) : 0
        // Remove only connected, near-neutral sheet background/halo pixels.
        // This preserves pale companion fills and Yuki's white highlights.
        let nearCropEdge = x <= 10 || x >= image.width - 11 || y <= 10 || y >= image.height - 11
        guard distance < 130, saturation < paleArtworkThreshold || (nearCropEdge && saturation < edgeArtworkThreshold) else { continue }
        data[index + 3] = 0
        enqueue(x - 1, y); enqueue(x + 1, y); enqueue(x, y - 1); enqueue(x, y + 1)
    }
    // Some sheets draw tinted dividers inside the crop rather than touching
    // its edge. Remove only long, near-neutral rows at the crop boundaries;
    // this cannot affect expressive marks or the companion silhouette.
    for y in 0..<image.height {
        guard y < 18 || y >= image.height - 18 else { continue }
        var neutralCount = 0
        for x in 0..<image.width {
            let index = (y * image.width + x) * 4
            let r = Double(data[index]) / 255
            let g = Double(data[index + 1]) / 255
            let b = Double(data[index + 2]) / 255
            let maximum = max(r, max(g, b))
            let minimum = min(r, min(g, b))
            if data[index + 3] > 0 && maximum > 0.65 && (maximum - minimum) / maximum < 0.25 { neutralCount += 1 }
        }
        guard neutralCount > image.width / 4 else { continue }
        for x in 0..<image.width {
            let index = (y * image.width + x) * 4
            let r = Double(data[index]) / 255
            let g = Double(data[index + 1]) / 255
            let b = Double(data[index + 2]) / 255
            let maximum = max(r, max(g, b))
            let minimum = min(r, min(g, b))
            if data[index + 3] > 0 && maximum > 0.65 && (maximum - minimum) / maximum < 0.25 { data[index + 3] = 0 }
        }
    }
    // Clear long divider runs that sit just inside the crop boundary.
    for y in 0..<image.height where y < 12 || y >= image.height - 12 {
        var count = 0
        for x in 0..<image.width {
            let index = (y * image.width + x) * 4
            let r = Double(data[index]) / 255, g = Double(data[index + 1]) / 255, b = Double(data[index + 2]) / 255
            let maximum = max(r, max(g, b)), minimum = min(r, min(g, b))
            if data[index + 3] > 0 && maximum > 0.65 && (maximum - minimum) / maximum < 0.25 { count += 1 }
        }
        if count > image.width / 3 { for x in 0..<image.width { data[(y * image.width + x) * 4 + 3] = 0 } }
    }
    for x in 0..<image.width where x < 12 || x >= image.width - 12 {
        var count = 0
        for y in 0..<image.height {
            let index = (y * image.width + x) * 4
            let r = Double(data[index]) / 255, g = Double(data[index + 1]) / 255, b = Double(data[index + 2]) / 255
            let maximum = max(r, max(g, b)), minimum = min(r, min(g, b))
            if data[index + 3] > 0 && maximum > 0.65 && (maximum - minimum) / maximum < 0.25 { count += 1 }
        }
        if count > image.height / 3 { for y in 0..<image.height { data[(y * image.width + x) * 4 + 3] = 0 } }
    }
    var visitedComponents = Array(repeating: false, count: pixelCount)
    for y in 0..<image.height {
        for x in 0..<image.width {
            let start = y * image.width + x
            guard !visitedComponents[start], data[start * 4 + 3] > 0 else { continue }
            var component: [(Int, Int)] = []
            var queue = [(x, y)]
            visitedComponents[start] = true
            var cursor = 0
            var touchesVerticalEdge = false
            while cursor < queue.count {
                let (cx, cy) = queue[cursor]; cursor += 1
                component.append((cx, cy))
                if cy == 0 || cy == image.height - 1 { touchesVerticalEdge = true }
                for (nx, ny) in [(cx - 1, cy), (cx + 1, cy), (cx, cy - 1), (cx, cy + 1)] {
                    guard nx >= 0, nx < image.width, ny >= 0, ny < image.height else { continue }
                    let next = ny * image.width + nx
                    guard !visitedComponents[next], data[next * 4 + 3] > 0 else { continue }
                    visitedComponents[next] = true
                    queue.append((nx, ny))
                }
            }
            // Neighboring-row fragments are small and touch the crop edge.
            // Keep any substantial component so a companion can never be
            // accidentally removed by this cleanup.
            if touchesVerticalEdge && component.count < 2000 {
                for (px, py) in component { data[(py * image.width + px) * 4 + 3] = 0 }
            }
        }
    }
    // JPEG resampling can leave a near-white fringe attached to a dark
    // outline. Remove only neutral pixels directly exposed to transparency;
    // enclosed white highlights remain intact.
    for y in 1..<(image.height - 1) {
        for x in 1..<(image.width - 1) {
            let index = (y * image.width + x) * 4
            guard data[index + 3] > 0 else { continue }
            let r = Double(data[index]) / 255
            let g = Double(data[index + 1]) / 255
            let b = Double(data[index + 2]) / 255
            let maximum = max(r, max(g, b))
            let minimum = min(r, min(g, b))
            guard maximum > 0.72, (maximum - minimum) / maximum < 0.06 else { continue }
            let neighbors = [(x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1)]
            if neighbors.contains(where: { data[($0.1 * image.width + $0.0) * 4 + 3] == 0 }) {
                data[index + 3] = 0
            }
        }
    }
    let output = rgbaContext(width: image.width, height: image.height)
    output.data?.copyMemory(from: data, byteCount: pixelCount * 4)
    return output.makeImage()!
}

func largestComponentBounds(_ image: CGImage) -> CGRect? {
    let context = rgbaContext(width: image.width, height: image.height)
    context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
    let data = context.data!.assumingMemoryBound(to: UInt8.self)
    var visited = Array(repeating: false, count: image.width * image.height)
    var best: [(Int, Int)] = []
    for y in 0..<image.height {
        for x in 0..<image.width {
            let start = y * image.width + x
            guard !visited[start], data[start * 4 + 3] > 20 else { continue }
            var queue = [(x, y)], component: [(Int, Int)] = []
            visited[start] = true
            var cursor = 0
            while cursor < queue.count {
                let point = queue[cursor]; cursor += 1
                component.append(point)
                for neighbor in [(point.0 - 1, point.1), (point.0 + 1, point.1), (point.0, point.1 - 1), (point.0, point.1 + 1)] {
                    guard neighbor.0 >= 0, neighbor.0 < image.width, neighbor.1 >= 0, neighbor.1 < image.height else { continue }
                    let index = neighbor.1 * image.width + neighbor.0
                    guard !visited[index], data[index * 4 + 3] > 20 else { continue }
                    visited[index] = true
                    queue.append(neighbor)
                }
            }
            if component.count > best.count { best = component }
        }
    }
    guard !best.isEmpty else { return nil }
    let xs = best.map(\.0), ys = best.map(\.1)
    return CGRect(x: xs.min()!, y: ys.min()!, width: xs.max()! - xs.min()! + 1, height: ys.max()! - ys.min()! + 1)
}

func writeFrame(_ image: CGImage, to url: URL) {
    let canvas = rgbaContext(width: 512, height: 512)
    let scale = min(480.0 / CGFloat(image.width), 480.0 / CGFloat(image.height))
    let drawWidth = CGFloat(image.width) * scale
    let drawHeight = CGFloat(image.height) * scale
    // Use the largest visual mass as the anchor. The source sheets are
    // hand-laid-out, so action marks and pose shifts must not move the body.
    // The fixed crop still guarantees a stable scale across every frame.
    let bounds = largestComponentBounds(image)
    let anchorX = bounds?.midX ?? CGFloat(image.width) / 2
    let anchorY = bounds?.midY ?? CGFloat(image.height) / 2
    let drawOrigin = CGPoint(x: 256 - anchorX * scale, y: 270 - anchorY * scale)
    canvas.draw(image, in: CGRect(x: drawOrigin.x, y: drawOrigin.y, width: drawWidth, height: drawHeight))
    // Keep isolated source-sheet remnants from touching the runtime canvas.
    if let data = canvas.data?.assumingMemoryBound(to: UInt8.self) {
        for y in 0..<512 {
            for x in 0..<512 where x < 6 || x >= 506 || y < 6 || y >= 506 {
                data[(y * 512 + x) * 4 + 3] = 0
            }
        }
    }
    let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(destination, canvas.makeImage()!, nil)
    CGImageDestinationFinalize(destination)
}

try! FileManager.default.createDirectory(at: outputURL, withIntermediateDirectories: true)
for row in 0..<rows {
    let folder = ["Idle", "Click", "Thinking", "Replying", "AnswerStart", "AnswerComplete", "Error", "Look", "RareIdle"][row]
    let prefix = ["idle_", "click_", "thinking_", "replying_", "answerstart_", "answercomplete_", "error_", "look_", "rareidle_"][row]
    let folderURL = outputURL.appendingPathComponent(folder, isDirectory: true)
    try! FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
    for column in 0..<columns {
        let columnOffset: CGFloat = assetPrefix == "belle" ? 15 : -10
        let centerX = leftInset + cellWidth * (CGFloat(column) + 0.5) + columnOffset
        let centerY = topInset + cellHeight * (CGFloat(row) + 0.5) + (height > 800 ? 6 : 2)
        let crop = CGRect(x: max(0, centerX - cropWidth / 2), y: max(0, centerY - cropHeight / 2), width: cropWidth, height: cropHeight)
        let frame = transparent(sourceCG.cropping(to: crop)!)
        writeFrame(frame, to: folderURL.appendingPathComponent("\(assetPrefix)_\(prefix)\(String(format: "%03d", column)).png"))
    }
}
