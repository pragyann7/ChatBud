# 📋 ChatBud — Industry/Production-Ready Comprehensive Project Review Handbook (Phases 1–5)

This handbook provides exhaustive technical specifications, architectural details, and testing instructions for reviewing **ChatBud** across all 5 development phases. Any AI model or engineer reviewing this project folder should inspect each phase according to the instructions below to verify production readiness.

---

## 📌 Executive Overview & Architectural Mandate

- **App Name**: ChatBud
- **Vision**: A private, fully offline, production-grade mobile AI chat application built in Flutter with local Isar NoSQL persistence, dynamic AI persona ("Bud") management, background job streaming coordinator, network Ollama streaming, native C++ `llama.cpp` Dart FFI interop, and an in-app Hugging Face GGUF Model Hub & Downloader.
- **Review Goal**: Inspect code quality, state management, thread isolation, memory safety, and automated test coverage to confirm 100% industry/production readiness.

---

## 🚦 Phase-by-Phase Technical Specifications & Review Instructions

### 1. **Phase 1 — Dynamic Chat UI & Asynchronous Streaming Architecture**

#### 🔹 Implementation Summary:
- **60 FPS Token Streaming**: `ValueNotifier<String>` stream notifiers update `MessageBubble` widgets smoothly without triggering full screen or `ListView` rebuilds.
- **Unified Expanding Input Container (`ChatInput` in `lib/widgets/chat_input.dart`)**: ChatGPT-style multiline text field expanding up to 11 lines with embedded, independent action buttons (+ and Send/Stop) and concurrent typing enabled during generation.
- **Reverse Scrolling & Auto-Navigation**: Reverse `ListView.builder`, manual scroll override detector, auto-scroll to latest token, and scroll-to-bottom FloatingActionButton.

#### 🔍 Reviewer Checklist:
- [ ] Inspect `lib/widgets/chat_input.dart`: Verify `minLines: 1`, `maxLines: 11`, and `CrossAxisAlignment.end` layout alignment.
- [ ] Inspect `lib/widgets/message_bubble.dart`: Verify `ValueListenableBuilder` reactive rebuilds and `ParsedMessage` string parsing.
- [ ] Verify no UI frame drops occur during active token streaming.

---

### 2. **Phase 2 — High-Performance On-Device Database & Bud Management**

#### 🔹 Implementation Summary:
- **Isar NoSQL Persistence**: Complete schemas for `Conversation`, `Message`, `Bud`, and `AppSettings`.
- **4 Domain Repositories (Provider DI)**:
  - `ConversationRepository`: Chat session CRUD, pinning, renaming, cascade message deletion, Isar streams.
  - `MessageRepository`: Pair message saving, `updatedAt` touch timestamps, parent-conversation verification inside transactions (`writeTxn`) to prevent orphan messages if chats are deleted mid-generation.
  - `BudRepository`: Stable identity seeding (IDs 1–4: *General*, *Coding*, *Study*, *Creative*), custom Bud CRUD.
  - `SettingsRepository`: Single-instance app settings (`theme`, `selectedModel`, `serverIp`, `engineType`, `modelPath`, `cpuThreads`, `contextSize`, `batchSize`) enforcing fixed **ID = 1** and atomic `writeTxn` updates.
- **Indexing & Paginated Queries**: Indexed `@Index()` on `Message.conversationId` and `Message.createdAt` with deterministic paginated history loading.
- **AI Persona ("Bud") System**: Custom Bud management screen (`BudsScreen`), turn-by-turn persona switching via `BudSelectorChip` with a **"No Bud / Raw LLM"** clean-slate fallback, and auto-repair for deleted Bud references.

#### 🔍 Reviewer Checklist:
- [ ] Inspect `lib/repositories/message_repository.dart`: Verify parent conversation existence checks inside `writeTxn` transactions to guarantee ACID race-condition protection.
- [ ] Inspect `lib/repositories/bud_repository.dart`: Verify stable seeding for IDs 1–4 and fallback repairing logic.
- [ ] Inspect `lib/repositories/settings_repository.dart`: Verify fixed ID = 1 single-instance setting enforcement.

---

### 3. **Phase 3 — Network AI Streaming, Ollama Integration & Background Engine**

#### 🔹 Implementation Summary:
- **Multi-Turn Conversation Context (`/api/chat`)**: Passes past conversation turns directly to Ollama so the model maintains multi-turn context memory.
- **Sliding Window Context Limits**: Limits conversation history to the last 10 messages max (~1500 tokens) to prevent prompt bloat and mobile OOM crashes.
- **Global `GenerationManager` Engine**: Decouples generation jobs from `ChatScreen` widget lifecycle. Supports background multi-chat streaming without cross-talk or token leakage.
- **Drawer Status Indicators**: Live spinning progress circle for active streaming chats + Red unread notification dot for completed background responses (cleared upon opening).
- **Clean Service Contract (`AiService`)**: Abstract contract implemented by `MacAiService` and `LlamaCppAiService`.
- **Ollama HTTP Stream Engine**: Connects to Ollama (`POST /api/chat`) over local Wi-Fi with conditional `'think': true` handling for reasoning models (`qwen3`, `deepseek-r1`, `qwq`) to prevent HTTP 400 errors on standard models (`llama3.1`, `llama3.2`).
- **NDJSON Stream Transformer & Safety**: Uses `utf8.decoder` + `LineSplitter()` with `try-catch` JSON line parsing to guarantee 100% multibyte UTF-8 safety and malformed line protection.
- **Dual Network Timeout Protection**: 50s initial connection timeout (allows heavy model cold loads & context prefill) and 15s in-flight idle token timeout.
- **User-Initiated Cancellation**: Added Stop Generation button in `ChatInput` that severs the HTTP socket (`_client.close()`), preserves all partial tokens generated up to that moment, and saves them as completed.
- **In-Place Message Retry & Error UX**: Failed/interrupted responses render an inline `⚠️ Generation failed` status with an in-place `[ 🔄 Retry ]` button that re-streams directly into that message bubble without polluting the chat log or popping global SnackBars.
- **Collapsible Thinking Accordion**: Parses `<think>...</think>` XML tags and Ollama `thinking` / `reasoning_content` JSON fields. Renders live streaming reasoning inside a collapsible `🧠 Thought Process` card above the main answer.

