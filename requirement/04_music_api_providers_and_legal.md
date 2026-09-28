# Music API Providers & Legal Considerations

## 1. API Options for Development

### Option A: YouTube Music Wrapper (Best for Learning/Portfolio)
- **Implementation:** Use a backend (Node.js/Python) with `yt-dlp` or `youtubei.js` to extract audio streams, then serve it to Flutter via a custom REST API.
- **Pros:** Massive catalog, free, high-quality audio.
- **Cons:** **Strictly violates YouTube TOS for commercial apps.** Will get banned from PlayStore/AppStore if monetized or published publicly.

### Option B: SoundCloud / Jamendo API (Best for Legal Indie Apps)
- **Implementation:** Official REST APIs.
- **Pros:** 100% legal for streaming full tracks. Great for Lo-Fi, Indie, Remixes.
- **Cons:** Lacks mainstream/popular artists.

### Option C: Spotify Web API (Best for Metadata)
- **Implementation:** Official API.
- **Pros:** Best-in-class metadata, recommendations, and lyrics.
- **Cons:** Only provides 30-second previews. Full playback requires the user to have Spotify Premium and use the Spotify SDK.

### Option D: Commercial B2B APIs (Best for Real Business)
- **Providers:** 7digital, Napster API, TuneCore.
- **Pros:** Fully licensed, legal, massive catalog.
- **Cons:** Requires business contracts and revenue sharing.

## 2. Recommended Setup for this Project
For the MVP/Portfolio phase, build a lightweight **Node.js/Express Backend** that acts as a proxy. 
- Flutter calls your Node.js API.
- Node.js fetches the audio URL from a YouTube wrapper.
- Node.js streams the audio to Flutter.
*This keeps your API keys hidden and allows you to switch providers easily in the future.*

## 3. Flutter Packages Checklist
```yaml
dependencies:
  flutter:
    sdk: flutter
  # Audio
  just_audio: ^0.9.36
  just_audio_background: ^0.0.1-beta.11
  audio_session: ^0.1.18
  # State & DI
  flutter_bloc: ^8.1.3
  get_it: ^7.6.4
  injectable: ^7.0.0
  # Network & DB
  dio: ^5.4.0
  isar: ^3.1.0+1
  cached_network_image: ^3.3.1
  # UI & Routing
  go_router: ^13.2.0
  shimmer: ^3.0.0
  # Utils
  freezed_annotation: ^2.4.1
  json_annotation: ^4.8.1