# Walkman Studio Design System Language

## Overview & Philosophy

The Walkman Studio Design System Language is inspired by the precision industrial engineering and tactile craftsmanship of Sony Walkman digital audio players (NW-A55, NW-ZX300, NW-WM1A/Z) paired with modern Apple macOS Liquid Glass interface aesthetics.

Rather than adopting generic consumer software aesthetics or futuristic cyber/gaming glows, Walkman Studio embraces a **clean, tactile, and physical studio audio console** design philosophy: deep solid obsidian chassis, physical milled aluminum bevels, authentic optical glass refractions, and fluid spring kinetics.

---

## Core System Principles

### 1. Zero Background Gradients
* **Pure Solid Obsidian Backdrops**: All application windows, split view panels, sidebar backgrounds, and main view containers use solid, deep matte obsidian (`#101114`) and matte cards (`#18191D`).
* **No Ambient Radial Washes or Caustics**: Backdrops must never use radial gradient lighting, simulated atmospheric glow, or multi-color ambient lighting. Flat, high-contrast, distraction-free surfaces allow music metadata and album artwork to take center stage.

### 2. Zero Glow & Zero Bloom Effects
* **No Colored Shadows / Halos**: Colored drop shadows (e.g. gold, green, cyan, or orange glow halos) are strictly prohibited across the entire design system.
* **No Luminescent Bloom**: Indicators, beacons, and highlighted states must not emit light or glow outward. Status dots, badges, and compliance checkmarks are rendered with crisp vector geometry and solid contrast without neon bloom.
* **Deprecation of `goldGlow`**: The design system sets `WalkmanTheme.goldGlow` to `Color.clear`.
* **Zero Color Theming for System Tools & Dialogs**: System administration workflows, confirmation alerts, duplicate guardrail popups, and Backup & Restore operations must remain completely unthemed. Never apply arbitrary warm/gold or orange tinting to dialog containers, progress bars, radio buttons, or destructive warning banners. The interface uses pure, optical platinum/silver Liquid Glass exclusively.

### 3. Tactile Physical Depth
* **Natural Spatial Shadows**: Elevation and depth are achieved exclusively with subtle, neutral black drop shadows (`Color.black.opacity(...)`).
* **Crisp Hairline Rims**: Container edges and card outlines use 1px or 0.8px high-precision hairline borders (`Color.white.opacity(...)` or `WalkmanTheme.silverLight`) simulating milled aluminum chassis bezels.
* **Physical Spring Kinetics**: Interactive controls respond to clicks and hovers with snappy, subtle physical scale (`0.97` on press, `1.025` to `1.03` on hover) with zero motion blur.

### 4. Liquid Glass Optics & Matched Geometry Transitions
* **Authentic Optical Refraction**: Glass elements feature subtle top specular refraction sheens (`LinearGradient` from white opacity to clear) simulating light catching the top beveled edge of physical glass, rather than arbitrary flat transparency.
* **Seamless Sliding Glass Lens**: When switching segmented tabs or active controls, the selected Liquid Glass highlight must smoothly glide and morph its geometry across the track to the new selection using `matchedGeometryEffect` with an interactive spring curve (`.spring(response: 0.30, dampingFraction: 0.78)`).
* **Performance-Isolated Transitions**: High-frequency visual animations (e.g. pill sliding) must be scoped strictly to visual highlight states and never wrap data-source mutations or large collections (e.g., 7,000+ item tables), ensuring instantaneous `< 1ms` filtering.

---

## Palette & Surface Tokens

| Token | Hex / Value | Purpose |
|---|---|---|
| `WalkmanTheme.obsidian` | `#101114` | Primary solid app background (matte chassis body) |
| `WalkmanTheme.card` | `#18191D` | Standard card, inspector panel, and modal background |
| `WalkmanTheme.cardHover` | `#202126` | Interactive card hover state |
| `WalkmanTheme.silver` | `#DCE0E8` | Primary text and crisp brushed aluminum accents |
| `WalkmanTheme.silverLight` | `#F2F4F8` | Platinum highlight text and active border rims |
| `WalkmanTheme.silverMuted` | `#9BA0AC` | Secondary captions, icon symbols, and inactive states |
| `WalkmanTheme.hiResGold` | `#E8B944` | Authentic Sony Hi-Res Audio gold accent (matte, no glow) |
| `WalkmanTheme.hiResGoldLight` | `#F8D470` | Specular highlight for Hi-Res Audio elements |
| `WalkmanTheme.border` | `rgba(255, 255, 255, 0.08)` | Hairline container dividers and subtle separators |

