// C interface of the Hayaki bridge to Anki's Rust core.
//
// Four functions: open a backend, run a method, free a buffer, close a backend.
// Requests and responses are protobuf messages from Anki's proto/anki/*.proto.
// Errors are an encoded anki.backend.BackendError. A panic inside the core is
// caught and returned as a BackendError of kind ANKIDROID_PANIC_ERROR.

#ifndef HAYAKI_BRIDGE_H
#define HAYAKI_BRIDGE_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/// An open backend. Opaque; only valid between open and close.
typedef struct HayakiBackend HayakiBackend;

/// Bytes owned by the bridge. Release with hayaki_buffer_free.
/// An empty buffer has data == NULL and len == 0.
typedef struct HayakiBuffer {
    uint8_t *_Nullable data;
    size_t len;
} HayakiBuffer;

/// Opens a backend from an encoded anki.backend.BackendInit.
/// On success returns the backend and leaves *error empty.
/// On failure returns NULL and stores an encoded BackendError in *error.
HayakiBackend *_Nullable hayaki_backend_open(const uint8_t *_Nullable init,
                                             size_t init_len,
                                             HayakiBuffer *_Nonnull error);

/// Runs one method of the core. The service and method numbers come from the
/// core's descriptor set and change between Anki versions.
/// Returns 0 and stores the encoded response in *output on success.
/// Returns 1 and stores an encoded BackendError in *output on failure.
int32_t hayaki_backend_run(HayakiBackend *_Nonnull backend,
                           uint32_t service,
                           uint32_t method,
                           const uint8_t *_Nullable input,
                           size_t input_len,
                           HayakiBuffer *_Nonnull output);

/// Frees a buffer returned by the bridge. Freeing an empty buffer is allowed.
void hayaki_buffer_free(HayakiBuffer buffer);

/// Closes a backend. Close any open collection first with the core's
/// CloseCollection method. The pointer is invalid afterwards.
void hayaki_backend_close(HayakiBackend *_Nullable backend);

#ifdef __cplusplus
}
#endif

#endif
