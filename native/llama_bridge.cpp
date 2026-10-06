#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <stdio.h>

extern "C" {

// Lightweight file-integrity check for tooling. This is not model loading or
// inference; those operations are owned by the llama.cpp runtime binding.
int32_t verify_gguf_model_health_cpp(const char* model_path) {
    if (model_path == NULL || strlen(model_path) == 0) {
        return 0;
    }

    FILE* file = fopen(model_path, "rb");
    if (file == NULL) {
        return 0;
    }

    char magic[4];
    size_t read_bytes = fread(magic, 1, 4, file);
    fclose(file);

    if (read_bytes < 4) {
        return 0;
    }

    return magic[0] == 'G' && magic[1] == 'G' &&
                   magic[2] == 'U' && magic[3] == 'F'
               ? 1
               : 0;
}

} // extern "C"