---

## Component Guidelines

### 1. View Containers & Top Navigation Toolbars
* **100% Transparent Bar Background**: Top navigation strips and toolbar header containers must use `Color.clear` as their background. Never render dark gray or opaque backdrop rectangles (e.g. `#1E1F21`) behind top menu options.
* **Seamless Floating Controls**: Search capsules, segmented format bars, playback buttons, and status indicators must float directly over the solid `#101114` obsidian window backdrop.
* **Hairline Separation**: Separate toolbar controls from list/table content using a subtle bottom separator line (`Color.white.opacity(0.06)`, height: 0.8pt).
* **Responsive Adaptation (`ViewThatFits`)**:
  - Toolbars must gracefully support compact window dimensions (e.g. 13-inch MacBooks, split-screen mode, or when the right inspector panel is open).
  - Use `ViewThatFits(in: .horizontal)` to automatically switch between:
    - **Wide Layout**: Single-row configuration with search, segmented controls, playback controls, and track counts.
    - **Compact Layout**: Multi-row configuration where Row 1 displays the flexible search capsule and playback actions, and Row 2 displays segmented controls wrapped in `ScrollView(.horizontal, showsIndicators: false)`.
  - All segmented bars and tab pills **must** declare `.fixedSize(horizontal: true, vertical: false)` and `.lineLimit(1)` on their labels to strictly prevent text from wrapping vertically or distorting into squished circular shapes.

### 2. Liquid Glass Segmented Controls & Tabs
Segmented format bars and category switchers must follow this exact architecture across all views:

* **Outer Capsule Track**:
  - `padding(3)`, `frame(height: 38)`, `background(Color.white.opacity(0.04))`, `clipShape(Capsule())`, `overlay(Capsule().stroke(Color.white.opacity(0.10), lineWidth: 0.8))`.
  - Add `.fixedSize(horizontal: true, vertical: false)` to prevent horizontal stretching.
  - Spacing between tab pills: 4pt.
  - **Geometry**: The outer track is exactly **38pt tall**. Inner tab pills are exactly **32pt tall** (3pt inset padding each side = 38pt total).

* **Unselected & Idle State (Clean Transparency)**:
  - When a tab is neither hovered nor selected, its pill background and border stroke are **completely transparent** (`Color.clear`).
  - Text and icons float cleanly on the track with `Color.white.opacity(0.70)`.
  - **Full Round Click Box (Easy Hit Target)**: Must apply `.contentShape(Capsule())` backed by a non-zero alpha hit surface (`Color.white.opacity(0.001)`) across the entire capsule (`frame(height: 32)` — never `minHeight`, 14pt horizontal padding, 7pt vertical padding). Users must never have to click directly on label text glyphs; clicking anywhere in the round pill area triggers selection immediately.

* **Hover State (Tactile Liquid Glass Lift)**:
  - Subtly expands on hover using spring physics: `.scaleEffect(isHovered ? 1.03 : 1.0)` with `.animation(.spring(response: 0.22, dampingFraction: 0.72), value: isHovered)`.
  - Lights up with a frosted glass body: `Color.white.opacity(0.09)`.
  - Specular top refraction sheen (`LinearGradient` of `Color.white.opacity(0.20)` down to `clear`, height 5.5pt).
  - Hairline glass border (`Capsule().stroke(Color.white.opacity(0.22), lineWidth: 0.85)`).
  - Subtle physical drop shadow (`Color.black.opacity(0.15), radius: 2, y: 1`).
  - Text brightens to crisp `Color.white`.
  - Cursor changes to `NSCursor.pointingHand`.

* **Selected State (Seamless Gliding Lens)**:
  - Active Liquid Glass pill: `Color.white.opacity(isHiRes ? 0.13 : 0.16)`.
  - Bright specular refraction highlight (`LinearGradient` from `Color.white.opacity(isHovered ? 0.42 : 0.35)` to `clear`, height 6pt).
  - Crisp specular border: `Capsule().stroke(isHiRes ? WalkmanTheme.hiResGold.opacity(0.55) : Color.white.opacity(isHovered ? 0.45 : 0.34), lineWidth: 0.85)`.
  - Solid neutral depth shadow: `Color.black.opacity(0.25), radius: 3, y: 1`.
  - Bold typography in pure white or Hi-Res gold (`WalkmanTheme.hiResGoldLight`).
  - **Matched Geometry Animation**: Attached via `.matchedGeometryEffect(id: "activeTabHighlight", in: namespace)`. When selecting another tab, the entire glass lens (fill, specular highlight, border, and shadow) slides and morphs seamlessly to the newly selected tab using `.spring(response: 0.30, dampingFraction: 0.78)`.
  - **Data Isolation**: The visual highlight state (`activeHighlightId`) animates independently; the underlying filter data state updates without animation to keep data filtering instant (< 1ms).

