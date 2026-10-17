# Teleprompter (iPad)

A simple iPad teleprompter. SwiftUI app with a UIKit scrolling engine, iPadOS 17 or later, iPad only.

## Install on your iPad

1. Open `Teleprompter.xcodeproj` in Xcode.
2. Plug in the iPad (or use the same Wi-Fi with "Connect via network") and pick it as the run destination at the top of Xcode.
3. Target **Teleprompter → Signing & Capabilities**: the team is preset to `RJNF5CMXY6` (the Flashoot team). Choose your own team there if needed. If Xcode says the bundle ID is taken, change `com.flashoot.teleprompter` to something unique.
4. Press **Run** (⌘R). The first time, on the iPad open **Settings → Privacy & Security → Developer Mode** and turn it on if asked. With a free Apple ID you may also need to trust the developer under **Settings → General → VPN & Device Management**.

If you change `project.yml`, regenerate the project with `xcodegen generate`.

## Features

- Script library: create, duplicate, delete, import `.txt` / `.rtf` files from Files, saved automatically.
- Editor: Paste (replace or add to the end), Undo, word count, line count and estimated reading time.
- Clean Up menu: remove extra blank lines, remove all blank lines, join broken lines into paragraphs, blank line between paragraphs, remove punctuation (keeps don't, 3.50, 1,000), remove [notes] and (directions), trim spaces, UPPERCASE, quick clean. Optional auto clean on paste.
- Full-screen prompter: smooth 120 Hz scrolling, speed 1–100, countdown, tap to pause / play, drag to move back or forward, jump buttons, back to top, elapsed and remaining time, screen never sleeps while prompting.
- Display: mirror left–right (for teleprompter glass), flip upside down, 14 fonts, 5 weights, size 20–200 pt, line spacing, side margins, alignment, ALL CAPS, colour themes and custom colours, reading guide (arrows, line or highlight band) with adjustable position, fading top and bottom edges.
- Keyboard and Bluetooth remotes: Space / Return play-pause, ← → speed, ↑ ↓ one line, Page Up / Page Down jump, Home back to top, − = text size, M mirror, Esc close. Hold ⌘ on a keyboard to see the list.

## Remote control from a Mac or iPhone (same Wi-Fi only)

1. On the iPad: Scripts list → Remote button (the waves icon) → turn on **Allow remote control**. Allow Local Network access if iOS asks.
2. On the Mac, open the address shown (for example `http://192.168.1.20:8080`) in Safari or Chrome and type the 6-digit code. On an iPhone, scan the QR code with the Camera (it carries the code).
3. The page has play / pause, jump, line nudge, speed, text size, mirror, close, a list of scripts to open on the iPad, and a box to paste a new script and send it to the iPad. Mac keyboard shortcuts match the iPad's.

Safety: the iPad app only answers devices with private local-network addresses (192.168.x.x, 10.x.x.x, 172.16–31.x.x), never cellular, and every request needs the code. 10 wrong codes block that device for 5 minutes. "Make a new code" disconnects everyone. The remote pauses while the app is in the background.

## Code map

- `Teleprompter/Models` — scripts store (JSON in Application Support), settings (UserDefaults), text clean-up.
- `Teleprompter/Prompter` — `PrompterEngine` (display-link scrolling), `PrompterTextController` (TextKit 1 text view, mirroring, guide, keys), `PrompterView` (full-screen UI).
- `Teleprompter/Views` — library, editor, settings form.
- `Teleprompter/Remote` — `RemoteServer` (tiny HTTP server on Network.framework, port 8080), `RemotePage` (the web page), `RemoteControlView` (iPad screen with address, code, QR).
