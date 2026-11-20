#ifndef GPU_FRAME_PROTOCOL_H
#define GPU_FRAME_PROTOCOL_H
#include <stdint.h>
#define GF_MAGIC 0x47465031u
#define GF_VERSION 1u
#define GF_MAX_W 256u
#define GF_MAX_H 128u
#define GF_CAPACITY (GF_MAX_W * GF_MAX_H * 4u)
#define GF_RENDER 1u
#define GF_CLOSE 2u
#define GF_FRAME 1u
#define GF_CLOSED 2u
/* One outstanding request; separate parent command/child response ownership.
 * Events publish the header/payload. commit is a release/acquire sequence guard.
 * No pointers or process-dependent sizes cross the boundary. */
typedef struct {
    uint32_t magic, version, mapping_bytes, capacity;
    uint32_t command, epoch, sequence, width, height;
    uint32_t status, response_magic, response_version, header_bytes;
    uint32_t frame_epoch, frame_sequence, frame_width, frame_height;
    uint32_t stride, payload_bytes;
    volatile int32_t commit;
    unsigned char pixels[GF_CAPACITY];
} GpuFrameMap;
#define GF_HEADER_BYTES 80u
#endif
