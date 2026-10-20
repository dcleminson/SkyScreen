# SkyLite Photo App

Local Vue app for testing a photo frame workflow on the Rockchip RK3566 device.

## Features

- Upload local images from the browser.
- Load images from a public JSON feed URL (no OAuth needed).
- Presentation mode for true full-screen viewing.
- Tap-on-screen in presentation mode to exit back to full controls.
- Fade transitions, shuffle mode, and slideshow progress bar.
- Feed editor for URL lists and one-click `photos.json` download.
- Swipe support in presentation mode (left/right for next/previous).
- Mini presentation HUD with slide index and play state.
- Connect to Google Drive with OAuth and import recent images.
- Display images in a full-screen-friendly frame view.
- Manual previous/next controls.
- Slideshow play/pause with configurable delay.
- Clear loaded images and reset state.

## Run locally

```bash
npm install
npm run dev
```

Then open `http://127.0.0.1:5173`.

## Run on Android device through ADB reverse

```bash
adb reverse tcp:5173 tcp:5173
adb shell am start -a android.intent.action.VIEW -d http://127.0.0.1:5173
```

This allows the Android/Rockchip device browser to access the dev server running on your Mac.

You can also use the helper script:

```bash
./open-app.sh
```

Optional custom URL:

```bash
./open-app.sh http://127.0.0.1:5173
```

## Production-style run (stable build)

Use this mode when you want to test without hot-reload behavior:

```bash
npm run build
npm run preview -- --host 127.0.0.1 --port 4173
```

Then, in another terminal:

```bash
./open-prod-app.sh
```

One-command variant:

```bash
npm run prod:start
```

## Google Drive setup

1. In Google Cloud Console, create an OAuth Client ID for a web app.
2. Add your dev origin (for example `http://127.0.0.1:5173`) to authorized JavaScript origins.
3. Enable the Google Drive API for the same project.
4. Paste the OAuth client ID into the app's **OAuth Client ID** field.
5. Click **Connect Drive**, sign in, then use **Import Drive Photos**.

Use **Folder ID** to restrict imports to one Drive folder. You can paste either the raw folder ID or the full Google Drive folder URL.

## Public image feed mode (no Google setup)

If you want to avoid Google OAuth setup, use **Public image feed**.

The app accepts either JSON format:

```json
[
  "https://example.com/image1.jpg",
  "https://example.com/image2.jpg"
]
```

or:

```json
{
  "images": [
    { "name": "Sunset", "url": "https://example.com/sunset.jpg" },
    { "name": "Beach", "url": "https://example.com/beach.jpg" }
  ]
}
```

Note: image URLs must be publicly reachable by the device browser.

Quick local test feed in this project:

`/photos.json` (recommended on device)  
or `http://127.0.0.1:5173/photos.json`

Generated feed from your shared Drive folder:

`/photos-from-drive.json`

## Feed quality check

Validate and filter a feed to reachable image URLs:

```bash
npm run feed:check
```

This reads `public/photos-from-drive.json` and writes filtered output to:

- `public/photos-from-drive.filtered.json`

## Persistent deployment note

On this Android/Rockchip setup, the browser cannot reliably self-register as a boot kiosk app without device-level launcher/device-owner configuration. A practical path is:

1. Run production preview (`npm run preview`) from your host.
2. Auto-open URL on device with `./open-prod-app.sh`.
3. Optionally configure your launcher/browser settings on device to reopen the last page after reboot.

### Android home/settings helpers (host-side ADB)

To ensure you can always reach Android UI instead of terminal flows:

```bash
./open-android-home.sh
./open-android-settings.sh
```

- `open-android-home.sh` sends HOME and sets Lawnchair as preferred home activity when available.
- `open-android-settings.sh` opens the Android Settings app directly.

One-shot recovery helper:

```bash
./recover-ui.sh
```

Optional custom app URL:

```bash
./recover-ui.sh http://127.0.0.1:5173
```

Emergency escape back to launcher:

```bash
./escape.sh
```

### Remove Alexa from default interface path

If the device keeps launching Alexa in the default interface flow, disable the
Alexa package for user 0:

```bash
./disable-alexa-default.sh
```

To restore Alexa later:

```bash
./enable-alexa.sh
```
