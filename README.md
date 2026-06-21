# Audix

A cross-platform (Android + iOS) audiobook player built with Flutter.

## Features

- Local library of `.m4b` audiobooks with **cue-based chapters**.
- Add **HTTP servers** (basic auth) that host one folder per book (`.m4b` + `.cue`);
  browse and **download** them.
- **Import** an `.m4b` (+ optional `.cue`) directly from the device.
- **Background playback** with lock-screen / notification / headset controls.
- **Pauses automatically when headphones or an earbud are removed.**
- **Resume** from where you stopped; per-book **playback speed**.
- Current **chapter** shown, plus a tappable chapter list; skip ±30s and prev/next chapter.
- **Sleep timer** (fixed durations or end of chapter).
- Credentials stored in the device **keychain / keystore**; deletable per server.

## Requirements

- Flutter (Dart ≥ 3.11). Android: `minSdk` 24. iOS: build on macOS with Xcode.

## Run

```bash
flutter pub get
dart run build_runner build   # generates drift database code (lib/core/database/database.g.dart)
flutter run
```

## Analyze / test

```bash
flutter analyze
flutter test
```

## Nix

```bash
nix run github:JinBlack/audix    # build and serve the web app
nix build github:JinBlack/audix  # build the arm64-v8a APK (-> result/)
```

Builds are reproducible and offline; dependencies are vendored as fixed-output
derivations. CI builds the APK and web app and publishes both to the release.

## Web (experimental)

Library, bookmarks and settings work on the web (import/download are
mobile-only). drift runs via wasm; `nix run` / `nix build .#web` fetch
`drift_worker.js` + `sqlite3.wasm` automatically. To build manually, fetch them
first:

```bash
tool/web/fetch-web-deps.sh && flutter build web
```

A Playwright smoke test (`tool/web/smoke_test.py`) loads the built app, navigates
every tab and records a video; CI runs it and attaches the video to the release.

## Project layout

```
lib/
  core/
    audio/      audio_service handler, audio-session config, player controller + providers
    database/   drift schema + DAOs (servers, books, chapters, playback)
    cue/        .cue parser (MM:SS:FF, 75 frames/sec)
    remote/     pluggable server sources (HTTP autoindex now; WebDAV/JSON stubs)
    download/   background_downloader wrapper (auth header + progress)
    import/     device file import
    library/    book finalizer (probe duration, build chapters) — shared by import & download
    storage/    secure credentials + file paths (stored RELATIVE to app documents)
  features/     library, player, servers, settings, home (UI)
```

## Local test server (for the download flow)

The HTTP source parses a standard directory-listing page. The easiest local server
with basic auth **and** a listing is rclone:

```bash
rclone serve http --addr :8080 --user user --pass pass /path/to/audiobooks
```

Lay out each book as one folder containing a `.m4b` and a `.cue`. In the app:
**Servers → +** → `http://<your-ip>:8080/`, username `user`, password `pass` → open it,
enter a book folder, **Download**.

(The WebDAV and JSON server types are recognized but currently fall back to autoindex
parsing — they're extension points in `lib/core/remote/`.)

## iOS notes

Background audio mode and an App Transport Security exception (for plain-HTTP servers)
are already set in `ios/Runner/Info.plist`. Build on macOS:

```bash
cd ios && pod install
flutter run
```

## Security

Basic auth over plain `http://` is **base64-encoded, not encrypted** — prefer HTTPS.
Passwords live in `flutter_secure_storage` (Keychain / Keystore) and are removed when you
delete a server. Deleting a server keeps already-downloaded books in your library.

## Manual verification checklist

1. Import an `.m4b` (+ `.cue`) → it appears in **Library**.
2. Add a server → browse → **Download** a book (progress shown) → appears in Library.
3. Play → lock screen controls work; audio continues with the app backgrounded.
4. **Unplug headphones / remove an earbud → playback pauses.**
5. Chapter indicator updates; tapping a chapter seeks; ±30s and prev/next chapter work.
6. Stop mid-book, reopen → **resumes at the saved position**; speed remembered.
7. Delete a server → its credentials are cleared; downloaded books remain.
