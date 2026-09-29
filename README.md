# ChatBud

ChatBud is a Flutter project to build a private, fully offline AI chat app for mobile. The long-term goal is to let a user chat with a language model that runs on their device, without needing an internet connection or sending conversation data to a cloud service.

The app is being developed in learning phases. The current build includes on-device persistence and dynamic AI persona ("Bud") management powered by Isar Database, connected to a real local network Ollama AI server for streaming response generation.

## Project vision

The finished app is intended to provide:

- On-device AI chat using local GGUF models
- Smooth, token-by-token response streaming
- Local conversation history and settings using Isar NoSQL Database
- Custom assistant profiles (“Buds”) with their own names, icons, and system prompts
- A Flutter interface backed by native `llama.cpp` inference through Dart FFI
- Background generation and memory safeguards for mobile devices

The network API phase below is a temporary learning step for understanding streaming from a remote/local network service. It is an educational bridge before moving to pure offline C++ FFI inference.

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
- **Phase 3 — Network-based AI streaming & Ollama integration:** Live network streaming from an Ollama AI server (`POST /api/generate`).
  - **Clean Service Contract (`AiService`)**: Abstract contract implemented by `MacAiService`, supporting prompt and Bud `systemPrompt` parameters for real-time persona completions.
  - **NDJSON Stream Transformer**: Transformed byte streams using `utf8.decoder` + `LineSplitter()` for 100% multibyte UTF-8 safety (emojis, non-English text) and line-by-line JSON parsing without string allocation churn.
  - **Dual Timeout Protection**: Implemented 15s connection timeout (for Ollama model cold loads & context prefill) and 15s in-flight idle token timeout.
  - **User-Initiated Cancellation**: Added Stop Generation button in `ChatInput` that severs the HTTP socket (`_client.close()`), preserves all partial tokens generated up to that moment, and saves them as completed.
  - **In-Place Message Retry & Error UX**: Failed/interrupted responses render an inline `⚠️ Generation failed` status with an in-place `[ 🔄 Retry ]` button that re-streams directly into that message bubble without polluting the chat log or popping global SnackBars.
  - **Dynamic Server IP Settings**: Configurable local server IP address stored in `AppSettings` (`SettingsRepository`) and editable via drawer dialog (`AI Server Settings`).

### In progress

- No phase is currently in progress.

### Planned

- **Phase 4 — Dart FFI and `llama.cpp`:** Connect Dart to native C++ inference using `llama_cpp_dart` or a focused FFI wrapper, and build the required Android and iOS native libraries.
- **Phase 5 — Isolates and memory safeguards:** Move model loading and inference work off the UI isolate, manage large GGUF models carefully, and handle device memory limits and out-of-memory risks.

## Current implementation

The app persists conversations, messages, custom Bud profiles, and global settings locally on-device using Isar NoSQL Database. It connects over the local network to an Ollama server (e.g. `http://<local-ip>:11434`), streaming live token-by-token completions with dynamic Bud system prompts, Isar database persistence, in-place retry, and stop generation controls.

Try these features in the current build:

- Send any prompt to stream live responses from your local Ollama model (e.g. `llama3.2:1b` or `qwen2.5-coder:3b`).
- Select different AI personas (**Coding Bud**, **Study Bud**, **Creative Bud**, or **No Bud / Raw LLM**) using the top selector chip or drawer!
- Type your next message freely while generation is in progress.
- Tap the **Stop Button** while generating to cleanly halt response generation and save partial text to disk.
- Tap **[ Retry ]** on any failed message to re-trigger generation in-place.
- Open the drawer and tap the **Settings** icon to update your local Ollama server IP dynamically.

## Project structure

```
lib/
├── database/
│   └── database.dart           # Isar DB initialization & default seeding
├── models/
│   ├── app_settings.dart       # Global settings model (Theme, Model selection, Server IP)
│   ├── bud.dart                # AI Persona model
│   ├── conversation.dart       # Chat session model
│   └── message.dart            # Indexed message model
├── repositories/
│   ├── bud_repository.dart          # Persona CRUD & stable ID seeding
│   ├── conversation_repository.dart # Chat session CRUD & Isar streams
│   ├── message_repository.dart      # Pair-saving, pagination & touch timestamps
│   └── settings_repository.dart     # Atomic app settings (Fixed ID = 1, Server IP)
├── screens/
│   ├── buds_screen.dart        # Custom Bud management UI
│   └── chat_screen.dart        # Main chat UI with paginated history, in-place retry & stream handling
├── services/
│   ├── ai_service.dart         # AiService contract & MacAiService Ollama stream engine
│   └── llm_service.dart        # Local mock stream fallback engine
├── widgets/
│   ├── bud_selector.dart       # Header chip for turn-by-turn persona switching
│   ├── chat_input.dart         # Chat input box, concurrent typing & stop control
│   └── message_bubble.dart     # Reactive message bubble with in-place Retry & status
└── main.dart                   # App shell, Provider DI, drawer, server IP dialog & error fallbacks

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
