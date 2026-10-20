import Foundation

public struct SupportedWalkmanModel: Identifiable, Sendable {
    public var id: String { modelCode }
    public let series: String
    public let modelCode: String
    public let description: String
    public let releaseYear: String
    public let storageOptions: String
    public let osType: String
    
    public init(series: String, modelCode: String, description: String, releaseYear: String, storageOptions: String, osType: String = "Sony OS (Linux DAP)") {
        self.series = series
        self.modelCode = modelCode
        self.description = description
        self.releaseYear = releaseYear
        self.storageOptions = storageOptions
        self.osType = osType
    }
}

public struct UnsupportedWalkmanModel: Identifiable, Sendable {
    public var id: String { modelCode }
    public let modelCode: String
    public let androidVersion: String
    public let reason: String
}

public final class WalkmanDeviceDetector: Sendable {
    public static let shared = WalkmanDeviceDetector()
    
    // -------------------------------------------------------------------------
    // All Supported Non-Android Sony Walkman Hardware
    // -------------------------------------------------------------------------
    public static let supportedSeriesCategories: [(category: String, models: [SupportedWalkmanModel])] = [
        (
            category: "NW-A Series (Sony OS / Linux DAP)",
            models: [
                SupportedWalkmanModel(
                    series: "NW-A50 Series",
                    modelCode: "NW-A55 / NW-A55HN / NW-A55L",
                    description: "High-Resolution Audio, S-Master HX, DSEE HX, Vinyl Processor, USB DAC, LDAC / aptX HD",
                    releaseYear: "2018",
                    storageOptions: "16GB Internal + MicroSD"
                ),
                SupportedWalkmanModel(
                    series: "NW-A50 Series",
                    modelCode: "NW-A56 / NW-A56HN",
                    description: "High-Resolution Audio, S-Master HX, DSEE HX, Vinyl Processor, USB DAC",
                    releaseYear: "2018",
                    storageOptions: "32GB Internal + MicroSD"
                ),
                SupportedWalkmanModel(
                    series: "NW-A50 Series",
                    modelCode: "NW-A57",
                    description: "High-Resolution Audio, S-Master HX, DSEE HX, Vinyl Processor, USB DAC",
                    releaseYear: "2018",
                    storageOptions: "64GB Internal + MicroSD"
                ),
                SupportedWalkmanModel(
                    series: "NW-A40 Series",
                    modelCode: "NW-A45 / NW-A45HN / NW-A46 / NW-A47",
                    description: "High-Resolution Audio, S-Master HX, DSEE HX, USB DAC Mode, Ambient Sound",
                    releaseYear: "2017",
                    storageOptions: "16GB / 32GB / 64GB + MicroSD"
                ),
                SupportedWalkmanModel(
                    series: "NW-A30 Series",
                    modelCode: "NW-A35 / NW-A35HN / NW-A36 / NW-A37",
                    description: "High-Resolution Audio, S-Master HX, DSD playback via PCM, 3.1-inch Touchscreen",
                    releaseYear: "2016",
                    storageOptions: "16GB / 32GB / 64GB + MicroSD"
                ),
                SupportedWalkmanModel(
                    series: "NW-A20 Series",
                    modelCode: "NW-A25 / NW-A25HN / NW-A27HN",
                    description: "High-Resolution Audio, Digital Noise Cancelling, LDAC Bluetooth, Slim form factor",
                    releaseYear: "2015",
                    storageOptions: "16GB / 64GB + MicroSD"
                ),
                SupportedWalkmanModel(
                    series: "NW-A10 Series",
                    modelCode: "NW-A15 / NW-A17",
                    description: "Ultra-compact High-Resolution Audio Player with S-Master HX & DSEE HX",
                    releaseYear: "2014",
                    storageOptions: "16GB / 64GB + MicroSD"
                ),
                SupportedWalkmanModel(
                    series: "Legacy A Series",
                    modelCode: "NW-A800 / NW-A820 / NW-A840 / NW-A860",
                    description: "Classic Non-Android Sony MP3/AAC/WAV Mass Storage Players",
                    releaseYear: "2007–2011",
                    storageOptions: "8GB–64GB Flash"
                )
            ]
        ),
        (
            category: "NW-ZX Series (Non-Android Flagships)",
            models: [
                SupportedWalkmanModel(
                    series: "NW-ZX300 Series",
                    modelCode: "NW-ZX300",
                    description: "Balanced 4.4mm Output, S-Master HX, Native DSD 11.2MHz, 384kHz/32-bit PCM, MQA, USB DAC",
                    releaseYear: "2017",
                    storageOptions: "64GB Internal + MicroSD"
                ),
                SupportedWalkmanModel(
                    series: "NW-ZX300 Series",
                    modelCode: "NW-ZX300A",
                    description: "Balanced 4.4mm Output, S-Master HX, Native DSD, MQA, USB DAC Mode",
                    releaseYear: "2017",
                    storageOptions: "16GB Internal + MicroSD"
                ),
                SupportedWalkmanModel(
                    series: "NW-ZX100 Series",
                    modelCode: "NW-ZX100 / NW-ZX100HN",
                    description: "High-Resolution Audio, S-Master HX, DSEE HX, LDAC, CNC Aluminum chassis",
                    releaseYear: "2015",
                    storageOptions: "128GB Internal + MicroSD"
                )
            ]
        ),
        (
            category: "Signature Series (Non-Android Reference Flagships)",
            models: [
                SupportedWalkmanModel(
                    series: "NW-WM1 Series",
                    modelCode: "NW-WM1A",
                    description: "Signature Series Reference Flagship, Precision Milled Aluminum, Balanced 4.4mm Pentaconn, Dual Clocks",
                    releaseYear: "2016",
                    storageOptions: "128GB Internal + MicroSD"
                ),
                SupportedWalkmanModel(
                    series: "NW-WM1 Series",
                    modelCode: "NW-WM1Z",
                    description: "Ultimate Reference Flagship, Gold-Plated Oxygen-Free Copper (OFC) Chassis, Kimber Kable internal wiring",
                    releaseYear: "2016",
                    storageOptions: "256GB Internal + MicroSD"
                )
            ]
        ),
        (
            category: "Sports & Wearable Series (Non-Android)",
            models: [
                SupportedWalkmanModel(
                    series: "NW-WS620 Series",
                    modelCode: "NW-WS623 / NW-WS625",
                    description: "Waterproof & Saltwater Resistant, Dustproof, Bluetooth with Ambient Sound Mode",
                    releaseYear: "2017",
                    storageOptions: "4GB / 16GB Waterproof Flash"
                ),
                SupportedWalkmanModel(
                    series: "NW-WS410 Series",
                    modelCode: "NW-WS413 / NW-WS414",
                    description: "All-in-One Ergonomic Waterproof & Saltwater Sports Walkman",
                    releaseYear: "2016",
                    storageOptions: "4GB / 8GB Waterproof Flash"
                )
            ]
        ),
        (
            category: "Compact & Stick Series (Non-Android)",
            models: [
                SupportedWalkmanModel(
                    series: "NW-E390 Series",
                    modelCode: "NW-E393 / NW-E394 / NW-E395",
                    description: "Lightweight Compact Walkman with FM Radio, ClearAudio+, 35-hour battery life",
                    releaseYear: "2016",
                    storageOptions: "4GB / 8GB / 16GB"
                ),
                SupportedWalkmanModel(
                    series: "NW-S310 Series",
                    modelCode: "NW-S313 / NW-S315",
                    description: "Compact Sony OS Walkman with Digital Noise Cancelling",
                    releaseYear: "2017",
                    storageOptions: "4GB / 16GB"
                ),
                SupportedWalkmanModel(
                    series: "NW-B180 Series",
                    modelCode: "NW-B183 / NW-B183F",
                    description: "Direct USB Plug Stick Walkman with Bass Boost & Quick Charge",
                    releaseYear: "2014",
                    storageOptions: "4GB Built-in USB"
                )
            ]
        )
    ]
    
