#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <stdio.h>

#ifdef __cplusplus
extern "C" {
#endif

// Simple native C function to test Dart FFI interop
int32_t add_numbers(int32_t a, int32_t b) {
    return a + b;
}

int32_t multiply_numbers(int32_t a, int32_t b) {
    return a * b;
}

// Native function that accepts a C string (const char*) and returns length
int32_t get_string_length(const char* text) {
    if (text == NULL) return 0;
    return (int32_t)strlen(text);
}

// Native function that allocates and formats a greeting string on the C-heap
char* format_greeting(const char* name) {
    if (name == NULL) return NULL;

    size_t length = strlen("Hello ") + strlen(name) + strlen("! Welcome to ChatBud FFI.") + 1;
    char* result = (char*)malloc(length);
    if (result == NULL) return NULL;

    snprintf(result, length, "Hello %s! Welcome to ChatBud FFI.", name);
    return result; // Must be freed by caller using free_native_string()
}

// Free C-heap allocated memory
void free_native_string(char* str) {
    if (str != NULL) {
        free(str);
    }
}

// Native C function that verifies if a .gguf model file exists, is readable, and has valid GGUF header
int32_t verify_gguf_model_health(const char* model_path) {
    if (model_path == NULL || strlen(model_path) == 0) {
        return 0; // Invalid path
    }

    FILE* file = fopen(model_path, "rb");
    if (file == NULL) {
        return 0; // File unreadable or missing
    }

    // Read 4-byte GGUF magic header ("GGUF" = 0x46554747)
    char magic[4];
    size_t read_bytes = fread(magic, 1, 4, file);
    fclose(file);

    if (read_bytes < 4) {
        return 0; // Incomplete or corrupted file
    }

    if (magic[0] == 'G' && magic[1] == 'G' && magic[2] == 'U' && magic[3] == 'F') {
        return 1; // Healthy GGUF model file!
    }

    return 0; // Invalid magic header
}

// Step 6: Native C token streaming callback definition
typedef void (*TokenCallbackFunction)(const char* token, int32_t is_done);

// Simulates llama.cpp token-by-token generation in C using callbacks
void simulate_llm_generation(const char* prompt, TokenCallbackFunction callback) {
    if (callback == NULL) return;

    const char* tokens[] = {
        "Hello", "! ", "This ", "is ", "a ", "token", "-by", "-token ",
        "stream ", "generated ", "from ", "native ", "C++ ", "via ", "Dart ", "FFI."
    };
    size_t count = sizeof(tokens) / sizeof(tokens[0]);

    for (size_t i = 0; i < count; i++) {
        int32_t is_done = (i == count - 1) ? 1 : 0;
        callback(tokens[i], is_done); // Invokes the Dart NativeCallable callback!
    }
}

#ifdef __cplusplus
}
#endif
