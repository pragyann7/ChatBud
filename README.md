# ChatBud

ChatBud is a Flutter project to build a private, fully offline AI chat app for mobile. The long-term goal is to let a user chat with a language model that runs on their device, without needing an internet connection or sending conversation data to a cloud service.

The app is being developed in learning phases. The current build includes on-device Isar NoSQL persistence, dynamic AI persona ("Bud") management, background generation architecture, real-time multi-turn streaming with Ollama, Dart FFI native interop, and an in-app Hugging Face GGUF Model Hub & Downloader.

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
- **Phase 3 — Network-based AI streaming & Ollama integration:** Live network streaming from a local/LAN Ollama AI server (`POST /api/chat`).
  - **Multi-Turn Conversation Context**: Passes past conversation turns directly to Ollama so the model maintains multi-turn context memory.
  - **Sliding Window Context Limits**: Limits conversation history to the last 10 messages max (~1500 tokens) to prevent prompt bloat and out-of-memory crashes on mobile devices.
  - **GenerationManager & Background Generation**: Global Provider service decoupling AI generation jobs from screen lifecycle; supports concurrent chat streams, cross-talk isolation, and atomic Isar DB persistence.
  - **Drawer Notification Badges**: Live spinning progress circle for actively generating chats and a red notification dot for background-completed unread chats (cleared upon opening).
  - **Clean Service Contract (`AiService`)**: Abstract contract implemented by `MacAiService` and `LlamaCppAiService`.
  - **Ollama HTTP Stream Engine**: Connects to Ollama (`POST /api/chat`) over local Wi-Fi with conditional `'think': true` handling for reasoning models (`qwen3`, `deepseek-r1`, `qwq`) to prevent HTTP 400 errors on standard models (`llama3.1`, `llama3.2`).
  - **NDJSON Stream Transformer & Safety**: Uses `utf8.decoder` + `LineSplitter()` with `try-catch` JSON line parsing to guarantee 100% multibyte UTF-8 safety and malformed line protection.
  - **Dual Network Timeout Protection**: 50s initial connection timeout (allows heavy model cold loads & context prefill) and 15s in-flight idle token timeout.
  - **Unified Expanding Input Container (`ChatInput`)**: ChatGPT-style multiline input container expanding up to 11 lines with embedded, independent attachment (+) and send/stop action buttons.
  - **User-Initiated Cancellation**: Added Stop Generation button in `ChatInput` that severs the HTTP socket (`_client.close()`), preserves all partial tokens generated up to that moment, and saves them as completed.
  - **In-Place Message Retry & Error UX**: Failed/interrupted responses render an inline `⚠️ Generation failed` status with an in-place `[ 🔄 Retry ]` button that re-streams directly into that message bubble without polluting the chat log or popping global SnackBars.
  - **Collapsible Thinking Accordion**: Parses `<think>...</think>` XML tags and Ollama `thinking` / `reasoning_content` JSON fields. Renders live streaming reasoning inside a collapsible `🧠 Thought Process` card above the main answer.
  - **Dynamic AI Server IP Settings**: Configurable local server IP address stored in `AppSettings` (`SettingsRepository`) and editable via drawer dialog (`AI Server Settings`).
- **Phase 4 — Dart FFI, `llama.cpp` Native Engine & Hugging Face Model Hub:** Native C/C++ interop pipeline and in-app model downloader.
  - **Dart FFI (`dart:ffi`) Interop Pipeline**: Native C/C++ memory rules and native string marshalling (`package:ffi` `Pointer<Utf8>`, `calloc.free()`).
  - **Native Shared Dynamic Library (`native/llama_bridge.cpp` & `simple_bridge.c`)**: Compiled into `native/libsimple_bridge.dylib` using `xcrun clang++` with unmangled C linkage.
  - **Native GGUF Health Check**: Implemented native `verify_gguf_model_health_cpp()` that reads the 4-byte `"GGUF"` magic header (`0x46554747`) to verify file integrity.
  - **Native Token Callbacks**: Implemented token streaming callbacks (`NativeCallable.listener`) streaming tokens token-by-token from C++ to Dart.
  - **Background Isolate Offloading**: Offloaded native FFI calls to background Dart Isolates (`Isolate.spawn`) so the 60/120 FPS UI thread never drops a frame.
  - **`LlamaCppAiService`**: Implements `AiService` abstract contract for 100% offline on-device FFI execution.
  - **Polymorphic Dual Engine**: Added `engineType` (`'ollama'` vs `'llama_cpp'`) to `AppSettings` & `SettingsRepository` with an interactive SegmentedButton engine switcher in the Drawer Settings Dialog (`AI Engine & Settings`).
  - **In-App Hugging Face Model Hub & Downloader (`ModelHubScreen` / `HuggingFaceService`)**:
    - **Recommended Mobile Models**: Preset list of lightweight mobile GGUF models (*Qwen 2.5 0.5B*, *Llama 3.2 1B*, *DeepSeek R1 Distill Qwen 1.5B*, *Qwen 2.5 1.5B*).
    - **Hugging Face REST API Search**: Search any GGUF repository on Hugging Face and inspect `.gguf` quantization files.
    - **Native `HttpClient` Byte Streaming**: Real-time progress bar (`MB / Total MB`), instant mid-download cancellation, and automatic `.tmp` file deletion on cancellation.
    - **Downloaded Models Manager**: View downloaded `.gguf` files, set active model in 1 tap, or delete files to free device storage.
  - **On-Device Model Status Bar**:
    - Displays loaded GGUF model status below Bud selector in `llama_cpp` mode.
    - 1-tap **`[ ⚡ Load Model ]`** and **`[ Unload RAM ]`** controls to manage phone RAM/VRAM manually.
    - Auto-loads model before generation if not loaded.

