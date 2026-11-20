import Foundation
import ObjectiveC

/// Built-in keyboard backlight control through CoreBrightness' private
/// `KeyboardBrightnessClient`. macOS has no public API for this, so everything
/// is looked up at runtime: if any piece is missing, `shared` is nil and the
/// caller falls back to something else instead of crashing.
public final class KeyboardBacklightController {
    public static let shared: KeyboardBacklightController? = KeyboardBacklightController()

    private typealias CopyIDsFn = @convention(c) (NSObject, Selector) -> Unmanaged<AnyObject>
    private typealias IsBuiltInFn = @convention(c) (NSObject, Selector, UInt64) -> ObjCBool
    private typealias GetFn = @convention(c) (NSObject, Selector, UInt64) -> Float
    private typealias SetFn = @convention(c) (NSObject, Selector, Float, Int32, Bool, UInt64) -> ObjCBool

    private let client: NSObject
    private let keyboardID: UInt64
    private let getBrightness: GetFn
    private let setBrightness: SetFn
    private let getSelector = NSSelectorFromString("brightnessForKeyboard:")
    private let setSelector = NSSelectorFromString("setBrightness:fadeSpeed:commit:forKeyboard:")

    /// The level to come back to when switching on again.
    private var lastOnLevel: Float = 0.5

    private init?() {
        guard
            let framework = Bundle(path: "/System/Library/PrivateFrameworks/CoreBrightness.framework"),
            framework.load(),
            let clientClass = NSClassFromString("KeyboardBrightnessClient") as? NSObject.Type
        else { return nil }

        let client = clientClass.init()
        let copySelector = NSSelectorFromString("copyKeyboardBacklightIDs")
        let builtInSelector = NSSelectorFromString("isKeyboardBuiltIn:")

        guard
            let copyIDs = Self.implementation(client, "copyKeyboardBacklightIDs", as: CopyIDsFn.self),
            let isBuiltIn = Self.implementation(client, "isKeyboardBuiltIn:", as: IsBuiltInFn.self),
            let getBrightness = Self.implementation(client, "brightnessForKeyboard:", as: GetFn.self),
            let setBrightness = Self.implementation(
                client, "setBrightness:fadeSpeed:commit:forKeyboard:", as: SetFn.self),
            let ids = copyIDs(client, copySelector).takeRetainedValue() as? [NSNumber]
        else { return nil }

        let builtIn = ids.map { $0.uint64Value }.first { isBuiltIn(client, builtInSelector, $0).boolValue }
        guard let id = builtIn ?? ids.first?.uint64Value else { return nil }

        self.client = client
        self.keyboardID = id
        self.getBrightness = getBrightness
        self.setBrightness = setBrightness
    }

    /// Switches the backlight off if it is on, or back to its last level if it is off.
    @discardableResult
    public func toggle() -> Bool {
        let current = getBrightness(client, getSelector, keyboardID)
        let target: Float
        if current > 0.02 {
            lastOnLevel = current
            target = 0
        } else {
            target = lastOnLevel
        }
        let ok = setBrightness(client, setSelector, target, 0, true, keyboardID).boolValue
        return ok
    }

    private static func implementation<T>(_ object: NSObject, _ name: String, as _: T.Type) -> T? {
        guard let method = class_getInstanceMethod(type(of: object), NSSelectorFromString(name)) else {
            return nil
        }
        return unsafeBitCast(method_getImplementation(method), to: T.self)
    }
}
