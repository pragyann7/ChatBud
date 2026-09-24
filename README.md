# ChatBud

ChatBud is a Flutter project to build a private, fully offline AI chat app for mobile. The long-term goal is to let a user chat with a language model that runs on their device, without needing an internet connection or sending conversation data to a cloud service.

The app is being developed in learning phases. The current build is an early UI prototype: it simulates streamed responses and does not yet load or run a language model.

## Project vision

The finished app is intended to provide:

- On-device AI chat using local GGUF models
- Smooth, token-by-token response streaming
- Local conversation history and settings
- Custom assistant profiles (“Buds”) with their own names and system prompts
- A Flutter interface backed by native `llama.cpp` inference through Dart FFI
- Background generation and memory safeguards for mobile devices

The network API phase below is a temporary learning step for understanding streaming from a remote service. It is not a requirement for the finished offline app.

## Project status

**Completed** means the phase objective is implemented in the current project. **In progress** means it is actively being built. **Planned** means it has not started yet.

### Completed

- **Phase 1 — Dynamic chat UI and asynchronous streams:** Chat UI, message bubbles, a reverse scrolling message list, scroll-to-latest control, unique message IDs, and a simulated service that emits response chunks over time. The screen prevents overlapping generations and handles stream errors.

### In progress

- No phase is currently in progress.

### Planned

- **Phase 2 — On-device database:** Choose and use Isar or Hive to save and retrieve chat history, settings, and custom Bud profiles, including paginating older messages.
- **Phase 3 — Network-based streaming (learning bridge):** Use an external REST API or WebSocket to practice handling a real asynchronous token stream. This is an educational bridge and is not part of the final offline runtime.
- **Phase 4 — Dart FFI and `llama.cpp`:** Connect Dart to native C++ inference using `llama_cpp_dart` or a focused FFI wrapper, and build the required Android and iOS native libraries.
- **Phase 5 — Isolates and memory safeguards:** Move model loading and inference work off the UI isolate, manage large GGUF models carefully, and handle device memory limits and out-of-memory risks.

## Current implementation

The app currently uses a preset-response service to simulate an LLM stream. It does not yet persist conversations, call a network API, load a GGUF model, or run `llama.cpp`.

Try these prompts in the current prototype:

- `hello` or `hi`
- `what is flutter`
- `how are you`
- `who are you`
- `long`, `test`, or `tell me a long story`

Other prompts receive a default response.

## Project structure

```
lib/
├── main.dart                 # App shell, chat screen, and message bubbles
├── models/
│   └── message.dart          # Message data model
└── services/
    └── llm_service.dart     # Simulated asynchronous response stream

assets/
├── buds.png
├── models.png
└── new_chat.png
```

## Run the app

Install Flutter for your platform, then run these commands from the project directory:

```
flutter pub get
flutter run
```

## Phase-by-phase README updates

This README is the project’s vision and progress record. When a phase is completed, update its status, summarize what was implemented, and move the next active phase to **In progress**. Keep future phases under **Planned** and revise the current implementation notes to match the code.
