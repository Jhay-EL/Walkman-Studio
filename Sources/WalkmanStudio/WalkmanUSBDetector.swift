import Foundation
import IOKit
import IOKit.usb

public struct ConnectedUSBWalkman: Identifiable, Sendable {
    public var id: String { "\(vendorId):\(productId):\(serialNumber ?? modelName)" }
    public let modelName: String
    public let seriesName: String
    public let vendorId: Int
    public let productId: Int
    public let serialNumber: String?
    public let isAndroid: Bool
    public let iconKey: String
    
    public init(
        modelName: String,
        seriesName: String,
        vendorId: Int,
        productId: Int,
        serialNumber: String?,
        isAndroid: Bool,
        iconKey: String
    ) {
        self.modelName = modelName
        self.seriesName = seriesName
        self.vendorId = vendorId
        self.productId = productId
        self.serialNumber = serialNumber
        self.isAndroid = isAndroid
        self.iconKey = iconKey
    }
}

public final class WalkmanUSBDetector: ObservableObject, @unchecked Sendable {
    public static let shared = WalkmanUSBDetector()
    
    @Published public private(set) var connectedDevices: [ConnectedUSBWalkman] = []
    
    public init() {
        refresh()
    }
    
    public func refresh() {
        let devs = scanUSBDevices()
        DispatchQueue.main.async {
            self.connectedDevices = devs
        }
    }
    
