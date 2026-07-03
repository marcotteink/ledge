# Ledge

A free, open source drag-and-drop shelf for macOS.

Start dragging a file anywhere on your Mac and a small shelf fades in at the
edge of your screen. Drop the file there, navigate wherever you need to go,
then drag it back out. No subscription, no account, no network calls. Runs
entirely on your machine.

**[Download Ledge.zip](https://github.com/marcotteink/ledge/releases/latest/download/Ledge.zip)**
(macOS 13+, universal for Apple Silicon and Intel)

**[Website and install guide](https://marcotteink.github.io/ledge/)**

First launch: Ledge is not notarized through Apple's paid developer program,
so right-click the app and choose Open (or use System Settings > Privacy &
Security > Open Anyway). Or clear the flag in Terminal:

```
xattr -d com.apple.quarantine /Applications/Ledge.app
```

## How it works

- Lives in the menu bar (tray icon), no Dock icon.
- Watches the system drag pasteboard with a lightweight 10x/second poll.
  No accessibility permissions needed.
- The shelf appears when you start dragging files, file promises (images from
  browsers, Mail attachments), or text. It hides again when it is empty.
- Dragging an item out of the shelf to another app or Finder removes it from
  the shelf automatically. Dragging out performs a copy, so the original file
  stays where it was.
- Items persist across restarts (stored in
  `~/Library/Application Support/Ledge/`).

## Using it

| Action | Result |
| --- | --- |
| Drag a file, drop on shelf | Item parked on the shelf |
| Drag item off shelf | Copied to destination, removed from shelf |
| Double-click an item | Opens the file |
| Hover, click the x | Removes the item |
| Trash icon in header | Clears the whole shelf |
| F5 | Show or hide the shelf from anywhere |
| Drag the shelf header | Move the shelf anywhere |

## Menu bar features

- **Bring Back Last Removed Files**: undoes the last removal (drag-out, x,
  or Clear). Remembers the last 10 removals, most recent first.
- **Add Clipboard Contents to Ledge**: parks whatever is on the clipboard.
  Files are added as references; images land as PNG files; text becomes a
  .txt snippet.
- **Automatically Add Clipboard**: toggle clipboard watching. While on,
  every copy you make anywhere lands on the shelf silently, so you can copy
  several things in a row and they all stack up instead of overwriting each
  other. Duplicate back-to-back copies are skipped, and anything a password
  manager marks as concealed is ignored.
- **Import from iPhone or iPad**: Continuity Camera. Take a photo or scan a
  document with your iPhone and it lands on the shelf. Requires the iPhone
  to be signed into the same Apple ID with Wi-Fi and Bluetooth on.
- **Window Position**: left or right edge (top, middle, bottom), or at the
  mouse pointer.
- **Window Size**: Small, Medium, Large.
- **Show Ledge (F5)**: global hotkey, works from any app. If F5 triggers
  dictation or a media function instead, either hold Fn or enable
  "Use F1, F2, etc. keys as standard function keys" in System Settings >
  Keyboard.
- **Show Shelf for Text Drags**: toggle whether dragging selected text pops
  the shelf.
- **Start at Login**: registers the app as a login item (shown when running
  from the built .app).

## Building

Requires the Xcode Command Line Tools (Swift 5.9+).

```
./build.sh
open dist/Ledge.app
```

To keep it around permanently, copy `dist/Ledge.app` to `/Applications` and
enable "Start at Login" from the menu bar icon.

## Known limitations vs Yoink

- Dragging out always copies (Yoink can move).
- One item per drag out (no multi-select or drag-all handle yet).
- The shelf returns to its configured position each time it appears; manual
  repositioning lasts only while it stays visible.
- No Force Touch, stacking, or Handoff extras.
