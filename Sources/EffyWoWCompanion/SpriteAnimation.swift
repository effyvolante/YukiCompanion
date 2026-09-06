import AppKit
import SwiftUI

@MainActor final class SpriteAnimationController: ObservableObject {
    @Published private(set) var image: NSImage?
    private var timer: Timer?
    private var frames: [NSImage] = []
    private var index = 0
    private var state: PetState = .idle
    func set(_ state: PetState) {
        guard self.state != state || frames.isEmpty else { return }
        self.state = state; timer?.invalidate(); index = 0
        let packaged = Bundle.main.url(forResource: "EffyWoWCompanion_EffyWoWCompanion", withExtension: "bundle").flatMap(Bundle.init(url:))
        let assets = packaged ?? Bundle.module
        frames = (0..<state.frameCount).compactMap { i in assets.image(named: "\(state.filePrefix)_\(String(format: "%03d", i))") }
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

private extension Bundle { func image(named path: String) -> NSImage? { url(forResource: path, withExtension: "png").flatMap(NSImage.init(contentsOf:)) } }
private extension PetState {
    var folder: String { switch self { case .idle,.ready: "Idle"; case .capturing: "Thinking"; case .opening,.waiting: "Thinking"; case .replying: "Replying"; case .clicked: "Click"; case .error: "Error" } }
    var filePrefix: String { switch self { case .idle,.ready: "idle"; case .capturing,.opening,.waiting: "thinking"; case .replying: "replying"; case .clicked: "click"; case .error: "error" } }
    var frameCount: Int { switch self { case .idle,.ready: 7; case .capturing,.opening,.waiting: 10; case .replying: 7; case .clicked: 8; case .error: 8 } }
    func duration(at index: Int) -> TimeInterval {
        let values: [TimeInterval]
        switch self {
        case .idle,.ready: values = [0.55,0.75,0.55,0.70,0.55,0.65,0.95]
        case .capturing,.opening,.waiting: values = Array(repeating: 0.34, count: 10)
        case .replying: values = [0.42,0.55,0.42,0.60,0.42,0.55,0.75]
        case .clicked: values = [0.09,0.08,0.09,0.11,0.13,0.15,0.20,0.30]
        case .error: values = [0.45,0.55,0.40,0.55,0.60,0.70,0.55,0.80]
        }
        return values[index % values.count]
    }
}
