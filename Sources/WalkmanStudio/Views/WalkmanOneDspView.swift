import SwiftUI

public struct WalkmanOneDspView: View {
    let drives: [WalkmanDrive]
    let activeDrive: WalkmanDrive?
    
    @State private var selectedMountPoint: String = ""
    @State private var soundSignature: String = "WM1Z"
    @State private var dacGain: String = "0"
    @State private var plusV2: String = "1"
    @State private var vinylProcessor: String = "0"
    @State private var hardwareTuning: String = "Neutral"
    @State private var rawText: String = ""
    @State private var isRawMode: Bool = false
    @State private var hasCfwFolder: Bool = false
    @State private var saveStatus: String?
    
    public init(drives: [WalkmanDrive], activeDrive: WalkmanDrive?) {
        self.drives = drives
        self.activeDrive = activeDrive
        _selectedMountPoint = State(initialValue: activeDrive?.mountPoint ?? drives.first?.mountPoint ?? "")
    }
    
    private let soundSignatures: [(id: String, name: String, desc: String, badge: String)] = [
        ("WM1Z", "Sony NW-WM1Z Signature", "Warm, organic sound with deep analog bass extension and rich vocal warmth.", "Flagship Signature"),
        ("DMP-Z1", "Sony DMP-Z1 Digital Music Player", "Ultra-wide holographic soundstage, reference transient speed, and crystalline highs.", "Ultimate Reference"),
        ("ZX300", "Sony NW-ZX300", "Punchy, aggressive mid-bass slam with energetic forward dynamics.", "Dynamic Energy"),
        ("Neutral", "Studio Reference Flat", "Uncolored bit-perfect frequency response for clinical monitoring.", "Monitoring")
    ]
    
    private func loadSettings() {
        let mount = selectedMountPoint.isEmpty ? (activeDrive?.mountPoint ?? "") : selectedMountPoint
        guard !mount.isEmpty else { return }
        
        let settings = WalkmanEngine.shared.readCfwSettings(mountPoint: mount)
        self.hasCfwFolder = settings.hasCfw
        self.rawText = settings.rawText
        
        let parsed = settings.parsed
        if let sig = parsed["sound_signature"] { self.soundSignature = sig }
        if let gain = parsed["dac_gain"] { self.dacGain = gain }
        if let v2 = parsed["plus_v2"] { self.plusV2 = v2 }
        if let vinyl = parsed["vinyl_processor"] { self.vinylProcessor = vinyl }
        if let tune = parsed["hardware_tuning"] { self.hardwareTuning = tune }
    }
    
