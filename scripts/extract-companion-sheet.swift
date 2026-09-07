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
let cellWidth = (CGFloat(width) - leftInset) / CGFloat(columns)
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
        guard distance < 130, saturation < 0.06 || (nearCropEdge && saturation < 0.18) else { continue }
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
            if maximum > 0.65 && (maximum - minimum) / maximum < 0.25 { neutralCount += 1 }
        }
        guard neutralCount > image.width / 4 else { continue }
        for x in 0..<image.width {
            let index = (y * image.width + x) * 4
            let r = Double(data[index]) / 255
            let g = Double(data[index + 1]) / 255
            let b = Double(data[index + 2]) / 255
            let maximum = max(r, max(g, b))
            let minimum = min(r, min(g, b))
            if maximum > 0.65 && (maximum - minimum) / maximum < 0.25 { data[index + 3] = 0 }
        }
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
    let output = rgbaContext(width: image.width, height: image.height)
    output.data?.copyMemory(from: data, byteCount: pixelCount * 4)
    return output.makeImage()!
}

func writeFrame(_ image: CGImage, to url: URL) {
    let canvas = rgbaContext(width: 512, height: 512)
    let scale = min(480.0 / CGFloat(image.width), 480.0 / CGFloat(image.height))
    let drawWidth = CGFloat(image.width) * scale
    let drawHeight = CGFloat(image.height) * scale
    canvas.draw(image, in: CGRect(x: (512 - drawWidth) / 2, y: (512 - drawHeight) / 2, width: drawWidth, height: drawHeight))
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
        let centerX = leftInset + cellWidth * (CGFloat(column) + 0.5) - 10
        let centerY = topInset + cellHeight * (CGFloat(row) + 0.5) + (height > 800 ? 16 : 2)
        let crop = CGRect(x: max(0, centerX - cropWidth / 2), y: max(0, centerY - cropHeight / 2), width: cropWidth, height: cropHeight)
        let frame = transparent(sourceCG.cropping(to: crop)!)
        writeFrame(frame, to: folderURL.appendingPathComponent("\(assetPrefix)_\(prefix)\(String(format: "%03d", column)).png"))
    }
}
