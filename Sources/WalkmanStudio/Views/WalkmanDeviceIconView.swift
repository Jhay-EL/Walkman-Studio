import SwiftUI
import AppKit

public struct WalkmanDeviceIconView: View {
    var size: CGFloat = 64
    var mountPoint: String? = nil
    
    @State private var loadedImage: NSImage? = nil
    
    public init(size: CGFloat = 64, mountPoint: String? = nil) {
        self.size = size
        self.mountPoint = mountPoint
    }
    
    private func loadIcon() -> NSImage? {
        // 1. Try mountPoint/DevIcon.fil
        if let mp = mountPoint {
            let filURL = URL(fileURLWithPath: mp).appendingPathComponent("DevIcon.fil")
            if FileManager.default.fileExists(atPath: filURL.path),
               let img = NSImage(contentsOf: filURL) {
                return img
            }
        }
        
        // 2. Try default /Volumes/WALKMAN/DevIcon.fil
        let defaultWalkman = "/Volumes/WALKMAN/DevIcon.fil"
        if FileManager.default.fileExists(atPath: defaultWalkman),
           let img = NSImage(contentsOfFile: defaultWalkman) {
            return img
        }
        
        // 3. Try App Bundle Resources
        if let res = Bundle.main.url(forResource: "walkman_device_cropped", withExtension: "png"),
           let img = NSImage(contentsOf: res) {
            return img
        }
        if let res = Bundle.main.url(forResource: "walkman_device", withExtension: "png"),
           let img = NSImage(contentsOf: res) {
            return img
        }
        
        // 4. Try Relative Path from workspace
        for path in ["assets/walkman_device_cropped.png", "assets/walkman_device.png"] {
            if FileManager.default.fileExists(atPath: path),
               let img = NSImage(contentsOfFile: path) {
                return img
            }
        }
        
        return nil
    }
    
    public var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
                .fill(WalkmanTheme.cardHeaderGradient)
                .frame(width: size, height: size)
                .overlay(
                    RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
                        .stroke(Color.white.opacity(0.12), lineWidth: 1)
                )
            
            if let img = loadedImage ?? loadIcon() {
                Image(nsImage: img)
                    .resizable()
                    .scaledToFit()
                    .frame(width: size * 0.72, height: size * 0.78)
            } else {
                VectorWalkmanIcon(size: size * 0.7)
            }
        }
        .onAppear {
            self.loadedImage = loadIcon()
        }
        .onChange(of: mountPoint) {
            self.loadedImage = loadIcon()
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