    private func saveSettings() {
        let mount = selectedMountPoint.isEmpty ? (activeDrive?.mountPoint ?? "") : selectedMountPoint
        guard !mount.isEmpty else { return }
        
        do {
            if isRawMode {
                try WalkmanEngine.shared.saveCfwSettings(mountPoint: mount, settings: [:], rawOverride: rawText)
            } else {
                let dict: [String: String] = [
                    "sound_signature": soundSignature,
                    "dac_gain": dacGain,
                    "plus_v2": plusV2,
                    "vinyl_processor": vinylProcessor,
                    "hardware_tuning": hardwareTuning
                ]
                try WalkmanEngine.shared.saveCfwSettings(mountPoint: mount, settings: dict)
            }
            
            withAnimation {
                saveStatus = "Saved to /CFW/settings.txt (Reboot Walkman to apply)"
                hasCfwFolder = true
            }
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
                withAnimation { saveStatus = nil }
            }
        } catch {
            withAnimation {
                saveStatus = "Error saving: \(error.localizedDescription)"
            }
        }
    }
    
    public var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Header
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 8) {
                            Text("Walkman One CFW Tuning")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundStyle(.white)
                            
                            Text("Custom Firmware")
                                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(WalkmanTheme.gold.opacity(0.15))
                                .foregroundStyle(WalkmanTheme.gold)
                                .clipShape(Capsule())
                        }
                        
                        Text("Configure S-Master HX hardware DSP registers and emulation models on your NW-A55L.")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    
                    Spacer()
                    
                    if let status = saveStatus {
                        Text(status)
                            .font(.system(size: 11, weight: .medium))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(WalkmanTheme.gold.opacity(0.2))
                            .foregroundStyle(WalkmanTheme.gold)
                            .clipShape(Capsule())
                    }
                    
                    Button(action: saveSettings) {
                        HStack(spacing: 6) {
                            Image(systemName: "bolt.fill")
                            Text("Flash to Walkman")
                        }
                        .font(.system(size: 11, weight: .bold))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(WalkmanTheme.goldGradient)
                        .foregroundStyle(.black)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 4)
                
                // Target Drive & Mode Picker
                HStack(spacing: 14) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("TARGET VOLUME")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.tertiary)
                        
                        Picker("", selection: $selectedMountPoint) {
                            ForEach(drives) { d in
                                Text(d.name).tag(d.mountPoint)
                            }
                        }
                        .pickerStyle(.menu)
                        .tint(WalkmanTheme.gold)
                        .onChange(of: selectedMountPoint) {
                            loadSettings()
                        }
                    }
                    .padding(12)
                    .liquidGlass(cornerRadius: 10)
                    
                    VStack(alignment: .leading, spacing: 6) {
                        Text("EDITOR MODE")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.tertiary)
                        
                        Picker("", selection: $isRawMode) {
                            Text("Visual Presets").tag(false)
                            Text("Raw /CFW/settings.txt").tag(true)
                        }
                        .pickerStyle(.segmented)
                    }
                    .padding(12)
                    .liquidGlass(cornerRadius: 10)
                }
                
                if isRawMode {
                    // Raw Settings Text Editor
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("RAW SETTINGS.TXT (CRLF)")
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .foregroundStyle(WalkmanTheme.gold)
                            Spacer()
                            Text("Saved to /CFW/settings.txt")
                                .font(.system(size: 9))
                                .foregroundStyle(.secondary)
                        }
                        
                        TextEditor(text: $rawText)
                            .font(.system(size: 11, design: .monospaced))
                            .scrollContentBackground(.hidden)
                            .padding(10)
                            .frame(minHeight: 280)
                            .background(WalkmanTheme.surface)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .padding(16)
                    .liquidGlass(cornerRadius: 12)
                } else {
                    // Visual Sound Signatures Cards
                    VStack(alignment: .leading, spacing: 12) {
                        Text("EMULATION SOUND SIGNATURE")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, 4)
                        
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                            ForEach(soundSignatures, id: \.id) { sig in
                                let isSel = soundSignature == sig.id
                                Button(action: { soundSignature = sig.id }) {
                                    VStack(alignment: .leading, spacing: 8) {
                                        HStack {
                                            Text(sig.name)
                                                .font(.system(size: 12, weight: .bold))
                                                .foregroundStyle(isSel ? WalkmanTheme.gold : .white)
                                            
                                            Spacer()
                                            
                                            Text(sig.badge)
                                                .font(.system(size: 8, weight: .bold, design: .monospaced))
                                                .padding(.horizontal, 5)
                                                .padding(.vertical, 2)
                                                .background(isSel ? WalkmanTheme.gold.opacity(0.2) : WalkmanTheme.card)
                                                .foregroundStyle(isSel ? WalkmanTheme.gold : .secondary)
                                                .clipShape(Capsule())
                                        }
                                        
                                        Text(sig.desc)
                                            .font(.system(size: 10))
                                            .foregroundStyle(.secondary)
                                            .lineLimit(3)
                                            .fixedSize(horizontal: false, vertical: true)
                                    }
                                    .padding(14)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(
                                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                                            .fill(isSel ? WalkmanTheme.cardHover : WalkmanTheme.card)
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                                            .stroke(isSel ? WalkmanTheme.gold : Color.white.opacity(0.05), lineWidth: isSel ? 1.5 : 1)
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    
                    // Hardware DSP Registers
                    VStack(alignment: .leading, spacing: 14) {
                        Text("S-MASTER HX DSP & GAIN CONTROLS")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, 4)
                        
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                            // DAC Gain
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text("DAC Output Gain")
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundStyle(.white)
                                    Spacer()
                                    Text(dacGain == "1" ? "High Gain (+6dB)" : "Normal Gain (0dB)")
                                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                                        .foregroundStyle(WalkmanTheme.gold)
                                }
                                
                                Picker("", selection: $dacGain) {
                                    Text("Normal (IEMs)").tag("0")
                                    Text("High Gain (Over-ear)").tag("1")
                                }
                                .pickerStyle(.segmented)
                                
                                Text("High Gain delivers higher voltage swing for high-impedance headphones.")
                                    .font(.system(size: 9))
                                    .foregroundStyle(.secondary)
                            }
                            .padding(14)
                            .liquidGlass(cornerRadius: 10)
                            
                            // Vinyl Processor
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text("Vinyl Processor")
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundStyle(.white)
                                    Spacer()
                                    Text(vinylProcessor == "1" ? "Enabled" : "Bypassed")
                                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                                        .foregroundStyle(vinylProcessor == "1" ? WalkmanTheme.gold : .secondary)
                                }
                                
                                Picker("", selection: $vinylProcessor) {
                                    Text("Bypassed").tag("0")
                                    Text("Analog Emulation").tag("1")
                                }
                                .pickerStyle(.segmented)
                                
                                Text("Recreates tone-arm resonance, surface noise absorption, and acoustic feedback.")
                                    .font(.system(size: 9))
                                    .foregroundStyle(.secondary)
                            }
                            .padding(14)
                            .liquidGlass(cornerRadius: 10)
                            
                            // Plus v2 Audio Stack
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text("Walkman Plus v2 Engine")
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundStyle(.white)
                                    Spacer()
                                    Text(plusV2 == "1" ? "Active" : "Disabled")
                                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                                        .foregroundStyle(plusV2 == "1" ? WalkmanTheme.gold : .secondary)
                                }
                                
                                Picker("", selection: $plusV2) {
                                    Text("Standard").tag("0")
                                    Text("Plus v2 Active").tag("1")
                                }
                                .pickerStyle(.segmented)
                                
                                Text("Custom audio driver pipeline prioritizing lower jitter and cleaner phase alignment.")
                                    .font(.system(size: 9))
                                    .foregroundStyle(.secondary)
                            }
                            .padding(14)
                            .liquidGlass(cornerRadius: 10)
                            
                            // Hardware Tuning
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text("Hardware Tuning Profile")
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundStyle(.white)
                                    Spacer()
                                    Text(hardwareTuning)
                                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                                        .foregroundStyle(WalkmanTheme.gold)
                                }
                                
                                Picker("", selection: $hardwareTuning) {
                                    Text("Neutral").tag("Neutral")
                                    Text("Warm").tag("Warm")
                                    Text("Bright").tag("Bright")
                                }
                                .pickerStyle(.segmented)
                                
                                Text("Adjusts digital high-pass and low-pass capacitor response characteristics.")
                                    .font(.system(size: 9))
                                    .foregroundStyle(.secondary)
                            }
                            .padding(14)
                            .liquidGlass(cornerRadius: 10)
                        }
                    }
                }
            }
            .padding(16)
        }
        .onAppear {
            loadSettings()
        }
        .onChange(of: activeDrive?.mountPoint) { _, newMount in
            if let m = newMount {
                selectedMountPoint = m
                loadSettings()
            }
        }
    }
}
