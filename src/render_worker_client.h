#ifndef LOCALTERM_RENDER_WORKER_CLIENT_H
#define LOCALTERM_RENDER_WORKER_CLIENT_H
#include <stddef.h>
#include <stdint.h>

/* CPU/Win32 transport only: never link OpenGL into its caller.
 * One owner thread for open/call/finish/destroy; cancel may be called remotely.
 * Packets are explicit Protocol-v2 bytes, not native structs. */
typedef struct RwClient RwClient;
typedef struct {
    uint32_t win_error;
    uint32_t child_exit;
    uint32_t stage;
    int close_ack;
    int process_exited;
    int job_empty;
    int forced;
} RwStatus;

/* Child path is pinned to the current executable directory. Capacities include
 * the 16-byte publication prefix plus Protocol header/body. diagnostics_handle
 * is an optional caller-owned writable Win32 HANDLE; zero sends stderr to NUL.
 * No parent environment mutation, shell, PATH lookup, GUI or clipboard access.
 * Serialize open with other inheriting launches in the caller: temporary
 * inheritable handles are private-listed and immediately cleared/closed. */
int rw_open(uint64_t surface, uint64_t generation, uint32_t request_capacity,
            uint32_t response_capacity, uint32_t timeout_ms,
            uintptr_t diagnostics_handle, RwClient **out, RwStatus *status);
int rw_call(RwClient *, const uint8_t *request, size_t request_len,
            uint8_t *response, size_t response_capacity, size_t *response_len,
            uint32_t timeout_ms, RwStatus *status);
void rw_cancel(RwClient *);
/* Call only after caller validated the matching .closed reply. Success requires
 * natural exit code 0 AND empty owned job, not merely a close ACK. */
int rw_finish(RwClient *, uint32_t timeout_ms, RwStatus *status);
/* Frees all owned objects. Forced termination is cleanup, never healthy close. */
int rw_destroy(RwClient *, uint32_t timeout_ms, RwStatus *status);
#endif
