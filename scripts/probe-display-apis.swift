// Read-only research probe. Does not begin or commit display configurations.
// Run with: swift scripts/probe-display-apis.swift
import AppKit
import CoreGraphics
import Darwin

typealias DisplayListFunction = @convention(c)
    (UInt32, UnsafeMutablePointer<CGDirectDisplayID>?, UnsafeMutablePointer<UInt32>?) -> CGError

func list(_ function: DisplayListFunction) throws -> [CGDirectDisplayID] {
    // Grow when full instead of assuming a fixed maximum display count.
    var capacity: UInt32 = 16
    while capacity <= 4096 {
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(capacity))
        var count: UInt32 = 0
        let error = function(capacity, &ids, &count)
        guard error == .success else { throw NSError(domain: "CGError", code: Int(error.rawValue)) }
        if count < capacity { return Array(ids.prefix(Int(count))) }
        capacity *= 2
    }
    throw NSError(domain: "DisplayProbe", code: 1,
                  userInfo: [NSLocalizedDescriptionKey: "Display list exceeded probe limit"])
}

print("System: \(ProcessInfo.processInfo.operatingSystemVersionString)")
guard let handle = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY | RTLD_LOCAL) else {
    fatalError("SkyLight could not be loaded")
}
defer { dlclose(handle) }
for name in ["CGSConfigureDisplayEnabled", "SLSConfigureDisplayEnabled", "CGSGetDisplayList", "SLSGetDisplayList"] {
    print("\(name): \(dlsym(handle, name) == nil ? "missing" : "present")")
}
let online = try list(CGGetOnlineDisplayList)
print("Public online IDs: \(online)")
guard let symbol = dlsym(handle, "CGSGetDisplayList") ?? dlsym(handle, "SLSGetDisplayList") else {
    fatalError("Private display enumeration unavailable")
}
let all = try list(unsafeBitCast(symbol, to: DisplayListFunction.self))
print("Private display IDs: \(all)")
for id in all {
    let name = NSScreen.screens.first {
        ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == id
    }?.localizedName ?? "(no AppKit screen)"
    print("id=\(id) name=\(name) builtIn=\(CGDisplayIsBuiltin(id)) online=\(CGDisplayIsOnline(id)) active=\(CGDisplayIsActive(id)) mirrored=\(CGDisplayIsInMirrorSet(id)) vendor=\(CGDisplayVendorNumber(id)) model=\(CGDisplayModelNumber(id))")
}
print("Read-only probe complete; no display settings changed.")
