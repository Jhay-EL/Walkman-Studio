import Foundation
import AppKit
import UniformTypeIdentifiers

@MainActor
public enum ArtworkExportService {
    
    /// Exports the cover art for a specific track to the Mac
    public static func exportArtwork(for track: Track) {
        let url = URL(fileURLWithPath: track.fullPath)
        
        var artData = AudioTagger.shared.extractCoverArt(fileURL: url)
        if artData == nil, let thumb = CoverArtCache.shared.thumbnail(for: track) {
            artData = imageToJPEGData(thumb)
        }
        
        guard let data = artData, !data.isEmpty else {
            showNoArtworkAlert(itemDescription: "\"\(track.title)\"")
            return
        }
        
        let cleanArtist = WalkmanEngine.shared.sanitizeFilename(track.artist.isEmpty ? "Unknown Artist" : track.artist)
        let cleanAlbum = WalkmanEngine.shared.sanitizeFilename(track.album.isEmpty ? track.title : track.album)
        let defaultName = "\(cleanArtist) - \(cleanAlbum) Cover.jpg"
        
        presentSavePanel(data: data, defaultFilename: defaultName)
    }
    
    /// Exports the cover art for an entire album to the Mac
    public static func exportArtwork(for album: AlbumItem) {
        var artData: Data? = nil
        
        if let rep = album.representativeTrack {
            let url = URL(fileURLWithPath: rep.fullPath)
            artData = AudioTagger.shared.extractCoverArt(fileURL: url)
            if artData == nil, let thumb = CoverArtCache.shared.thumbnail(for: rep) {
                artData = imageToJPEGData(thumb)
            }
        }
        
        guard let data = artData, !data.isEmpty else {
            showNoArtworkAlert(itemDescription: "album \"\(album.name)\"")
            return
        }
        
        let cleanArtist = WalkmanEngine.shared.sanitizeFilename(album.artist.isEmpty ? "Unknown Artist" : album.artist)
        let cleanAlbum = WalkmanEngine.shared.sanitizeFilename(album.name.isEmpty ? "Unknown Album" : album.name)
        let defaultName = "\(cleanArtist) - \(cleanAlbum) Cover.jpg"
        
        presentSavePanel(data: data, defaultFilename: defaultName)
    }
    
    /// Exports arbitrary artwork data or an NSImage with a suggested filename
    public static func exportCustomArtwork(data: Data?, image: NSImage?, suggestedFilename: String) {
        var exportData = data
        if (exportData == nil || exportData?.isEmpty == true), let img = image {
            exportData = imageToJPEGData(img)
        }
        
        guard let validData = exportData, !validData.isEmpty else {
            showNoArtworkAlert(itemDescription: "this item")
            return
        }
        
        var finalName = WalkmanEngine.shared.sanitizeFilename(suggestedFilename)
        if !finalName.lowercased().hasSuffix(".jpg") && !finalName.lowercased().hasSuffix(".jpeg") && !finalName.lowercased().hasSuffix(".png") {
            finalName += ".jpg"
        }
        
        presentSavePanel(data: validData, defaultFilename: finalName)
    }
    
    // MARK: - Internal Helpers
    
    private static func presentSavePanel(data: Data, defaultFilename: String) {
        let panel = NSSavePanel()
        panel.title = "Save Cover Art to Mac"
        panel.prompt = "Save Artwork"
        panel.nameFieldStringValue = defaultFilename
        panel.allowedContentTypes = [.jpeg, .png]
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        
        // Default to user's Pictures or Downloads folder
        if let pictures = FileManager.default.urls(for: .picturesDirectory, in: .userDomainMask).first {
            panel.directoryURL = pictures
        } else if let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first {
            panel.directoryURL = downloads
        }
        
        if panel.runModal() == .OK, let targetURL = panel.url {
            do {
                try data.write(to: targetURL)
                // Reveal the newly saved file in Finder
                NSWorkspace.shared.activateFileViewerSelecting([targetURL])
            } catch {
                let alert = NSAlert()
                alert.messageText = "Failed to Save Cover Art"
                alert.informativeText = error.localizedDescription
                alert.alertStyle = .warning
                alert.runModal()
            }
        }
    }
    
    private static func imageToJPEGData(_ image: NSImage) -> Data? {
        guard let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff) else {
            return nil
        }
        return bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.95])
    }
    
    private static func showNoArtworkAlert(itemDescription: String) {
        let alert = NSAlert()
        alert.messageText = "No Artwork Available"
        alert.informativeText = "There is no embedded album artwork or companion folder image for \(itemDescription)."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}
