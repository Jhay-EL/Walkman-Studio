import os

# Volume name (displayed in Finder title bar and mount point)
volume_name = defines.get('volume_name', 'Walkman Studio')

# App bundle path
app_path = defines.get('app_path', 'Walkman Studio.app')

# Resolve paths relative to project root
PROJECT_DIR = defines.get('project_dir', os.getcwd())

# Files to include in the DMG root
files = [app_path]

# Symlink to /Applications folder
symlinks = {'Applications': '/Applications'}

# Volume badge icon
badge_icon_path = os.path.join(PROJECT_DIR, 'assets', 'AppIcon.icns')
badge_icon = badge_icon_path if os.path.exists(badge_icon_path) else None

# Background image (dmgbuild automatically bundles dmg_background@2x.png alongside it)
background = os.path.join(PROJECT_DIR, 'assets', 'dmg_background.png')

# Window positioning and bounds ((x, y), (width, height))
# Matches 660 x 400 pt (1320 x 800 px @2x)
window_rect = ((200, 120), (660, 400))

# Icon size in points (crisp 120pt presentation)
icon_size = 120.0
text_size = 13.0

# Target icon coordinates on the canvas
app_name = os.path.basename(app_path)
icon_locations = {
    app_name: (170, 185),
    'Applications': (490, 185)
}

# Clean dialog layout (no Finder toolbars or status bars)
show_status_bar = False
show_tab_view = False
show_toolbar = False
show_pathbar = False
show_sidebar = False
default_view = 'icon-view'

# Compression format (UDZO = zlib compressed DMG, standard for macOS distribution)
format = 'UDZO'
