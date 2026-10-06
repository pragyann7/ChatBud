# ChatBud

ChatBud is a Flutter chat application with local Isar storage, assistant personas, an Ollama network client, and an experimental llama.cpp engine. The project is still under development and is not yet production-ready.

## Current capabilities

- Store conversations, messages, Buds, and settings on the device with Isar.
- Stream chat responses from an Ollama server selected by the user.
- Search Hugging Face and download GGUF model files for offline use.
- Run on-device llama.cpp inference on Android ARM64 using the runtime bundled by `llama_cpp_dart`.
- Stop generations, retry failed assistant messages, pin and rename chats, and switch Buds.

Ollama mode sends prompts to the configured local server over HTTP. Model search and downloads require an internet connection. Downloaded models and local inference are intended to work offline.

## Platform status

The checked-in application platform scaffold is Android. The llama.cpp Android CPU runtime is bundled for `arm64-v8a` by `llama_cpp_dart`; use an ARM64 Android device. The x86_64 emulator and iOS are not supported by this configuration. Local inference still needs smoke testing on physical devices with real GGUF models before it is considered production-ready.

The native C/C++ files are not the production inference runtime. `simple_bridge.c` contains FFI examples used by the interop exercises; `llama_bridge.cpp` only provides a GGUF header check.

## Build

Install Flutter 3.44 or newer and run:

```sh
flutter pub get
dart run build_runner build --delete-conflicting-outputs
flutter run
```

The first Android build downloads the native runtime assets. After changing the llama.cpp dependency, run `flutter pub get` and rebuild/reinstall the app so the native libraries are included in the APK.

For a distributable Android release, configure a release signing key and replace the sample application ID with an identifier owned by the publisher. Do not ship a debug-signed release.

## Quality status

The codebase is being hardened phase by phase. Automated test coverage and device validation are not yet sufficient to claim production readiness. See [FULL_PROJECT_REVIEW.md](FULL_PROJECT_REVIEW.md) for the target review checklist.