#### 🔍 Reviewer Checklist:
- [ ] Inspect `lib/services/generation_manager.dart`: Verify active background jobs are keyed strictly by `conversationId`.
- [ ] Inspect `lib/services/ai_service.dart`: Verify NDJSON transformer and `<think>` tag extraction logic.
- [ ] Verify chat switching during background generation does not leak tokens between conversations.

---

### 4. **Phase 4 — Dart FFI, `llama.cpp` Native Engine & Hugging Face Model Hub**

#### 🔹 Implementation Summary:
- **Dart FFI (`dart:ffi`) Interop Pipeline**: Native C/C++ memory rules and native string marshalling (`package:ffi` `Pointer<Utf8>`, `calloc.free()`).
- **Native Shared Dynamic Library (`native/llama_bridge.cpp` & `simple_bridge.c`)**: Compiled into `native/libsimple_bridge.dylib` using `xcrun clang++` with C unmangled linkage (`extern "C"`).
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

#### 🔍 Reviewer Checklist:
- [ ] Inspect `native/llama_bridge.cpp`: Verify `extern "C"` exports and native memory safety.
- [ ] Inspect `lib/services/llama_cpp_service.dart`: Verify cross-platform dynamic library resolution (`openDynamicLibrary`) and Isolate spawning (`_llamaCppIsolateEntry`).
- [ ] Inspect `lib/services/huggingface_service.dart`: Verify byte streaming, cancellation, and temporary `.tmp` file cleanup.

---

### 5. **Phase 5 — Thread Isolation, App Lifecycle Memory Safeguards & Stress Testing**

#### 🔹 Implementation Summary:
- **App Lifecycle Memory Safeguards**: `GenerationManager` listens to `WidgetsBindingObserver` (`didChangeAppLifecycleState`). When ChatBud is backgrounded (`AppLifecycleState.paused`), it automatically calls `LlamaCppAiService.unloadModel()` to release native C-heap RAM to the mobile operating system!
- **Inference Parameter Tuning**: Added `cpuThreads` (default: 4 threads), `contextSize` (default: 2048 tokens), and `batchSize` (default: 512 tokens) to `AppSettings` and passed directly to C++ native `run_llama_cpp_inference()`.
- **Automated Stress Test Suite (`test/stress_test.dart`)**:
  - Verifies rapid chat switching during background streaming.
  - Verifies multi-chat concurrent background jobs and isolated notifiers.
  - Verifies rapid cancellation and state recovery.
  - Verifies unread completion badge updates across multi-chat sessions.

#### 🔍 Reviewer Checklist:
- [ ] Inspect `test/stress_test.dart`: Verify rapid chat switching, cancellation, and state recovery tests.
- [ ] Inspect `lib/services/generation_manager.dart`: Verify `WidgetsBindingObserver` `didChangeAppLifecycleState` RAM unloading logic.

---

## 📂 Complete Production Codebase Directory Map

```
lib/
├── database/
│   └── database.dart           # Isar DB initialization, schema definitions & default seeding
├── models/
│   ├── app_settings.dart       # Global settings model (Theme, Selected Model, Server IP, EngineType, ModelPath, CPU Threads, ContextSize)
│   ├── bud.dart                # AI Persona model
│   ├── conversation.dart       # Chat session model
│   ├── hugging_face_model.dart # Hugging Face Repo & GGUF file models
│   └── message.dart            # Indexed message model with MessageRole & MessageStatus
├── repositories/
│   ├── bud_repository.dart          # Persona CRUD & stable ID (1-4) seeding
│   ├── conversation_repository.dart # Chat session CRUD & Isar streams
│   ├── message_repository.dart      # Pair-saving, pagination & touch timestamps
│   └── settings_repository.dart     # Atomic app settings (Fixed ID = 1, Server IP, EngineType, ModelPath, CPU Threads)
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
├── stress_test.dart            # Phase 5 production stress & memory safeguard test suite
└── widget_test.dart            # Widget rendering & Provider harness test
```

---

## 🧪 Verification & Quality Control Commands

To verify full production readiness across all 5 phases, run:

```bash
# 1. Resolve pub dependencies
flutter pub get

# 2. Run Isar schema code generation
dart run build_runner build --delete-conflicting-outputs

# 3. Run full automated test suite (18 unit, widget, database, FFI & stress tests)
flutter test
```

**Expected Test Result**:
```bash
00:04 +18: All tests passed!
```
