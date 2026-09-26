# ChatBud

ChatBud is a Flutter project to build a private, fully offline AI chat app for mobile. The long-term goal is to let a user chat with a language model that runs on their device, without needing an internet connection or sending conversation data to a cloud service.

The app is being developed in learning phases. The current build includes on-device persistence and dynamic AI persona ("Bud") management powered by Isar Database, with simulated response streaming ahead of network/offline LLM engine integration.

## Project vision

The finished app is intended to provide:

- On-device AI chat using local GGUF models
- Smooth, token-by-token response streaming
- Local conversation history and settings using Isar NoSQL Database
- Custom assistant profiles (“Buds”) with their own names, icons, and system prompts
- A Flutter interface backed by native `llama.cpp` inference through Dart FFI
- Background generation and memory safeguards for mobile devices

The network API phase below is a temporary learning step for understanding streaming from a remote service. It is not a requirement for the finished offline app.

## Project status

**Completed** means the phase objective is implemented in the current project. **In progress** means it is actively being built. **Planned** means it has not started yet.

### Completed

- **Phase 1 — Dynamic chat UI and asynchronous streams:** Chat UI, message bubbles, a reverse scrolling message list, scroll-to-latest control, unique message IDs, and a simulated service that emits response chunks over time. The screen prevents overlapping generations and handles stream errors smoothly via `ValueNotifier`.
- **Phase 2 — High-performance on-device database & Bud management:** Full persistence using Isar NoSQL for conversations, messages, custom Bud profiles, and global app settings.
  - **Dynamic AI Persona ("Bud") System:** Built-in default personas (*General*, *Coding*, *Study*, *Creative*) with stable IDs (1–4), a custom Bud management screen (`BudsScreen`), and turn-by-turn persona switching via `BudSelectorChip` with a **"No Bud / Raw LLM"** clean-slate fallback.
  - **Contextual Attribution & Fallback:** Stores active `budId` on conversations and historical assistant messages; auto-repairs deleted Bud references gracefully.
  - **4 Domain Repositories:** Clean architecture splitting data access into `ConversationRepository`, `MessageRepository`, `BudRepository`, and `SettingsRepository` provided via `MultiProvider`.
  - **Indexing & Paginated Loading:** Database `@Index()` on `conversationId` and `createdAt` with deterministic paginated history queries.
  - **Reliability & Race Conditions:** Parent-conversation checks inside `writeTxn` transactions to prevent orphan messages if chats are deleted mid-generation, with 100% test suite pass rate (`flutter test`).

### In progress

- No phase is currently in progress.

### Planned

- **Phase 3 — Network-based streaming (learning bridge):** Use an external REST API or WebSocket to practice handling a real asynchronous token stream. This is an educational bridge and is not part of the final offline runtime.
- **Phase 4 — Dart FFI and `llama.cpp`:** Connect Dart to native C++ inference using `llama_cpp_dart` or a focused FFI wrapper, and build the required Android and iOS native libraries.
- **Phase 5 — Isolates and memory safeguards:** Move model loading and inference work off the UI isolate, manage large GGUF models carefully, and handle device memory limits and out-of-memory risks.

## Current implementation

The app persists conversations, messages, custom Bud profiles, and global settings locally on-device using Isar NoSQL Database. It currently uses a simulated token service to model streamed responses before connecting to a remote/offline LLM runtime.

Try these prompts in the current build:

- `hello` or `hi`
- `what is flutter`
- `how are you`
- `who are you`
- `long`, `test`, or `tell me a long story`

Try selecting different AI personas (**Coding Bud**, **Study Bud**, **Creative Bud**, or **No Bud / Raw LLM**) using the top selector chip or drawer!

## Project structure

```
lib/
├── database/
│   └── database.dart           # Isar DB initialization & default seeding
├── models/
│   ├── app_settings.dart       # Global settings model (Theme, Model selection)
│   ├── bud.dart                # AI Persona model
│   ├── conversation.dart       # Chat session model
│   └── message.dart            # Indexed message model
├── repositories/
│   ├── bud_repository.dart          # Persona CRUD & stable ID seeding
│   ├── conversation_repository.dart # Chat session CRUD & Isar streams
│   ├── message_repository.dart      # Pair-saving, pagination & touch timestamps
│   └── settings_repository.dart     # Atomic app settings (Fixed ID = 1)
├── screens/
│   ├── buds_screen.dart        # Custom Bud management UI
│   └── chat_screen.dart        # Main chat UI with paginated history & stream handling
├── services/
│   └── llm_service.dart        # Simulated response stream engine
├── widgets/
│   ├── bud_selector.dart       # Header chip for turn-by-turn persona switching
│   ├── chat_input.dart         # Chat input box and controls
│   └── message_bubble.dart     # Reactive message bubble with ValueNotifier stream
└── main.dart                   # App shell, Provider DI, drawer & error fallbacks

test/
├── repository_test.dart        # Unit tests for Isar repositories & race condition safeguards
└── widget_test.dart            # Widget rendering & Provider harness test
```

## Run the app

Install Flutter for your platform, then run these commands from the project directory:

```bash
flutter pub get
dart run build_runner build --delete-conflicting-outputs
flutter run
```

To run all automated repository and widget tests:

```bash
flutter test
```

## Phase-by-phase README updates

This README is the project’s vision and progress record. When a phase is completed, update its status, summarize what was implemented, and move the next active phase to **In progress**. Keep future phases under **Planned** and revise the current implementation notes to match the code.