    // -------------------------------------------------------------------------
    // Unsupported Android Walkmans (For Explicit Clarity)
    // -------------------------------------------------------------------------
    public static let unsupportedAndroidModels: [UnsupportedWalkmanModel] = [
        UnsupportedWalkmanModel(
            modelCode: "NW-A100 / NW-A105 / NW-A106",
            androidVersion: "Android 9",
            reason: "Runs Android OS with MTP protocol. Not a USB Mass Storage device."
        ),
        UnsupportedWalkmanModel(
            modelCode: "NW-A300 / NW-A306 / NW-A307",
            androidVersion: "Android 12 / 13",
            reason: "Runs Android OS with MTP protocol. Uses Android MediaStore."
        ),
        UnsupportedWalkmanModel(
            modelCode: "NW-ZX500 / NW-ZX507",
            androidVersion: "Android 9",
            reason: "Runs Android OS with MTP protocol. Not compatible with S-Master HX CFW."
        ),
        UnsupportedWalkmanModel(
            modelCode: "NW-ZX700 / NW-ZX707",
            androidVersion: "Android 12",
            reason: "Runs Android OS with MTP protocol."
        ),
        UnsupportedWalkmanModel(
            modelCode: "NW-WM1AM2",
            androidVersion: "Android 11",
            reason: "2nd-gen Android flagship with MTP and standard Android audio stack."
        ),
        UnsupportedWalkmanModel(
            modelCode: "NW-WM1ZM2",
            androidVersion: "Android 11",
            reason: "2nd-gen Android flagship with MTP and standard Android audio stack."
        )
    ]
    
