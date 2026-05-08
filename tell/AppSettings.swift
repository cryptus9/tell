import Carbon
import CoreGraphics
import Observation

@Observable
final class AppSettings {
    var hotkeyKeyCode: Int = kVK_Space {
        didSet { UserDefaults.standard.set(hotkeyKeyCode, forKey: "hotkeyKeyCode") }
    }
    var hotkeyModifiers: Int = Int(CGEventFlags.maskAlternate.rawValue) {
        didSet { UserDefaults.standard.set(hotkeyModifiers, forKey: "hotkeyModifiers") }
    }
    var modelSource: String = "hf:openai_whisper-base" {
        didSet { UserDefaults.standard.set(modelSource, forKey: "modelSource") }
    }

    init() {
        let d = UserDefaults.standard
        if let v = d.object(forKey: "hotkeyKeyCode") as? Int { hotkeyKeyCode = v }
        if let v = d.object(forKey: "hotkeyModifiers") as? Int { hotkeyModifiers = v }
        if let v = d.string(forKey: "modelSource") { modelSource = v }
    }
}