    public func scanUSBDevices() -> [ConnectedUSBWalkman] {
        var results: [ConnectedUSBWalkman] = []
        
        let matchingDict = IOServiceMatching(kIOUSBDeviceClassName) as NSMutableDictionary?
        guard let matching = matchingDict else { return [] }
        
        var iterator: io_iterator_t = 0
        let kr: kern_return_t
        if #available(macOS 12.0, *) {
            kr = IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator)
        } else {
            kr = IOServiceGetMatchingServices(kIOMasterPortDefault, matching, &iterator)
        }
        guard kr == KERN_SUCCESS, iterator != 0 else { return [] }
        
        defer { IOObjectRelease(iterator) }
        
        var device: io_service_t = IOIteratorNext(iterator)
        while device != 0 {
            defer {
                IOObjectRelease(device)
                device = IOIteratorNext(iterator)
            }
            
            guard let properties = getDeviceProperties(device) else { continue }
            
            let vid = (properties["idVendor"] as? NSNumber)?.intValue ?? 0
            guard vid == 0x054c else { continue } // Sony Corporation Vendor ID
            
            let pid = (properties["idProduct"] as? NSNumber)?.intValue ?? 0
            let prodName = (properties["USB Product Name"] as? String)
                ?? (properties["kUSBProductString"] as? String)
                ?? ""
            let serial = (properties["USB Serial Number"] as? String)
                ?? (properties["kUSBSerialNumberString"] as? String)
            
            if let walkman = identifySonyWalkman(vendorId: vid, productId: pid, productName: prodName, serial: serial) {
                if !results.contains(where: { $0.id == walkman.id }) {
                    results.append(walkman)
                }
            }
        }
        
        return results
    }
    
    private func getDeviceProperties(_ service: io_service_t) -> [String: Any]? {
        var properties: Unmanaged<CFMutableDictionary>?
        let kr = IORegistryEntryCreateCFProperties(service, &properties, kCFAllocatorDefault, 0)
        guard kr == KERN_SUCCESS, let props = properties?.takeRetainedValue() as? [String: Any] else {
            return nil
        }
        return props
    }
    
    private func identifySonyWalkman(vendorId: Int, productId: Int, productName: String, serial: String?) -> ConnectedUSBWalkman? {
        let upperName = productName.uppercased()
        
        // 1. Match by known Android Walkman USB Product IDs
        switch productId {
        case 0x0d00, 0x0cff:
            return ConnectedUSBWalkman(
                modelName: "NW-A105",
                seriesName: "NW-A100 Series",
                vendorId: vendorId,
                productId: productId,
                serialNumber: serial,
                isAndroid: true,
                iconKey: "nw-a100"
            )
        case 0x0d01:
            return ConnectedUSBWalkman(
                modelName: "NW-ZX507",
                seriesName: "NW-ZX500 Series",
                vendorId: vendorId,
                productId: productId,
                serialNumber: serial,
                isAndroid: true,
                iconKey: "nw-zx500"
            )
        case 0x0e6e:
            return ConnectedUSBWalkman(
                modelName: "NW-A306",
                seriesName: "NW-A300 Series",
                vendorId: vendorId,
                productId: productId,
                serialNumber: serial,
                isAndroid: true,
                iconKey: "nw-a300"
            )
        case 0x0e6f:
            return ConnectedUSBWalkman(
                modelName: "NW-ZX707",
                seriesName: "NW-ZX700 Series",
                vendorId: vendorId,
                productId: productId,
                serialNumber: serial,
                isAndroid: true,
                iconKey: "nw-zx700"
            )
        case 0x0e70:
            return ConnectedUSBWalkman(
                modelName: "NW-WM1AM2",
                seriesName: "NW-WM1 Series M2",
                vendorId: vendorId,
                productId: productId,
                serialNumber: serial,
                isAndroid: true,
                iconKey: "nw-wm1am2"
            )
        case 0x0e71:
            return ConnectedUSBWalkman(
                modelName: "NW-WM1ZM2",
                seriesName: "NW-WM1 Series M2",
                vendorId: vendorId,
                productId: productId,
                serialNumber: serial,
                isAndroid: true,
                iconKey: "nw-wm1zm2"
            )
        default:
            break
        }
        
        // 2. Heuristic match by USB Product String if PID was generic MTP
        if upperName.contains("A306") || upperName.contains("A307") || (upperName.contains("WALKMAN") && upperName.contains("A300")) {
            return ConnectedUSBWalkman(
                modelName: "NW-A306",
                seriesName: "NW-A300 Series",
                vendorId: vendorId,
                productId: productId,
                serialNumber: serial,
                isAndroid: true,
                iconKey: "nw-a300"
            )
        } else if upperName.contains("A105") || upperName.contains("A106") || (upperName.contains("WALKMAN") && upperName.contains("A100")) {
            return ConnectedUSBWalkman(
                modelName: "NW-A105",
                seriesName: "NW-A100 Series",
                vendorId: vendorId,
                productId: productId,
                serialNumber: serial,
                isAndroid: true,
                iconKey: "nw-a100"
            )
        } else if upperName.contains("ZX707") || upperName.contains("ZX700") {
            return ConnectedUSBWalkman(
                modelName: "NW-ZX707",
                seriesName: "NW-ZX700 Series",
                vendorId: vendorId,
                productId: productId,
                serialNumber: serial,
                isAndroid: true,
                iconKey: "nw-zx700"
            )
        } else if upperName.contains("ZX507") || upperName.contains("ZX500") {
            return ConnectedUSBWalkman(
                modelName: "NW-ZX507",
                seriesName: "NW-ZX500 Series",
                vendorId: vendorId,
                productId: productId,
                serialNumber: serial,
                isAndroid: true,
                iconKey: "nw-zx500"
            )
        } else if upperName.contains("WM1AM2") {
            return ConnectedUSBWalkman(
                modelName: "NW-WM1AM2",
                seriesName: "NW-WM1 Series M2",
                vendorId: vendorId,
                productId: productId,
                serialNumber: serial,
                isAndroid: true,
                iconKey: "nw-wm1am2"
            )
        } else if upperName.contains("WM1ZM2") {
            return ConnectedUSBWalkman(
                modelName: "NW-WM1ZM2",
                seriesName: "NW-WM1 Series M2",
                vendorId: vendorId,
                productId: productId,
                serialNumber: serial,
                isAndroid: true,
                iconKey: "nw-wm1zm2"
            )
        }
        
        return nil
    }
}
