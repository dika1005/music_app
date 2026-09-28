# Project Folder Structure
## Architecture: Feature-First + Clean Architecture

This structure ensures scalability, testability, and separation of concerns.

```text
lib/
├── core/                           # Global configurations and utilities
│   ├── constants/                  # API endpoints, colors, typography
│   ├── errors/                     # Custom exceptions and failure classes
│   ├── network/                    # Dio/HTTP client setup, interceptors
│   ├── theme/                      # Material 3 Theme, Light/Dark mode configs
│   └── utils/                      # Helper functions (duration formatter, etc.)
│
├── features/                       # Grouped by business features
│   ├── auth/                       # Login, Register, Profile
│   ├── home/                       # Dashboard, Recommendations
│   ├── search/                     # Search logic and UI
│   ├── library/                    # User playlists, Favorites, Downloads
│   └── player/                     # CORE FEATURE: Music Player
│       ├── data/
│       │   ├── datasources/        # Remote (API) & Local (Isar/Hive) sources
│       │   ├── models/             # DTOs, JSON serialization (freezed/json_serializable)
│       │   └── repositories/       # Repository implementations
│       ├── domain/
│       │   ├── entities/           # Pure Dart objects (Track, Album, Artist)
│       │   ├── repositories/       # Abstract repository contracts
│       │   └── usecases/           # Business logic (GetTopTracks, PlaySong)
│       └── presentation/
│           ├── bloc/               # BLoC/Cubit for state management
│           ├── pages/              # FullScreenPlayer, MiniPlayer
│           └── widgets/            # AlbumArt, SeekBar, ControlButtons
│
├── shared/                         # Reusable components across features
│   ├── widgets/                    # Custom buttons, loading skeletons, cards
│   ├── audio_service/              # JustAudio background service configuration
│   └── routing/                    # GoRouter configuration and route names
│
├── injection.dart                  # Dependency Injection setup (GetIt/Injectable)
└── main.dart                       # App entry point, initialization