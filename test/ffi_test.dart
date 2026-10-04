import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'package:ffi/ffi.dart';
import 'package:flutter_test/flutter_test.dart';

// Native C function signatures (matching C types)
typedef NativeAdd = Int32 Function(Int32 a, Int32 b);
typedef NativeMultiply = Int32 Function(Int32 a, Int32 b);
typedef NativeGetStringLength = Int32 Function(Pointer<Utf8> text);
typedef NativeFormatGreeting = Pointer<Utf8> Function(Pointer<Utf8> name);
typedef NativeFreeString = Void Function(Pointer<Utf8> str);
typedef NativeVerifyGgufHealth = Int32 Function(Pointer<Utf8> modelPath);

// Step 6 & 7: Native callback signatures for streaming
typedef NativeTokenCallback = Void Function(Pointer<Utf8> token, Int32 isDone);
typedef NativeSimulateLlm = Void Function(
  Pointer<Utf8> prompt,
  Pointer<NativeFunction<NativeTokenCallback>> callback,
);

// Dart function signatures (matching Dart types)
typedef DartAdd = int Function(int a, int b);
typedef DartMultiply = int Function(int a, int b);
typedef DartGetStringLength = int Function(Pointer<Utf8> text);
typedef DartFormatGreeting = Pointer<Utf8> Function(Pointer<Utf8> name);
typedef DartFreeString = void Function(Pointer<Utf8> str);
typedef DartSimulateLlm = void Function(
  Pointer<Utf8> prompt,
  Pointer<NativeFunction<NativeTokenCallback>> callback,
);
typedef DartVerifyGgufHealth = int Function(Pointer<Utf8> modelPath);

// Isolate message payload
class IsolateStreamRequest {
  final String dylibPath;
  final String prompt;
  final SendPort sendPort;

  IsolateStreamRequest({
    required this.dylibPath,
    required this.prompt,
    required this.sendPort,
  });
}

// Background Isolate entry point
void _nativeStreamIsolateEntryPoint(IsolateStreamRequest request) {
  final dylib = DynamicLibrary.open(request.dylibPath);
  final simulateLlm = dylib
      .lookup<NativeFunction<NativeSimulateLlm>>('simulate_llm_generation')
      .asFunction<DartSimulateLlm>();

  final nativeCallback = NativeCallable<NativeTokenCallback>.listener(
    (Pointer<Utf8> tokenPtr, int isDone) {
      final token = tokenPtr.toDartString();
      request.sendPort.send(token);
      if (isDone == 1) {
        request.sendPort.send(null); // Send EOF signal
      }
    },
  );

  final promptPtr = request.prompt.toNativeUtf8();
  try {
    simulateLlm(promptPtr, nativeCallback.nativeFunction);
  } finally {
    calloc.free(promptPtr);
  }
}

Stream<String> executeNativeStreamInIsolate(String dylibPath, String prompt) {
  final controller = StreamController<String>();
  final receivePort = ReceivePort();

  Isolate.spawn(
    _nativeStreamIsolateEntryPoint,
    IsolateStreamRequest(
      dylibPath: dylibPath,
      prompt: prompt,
      sendPort: receivePort.sendPort,
    ),
  );

  late StreamSubscription sub;
  sub = receivePort.listen((message) {
    if (message == null) {
      controller.close();
      receivePort.close();
      sub.cancel();
    } else if (message is String) {
      controller.add(message);
    }
  });

  return controller.stream;
}

