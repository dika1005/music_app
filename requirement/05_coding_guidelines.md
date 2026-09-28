# AI Agent Instructions & Coding Guidelines

**Context:** You are an expert Flutter developer assisting in building "MelodyFlow", a high-performance music streaming app.

## 1. Tech Stack & Packages
- **Framework:** Flutter 3.x (Stable channel).
- **State Management:** `flutter_bloc` (Preferred for complex states like Audio Player) or `riverpod`.
- **Audio Engine:** `just_audio` + `just_audio_background` + `audio_session`. **DO NOT** use `audioplayers` for this project.
- **Networking:** `dio` with interceptors for token refresh and error handling.
- **Local DB:** `isar` or `hive` for offline caching and playlists.
- **Routing:** `go_router`.
- **DI:** `get_it` and `injectable`.
- **Code Generation:** `freezed`, `json_serializable`, `build_runner`.

## 2. Architecture Rules
- Strictly follow **Clean Architecture** (Data, Domain, Presentation).
- Domain layer must have ZERO dependencies on Flutter (`package:flutter` is forbidden in `domain/`).
- Use `Either<Failure, Success>` pattern (via `dartz` or `fpdart`) for error handling in UseCases and Repositories.

## 3. UI & Responsive Rules
- Always use `LayoutBuilder` or `MediaQuery` to adapt UI for Tablets/Foldables.
- Use Material 3 components (`FilledButton`, `Card`, `NavigationBar`).
- Ensure all text uses `Theme.of(context).textTheme` (never hardcode font sizes/colors).
- Wrap long lists in `ListView.builder` or `GridView.builder` with `cacheExtent`.

## 4. Audio & State Management Rules
- The `PlayerBloc` must handle states: `Initial`, `Loading`, `Playing`, `Paused`, `Buffering`, `Error`, and `Completed`.
- Always update the Android Notification and iOS Lockscreen metadata (Title, Artist, Artwork) when a track changes.
- Handle audio interruptions (phone calls, other apps playing audio) using `audio_session`.

## 5. Code Quality & Formatting
- Write clean, readable, and well-commented code.
- Extract large widget trees into smaller, private widgets or separate files in the `widgets/` folder.
- Use `const` constructors wherever possible to optimize widget rebuilding.
- Always handle edge cases (e.g., no internet, empty playlist, null artwork URL).