### In progress

- No phase is currently in progress.

### Planned

- **Phase 5 — Isolates, C++ Tensor Linking & Memory Safeguards:** Link real `llama.cpp` C++ engine (`llama.h` / `llama.cpp`) into native FFI bridge for real GGUF tensor execution on device, manage large GGUF models carefully, and handle device memory limits and out-of-memory risks.

## Current implementation

The app persists conversations, messages, custom Bud profiles, and global settings locally on-device using Isar NoSQL Database. It connects over the local network to an Ollama server (e.g. `http://<local-ip>:11434`) or executes on-device FFI inference with `llama.cpp`, streaming live token-by-token completions with dynamic Bud system prompts, Isar database persistence, background generation, in-place retry, and stop generation controls.

Try these features in the current build:

- Send any prompt to stream live responses from your local Ollama model or offline `llama.cpp` engine.
- Select different AI personas (**Coding Bud**, **Study Bud**, **Creative Bud**, or **No Bud / Raw LLM**) using the top selector chip or drawer!
- Open **Model Hub (Download GGUF)** in the drawer to search Hugging Face and download GGUF models directly to your phone!
- Manage model loading/unloading into phone RAM using the top Model Status Bar.
- Watch the live **`🧠 Thought Process`** accordion stream reasoning when using reasoning models like `qwen3` or `deepseek-r1`.
- Type in the expanding multiline prompt box with embedded action buttons.
- Switch chats freely while generation runs in the background, and observe the live spinning circle and red completion dot on drawer tiles!
- Tap the **Stop Button** while generating to cleanly halt response generation and save partial text to disk.
- Tap **[ Retry ]** on any failed message to re-trigger generation in-place.
- Open the drawer and tap the **Settings** icon to update your local Ollama server IP or switch inference engines dynamically.

## Project structure

```
lib/
├── database/
│   └── database.dart           # Isar DB initialization & default seeding
├── models/
│   ├── app_settings.dart       # Global settings model (Theme, Model selection, Server IP, EngineType, ModelPath)
│   ├── bud.dart                # AI Persona model
│   ├── conversation.dart       # Chat session model
│   ├── hugging_face_model.dart # Hugging Face Repo & GGUF file models
│   └── message.dart            # Indexed message model
├── repositories/
│   ├── bud_repository.dart          # Persona CRUD & stable ID seeding
│   ├── conversation_repository.dart # Chat session CRUD & Isar streams
│   ├── message_repository.dart      # Pair-saving, pagination & touch timestamps
│   └── settings_repository.dart     # Atomic app settings (Fixed ID = 1, Server IP, EngineType, ModelPath)
├── screens/
│   ├── buds_screen.dart        # Custom Bud management UI
│   ├── chat_screen.dart        # Main chat UI with paginated history, model bar, in-place retry & stream handling
│   └── model_hub_screen.dart   # Hugging Face Model Hub & GGUF Downloader UI
├── services/
│   ├── ai_service.dart         # AiService contract & MacAiService Ollama stream engine
│   ├── generation_manager.dart # Global background generation manager & unread badge tracker
│   ├── huggingface_service.dart# Hugging Face API client, byte stream downloader & file manager
│   ├── llama_cpp_service.dart   # Llama.cpp FFI service & Isolate runner
│   └── llm_service.dart        # Local mock stream fallback engine
├── widgets/
│   ├── bud_selector.dart       # Header chip for turn-by-turn persona switching
│   ├── chat_input.dart         # Unified expanding input card with embedded action buttons
│   └── message_bubble.dart     # Reactive message bubble with ParsedMessage & ThinkingAccordion
└── main.dart                   # App shell, Provider DI, drawer, server/engine dialog & error fallbacks

native/
├── llama_bridge.cpp            # Native C++ inference & GGUF health check functions
├── simple_bridge.c             # C/C++ FFI native function & token streaming callback implementation
└── libsimple_bridge.dylib      # Compiled Mach-O 64-bit arm64 dynamic shared library

test/
├── ffi_test.dart               # FFI unit & Isolate integration test suite
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

To run all automated repository, widget, and FFI tests:

```bash
flutter test
```

## Phase-by-phase README updates

This README is the project’s vision and progress record. When a phase is completed, update its status, summarize what was implemented, and move the next active phase to **In progress**. Keep future phases under **Planned** and revise the current implementation notes to match the code.
