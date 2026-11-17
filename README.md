<div align="center">

**English** | [Français](README.fr.md)

# NicoFy

**A music streaming app made in Flutter**

[![GitHub release](https://img.shields.io/github/v/release/nicotontige/NicoFy?color=D3BEAB)](https://github.com/nicotontige/NicoFy/releases)
[![License](https://img.shields.io/github/license/nicotontige/NicoFy?color=D3BEAB)](LICENSE)

<a href="https://buymeacoffee.com/nicotontige" target="_blank" title="Buy me a coffee">
  <img src="https://img.shields.io/badge/Buy%20me%20a%20coffee-nicotontige-FFDD00?logo=buymeacoffee&logoColor=black" alt="Buy me a coffee">
</a>

</div>

NicoFy is a fork of [Musify](https://github.com/gokadzev/Musify) by Valeri
Gokadze. It started from Musify 10.6.0 and now goes its own way, with its own
releases, updates and features.

---

## Features

### Listening
- Online search with suggestions, results sorted into category tabs
- Offline listening, with downloaded songs marked in search results
- Reliable streaming: songs play from a buffer file, so they don't cut out
- Queue kept across restarts, resumed at the exact spot
- The queue lists only the song playing and what comes next; previous still works
- Radio from the song playing: up to 25 related songs replace what follows
- Automatic song picker when the queue runs out, with songs, mixes or both
- Previous restarts the song when pressed mid-song
- Chapter navigation inside long compilations
- Synced lyrics
- Built-in equalizer with presets, sleep timer, SponsorBlock
- Radio stations

### Library
- Custom playlists, also from a YouTube link, and playlist folders
- Spotify playlist import
- Act on several songs at once, sort playlists and artists by name
- Listening recaps
- Scrobbling to Last.fm and ListenBrainz
- Import and export your data

### Android TV
- Made for the remote: a now-playing screen that opens on Play/Pause, with the arrows for previous/next and ±10 s
- After a minute without the remote, the song playing shows up full screen
- The selected element is clearly outlined
- Hold OK on a song in the queue for its menu
- Voice control through the Assistant button

### Android Auto
- Browse your queue, liked songs, playlists, downloads and recently played
- Like, shuffle a playlist and start a radio from the car

### Between your devices
- Control the TV from your phone: see what it plays, pause, skip, seek, edit its queue; while connected, whatever you start on the phone plays on the TV
- Optional sync of your library over the local network
- Devices pair once with a PIN

### And also
- In-app updates: downloaded and installed from the app, with the notes of every version you skipped
- No ads, no subscription
- Material You: accent colors and dynamic colors (Android 12+)
- 21 languages

---

## Screenshots

| ![Screenshot 1](https://raw.githubusercontent.com/nicotontige/NicoFy/master/fastlane/metadata/android/en-US/images/phoneScreenshots/01.jpg) | ![Screenshot 2](https://raw.githubusercontent.com/nicotontige/NicoFy/master/fastlane/metadata/android/en-US/images/phoneScreenshots/02.jpg) | ![Screenshot 3](https://raw.githubusercontent.com/nicotontige/NicoFy/master/fastlane/metadata/android/en-US/images/phoneScreenshots/03.jpg) | ![Screenshot 4](https://raw.githubusercontent.com/nicotontige/NicoFy/master/fastlane/metadata/android/en-US/images/phoneScreenshots/04.jpg) |
|----------------------------------------------------------------------------------------------------------------------------------------|----------------------------------------------------------------------------------------------------------------------------------------|----------------------------------------------------------------------------------------------------------------------------------------|----------------------------------------------------------------------------------------------------------------------------------------|

---

## Supported platforms

| Platform | Status | Dependencies |
|----------|--------|--------------|
| Android (phone, Android TV, Android Auto) | ✅ Supported | — |
| Linux    | ✅  Supported (Beta) | libmpv |
| Windows    | ✅  Supported (Beta) | — |
| iOS    | ❌ Unsupported | — |

---

## Download

[<img src="https://github.com/nicotontige/NicoFy/raw/master/.github/assets/get-it-on-github.png" alt="Get it on Github" height="80">](https://github.com/nicotontige/NicoFy/releases/latest)

---

## Contribute

Contributions are welcome. Please read the [contributing guidelines](CONTRIBUTING.md) before contributing.

---

## Credits

- [Musify](https://github.com/gokadzev/Musify) by Valeri Gokadze and its
  contributors: NicoFy is built on its code, under the same license.
- [Musify](https://github.com/Harsh-23/Musify) by Harsh-23: the original
  inspiration for Musify's concept and name.

---

## License

```
Copyright © 2026 Valeri Gokadze (Musify)
Copyright © 2026 Nicolas Manceau (NicoFy modifications)

NicoFy is free software licensed under GPL v3.0, as is Musify, which it is a
modified version of. You may use, modify, and distribute this software freely,
but must keep the source code open and publicly available, retain all copyright
notices, disclose all changes made, and use the same GPL v3.0 license.
```

See the [GNU General Public License](LICENSE) for full details.

---

## Disclaimer

```
NicoFy and its contributors do not host, own, or distribute any copyrighted audio content.
The app provides access to content through plugins and external sources. All trademarks, songs, audio files, and related content remain the property of their respective owners and are protected by applicable copyright laws.
Included plugins are provided for interoperability and educational purposes only. Users are solely responsible for ensuring that their use of the app complies with local laws, copyright regulations, and the terms of service of the respective content providers.
The developers of NicoFy do not encourage or endorse copyright infringement and assume no liability for misuse of the software or third-party plugins.
```
---
