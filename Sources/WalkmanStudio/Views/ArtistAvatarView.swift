import SwiftUI
import AppKit
import Combine

public struct ArtistAvatarView: View {
    public let artistName: String
    public let representativeTrack: Track?
    public var size: CGFloat = 34
    public var isSelected: Bool = false
    public var showBorder: Bool = true
    
    @State private var image: NSImage?
    
    public init(
        artistName: String,
        representativeTrack: Track? = nil,
        size: CGFloat = 34,
        isSelected: Bool = false,
        showBorder: Bool = true
    ) {
        self.artistName = artistName
        self.representativeTrack = representativeTrack
        self.size = size
        self.isSelected = isSelected
        self.showBorder = showBorder
    }
    
    public var body: some View {
        ZStack {
            if let img = image {
                Image(nsImage: img)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: size, height: size)
                    .clipShape(Circle())
                    .overlay(
                        Circle()
                            .stroke(
                                isSelected ? WalkmanTheme.hiResGold.opacity(0.85) : (showBorder ? Color.white.opacity(0.14) : Color.clear),
                                lineWidth: isSelected ? 1.5 : 0.8
                            )
                    )
                    .shadow(
                        color: isSelected ? WalkmanTheme.hiResGold.opacity(0.35) : Color.black.opacity(0.25),
                        radius: isSelected ? 4 : 2
                    )
            } else {
                // Fallback circular badge with artist initials
                ZStack {
                    Circle()
                        .fill(isSelected ? WalkmanTheme.silverGradient : LinearGradient(
                            colors: [Color.white.opacity(0.12), Color.white.opacity(0.06)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ))
                        .frame(width: size, height: size)
                    
                    Text(String(artistName.prefix(1)).uppercased())
                        .font(.system(size: max(10, size * 0.42), weight: .bold))
                        .foregroundStyle(isSelected ? Color(red: 20/255, green: 20/255, blue: 24/255) : .white)
                }
                .overlay(
                    Circle()
                        .stroke(
                            isSelected ? WalkmanTheme.silver.opacity(0.5) : (showBorder ? Color.white.opacity(0.08) : Color.clear),
                            lineWidth: 0.8
                        )
                )
            }
        }
        .frame(width: size, height: size)
        .onAppear {
            loadImage()
        }
        .onChange(of: artistName) {
            loadImage()
        }
        .onReceive(NotificationCenter.default.publisher(for: .artistArtworkDidChange)) { notif in
            if let changed = notif.userInfo?["artist"] as? String,
               changed.localizedCaseInsensitiveCompare(artistName) == .orderedSame {
                loadImage(force: true)
            }
        }
    }
    
    private func loadImage(force: Bool = false) {
        if !force, let cached = ArtistArtCache.shared.cachedImage(for: artistName) {
            self.image = cached
            return
        }
        
        ArtistArtCache.shared.loadArtistImage(for: artistName, representativeTrack: representativeTrack, forceRefresh: force) { img in
            Task { @MainActor in
                withAnimation(.easeIn(duration: 0.15)) {
                    self.image = img
                }
            }
        }
    }
}
