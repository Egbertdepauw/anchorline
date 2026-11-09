// SPDX-License-Identifier: Apache-2.0
//
// Which stored record goes to the phone next (spec section 3): oldest first,
// one at a time, and only once the app has sent TIME on this connection. A
// record leaves the store only on its ACK; after a disconnect the same one is
// sent again from its REC line.
#pragma once
#include <stdbool.h>

#include "record_store.h"

typedef struct {
    bool ready;      // the app's TIME has come on this connection
    bool in_flight;  // a record was handed out and is not ACKed yet
    char rid[24];    // the one in flight
} outbox_t;

void outbox_init(outbox_t *o);
void outbox_on_disconnect(outbox_t *o);  // ready = false, in_flight = false
void outbox_on_time(outbox_t *o);        // the app's TIME: ready = true

// The rid to send now, or NULL: nothing is ready, one is in flight, or the
// store is empty. The pointer stays valid until the next outbox call.
const char *outbox_next(outbox_t *o, const record_store_t *s);

// The sender could not get the record out: it will be handed out again.
void outbox_on_send_failed(outbox_t *o);

// Deletes the record if it is stored; clears in_flight when it is the one in flight.
void outbox_on_ack(outbox_t *o, record_store_t *s, const char *rid);