void main() {
  group('Phase 4 — Dart FFI & Isolate Integration Tests', () {
    late DynamicLibrary dylib;
    late DartAdd addNumbers;
    late DartMultiply multiplyNumbers;
    late DartGetStringLength getStringLength;
    late DartFormatGreeting formatGreeting;
    late DartFreeString freeNativeString;
    late DartSimulateLlm simulateLlmGeneration;
    late DartVerifyGgufHealth verifyHealth;

    setUpAll(() {
      final libraryPath = File('native/libsimple_bridge.dylib').absolute.path;
      dylib = DynamicLibrary.open(libraryPath);

      addNumbers = dylib
          .lookup<NativeFunction<NativeAdd>>('add_numbers')
          .asFunction<DartAdd>();

      multiplyNumbers = dylib
          .lookup<NativeFunction<NativeMultiply>>('multiply_numbers')
          .asFunction<DartMultiply>();

      getStringLength = dylib
          .lookup<NativeFunction<NativeGetStringLength>>('get_string_length')
          .asFunction<DartGetStringLength>();

      formatGreeting = dylib
          .lookup<NativeFunction<NativeFormatGreeting>>('format_greeting')
          .asFunction<DartFormatGreeting>();

      freeNativeString = dylib
          .lookup<NativeFunction<NativeFreeString>>('free_native_string')
          .asFunction<DartFreeString>();

      simulateLlmGeneration = dylib
          .lookup<NativeFunction<NativeSimulateLlm>>('simulate_llm_generation')
          .asFunction<DartSimulateLlm>();

      verifyHealth = dylib
          .lookup<NativeFunction<NativeVerifyGgufHealth>>('verify_gguf_model_health')
          .asFunction<DartVerifyGgufHealth>();
    });

    test('Steps 3 & 4: Call primitive C math functions from Dart', () {
      final sum = addNumbers(15, 27);
      final product = multiplyNumbers(6, 7);

      expect(sum, equals(42));
      expect(product, equals(42));
    });

    test('Step 5: String & C-Heap Memory Marshalling (Dart String <-> Pointer<Utf8>)', () {
      final nameStr = 'Pragyan'.toNativeUtf8();
      try {
        final len = getStringLength(nameStr);
        expect(len, equals(7));

        final Pointer<Utf8> cResultPtr = formatGreeting(nameStr);
        expect(cResultPtr, isNot(equals(nullptr)));

        final dartResultStr = cResultPtr.toDartString();
        expect(
          dartResultStr,
          equals('Hello Pragyan! Welcome to ChatBud FFI.'),
        );

        freeNativeString(cResultPtr);
      } finally {
        calloc.free(nameStr);
      }
    });

    test('Step 6: Native Callbacks (C -> Dart token streaming via NativeCallable)', () async {
      final completer = Completer<String>();
      final accumulatedText = StringBuffer();

      final NativeCallable<NativeTokenCallback> nativeCallback =
          NativeCallable<NativeTokenCallback>.listener(
        (Pointer<Utf8> tokenPtr, int isDone) {
          final token = tokenPtr.toDartString();
          accumulatedText.write(token);

          if (isDone == 1) {
            completer.complete(accumulatedText.toString());
          }
        },
      );

      final promptPtr = 'What is FFI?'.toNativeUtf8();
      try {
        simulateLlmGeneration(promptPtr, nativeCallback.nativeFunction);
        final resultText = await completer.future;

        expect(
          resultText,
          equals('Hello! This is a token-by-token stream generated from native C++ via Dart FFI.'),
        );
      } finally {
        calloc.free(promptPtr);
        nativeCallback.close();
      }
    });

    test('Step 7: Background Isolate + FFI (offload heavy C++ loops away from UI Isolate)', () async {
      final libraryPath = File('native/libsimple_bridge.dylib').absolute.path;

      final stream = executeNativeStreamInIsolate(libraryPath, 'Prompt for Isolate');
      final tokens = await stream.toList();
      final fullText = tokens.join();

      expect(
        fullText,
        equals('Hello! This is a token-by-token stream generated from native C++ via Dart FFI.'),
      );
    });

    test('Native GGUF Health Verification (verify_gguf_model_health)', () {
      final invalidPathPtr = 'non_existent_file.gguf'.toNativeUtf8();
      try {
        final result = verifyHealth(invalidPathPtr);
        expect(result, equals(0)); // Returns 0 for non-existent / invalid GGUF files
      } finally {
        calloc.free(invalidPathPtr);
      }
    });
  });
}
