import CoreGraphics
import Foundation
import IOKit

@MainActor
public final class DDCController: ObservableObject {
    private typealias CreateFunction = @convention(c) (CFAllocator?, io_service_t) -> Unmanaged<CFTypeRef>?
    private typealias TransferFunction = @convention(c)
        (CFTypeRef?, UInt32, UInt32, UnsafeMutableRawPointer, UInt32) -> IOReturn

    @Published public private(set) var isAvailable = false
    @Published public private(set) var percent = 50
    @Published public var isEnabled: Bool {
        didSet {
            defaults.set(isEnabled, forKey: Keys.enabled)
            if isEnabled { rediscover() } else { isAvailable = false }
        }
    }

    private enum Keys {
        static let enabled = "brightnessEnabled"
        static let percent = "brightnessPercent"
    }

    private let defaults: UserDefaults
    private let queue = DispatchQueue(label: "com.apotenza.KeyControl.ddc", qos: .userInitiated)
    private let create: CreateFunction?
    private let writeI2C: TransferFunction?
    private let readI2C: TransferFunction?
    private var services: [CFTypeRef] = []
    private var maxValue = 100
    private var targetPercent = 50
    private var generation = 0
    private var pendingWrite: DispatchWorkItem?

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [Keys.enabled: true, Keys.percent: 50])
        let savedPercent = Level.clamp(defaults.integer(forKey: Keys.percent))
        isEnabled = defaults.bool(forKey: Keys.enabled)
        percent = savedPercent
        targetPercent = savedPercent
        create = Self.symbol("IOAVServiceCreateWithService").map { unsafeBitCast($0, to: CreateFunction.self) }
        writeI2C = Self.symbol("IOAVServiceWriteI2C").map { unsafeBitCast($0, to: TransferFunction.self) }
        readI2C = Self.symbol("IOAVServiceReadI2C").map { unsafeBitCast($0, to: TransferFunction.self) }
    }

    public var hasActiveBuiltInDisplay: Bool {
        var count: UInt32 = 0
        guard CGGetActiveDisplayList(0, nil, &count) == .success else { return false }
        var displays = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetActiveDisplayList(count, &displays, &count) == .success else { return false }
        return displays.prefix(Int(count)).contains { CGDisplayIsBuiltin($0) != 0 }
    }

    public func rediscover() {
        guard isEnabled else { return }
        let generationAtStart = generation
        let create = self.create
        let writeI2C = self.writeI2C
        let readI2C = self.readI2C
        queue.async { [weak self] in
            let result = Self.discover(create: create, writeI2C: writeI2C, readI2C: readI2C)
            DispatchQueue.main.async {
                guard let self else { return }
                self.services = result.services
                self.maxValue = result.maximum
                self.isAvailable = !result.services.isEmpty
                if let current = result.current {
                    self.percent = current
                    if self.generation == generationAtStart { self.targetPercent = current }
                }
            }
        }
    }

    public func nudge(_ delta: Int) {
        guard isEnabled, isAvailable else { return }
        targetPercent = Level.clamp(targetPercent + delta)
        generation += 1
        scheduleWrite()
    }

    public func set(_ value: Int) {
        guard isEnabled, isAvailable else { return }
        targetPercent = Level.clamp(value)
        generation += 1
        scheduleWrite()
    }

    private func scheduleWrite() {
        pendingWrite?.cancel()
        let target = targetPercent
        let services = self.services
        let maximum = maxValue
        let writeI2C = self.writeI2C
        let work = DispatchWorkItem { [weak self] in
            let raw = Int((Double(target) / 100 * Double(maximum)).rounded())
            for service in services {
                Self.writeLuminance(service, value: raw, writeI2C: writeI2C)
                usleep(20_000)
            }
            DispatchQueue.main.async {
                guard let self else { return }
                self.percent = target
                self.defaults.set(target, forKey: Keys.percent)
            }
        }
        pendingWrite = work
        queue.async(execute: work)
    }

    private nonisolated static func discover(
        create: CreateFunction?,
        writeI2C: TransferFunction?,
        readI2C: TransferFunction?
    ) -> (services: [CFTypeRef], current: Int?, maximum: Int) {
        guard let create, writeI2C != nil, readI2C != nil else { return ([], nil, 100) }
        var iterator = io_iterator_t()
        guard IOServiceGetMatchingServices(
            kIOMainPortDefault,
            IOServiceMatching("DCPAVServiceProxy"),
            &iterator
        ) == KERN_SUCCESS else { return ([], nil, 100) }
        defer { IOObjectRelease(iterator) }

        var found: [CFTypeRef] = []
        while case let service = IOIteratorNext(iterator), service != 0 {
            defer { IOObjectRelease(service) }
            let location = IORegistryEntryCreateCFProperty(
                service,
                "Location" as CFString,
                kCFAllocatorDefault,
                0
            )?.takeRetainedValue() as? String
            guard location == "External",
                  let avService = create(kCFAllocatorDefault, service)?.takeRetainedValue() else { continue }
            found.append(avService)
        }

        for service in found {
            if let reading = readLuminance(service, writeI2C: writeI2C, readI2C: readI2C) {
                let maximum = max(1, reading.maximum)
                let percent = Level.clamp(Int((Double(reading.current) / Double(maximum) * 100).rounded()))
                return (found, percent, maximum)
            }
        }
        return (found, nil, 100)
    }

    private nonisolated static func readLuminance(
        _ service: CFTypeRef,
        writeI2C: TransferFunction?,
        readI2C: TransferFunction?
    ) -> (current: Int, maximum: Int)? {
        guard let writeI2C, let readI2C else { return nil }
        var request = Self.readPacket(feature: 0x10)
        for _ in 0..<3 {
            let writeStatus = request.withUnsafeMutableBytes {
                writeI2C(service, 0x37, 0x51, $0.baseAddress!, UInt32($0.count))
            }
            usleep(40_000)
            var response = [UInt8](repeating: 0, count: 12)
            let readStatus = response.withUnsafeMutableBytes {
                readI2C(service, 0x37, 0x51, $0.baseAddress!, UInt32($0.count))
            }
            if writeStatus == KERN_SUCCESS,
               readStatus == KERN_SUCCESS,
               response[2] == 0x02,
               response[4] == 0x10 {
                return (
                    Int(response[8]) << 8 | Int(response[9]),
                    Int(response[6]) << 8 | Int(response[7])
                )
            }
            usleep(50_000)
        }
        return nil
    }

    private nonisolated static func writeLuminance(
        _ service: CFTypeRef,
        value: Int,
        writeI2C: TransferFunction?
    ) {
        guard let writeI2C else { return }
        var packet = Self.writePacket(feature: 0x10, value: UInt16(clamping: value))
        _ = packet.withUnsafeMutableBytes {
            writeI2C(service, 0x37, 0x51, $0.baseAddress!, UInt32($0.count))
        }
    }

    nonisolated static func readPacket(feature: UInt8) -> [UInt8] {
        var packet: [UInt8] = [0x82, 0x01, feature, 0]
        packet[3] = packet.dropLast().reduce(0x6E ^ 0x51, ^)
        return packet
    }

    nonisolated static func writePacket(feature: UInt8, value: UInt16) -> [UInt8] {
        var packet: [UInt8] = [0x84, 0x03, feature, UInt8(value >> 8), UInt8(value & 0xff), 0]
        packet[5] = packet.dropLast().reduce(0x6E ^ 0x51, ^)
        return packet
    }

    private nonisolated static func symbol(_ name: String) -> UnsafeMutableRawPointer? {
        for path in [
            "/System/Library/Frameworks/IOKit.framework/IOKit",
            "/System/Library/Frameworks/CoreDisplay.framework/CoreDisplay",
        ] {
            guard let handle = dlopen(path, RTLD_NOW) else { continue }
            if let symbol = dlsym(handle, name) { return symbol }
        }
        return nil
    }
}
