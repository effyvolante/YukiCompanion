import AppKit
import SwiftUI

@MainActor final class SpriteAnimationController: ObservableObject {
    @Published private(set) var image: NSImage?
    private var timer: Timer?
    private var frames: [NSImage] = []
    private var index = 0
    private var state: PetState = .idle
    private var themeID = "Yuki"
    func set(_ state: PetState, themeID: String = "Yuki") {
        guard self.state != state || self.themeID != themeID || frames.isEmpty else { return }
        self.state = state; timer?.invalidate(); index = 0
        self.themeID = themeID
        let packaged = Bundle.main.url(forResource: "EffyWoWCompanion_EffyWoWCompanion", withExtension: "bundle").flatMap(Bundle.init(url:))
        let assets = packaged ?? Bundle.module
        let theme = CompanionTheme.resolve(themeID)
        frames = (0..<state.frameCount).compactMap { i in
            let sourceIndex = state == .rareIdleB ? max(0, state.frameCount - i - 1) : i
            return assets.image(named: "\(theme.id.lowercased())_\(state.filePrefix)_\(String(format: "%03d", sourceIndex))")
        }
        if frames.isEmpty, theme.id == "Yuki" {
            frames = (0..<state.legacyFrameCount).compactMap { i in assets.image(named: "\(state.legacyPrefix)_\(String(format: "%03d", i))") }
        }
        image = frames.first
        guard frames.count > 1 else { return }; scheduleNextFrame()
    }
    private func scheduleNextFrame() {
        timer = Timer.scheduledTimer(withTimeInterval: state.duration(at: index), repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                index = (index + 1) % frames.count
                image = frames[index]
                scheduleNextFrame()
            }
        }
    }
}

private extension Bundle {
    func image(named path: String, subdirectory: String? = nil) -> NSImage? {
        url(forResource: path, withExtension: "png", subdirectory: subdirectory).flatMap(NSImage.init(contentsOf:))
    }
}
private extension PetState {
    var animationKey: String { switch self { case .idle,.ready: "idle"; case .clicked: "click"; case .capturing: "look"; case .opening,.waiting: "thinking"; case .replying: "replying"; case .error: "error"; case .hover: "hover"; case .look: "look"; case .answerStart: "answerStart"; case .answerComplete: "answerComplete"; case .rareIdleA: "rareIdleA"; case .rareIdleB: "rareIdleB" } }
    var filePrefix: String { switch self { case .idle,.ready: "idle"; case .capturing,.look,.hover: "look"; case .opening,.waiting: "thinking"; case .replying: "replying"; case .clicked: "click"; case .error: "error"; case .answerStart: "answerstart"; case .answerComplete: "answercomplete"; case .rareIdleA,.rareIdleB: "rareidle" } }
    var frameCount: Int { 8 }
    var legacyPrefix: String { switch self { case .idle,.ready: "idle"; case .capturing,.opening,.waiting: "thinking"; case .replying: "replying"; case .clicked: "click"; case .error: "error"; default: "idle" } }
    var legacyFrameCount: Int { switch self { case .idle,.ready: 7; case .capturing,.opening,.waiting: 10; case .replying: 7; case .clicked: 8; case .error: 8; default: 7 } }
    func duration(at index: Int) -> TimeInterval {
        let values: [TimeInterval]
        switch self {
        case .idle,.ready: values = [0.55,0.75,0.55,0.70,0.55,0.65,0.80,0.95]
        case .capturing,.opening,.waiting: values = Array(repeating: 0.28, count: 8)
        case .replying: values = [0.42,0.55,0.42,0.60,0.42,0.55,0.65,0.75]
        case .clicked: values = [0.09,0.08,0.09,0.11,0.13,0.15,0.20,0.30]
        case .error: values = [0.45,0.55,0.40,0.55,0.60,0.70,0.55,0.80]
        case .hover,.look,.answerStart,.answerComplete,.rareIdleA,.rareIdleB: values = Array(repeating: 0.22, count: 8)
        }
        return values[index % values.count]
    }
}