### 3. Action Buttons & Hit Targets

All toolbar action buttons (Play, Shuffle, etc.) are standardized at **38pt tall** with **19pt corner radius** for a consistent pill shape aligned to the toolbar height.

* **Standard Button Height**: `frame(height: 38)` — never `minHeight`. Corner radius: `19pt`.
* **Horizontal Padding**: `padding(.horizontal, 14)` for labeled buttons; icon-only buttons use a fixed `38×38` square frame.
* **`LiquidGlassButtonStyle` Variants**:
  - `.prominent` — opaque gold-tinted fill for the primary action (e.g. "Play Hi-Res", "Play All"). Text foreground: near-black `Color(red: 20/255, green: 20/255, blue: 24/255)`.
  - `.glass` — frosted liquid glass body for secondary actions (e.g. Shuffle). Text foreground: `WalkmanTheme.silverLight`.
* **Hover & Press Kinetics**:
  - Buttons use `.scaleEffect(configuration.isPressed ? 0.97 : (isHovered ? 1.025 : 1.0))` with spring physics (`.spring(response: 0.22, dampingFraction: 0.70)`).
  - Subtle black shadow elevation increases on hover (`radius: 6, y: 3`) and compresses on press (`radius: 2, y: 1`).
  - Pointing hand cursor (`NSCursor.pointingHand`) on hover with proper push/pop balancing.

### 4. Search Capsules & Input Fields

* **Liquid Glass Capsule**: Continuous rounded rectangle with `frame(height: 38)` — never `minHeight` — and 12pt horizontal padding.
* **Corner Radius**: `10pt` (continuous style).
* **Subdued Frosted Fill**: `Color.white.opacity(0.06)` with top specular sheen gradient (7pt, `Color.white.opacity(0.12)` → `clear`).
* **Active State Focus**: Border stroke transitions from `Color.white.opacity(0.12)` when empty to `Color.white.opacity(0.30)` when active or query is present.
* **Shadow**: `Color.black.opacity(0.15), radius: 2.5, y: 1`.

### 5. Cards & Section Panels (`backupRestoreGlassCard`)
* **Layered Optical Material**:
  - Base: `WalkmanTheme.card.opacity(0.85)` over `.ultraThinMaterial`.
  - Top Specular Refraction: 8pt linear gradient from `Color.white.opacity(0.16)` to `Color.white.opacity(0.03)` down to `Color.clear`.
  - Hairline Edge Bezel: 0.85pt continuous stroke gradient (`Color.white.opacity(0.24)` down to `0.04`).
  - Spatial Shadow: `Color.black.opacity(0.22), radius: 8, x: 0, y: 3`.
* **Zero Accent Border Theming**: Cards never use gold, green, or orange outer borders. Active/selected cards (e.g. drive partitions, backup scope, discovered archives) indicate selection through an increased border opacity (`Color.white.opacity(0.35)` vs `0.10`) and subtle interior fill highlight (`Color.white.opacity(0.08)` vs `0.02`).

### 6. Count Indicator Pills (Toolbar Stat Badges)

Count pills display the active item tally (tracks, albums, artists) in the toolbar. All count pills are standardized at **38pt tall** across every view.

* **Geometry**: `frame(height: 38)`, `padding(.horizontal, 14)`, `clipShape(Capsule())`, `.fixedSize(horizontal: true, vertical: false)`.
* **Icon Size**: `font(.system(size: 11.5, weight: .bold))`.
* **Label Size**: `font(.system(size: 12.5, weight: .medium, design: .monospaced))`.
* **Background**: Two-layer `ZStack`:
  1. Base tint fill (see per-view palette below).
  2. Top specular sheen — `LinearGradient` from `Color.white.opacity(0.10)` → `clear`, height 8pt, applied via a `VStack` + `Spacer`.
* **Rim Stroke**: `LinearGradient` capsule stroke (`lineWidth: 0.8`) running top-to-bottom:
  - Standard views (All Songs, Recently Added, Albums, Artists): `Color.white.opacity(0.45)` → `.opacity(0.20)` → `.opacity(0.0)`.
  - Hi-Res Audio view: `WalkmanTheme.hiResGold.opacity(0.45)` → `.opacity(0.20)` → `.opacity(0.0)`.
* **Shadow**: `Color.black.opacity(0.10), radius: 2, x: 0, y: 1`.

