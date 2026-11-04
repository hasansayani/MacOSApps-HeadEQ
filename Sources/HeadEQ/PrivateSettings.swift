import Foundation
import ObjectiveC

/// Minimal, crash-safe wrapper for an Apple private `HCSettings` singleton.
/// Every call checks the selector exists and uses a typed IMP (never
/// `perform` with scalars), so a renamed API simply reads as "unavailable".
final class PrivateSettings {
    let object: NSObject?

    init(framework: String, className: String) {
        dlopen("/System/Library/PrivateFrameworks/\(framework).framework/\(framework)", RTLD_NOW)
        guard let cls = NSClassFromString(className), let meta = object_getClass(cls) else { object = nil; return }
        let sel = NSSelectorFromString("sharedInstance")
        guard class_respondsToSelector(meta, sel), let imp = class_getMethodImplementation(meta, sel) else { object = nil; return }
        typealias F = @convention(c) (AnyObject, Selector) -> Unmanaged<AnyObject>?
        object = unsafeBitCast(imp, to: F.self)(cls, sel)?.takeUnretainedValue() as? NSObject
    }

    func responds(_ name: String) -> Bool { object?.responds(to: NSSelectorFromString(name)) ?? false }

    private func imp(_ name: String) -> (NSObject, Selector, IMP)? {
        let sel = NSSelectorFromString(name)
        guard let object, object.responds(to: sel) else { return nil }
        return (object, sel, object.method(for: sel))
    }

    func bool(_ name: String) -> Bool? {
        guard let (o, s, i) = imp(name) else { return nil }
        typealias F = @convention(c) (AnyObject, Selector) -> Bool
        return unsafeBitCast(i, to: F.self)(o, s)
    }

    func uint(_ name: String) -> UInt? {
        guard let (o, s, i) = imp(name) else { return nil }
        typealias F = @convention(c) (AnyObject, Selector) -> UInt
        return unsafeBitCast(i, to: F.self)(o, s)
    }

    func object(_ name: String) -> NSObject? {
        guard let (o, s, i) = imp(name) else { return nil }
        typealias F = @convention(c) (AnyObject, Selector) -> Unmanaged<AnyObject>?
        return unsafeBitCast(i, to: F.self)(o, s)?.takeUnretainedValue() as? NSObject
    }

    func set(_ name: String, bool value: Bool) {
        guard let (o, s, i) = imp(name) else { return }
        typealias F = @convention(c) (AnyObject, Selector, Bool) -> Void
        unsafeBitCast(i, to: F.self)(o, s, value)
    }

    func set(_ name: String, object value: AnyObject) {
        guard let (o, s, i) = imp(name) else { return }
        typealias F = @convention(c) (AnyObject, Selector, AnyObject) -> Void
        unsafeBitCast(i, to: F.self)(o, s, value)
    }

    // Per-device (address) variants used by AirPods transparency settings.
    func double(_ name: String, address: String) -> Double? {
        guard let (o, s, i) = imp(name) else { return nil }
        typealias F = @convention(c) (AnyObject, Selector, NSString) -> Double
        return unsafeBitCast(i, to: F.self)(o, s, address as NSString)
    }

    func bool(_ name: String, address: String) -> Bool? {
        guard let (o, s, i) = imp(name) else { return nil }
        typealias F = @convention(c) (AnyObject, Selector, NSString) -> Bool
        return unsafeBitCast(i, to: F.self)(o, s, address as NSString)
    }

    func set(_ name: String, double value: Double, address: String) {
        guard let (o, s, i) = imp(name) else { return }
        typealias F = @convention(c) (AnyObject, Selector, Double, NSString) -> Void
        unsafeBitCast(i, to: F.self)(o, s, value, address as NSString)
    }

    func set(_ name: String, bool value: Bool, address: String) {
        guard let (o, s, i) = imp(name) else { return }
        typealias F = @convention(c) (AnyObject, Selector, Bool, NSString) -> Void
        unsafeBitCast(i, to: F.self)(o, s, value, address as NSString)
    }

    /// Call a `setX:(NSUInteger)` on another object (e.g. a configuration).
    static func set(_ target: NSObject, _ name: String, uint value: UInt) {
        let sel = NSSelectorFromString(name)
        guard target.responds(to: sel) else { return }
        typealias F = @convention(c) (AnyObject, Selector, UInt) -> Void
        unsafeBitCast(target.method(for: sel), to: F.self)(target, sel, value)
    }

    static func uint(_ target: NSObject, _ name: String) -> UInt? {
        let sel = NSSelectorFromString(name)
        guard target.responds(to: sel) else { return nil }
        typealias F = @convention(c) (AnyObject, Selector) -> UInt
        return unsafeBitCast(target.method(for: sel), to: F.self)(target, sel)
    }
}
