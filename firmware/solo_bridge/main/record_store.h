// SPDX-License-Identifier: Apache-2.0
//
// The queue of OK records in flash (spec section 2). One file per record,
// named <epoch>-<counter>.rec, holding the REC, W and H lines exactly as they
// are sent; END is added by the sender. A record is deleted only on ACK.
//
// Plain stdio plus opendir/readdir/rename/fsync, so it runs on the Mac against
// a temp directory; on the device the directory is LittleFS mounted through
// VFS. A file is written as .tmp, fsynced and renamed, so a power cut leaves
// either no record or a whole one, never half of one.
#pragma once
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#include <stdio.h>

#include "hold_detector.h"

#define RECORD_STORE_MAX 50

typedef struct {
    char dir[64];
    char epoch[9];
    uint32_t next_counter;
    size_t count;  // finished (.rec) records, of any epoch
} record_store_t;

typedef struct {
    uint32_t boot;
    uint64_t up_ms;
    uint64_t wall_ms;  // 0 when no TIME has arrived this boot
    bool live;
} record_meta_t;

// Deletes *.tmp (a torn write), counts *.rec.
// next_counter = max(persisted, highest counter of this epoch on disk + 1, 1);
// a torn file's counter counts as on disk. False when dir can't be read.
bool record_store_open(record_store_t *s, const char *dir, const char *epoch,
                       uint32_t persisted_counter);
bool record_store_full(const record_store_t *s);

// Writes <epoch>-<counter>.tmp (the REC, W and H lines, each '\n'-terminated),
// fsyncs, renames to .rec. Calls persist(counter + 1) BEFORE writing, so a
// counter is never reused. False when full or on an I/O error.
bool record_store_put(record_store_t *s, const record_meta_t *m, const hold_t *h,
                      void (*persist)(uint32_t next, void *ctx), void *ctx, char rid_out[24]);

// The record to send next: the lowest counter of this epoch, else the lowest
// of any other. False when there is none.
bool record_store_oldest(const record_store_t *s, char rid_out[24]);

// Opens a record for reading; the caller fcloses. NULL when it is not there
// or rid is not a well-formed record id.
FILE *record_store_read(const record_store_t *s, const char *rid);

// Deletes a record. False when it is not there or rid is malformed (rids
// come from the phone: nothing with a '/' in it ever reaches the file system).
bool record_store_delete(record_store_t *s, const char *rid);
