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
    public struct VolumeInspectionResult: Sendable {
        public let isWalkman: Bool
        public let isSupported: Bool
        public let isInternal: Bool
        public let isMicroSD: Bool
        public let modelRaw: String?
        public let vendor: String?
        public let rawXml: String?
    }
    
    /// Checks whether a model identifier belongs to a supported non-Android Sony Walkman DAP
    public static func isSupportedModel(modelRaw: String) -> Bool {
        let clean = modelRaw.uppercased().replacingOccurrences(of: "-", with: "").replacingOccurrences(of: " ", with: "")
        
        // Unsupported Android models (use Android MTP, not non-Android USB mass storage)
        let unsupportedAndroid = ["A100", "A105", "A106", "A300", "A306", "A307", "ZX500", "ZX507", "ZX700", "ZX707", "WM1AM2", "WM1ZM2"]
        for token in unsupportedAndroid {
            if clean.contains(token) {
                return false
            }
        }
        
        // Supported Non-Android Sony DAP series tokens
        let supported = [
            "A50", "A55", "A56", "A57",
            "A40", "A45", "A46", "A47",
            "A30", "A35", "A36", "A37",
            "A20", "A25", "A27",
            "A10", "A15", "A17",
            "A800", "A820", "A840", "A860",
            "ZX300", "ZX100",
            "WM1", "WM1A", "WM1Z",
            "WS620", "WS623", "WS625",
            "WS410", "WS413", "WS414",
            "E390", "E393", "E394", "E395",
            "S310", "S313", "S315",
            "B180", "B183"
        ]
        
        for token in supported {
            if clean.contains(token) {
                return true
            }
        }
        
        return false
    }

    /// Returns the asset file identifier for the corresponding Walkman hardware image
    public static func iconKey(for modelString: String?) -> String {
        guard let raw = modelString?.uppercased().replacingOccurrences(of: "-", with: "").replacingOccurrences(of: " ", with: "") else {
            return "nw-a50"
        }
        
        if raw.contains("WM1Z") {
            return "nw-wm1z"
        } else if raw.contains("WM1") {
            return "nw-wm1a"
        } else if raw.contains("ZX300") {
            return "nw-zx300"
        } else if raw.contains("ZX100") {
            return "nw-zx100"
        } else if raw.contains("A50") || raw.contains("A55") || raw.contains("A56") || raw.contains("A57") {
            return "nw-a50"
        } else if raw.contains("A40") || raw.contains("A45") || raw.contains("A46") || raw.contains("A47") {
            return "nw-a40"
        } else if raw.contains("A30") || raw.contains("A35") || raw.contains("A36") || raw.contains("A37") {
            return "nw-a30"
        } else if raw.contains("A20") || raw.contains("A25") || raw.contains("A27") {
            return "nw-a20"
        } else if raw.contains("A10") || raw.contains("A15") || raw.contains("A17") {
            return "nw-a10"
        } else if raw.contains("WS620") || raw.contains("WS623") || raw.contains("WS625") {
            return "nw-ws620"
        } else if raw.contains("WS410") || raw.contains("WS413") || raw.contains("WS414") {
            return "nw-ws410"
        } else if raw.contains("E390") || raw.contains("E393") || raw.contains("E394") || raw.contains("E395") {
            return "nw-e390"
        } else if raw.contains("S310") || raw.contains("S313") || raw.contains("S315") {
            return "nw-s310"
        } else if raw.contains("B180") || raw.contains("B183") {
            return "nw-b180"
        } else {
            return "nw-a50"
        }
    }

    /// Inspects a mounted volume URL for authentic Sony Walkman hardware signatures
    public static func inspectVolume(at volumeURL: URL) -> VolumeInspectionResult? {
        let primaryXml = volumeURL.appendingPathComponent("default-capability.xml")
        let secondaryXml = volumeURL.appendingPathComponent("DEFAULT-CAPABILITY.XML")
        
        let xmlURL = FileManager.default.fileExists(atPath: primaryXml.path) ? primaryXml :
            (FileManager.default.fileExists(atPath: secondaryXml.path) ? secondaryXml : nil)
            
        if let url = xmlURL,
           let data = try? Data(contentsOf: url),
           let xml = String(data: data, encoding: .isoLatin1) ?? String(data: data, encoding: .utf8) {
            
            let vendor = extractXmlTag(tag: "vendor", from: xml)
            let classType = extractXmlTag(tag: "class", from: xml)
            let modelRaw = extractXmlTag(tag: "model", from: xml)
            let storageType = extractXmlTag(tag: "type", from: xml)?.uppercased()
            
            let vendorIsSony = vendor?.lowercased().contains("sony") ?? false
            let classIsWalkman = classType?.uppercased().contains("WALKMAN") ?? false
            let modelIsWalkman = modelRaw?.uppercased().contains("NW") ?? false
            
            guard vendorIsSony || classIsWalkman || modelIsWalkman else {
                return nil
            }
            
            let model = modelRaw ?? "NW-A50Series"
            let supported = isSupportedModel(modelRaw: model)
            let isInternal = (storageType == "INTERNAL") || (!volumeURL.lastPathComponent.uppercased().contains("SD") && storageType != "CARD")
            let isMicroSD = (storageType == "CARD") || volumeURL.lastPathComponent.uppercased().contains("SD")
            
            return VolumeInspectionResult(
                isWalkman: true,
                isSupported: supported,
                isInternal: isInternal,
                isMicroSD: isMicroSD,
                modelRaw: model,
                vendor: vendor,
                rawXml: xml
            )
        }
        
        // No XML: check for hardware signature files
        let volName = volumeURL.lastPathComponent.uppercased()
        let hasDevIcon = FileManager.default.fileExists(atPath: volumeURL.appendingPathComponent("DevIcon.fil").path)
        let hasSonyCardInd = FileManager.default.fileExists(atPath: volumeURL.appendingPathComponent("Sony_Card.IND").path)
            || FileManager.default.fileExists(atPath: volumeURL.appendingPathComponent("SONY_CARD.IND").path)
        let hasMusicDir = FileManager.default.fileExists(atPath: volumeURL.appendingPathComponent("MUSIC").path)
        
        // Internal heuristic: Volume name contains "WALKMAN" or starts with "NW-"
        if (volName.contains("WALKMAN") || volName.hasPrefix("NW-")) && (hasDevIcon || hasMusicDir) {
            return VolumeInspectionResult(
                isWalkman: true,
                isSupported: true,
                isInternal: true,
                isMicroSD: false,
                modelRaw: volName,
                vendor: "Sony Corporation",
                rawXml: nil
            )
        }
        
        // MicroSD heuristic: has Sony_Card.IND or (DevIcon.fil with MUSIC folder)
        if hasSonyCardInd || (hasDevIcon && hasMusicDir) {
            return VolumeInspectionResult(
                isWalkman: true,
                isSupported: true,
                isInternal: false,
                isMicroSD: true,
                modelRaw: nil,
                vendor: "Sony Corporation",
                rawXml: nil
            )
        }
        
        return nil
    }

    public func detect(drives: [WalkmanDrive]) -> WalkmanDeviceInfo? {
        return detectDevices(drives: drives).first?.deviceInfo
    }

    public func detectDevices(drives: [WalkmanDrive]) -> [WalkmanDevice] {
        guard !drives.isEmpty else { return [] }

        let internalDrives = drives.filter { $0.type == .internal }
        var microsdDrives = drives.filter { $0.type == .microsd }

        func readXml(from mountPoint: String) -> String? {
            let p1 = URL(fileURLWithPath: mountPoint).appendingPathComponent("default-capability.xml")
            let p2 = URL(fileURLWithPath: mountPoint).appendingPathComponent("DEFAULT-CAPABILITY.XML")
            if let data = try? Data(contentsOf: p1), let s = String(data: data, encoding: .isoLatin1) ?? String(data: data, encoding: .utf8) {
                return s
            }
            if let data = try? Data(contentsOf: p2), let s = String(data: data, encoding: .isoLatin1) ?? String(data: data, encoding: .utf8) {
                return s
            }
            return nil
        }

        func extractVolumeIndex(from mountPoint: String) -> Int {
            let last = URL(fileURLWithPath: mountPoint).lastPathComponent
            let parts = last.split(separator: " ")
            if parts.count > 1, let num = Int(parts.last!) {
                return num
            }
            return 0
        }

        var devices: [WalkmanDevice] = []

        // Pair each internal drive with its companion MicroSD drive if present
        for intDrive in internalDrives {
            let intXml = readXml(from: intDrive.mountPoint)
            let intModel = intXml.flatMap { Self.extractXmlTag(tag: "model", from: $0) }
            let intIdx = extractVolumeIndex(from: intDrive.mountPoint)

            var bestSdIndex: Int? = nil
            for (idx, sdDrive) in microsdDrives.enumerated() {
                let sdXml = readXml(from: sdDrive.mountPoint)
                let sdModel = sdXml.flatMap { Self.extractXmlTag(tag: "model", from: $0) }
                let sdIdx = extractVolumeIndex(from: sdDrive.mountPoint)

                // 1. Both have model XML and models match
                if let im = intModel, let sm = sdModel, im.localizedCaseInsensitiveCompare(sm) == .orderedSame {
                    if intIdx == sdIdx {
                        bestSdIndex = idx
                        break
                    }
                    if bestSdIndex == nil {
                        bestSdIndex = idx
                    }
                } else if intIdx == sdIdx && intIdx > 0 {
                    // 2. Matching numbered suffix e.g. WALKMAN 1 and SD_CARD 1
                    bestSdIndex = idx
                    break
                }
            }

            // Fallback: If only 1 internal drive and 1 SD card remain, pair them
            if bestSdIndex == nil && internalDrives.count == 1 && microsdDrives.count == 1 {
                bestSdIndex = 0
            }

            var pairedDrives: [WalkmanDrive] = [intDrive]
            var pairedSd: WalkmanDrive? = nil
            if let sdIdx = bestSdIndex {
                pairedSd = microsdDrives.remove(at: sdIdx)
                pairedDrives.append(pairedSd!)
            }

            let hasCfw = pairedDrives.contains(where: { $0.hasCfw })
            let capacityGb = Double(intDrive.totalBytes) / (1024 * 1024 * 1024)

            let info: WalkmanDeviceInfo
            if let xml = intXml ?? pairedSd.flatMap({ readXml(from: $0.mountPoint) }) {
                info = parseCapabilityXml(xml: xml, internalCapacityGb: capacityGb, hasCfw: hasCfw)
            } else {
                info = detectFromFilesystemHeuristics(drive: intDrive, drives: pairedDrives, capacityGb: capacityGb, hasCfw: hasCfw)
            }

            devices.append(WalkmanDevice(deviceInfo: info, drives: pairedDrives))
        }

        // Any leftover MicroSD cards (e.g. plugged into a Mac USB card reader directly)
        for sdDrive in microsdDrives {
            let sdXml = readXml(from: sdDrive.mountPoint)
            let capacityGb = Double(sdDrive.totalBytes) / (1024 * 1024 * 1024)
            let hasCfw = sdDrive.hasCfw

            let info: WalkmanDeviceInfo
            if let xml = sdXml {
                info = parseCapabilityXml(xml: xml, internalCapacityGb: capacityGb, hasCfw: hasCfw)
            } else {
                info = detectFromFilesystemHeuristics(drive: sdDrive, drives: [sdDrive], capacityGb: capacityGb, hasCfw: hasCfw)
            }

            devices.append(WalkmanDevice(deviceInfo: info, drives: [sdDrive]))
        }

        return devices
    }
    
    private func parseCapabilityXml(xml: String, internalCapacityGb: Double, hasCfw: Bool) -> WalkmanDeviceInfo {
        let modelRaw = Self.extractXmlTag(tag: "model", from: xml) ?? "NW-A50Series"
        let marketingName = Self.extractXmlTag(tag: "marketingname", from: xml) ?? "WALKMAN \(modelRaw)"
        let vendor = Self.extractXmlTag(tag: "vendor", from: xml) ?? "Sony Corporation"
        let firmwareVersion = Self.extractXmlTag(tag: "firmwareversion", from: xml) ?? "1.02"
        let width = Self.extractXmlTag(tag: "width", from: xml) ?? "800"
        let height = Self.extractXmlTag(tag: "height", from: xml) ?? "480"
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
        
        let seriesRaw: String
        if name.contains("ZX300") {
            seriesRaw = "NW-ZX300Series"
        } else if name.contains("WM1") {
            seriesRaw = "NW-WM1Series"
        } else if name.contains("A50") || name.contains("A55") {
            seriesRaw = "NW-A50Series"
        } else if name.contains("A40") || name.contains("A45") {
            seriesRaw = "NW-A40Series"
        } else if name.contains("A30") || name.contains("A35") {
            seriesRaw = "NW-A30Series"
        } else if name.contains("ZX100") {
            seriesRaw = "NW-ZX100"
        } else {
            seriesRaw = "Generic"
        }
        
        if seriesRaw != "Generic" {
            let (seriesName, specificModel, displayName) = resolveSpecificModel(modelRaw: seriesRaw, capacityGb: capacityGb, hasCfw: hasCfw)
            return WalkmanDeviceInfo(
                modelRaw: seriesRaw,
                marketingName: displayName,
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
        
        // Generic fallback when specific series is not identified
        let cfwTag = hasCfw ? " (Custom Firmware)" : ""
        return WalkmanDeviceInfo(
            modelRaw: "Sony Walkman DAP",
            marketingName: "Sony Walkman DAP",
            displayName: "Sony Walkman\(cfwTag)",
            seriesName: "Walkman DAP",
            specificModel: "Walkman",
            vendor: "Sony Corporation",
            firmwareVersion: "Sony OS DAP",
            isNonAndroid: true,
            hasCfw: hasCfw,
            displayResolution: "Standard RGB",
            internalCapacityGb: capacityGb,
            supportedAudioFormats: ["FLAC", "MP3", "WAV", "AIFF", "ALAC", "DSD", "APE"]
        )
    }
    
    public static func extractXmlTag(tag: String, from xml: String) -> String? {
        let pattern = "(?i)<\(tag)(?:\\s+[^>]*)?>([\\s\\S]*?)</\(tag)>"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return nil }
        let range = NSRange(xml.startIndex..., in: xml)
        if let match = regex.firstMatch(in: xml, options: [], range: range),
           let r = Range(match.range(at: 1), in: xml) {
            return String(xml[r]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return nil
    }
}