    // -------------------------------------------------------------------------
    // Accurate Detection from Hardware Volumes
    // -------------------------------------------------------------------------
    public func detect(drives: [WalkmanDrive]) -> WalkmanDeviceInfo? {
        guard !drives.isEmpty else { return nil }
        
        let internalDrive = drives.first(where: { $0.type == .internal }) ?? drives.first
        guard let drive = internalDrive else { return nil }
        
        // 1. Check for official default-capability.xml
        let primaryXml = URL(fileURLWithPath: drive.mountPoint).appendingPathComponent("default-capability.xml")
        let secondaryXml = URL(fileURLWithPath: drive.mountPoint).appendingPathComponent("DEFAULT-CAPABILITY.XML")
        
        var xmlContent: String?
        if let data = try? Data(contentsOf: primaryXml), let s = String(data: data, encoding: .isoLatin1) ?? String(data: data, encoding: .utf8) {
            xmlContent = s
        } else if let data = try? Data(contentsOf: secondaryXml), let s = String(data: data, encoding: .isoLatin1) ?? String(data: data, encoding: .utf8) {
            xmlContent = s
        } else {
            // Also check MicroSD card if mounted
            for d in drives where d.type == .microsd {
                let cardXml = URL(fileURLWithPath: d.mountPoint).appendingPathComponent("default-capability.xml")
                if let data = try? Data(contentsOf: cardXml), let s = String(data: data, encoding: .isoLatin1) ?? String(data: data, encoding: .utf8) {
                    xmlContent = s
                    break
                }
            }
        }
        
        let hasCfw = drives.contains(where: { $0.hasCfw })
        let capacityGb = Double(drive.totalBytes) / (1024 * 1024 * 1024)
        
        if let xml = xmlContent {
            return parseCapabilityXml(xml: xml, internalCapacityGb: capacityGb, hasCfw: hasCfw)
        }
        
        // 2. Fallback heuristic detection for formatted drives with MUSIC/ folder
        return detectFromFilesystemHeuristics(drive: drive, drives: drives, capacityGb: capacityGb, hasCfw: hasCfw)
    }
    