#### Per-View Palette

| View | Icon Color | Label Color | Base Fill |
|---|---|---|---|
| All Songs | `Color.white.opacity(0.55)` | `WalkmanTheme.silverLight` | `Color.white.opacity(0.08)` |
| Recently Added | `Color.white.opacity(0.55)` | `WalkmanTheme.silverLight` | `Color.white.opacity(0.08)` |
| Albums | `Color.white.opacity(0.55)` | `WalkmanTheme.silverLight` | `Color.white.opacity(0.08)` |
| Artists | `Color.white.opacity(0.55)` | `WalkmanTheme.silverLight` | `Color.white.opacity(0.08)` |
| Playlists | `Color.white.opacity(0.55)` | `WalkmanTheme.silverLight` | `Color.white.opacity(0.08)` |
| Duplicates | `Color.white.opacity(0.55)` | `WalkmanTheme.silverLight` | `Color.white.opacity(0.08)` |
| Hi-Res Audio | `WalkmanTheme.hiResGold` | `WalkmanTheme.hiResGoldLight` | `WalkmanTheme.hiResGold.opacity(0.08)` |

> **Rule**: Never apply white liquid glass styling to the Hi-Res Audio count pill — the gold tint palette must be preserved. In the Duplicates view, duplicate scanning is strictly scoped to the same storage drive, and the segmented filter bar presents Same Storage and Quality Diff (with Cyan contextual accent) while preserving the standard Liquid Glass sliding lens and specular sheen. In the Transfer & Convert view, the destination mode segmented bar glides between Music Library and Language Study (with Hi-Res gold styling when active), the hardware optimization chips float cleanly over obsidian as 32pt Liquid Glass toggle capsules with top specular refraction sheens, and the Primary Action ("Start Transfer" / "Browse Audio Files...") adheres to the 38pt prominent Liquid Glass button standard.

### 7. Toolbar Height Alignment Summary

All interactive toolbar elements share a unified **38pt height baseline**:

| Element | `frame(height)` | Corner Radius | Notes |
|---|---|---|---|
| Search capsule | `38` | `10pt` | `frame(height: 38)` — never `minHeight` |
| Segmented bar outer track | `38` | Capsule | `padding(3)` inset → inner pills are 32pt |
| Segmented bar inner tab pills | `32` | Capsule | `frame(height: 32)` — never `minHeight` |
| Primary action button (labeled) | `38` | `19pt` | `padding(.horizontal, 14)` |
| Secondary action button (icon-only) | `38×38` | `19pt` | Square frame, full circle pill |
| Count indicator pill | `38` | Capsule | `padding(.horizontal, 14)` |

### 8. Audio Badges & Status Indicators
* Status indicators (e.g. active drive beacon dot, compliance verified checkmark, Selected badge) use clean flat fills.
* Audio badges (e.g. Hi-Res Audio, FW version) use subtle, natural black drop shadows (`Color.black.opacity(0.18)`), never colored gold or neon halos.

### 9. Modal Dialog Sheets & Alert Containers
Modal dialog sheets (`DuplicateImportGuardSheet`, `BackupAlbumPickerSheet`, `BackupTrackPickerSheet`, `BackupConfirmationSheet`, `RestoreConfirmationSheet`) provide critical system interventions and selections without visual distraction:
* **Frosted Dialog Chassis**:
  - Backdrop: `WalkmanTheme.card.opacity(0.92)` over `.ultraThinMaterial`.
  - Top Specular Refraction Sheen: 10pt linear gradient (`Color.white.opacity(0.24)` → `Color.white.opacity(0.05)` → `Color.clear`).
  - Hairline Border Gradient: 0.85pt continuous stroke from `Color.white.opacity(0.35)` down to `Color.white.opacity(0.06)`.
  - Modal Drop Shadow: Spatial neutral black shadow (`Color.black.opacity(0.45), radius: 28, x: 0, y: 12`).
* **Unthemed Liquid Glass Header Badges**:
  - Frame: 44×44 or 48×48 continuous rounded rectangle (`cornerRadius: 12`).
  - Surface: `Color.white.opacity(0.08)` with 12–14pt top specular reflection sheen (`Color.white.opacity(0.28)` → `Color.clear`).
  - Hairline Rim: 0.85pt stroke gradient (`Color.white.opacity(0.38)` → `0.12` → `0.04`).
  - Iconography: Pure silver/platinum (`WalkmanTheme.silverLight`). Never use solid orange/yellow warning boxes.
