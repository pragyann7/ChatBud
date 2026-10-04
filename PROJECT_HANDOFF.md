# 🚀 ChatBud — Complete Project Handoff & Architecture Summary

## 📌 1. Project Overview & Vision
- **App Name**: ChatBud
- **Goal**: Build a private, fully offline local LLM mobile chat app (like ChatGPT) running quantized GGUF models on-device using native `llama.cpp` C++ inference via Dart FFI.
- **Development Strategy**: Phased learning approach (Progressive architecture).

---

## 🚦 2. Completed Learning Phases & Current Status

### ✅ **Phase 1: Dynamic Chat UI & Asynchronous Streaming Architecture**
- **60 FPS Token Streaming**: `ValueNotifier<String>` stream notifiers update `MessageBubble` widgets smoothly without rebuilding the full screen or `ListView`.
- **Unified Expanding Input Container (`ChatInput`)**: ChatGPT-style multiline input card expanding up to 11 lines with embedded action buttons (+ and Send/Stop) and concurrent typing enabled during generation.
- **Reverse List & Navigation**: Reverse `ListView`, auto-scroll to latest token, manual scroll override detector, and scroll-to-bottom FAB.

### ✅ **Phase 2: High-Performance On-Device Database & Bud Management**
- **Isar NoSQL Persistence**: Complete schemas for `Conversation`, `Message`, `Bud`, and `AppSettings`.
- **4 Domain Repositories (Provider DI)**:
  - `ConversationRepository`: Chat session lifecycle, pinning, renaming, cascade message deletion, Isar streams.
  - `MessageRepository`: Pair message saving, `updatedAt` touch timestamps, parent verification in transactions (`writeTxn`) to prevent orphan messages.
  - `BudRepository`: Stable identity seeding (IDs 1–4: *General*, *Coding*, *Study*, *Creative*), custom Bud CRUD.
  - `SettingsRepository`: Single-instance app settings (`theme`, `selectedModel`, `serverIp`, `engineType`, `modelPath`) enforcing fixed **ID = 1** and atomic `writeTxn` updates.
- **Indexing & Paginated Queries**: Indexed `@Index()` on `Message.conversationId` and `Message.createdAt` with deterministic paginated history loading.
- **AI Persona ("Bud") System**: Custom Bud management screen (`BudsScreen`), turn-by-turn persona switching via `BudSelectorChip` with a **"No Bud / Raw LLM"** clean-slate fallback, and auto-repair for deleted Bud references.

### ✅ **Phase 3: Network AI Streaming, Ollama Integration & Background Engine**
- **Multi-Turn Conversation Context (`/api/chat`)**: Passes past conversation turns directly to Ollama so the model maintains multi-turn context memory.
- **Sliding Window Context Limits**: Limits conversation history to the last 10 messages max (~1500 tokens) to prevent prompt bloat and out-of-memory crashes on mobile devices.
- **Global `GenerationManager` Engine**: Decouples generation jobs from `ChatScreen` widget lifecycle. Supports background multi-chat streaming without cross-talk or token leakage.
- **Drawer Status Indicators**: Live spinning progress circle for active streaming chats + Red unread notification dot for completed background responses (cleared upon opening).
- **Clean Service Contract (`AiService`)**: Abstract contract implemented by `MacAiService` and `LlamaCppAiService`.
- **Ollama HTTP Stream Engine**: Connects to Ollama (`POST /api/chat`) over local Wi-Fi with conditional `'think': true` handling for reasoning models (`qwen3`, `deepseek-r1`, `qwq`) to prevent HTTP 400 errors on standard models (`llama3.1`, `llama3.2`).
- **NDJSON Stream Transformer & Safety**: Uses `utf8.decoder` + `LineSplitter()` with `try-catch` JSON line parsing to guarantee 100% multibyte UTF-8 safety and malformed line protection.
- **Dual Network Timeout Protection**: 50s initial connection timeout (allows heavy model cold loads & context prefill) and 15s in-flight idle token timeout.
- **User-Initiated Cancellation**: Added Stop Generation button in `ChatInput` that severs the HTTP socket (`_client.close()`), preserves all partial tokens generated up to that moment, and saves them as completed.
- **In-Place Message Retry & Error UX**: Failed/interrupted responses render an inline `⚠️ Generation failed` status with an in-place `[ 🔄 Retry ]` button that re-streams directly into that message bubble without polluting the chat log or popping global SnackBars.
- **Collapsible Thinking Accordion**: Parses `<think>...</think>` XML tags and Ollama `thinking` / `reasoning_content` JSON fields. Renders live streaming reasoning inside a collapsible `🧠 Thought Process` card above the main answer.
- **Dynamic AI Server IP Settings**: Configurable local server IP address stored in `AppSettings` (`SettingsRepository`) and editable via drawer dialog (`AI Server Settings`).

### ✅ **Phase 4: Dart FFI, `llama.cpp` Native Engine & Hugging Face Model Hub**
- **Dart FFI (`dart:ffi`) Interop Pipeline**: Native C/C++ memory rules and native string marshalling (`package:ffi` `Pointer<Utf8>`, `calloc.free()`).
- **Native Shared Dynamic Library (`native/llama_bridge.cpp` & `simple_bridge.c`)**: Compiled into `native/libsimple_bridge.dylib` using `xcrun clang++` with C unmangled linkage.
- **Native GGUF Health Check**: Implemented native `verify_gguf_model_health_cpp()` that reads the 4-byte `"GGUF"` magic header (`0x46554747`) to verify file integrity on disk.
- **Cross-Platform Dynamic Library Resolver**: `LlamaCppAiService.openDynamicLibrary()` supports Android `.so`, iOS `process()`, macOS `.dylib`, Windows `.dll`, and Linux `.so` with multi-stage symbol fallback (`run_llama_cpp_inference_cpp` / `run_llama_cpp_inference`).
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

---

## 🏗️ 3. Current Codebase Structure

```
lib/
├── database/
│   └── database.dart           # Isar DB initialization, schema definitions & default seeding
├── models/
│   ├── app_settings.dart       # Global settings model (Theme, Model selection, Server IP, EngineType, ModelPath)
│   ├── bud.dart                # AI Persona model
│   ├── conversation.dart       # Chat session model
│   ├── hugging_face_model.dart # Hugging Face Repo & GGUF file models
│   └── message.dart            # Indexed message model with MessageRole & MessageStatus
├── repositories/
│   ├── bud_repository.dart          # Persona CRUD & stable ID (1-4) seeding
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

---

## 🧪 4. Test Suite Status
All automated repository, widget, and FFI integration tests pass 100%:
```bash
$ flutter test
00:03 +15: All tests passed!
```

---

## 🔮 5. Planned Next Phase (Phase 5)

- **Phase 5 — Isolates, C++ Tensor Linking & Memory Safeguards**:
  - Link real `llama.cpp` C++ tensor matrix multiplication engine (`llama.h` / `llama.cpp`) into `native/llama_bridge.cpp`.
  - Manage large GGUF models carefully, and handle device memory limits and out-of-memory risks.