    private func parseCapabilityXml(xml: String, internalCapacityGb: Double, hasCfw: Bool) -> WalkmanDeviceInfo {
        let modelRaw = extractXmlTag(tag: "model", from: xml) ?? "NW-A50Series"
        let marketingName = extractXmlTag(tag: "marketingname", from: xml) ?? "WALKMAN \(modelRaw)"
        let vendor = extractXmlTag(tag: "vendor", from: xml) ?? "Sony Corporation"
        let firmwareVersion = extractXmlTag(tag: "firmwareversion", from: xml) ?? "1.02"
        let width = extractXmlTag(tag: "width", from: xml) ?? "800"
        let height = extractXmlTag(tag: "height", from: xml) ?? "480"
        let resolution = "\(width)x\(height)"
        
        // Extract supported audio formats
        var formats: [String] = []
        let formatRegex = try? NSRegularExpression(pattern: #"<format\s+id="([^"]+)""#, options: [])
        if let matches = formatRegex?.matches(in: xml, range: NSRange(xml.startIndex..., in: xml)) {
            for m in matches {
                if let r = Range(m.range(at: 1), in: xml) {
                    let fmt = String(xml[r])
                    if !formats.contains(fmt) {
                        formats.append(fmt)
                    }
                }
            }
        }
        if formats.isEmpty {
            formats = ["FLAC", "MP3", "WAV", "AIFF", "ALAC", "DSD", "APE"]
        }
        
        // Resolve Specific Model Variant from internal capacity
        let (seriesName, specificModel, displayName) = resolveSpecificModel(modelRaw: modelRaw, capacityGb: internalCapacityGb, hasCfw: hasCfw)
        
        return WalkmanDeviceInfo(
            modelRaw: modelRaw,
            marketingName: marketingName,
            displayName: displayName,
            seriesName: seriesName,
            specificModel: specificModel,
            vendor: vendor,
            firmwareVersion: firmwareVersion,
            isNonAndroid: true,
            hasCfw: hasCfw,
            displayResolution: resolution,
            internalCapacityGb: internalCapacityGb,
            supportedAudioFormats: formats
        )
    }
    
    private func resolveSpecificModel(modelRaw: String, capacityGb: Double, hasCfw: Bool) -> (series: String, specific: String, display: String) {
        let upper = modelRaw.uppercased()
        
        if upper.contains("A50") {
            let specific: String
            if capacityGb < 20 {
                // 16GB model
                specific = "NW-A55 / NW-A55L"
            } else if capacityGb < 45 {
                specific = "NW-A56"
            } else {
                specific = "NW-A57"
            }
            let cfwTag = hasCfw ? " (Walkman One CFW)" : ""
            return ("NW-A50 Series", specific, "Sony Walkman \(specific)\(cfwTag)")
        } else if upper.contains("A40") {
            let specific = capacityGb < 20 ? "NW-A45" : (capacityGb < 45 ? "NW-A46" : "NW-A47")
            return ("NW-A40 Series", specific, "Sony Walkman \(specific)")
        } else if upper.contains("A30") {
            let specific = capacityGb < 20 ? "NW-A35" : (capacityGb < 45 ? "NW-A36" : "NW-A37")
            return ("NW-A30 Series", specific, "Sony Walkman \(specific)")
        } else if upper.contains("ZX300") {
            let specific = capacityGb < 25 ? "NW-ZX300A" : "NW-ZX300"
            return ("NW-ZX300 Series", specific, "Sony Walkman \(specific)")
        } else if upper.contains("WM1") {
            let specific = capacityGb < 180 ? "NW-WM1A" : "NW-WM1Z"
            return ("NW-WM1 Signature Series", specific, "Sony Walkman \(specific)")
        } else if upper.contains("ZX100") {
            return ("NW-ZX100 Series", "NW-ZX100", "Sony Walkman NW-ZX100")
        } else if upper.contains("A20") {
            let specific = capacityGb < 25 ? "NW-A25" : "NW-A27"
            return ("NW-A20 Series", specific, "Sony Walkman \(specific)")
        } else if upper.contains("A10") {
            let specific = capacityGb < 25 ? "NW-A15" : "NW-A17"
            return ("NW-A10 Series", specific, "Sony Walkman \(specific)")
        } else if upper.contains("WS620") {
            return ("NW-WS620 Series", "NW-WS623", "Sony Walkman NW-WS623")
        } else if upper.contains("WS410") {
            return ("NW-WS410 Series", "NW-WS413", "Sony Walkman NW-WS413")
        } else if upper.contains("E390") {
            return ("NW-E390 Series", "NW-E394", "Sony Walkman NW-E394")
        } else if upper.contains("B180") || upper.contains("B183") {
            return ("NW-B180 Series", "NW-B183F", "Sony Walkman NW-B183F")
        } else {
            return (modelRaw, modelRaw, "Sony Walkman \(modelRaw)")
        }
    }
    
    private func detectFromFilesystemHeuristics(drive: WalkmanDrive, drives: [WalkmanDrive], capacityGb: Double, hasCfw: Bool) -> WalkmanDeviceInfo {
        let name = drive.name.uppercased()
        
        let (seriesName, specificModel, displayName) = resolveSpecificModel(modelRaw: name.contains("ZX300") ? "NW-ZX300Series" : (name.contains("WM1") ? "NW-WM1Series" : "NW-A50Series"), capacityGb: capacityGb, hasCfw: hasCfw)
        
        return WalkmanDeviceInfo(
            modelRaw: "NW-A50Series",
            marketingName: "WALKMAN NW-A50Series",
            displayName: displayName,
            seriesName: seriesName,
            specificModel: specificModel,
            vendor: "Sony Corporation",
            firmwareVersion: "Sony OS DAP",
            isNonAndroid: true,
            hasCfw: hasCfw,
            displayResolution: "800x480",
            internalCapacityGb: capacityGb,
            supportedAudioFormats: ["FLAC", "MP3", "WAV", "AIFF", "ALAC", "DSD", "APE"]
        )
    }
    
    private func extractXmlTag(tag: String, from xml: String) -> String? {
        guard let start = xml.range(of: "<\(tag)>")?.upperBound,
              let end = xml.range(of: "</\(tag)>", range: start..<xml.endIndex)?.lowerBound else {
            return nil
        }
        return String(xml[start..<end]).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
