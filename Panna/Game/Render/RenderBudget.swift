import UIKit
import SceneKit

/// Keeps phones cool: caps render resolution, and steps quality down when the device heats up or is in Low Power Mode.
enum RenderBudget {
    /// Draw at most 2x pixel density (3x phones render 56% fewer pixels; with MSAA it reads the same at arm's length).
    static var scale: CGFloat { min(UIScreen.main.scale, 2.0) }

    /// Hot device or Low Power Mode: halve the frame rate and drop the glow.
    static private(set) var constrained: Bool = check()
    private static func check() -> Bool {
        let t = ProcessInfo.processInfo.thermalState
        return t == .serious || t == .critical || ProcessInfo.processInfo.isLowPowerModeEnabled
    }

    static func configure(_ v: SCNView, fps: Int) {
        v.contentScaleFactor = scale
        v.preferredFramesPerSecond = constrained ? min(fps, 30) : fps
    }

    /// Re-applies the budget whenever thermal state or Low Power Mode changes (match and menus).
    static func observe(_ v: SCNView, fps: Int, camera: SCNCamera? = nil, bloom: CGFloat = 0) -> [NSObjectProtocol] {
        let apply = { [weak v] in
            guard let v else { return }
            constrained = check()
            configure(v, fps: fps)
            if let camera { camera.bloomIntensity = constrained ? 0 : bloom }
        }
        apply()
        let c = NotificationCenter.default
        return [ProcessInfo.thermalStateDidChangeNotification, Notification.Name.NSProcessInfoPowerStateDidChange].map {
            c.addObserver(forName: $0, object: nil, queue: .main) { _ in apply() }
        }
    }
}