* **Tactile Sheet Close Button (`SheetCloseButton`)**:
  - Frame: Fixed 28×28 circular hit target.
  - Base Fill: `Color.white.opacity(0.08)`, expanding to `Color.white.opacity(0.16)` on hover.
  - Border Stroke: 0.8pt hairline (`Color.white.opacity(0.12)` → `0.30` on hover).
  - Kinetics & Accessibility: `.scaleEffect(isHovered ? 1.08 : 1.0)`, `NSCursor.pointingHand`, and bound to `.keyboardShortcut(.cancelAction)` (`Esc`).
* **Action Footer Layout**:
  - Direct, clear action nomenclature (e.g. `"Skip Duplicates"`, `"Add All Anyway"` rather than verbose duplicate descriptions).
  - Secondary / Cancel: 38pt height `LiquidGlassButtonStyle(variant: .glass, cornerRadius: 19)` with silver text.
  - Primary Action: 38pt height `LiquidGlassButtonStyle(variant: .prominent, cornerRadius: 19)` with platinum gradient and near-black text (`Color(red: 20/255, green: 20/255, blue: 24/255)`).

### 10. Asynchronous Operations & Progressive Import UX
* **Zero UI Thread Blocking**:
  - File system enumeration, nested directory walking, duplicate hash calculation, and tag extraction must **never** run on `@MainActor`.
  - All disk scanning is offloaded to detached background tasks (`Task.detached(priority: .userInitiated)`), keeping the SwiftUI runloop fully responsive at 60/120fps.
* **Liquid Glass Live Import Progress UI**:
  - When dragging and dropping audio folders into the Transfer Queue or Library, the view transitions to a dedicated Liquid Glass importing container rather than freezing or leaving the drop zone blank.
  - Real-time track counter ("Importing track X of Y..."), monospaced file pill, and an optical progress bar (`ImportProgressBar`) featuring a top specular reflection sheen and neutral drop shadow.
  - Queue-level progress banner for unobtrusive background importing when the user is navigating away from the drop target.

### 11. Storage-Scoped Data Workflows (Duplicates & Backup/Restore Partition Safety)
* **Same-Storage Scoping for Deduplication**:
  - In Sony Walkman devices, the internal flash storage and external MicroSD expansion card have distinct mount points and FAT32/exFAT directory trees.
  - Duplicate detection is strictly scoped within the **same storage partition** (Internal vs. Internal, SD Card vs. SD Card). The legacy "All" vs "Same Storage" split is consolidated into an automatic same-storage engine to prevent unintentional deletion across partitions.
* **Dedicated Partition Pickers**:
  - Both Source and Target drive pickers in Backup & Restore use tactile Liquid Glass partition cards displaying clean drive labels, partition types (Internal Flash vs. MicroSD Card), and exact byte metrics (`formatBytes(usedBytes)` • `formatBytes(freeBytes)`).
  - Active partition selection is indicated with a clean `WalkmanTheme.silverLight` checkmark and an active 1.2pt platinum stroke without gold or colored halos.

### 12. Component Baseline Height & Radius Standardization
A unified dimensional scale enforces physical alignment across the entire console:

| Component Type | Height | Corner Radius | Style Variant | Hit Target Rule |
|---|---|---|---|---|
| Search Capsule | `38pt` | `10pt` | Frosted Glass Fill | Minimum 12pt horizontal inset |
| Mode / Segmented Track | `38pt` | Capsule | Glass Capsule Track | Inset `padding(3)`, inner pills: `32pt` |
| Mode / Tab Inner Pill | `32pt` | Capsule | Gliding Glass Lens | Full capsule click box via `.contentShape(Capsule())` |
| Primary Action Button | `38pt` | `19pt` | `.prominent` (Platinum) | Near-black text on white/platinum glass |
| Secondary Action Button | `38pt` | `19pt` | `.glass` (Translucent) | Silver text with hairline glass rim |
| Utility / Mini Action Button | `28pt` | `8pt` | `.glass` (Compact) | In-row actions (Browse, Reveal, Cancel) |
| Toolbar Count Pill | `38pt` | Capsule | Specular Sheen Pill | `padding(.horizontal, 14)` |
| Modal Sheet Close Button | `28×28pt` | Circle | Glass Circle | Hover spring scale `1.08`, `NSCursor.pointingHand` |
| Dialog / Modal Chassis | Dynamic | `16pt` | Frosted Modal Overlay | 10pt specular sheen, 0.85pt hairline border |
| Studio Card / Section Panel | Dynamic | `14pt` | Glass Card Modifier | 8pt specular sheen, 0.85pt hairline border |
