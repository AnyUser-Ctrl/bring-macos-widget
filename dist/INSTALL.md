# Bring Widget — Offline installation

This guide covers installing **Bring Widget** from a package you built
yourself with `scripts/package.sh` (for example to reinstall without
GitHub access). You only need the files in this `dist/` folder and a Mac
running macOS 14 (Sonoma) or later.

> The packages are signed with your own "Apple Development" certificate.
> They run reliably only on the Mac they were built on. Never publish them
> (e.g. as a GitHub release): the signature contains the name and email
> of the Apple Account holder.

## What you have

- `BringWidget.dmg` — when mounted, shows a window with `BringWidget.app`
  and a drag target to `/Applications/`. The most convenient option.
- `BringWidget.app.zip` — portable alternative. Double-click it in Finder
  → `BringWidget.app` appears next to it.
- `INSTALL.md` — this guide.

Both packages contain **the same app** — use whichever format you prefer.

## Option A — `.dmg` (recommended)

1. **Mount the DMG:** double-click `BringWidget.dmg`.
2. **Drag the app:** in the window that opens, drag `BringWidget.app` onto
   the `Applications` icon.
3. **Eject the DMG:** in the Finder sidebar, click the eject icon next to
   "Bring Widget".
4. Continue with **"First launch"** below.

## Option B — `.zip`

1. **Unpack:** double-click `BringWidget.app.zip` → `BringWidget.app`
   appears.
2. **Move:** drag `BringWidget.app` into the `/Applications/` folder.
3. Continue with **"First launch"**.

## First launch

On first launch, Gatekeeper notices that the app isn't from the App Store
and may block it.

1. **Open Terminal** (Spotlight: `⌘ + Space` → "Terminal" → Enter)
2. **Remove the quarantine attribute** (once per installation):

   ```sh
   xattr -dr com.apple.quarantine /Applications/BringWidget.app
   ```

3. **Launch the app:**

   ```sh
   open /Applications/BringWidget.app
   ```

   If macOS still warns ("developer cannot be verified"):
   - System Settings → **Privacy & Security**
   - At the bottom: click **"Open Anyway"** for "BringWidget"

   On first launch the app opens a **sign-in window** — enter your Bring!
   account credentials (`web.getbring.com`) and choose the list the widget
   should show.

## Start at login

1. Open **System Settings**
2. **General → Login Items** (macOS 15 and later: **Login Items & Extensions**)
3. Under "Open at Login", click **+** → select `/Applications/BringWidget.app`
   → Add.

From then on the app starts silently in the background at every login —
**no Dock icon, no ⌘-Tab entry**, it runs as an "agent". The widget can
refresh at any time because the app is available in the background.

## Put the widget on your desktop

1. **Right-click** an empty spot on your desktop → **"Edit Widgets…"**
2. In the gallery: search for "Bring" or scroll to the app list.
3. Choose **BringWidget** — the widget is called **"Bring! Shopping List"**
   (small, medium or large).
4. Drag it onto the desktop.
5. Click "Done" / close the gallery.

The widget now shows your selected Bring! list:
- **Click the header** (cart icon + list name + ↗) → opens the list on
  `web.getbring.com` in your default browser.
- **Click the items** → reloads the list immediately, straight from
  Bring!.

## When you need the app window again

The app is invisible by default (no Dock, no ⌘-Tab). If you need the UI
(sign in again, choose another list):

- **Spotlight** (`⌘ + Space`): type "BringWidget" → Enter.
- **Terminal:** `open -a "BringWidget"`

If the app wasn't running yet, the first launch stays invisible — press Enter in Spotlight again (or run `open -a BringWidget` a second time) and the window appears.

## Troubleshooting

**"App is damaged and can't be opened"** —
the quarantine flag is still set. In Terminal:
```sh
xattr -dr com.apple.quarantine /Applications/BringWidget.app
```

**Widget shows "Not Signed In" although the app is signed in** —
remove the widget from the desktop → add it again from the gallery. If
that doesn't help:
```sh
killall chronod 2>/dev/null; killall WidgetKitExtensionAgent 2>/dev/null
```
and add the widget again.

**Widget refreshes too rarely** — macOS rate-limits widgets aggressively.
Clicking the item tiles always triggers an immediate refresh that is NOT
rate-limited.

**App won't run on another Mac** — the app is signed with a specific
Apple Developer Team ID. If a Mac doesn't know that identity, Gatekeeper
blocks it. Solution: build the app from source on that Mac (see
`docs/GUIDE.md` in the repository).

**App doesn't start or quits immediately, widget missing from the
gallery** — the "Apple Development" certificate the package was signed
with has expired (it is valid for one year). Solution: create a new
certificate in Xcode and rebuild with `scripts/package.sh`.

## Updates

There is no auto-update. When a new `BringWidget.dmg` or
`BringWidget.app.zip` is available:

1. Quit the running BringWidget instance (`killall BringWidget`).
2. Repeat option A or B above.
3. The login item persists — nothing to reconfigure.

## Uninstall

1. `rm -rf /Applications/BringWidget.app`
2. System Settings → General → Login Items → remove the entry.
3. App Group container with stored tokens and password (optional
   cleanup; replace `<TEAM-ID>` with your Team ID):
   ```sh
   rm -rf ~/Library/Group\ Containers/<TEAM-ID>.com.AnyUser-Ctrl.BringWidget
   ```
4. Remove the widget from the desktop (right-click → Remove Widget).
