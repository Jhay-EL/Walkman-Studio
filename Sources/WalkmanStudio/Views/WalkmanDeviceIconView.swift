import SwiftUI
import AppKit

public struct WalkmanDeviceIconView: View {
    var size: CGFloat = 64
    var mountPoint: String? = nil
    var modelName: String? = nil
    var deviceInfo: WalkmanDeviceInfo? = nil
    var hasBackground: Bool = true
    
    @State private var loadedImage: NSImage? = nil
    
    public init(
        size: CGFloat = 64,
        mountPoint: String? = nil,
        modelName: String? = nil,
        deviceInfo: WalkmanDeviceInfo? = nil,
        hasBackground: Bool = true
    ) {
        self.size = size
        self.mountPoint = mountPoint
        self.modelName = modelName
        self.deviceInfo = deviceInfo
        self.hasBackground = hasBackground
    }
    
    private func loadIcon() -> NSImage? {
        // 1. Resolve model string
        var resolvedModel: String? = modelName ?? deviceInfo?.modelRaw ?? deviceInfo?.specificModel ?? deviceInfo?.displayName
        
        // If not explicitly provided, try to extract model from mountPoint default-capability.xml
        if resolvedModel == nil, let mp = mountPoint {
            let primaryXml = URL(fileURLWithPath: mp).appendingPathComponent("default-capability.xml")
            let secondaryXml = URL(fileURLWithPath: mp).appendingPathComponent("DEFAULT-CAPABILITY.XML")
            let xmlPath = FileManager.default.fileExists(atPath: primaryXml.path) ? primaryXml :
                (FileManager.default.fileExists(atPath: secondaryXml.path) ? secondaryXml : nil)
            
            if let p = xmlPath, let data = try? Data(contentsOf: p),
               let xml = String(data: data, encoding: .isoLatin1) ?? String(data: data, encoding: .utf8),
               let model = WalkmanDeviceDetector.extractXmlTag(tag: "model", from: xml) {
                resolvedModel = model
            }
        }
        
        let key = WalkmanDeviceDetector.iconKey(for: resolvedModel)
        
        // 2. Try Model-Specific Asset from App Bundle
        if let res = Bundle.main.url(forResource: key, withExtension: "png", subdirectory: "devices"),
           let img = NSImage(contentsOf: res) {
            return img
        }
        if let res = Bundle.main.url(forResource: key, withExtension: "png"),
           let img = NSImage(contentsOf: res) {
            return img
        }
        
        // 3. Try Relative Workspace path (for dev/testing)
        for relPath in [
            "assets/devices/\(key).png",
            "assets/devices/\(key).PNG",
            "assets/devices/\(key.uppercased()).png"
        ] {
            if FileManager.default.fileExists(atPath: relPath),
               let img = NSImage(contentsOfFile: relPath) {
                return img
            }
        }
        
        // 4. Fallback to mountPoint/DevIcon.fil (Sony official icon on device)
        if let mp = mountPoint {
            let filURL = URL(fileURLWithPath: mp).appendingPathComponent("DevIcon.fil")
            if FileManager.default.fileExists(atPath: filURL.path),
               let img = NSImage(contentsOf: filURL) {
                return img
            }
        }
        
        // 5. Fallback to default assets/walkman_device_cropped.png or walkman_device.png
        if let res = Bundle.main.url(forResource: "walkman_device_cropped", withExtension: "png"),
           let img = NSImage(contentsOf: res) {
            return img
        }
        if let res = Bundle.main.url(forResource: "walkman_device", withExtension: "png"),
           let img = NSImage(contentsOf: res) {
            return img
        }
        for path in ["assets/walkman_device_cropped.png", "assets/walkman_device.png"] {
            if FileManager.default.fileExists(atPath: path),
               let img = NSImage(contentsOfFile: path) {
                return img
            }
        }
        
        return nil
    }
    
    public var body: some View {
        Group {
            if hasBackground {
                ZStack {
                    RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
                        .fill(WalkmanTheme.cardHeaderGradient)
                        .frame(width: size, height: size)
                        .overlay(
                            RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
                                .stroke(Color.white.opacity(0.12), lineWidth: 1)
                        )
                    
                    deviceImage
                        .frame(width: size * 0.72, height: size * 0.78)
                }
            } else {
                deviceImage
                    .frame(width: size, height: size)
            }
        }
        .onAppear {
            self.loadedImage = loadIcon()
        }
        .onChange(of: mountPoint) {
            self.loadedImage = loadIcon()
        }
        .onChange(of: modelName) {
            self.loadedImage = loadIcon()
        }
        .onChange(of: deviceInfo?.modelRaw) {
            self.loadedImage = loadIcon()
        }
    }
    
    @ViewBuilder
    private var deviceImage: some View {
        if let img = loadedImage ?? loadIcon() {
            Image(nsImage: img)
                .resizable()
                .scaledToFit()
        } else {
            VectorWalkmanIcon(size: size * 0.85)
        }
    }
}

public struct VectorWalkmanIcon: View {
    var size: CGFloat = 44
    
    public init(size: CGFloat = 44) {
        self.size = size
    }
    
    public var body: some View {
        let w = size * 0.52
        let h = size
        
        ZStack {
            // Main Aluminum Chassis (Sony A55 Form Factor)
            RoundedRectangle(cornerRadius: size * 0.1, style: .continuous)
                .fill(WalkmanTheme.silverGradient)
                .frame(width: w, height: h)
                .overlay(
                    RoundedRectangle(cornerRadius: size * 0.1, style: .continuous)
                        .stroke(Color.white.opacity(0.25), lineWidth: 0.8)
                )
            
            // Screen Area (Black Glass Display)
            VStack(spacing: size * 0.05) {
                RoundedRectangle(cornerRadius: size * 0.05, style: .continuous)
                    .fill(Color(red: 16/255, green: 17/255, blue: 20/255))
                    .frame(width: w * 0.86, height: h * 0.62)
                    .overlay(
                        VStack(spacing: size * 0.04) {
                            // Mini Hi-Res playback waveform indicator
                            HStack(alignment: .bottom, spacing: 1.5) {
                                RoundedRectangle(cornerRadius: 1).fill(Color.white.opacity(0.7)).frame(width: 1.5, height: 4)
                                RoundedRectangle(cornerRadius: 1).fill(Color.white.opacity(0.7)).frame(width: 1.5, height: 8)
                                RoundedRectangle(cornerRadius: 1).fill(Color.white.opacity(0.7)).frame(width: 1.5, height: 6)
                                RoundedRectangle(cornerRadius: 1).fill(Color.white.opacity(0.7)).frame(width: 1.5, height: 10)
                                RoundedRectangle(cornerRadius: 1).fill(Color.white.opacity(0.7)).frame(width: 1.5, height: 5)
                            }
                            
                            // Track Progress Line
                            RoundedRectangle(cornerRadius: 1)
                                .fill(Color.white.opacity(0.2))
                                .frame(width: w * 0.6, height: 1.5)
                        }
                    )
                
                // Bottom Aluminum Bevel with Sony "W." Logo
                Text("W.")
                    .font(.system(size: size * 0.16, weight: .black, design: .rounded))
                    .foregroundStyle(Color(red: 20/255, green: 20/255, blue: 24/255))
            }
            .padding(.top, size * 0.06)
        }
    }
}
