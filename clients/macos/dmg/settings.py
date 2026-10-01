# dmgbuild settings for FuseOS.dmg (make-dmg.sh passes app, readme and background with -D).
# Icon positions must match make-background.py.
import os

app = defines["app"]
readme = defines["readme"]

volume_name = "FuseOS"
format = "UDZO"
files = [app, readme]
symlinks = {"Applications": "/Applications"}
hide_extension = [os.path.basename(app), os.path.basename(readme)]

background = defines["background"]
# Taller than the layout: newer Finders always show the toolbar and status bar (~125 pt).
window_rect = ((200, 120), (660, 540))
default_view = "icon-view"
show_status_bar = False
show_tab_view = False
show_toolbar = False
show_pathbar = False
show_sidebar = False
icon_size = 96
text_size = 13
icon_locations = {
    os.path.basename(app): (170, 180),
    "Applications": (490, 180),
    os.path.basename(readme): (330, 320),
}
