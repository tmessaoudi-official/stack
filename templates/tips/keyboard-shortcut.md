# Text Snippet Automation with AutoKey

**What it solves**: Typing long, repetitive text strings (email signatures, code templates, boilerplate commands) by expanding short abbreviations — system-wide, in any application. This is the Linux equivalent of macOS's text replacement or Windows AutoHotKey for text snippets.

**When to reach for it**: You find yourself typing the same multi-line blocks repeatedly across different applications (terminal, browser, IDE). Unlike IDE snippets, AutoKey works everywhere on the desktop.

**The non-obvious part**: AutoKey comes in two versions — `autokey-gtk` (GTK/X11 apps) and `autokey-qt` (KDE). On Wayland, AutoKey has limited support because Wayland restricts applications from injecting input into other windows. If you're on Wayland (`echo $XDG_SESSION_TYPE`), it may work via XWayland for some apps but not natively. X11 sessions have full support.

Install:
```bash
sudo apt install autokey-gtk
```

Reference: https://askubuntu.com/questions/543968/tool-to-insert-text-snippets-into-applications/799654#799654
