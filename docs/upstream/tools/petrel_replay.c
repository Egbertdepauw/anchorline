// SPDX-License-Identifier: LGPL-2.1-or-later
//
// Copyright (C) 2026 Egbert de Pauw
//
// petrel_replay: run libdivecomputer's own Shearwater Petrel driver
// against a simulated Petrel that serves data recorded from a real one.
//
// The simulated device speaks the Shearwater BLE protocol (SLIP framing,
// 2-byte BLE frame header, RDBI 0x22, download init/block/quit
// 0x35/0x36/0x37). It serves:
//   - manifest pages from a manifest file (0x600 bytes per page, one page
//     per manifest download, in order);
//   - compressed dive streams from <dir>/<address>.lre, in 144-byte blocks,
//     exactly as recorded from a Petrel 3;
//   - for any other address, a stream that holds only the LRE end marker
//     (an empty dive), so that a full log can be walked without the data
//     of every dive.
//
// It then calls dc_device_foreach() and prints every dive address that
// libdivecomputer requested, next to the valid manifest records, so that
// a record that was never downloaded stands out.
//
// Build against an installed libdivecomputer:
//   cc -o petrel_replay petrel_replay.c \
//      -I<prefix>/include <prefix>/lib/libdivecomputer.a
//
// Usage:
//   petrel_replay <manifest.bin> <lre-dir> [--delete N]... [--fingerprint N]
//
//   --delete N       mark manifest record N (0-based, newest first) as
//                    deleted (header 0x5A23), as the Petrel does when a
//                    dive is deleted on the device
//   --fingerprint N  pass manifest record N's fingerprint to libdc, so
//                    the download stops at that (already known) dive

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include <libdivecomputer/context.h>
#include <libdivecomputer/custom.h>
#include <libdivecomputer/descriptor.h>
#include <libdivecomputer/device.h>
#include <libdivecomputer/iterator.h>

#define END     0xC0
#define ESC     0xDB
#define ESC_END 0xDC
#define ESC_ESC 0xDD

#define MANIFEST_ADDR 0xE0000000u
#define MANIFEST_PAGE 0x600
#define RECORD_SIZE   0x20
#define BASE_ADDR     0x80000000u
#define BLOCK_PLAIN   128 // manifest block size seen from a Petrel 3
#define BLOCK_LRE     144 // compressed block size seen from a Petrel 3
#define FRAME_MAX     75  // BLE payload per notification seen from a Petrel 3

#define MAX_REQUESTS 1024

typedef struct petrel_t {
	// Host -> device.
	unsigned char rx[8192];
	size_t rxlen;
	int escaped;

	// Device -> host, as a queue of BLE frames.
	unsigned char frames[64][FRAME_MAX + 2];
	size_t framelen[64];
	size_t nframes, nextframe;

	// Data.
	unsigned char *manifest;
	size_t manifest_size;
	size_t manifest_page;
	const char *lredir;

	// Current download.
	unsigned char *stream;
	size_t stream_size, stream_offset, blocksize;

	// Log of dive addresses that libdc requested.
	unsigned int requested[MAX_REQUESTS];
	size_t nrequested;
} petrel_t;

static unsigned int
be32 (const unsigned char *p)
{
	return ((unsigned int) p[0] << 24) | (p[1] << 16) | (p[2] << 8) | p[3];
}

static unsigned char *
load (const char *path, size_t *size)
{
	FILE *fp = fopen (path, "rb");
	if (fp == NULL)
		return NULL;
	fseek (fp, 0, SEEK_END);
	long n = ftell (fp);
	fseek (fp, 0, SEEK_SET);
	unsigned char *buf = malloc (n > 0 ? n : 1);
	if (fread (buf, 1, n, fp) != (size_t) n) {
		fclose (fp);
		free (buf);
		return NULL;
	}
	fclose (fp);
	*size = n;
	return buf;
}

// Queue a response payload: 01 FF [len+1] 00 <payload>, SLIP-encoded, cut
// into BLE frames with the [nframes, index] header.
static void
respond (petrel_t *dev, const unsigned char *payload, size_t len)
{
	unsigned char packet[4096];
	size_t n = 0;
	unsigned char raw[1024];
	size_t m = 0;

	raw[m++] = 0x01;
	raw[m++] = 0xFF;
	raw[m++] = (unsigned char) (len + 1);
	raw[m++] = 0x00;
	memcpy (raw + m, payload, len);
	m += len;

	for (size_t i = 0; i < m; ++i) {
		if (raw[i] == END) {
			packet[n++] = ESC;
			packet[n++] = ESC_END;
		} else if (raw[i] == ESC) {
			packet[n++] = ESC;
			packet[n++] = ESC_ESC;
		} else {
			packet[n++] = raw[i];
		}
	}
	packet[n++] = END;

	size_t count = (n + FRAME_MAX - 1) / FRAME_MAX;
	for (size_t f = 0; f < count; ++f) {
		size_t chunk = n - f * FRAME_MAX;
		if (chunk > FRAME_MAX)
			chunk = FRAME_MAX;
		unsigned char *frame = dev->frames[dev->nframes];
		frame[0] = (unsigned char) count;
		frame[1] = (unsigned char) f;
		memcpy (frame + 2, packet + f * FRAME_MAX, chunk);
		dev->framelen[dev->nframes] = chunk + 2;
		dev->nframes++;
	}
}

static void
handle (petrel_t *dev, const unsigned char *p, size_t n)
{
	// Request: FF 01 [len+1] 00 <payload>
	if (n < 5 || p[0] != 0xFF || p[1] != 0x01) {
		fprintf (stderr, "petrel: bad request header\n");
		exit (2);
	}
	const unsigned char *cmd = p + 4;
	size_t len = n - 4;

	switch (cmd[0]) {
	case 0x22: { // RDBI
		unsigned int id = (cmd[1] << 8) | cmd[2];
		unsigned char rsp[64] = {0x62, cmd[1], cmd[2]};
		size_t rlen = 3;
		if (id == 0x8010) { // serial (ASCII hex)
			memcpy (rsp + 3, "B89641E4", 8);
			rlen += 8;
		} else if (id == 0x8011) { // firmware
			memcpy (rsp + 3, "V103 DiveCAN", 12);
			rlen += 12;
		} else if (id == 0x8060) { // model number: Petrel 3
			rsp[3] = 10;
			rlen += 1;
		} else if (id == 0x8050) { // hardware id
			rsp[3] = 0xB4;
			rsp[4] = 0x07;
			rlen += 2;
		} else if (id == 0x8021) { // logbook type, as recorded
			const unsigned char lu[] = {0x01, 0x80, 0x00, 0x00, 0x00, 0x00, 0x02, 0x00, 0x80};
			memcpy (rsp + 3, lu, sizeof (lu));
			rlen += sizeof (lu);
		} else {
			const unsigned char nak[] = {0x7F, 0x22, 0x31};
			respond (dev, nak, sizeof (nak));
			return;
		}
		respond (dev, rsp, rlen);
		return;
	}
	case 0x2E: // WDBI (shutdown 0x9020): libdc expects no response
		return;
	case 0x35: { // download init
		unsigned int compressed = cmd[1] & 0x10;
		unsigned int address = be32 (cmd + 3);
		free (dev->stream);
		dev->stream = NULL;
		dev->stream_offset = 0;
		if (address == MANIFEST_ADDR) {
			size_t off = dev->manifest_page * MANIFEST_PAGE;
			dev->stream = malloc (MANIFEST_PAGE);
			memset (dev->stream, 0xFF, MANIFEST_PAGE);
			if (off < dev->manifest_size) {
				size_t avail = dev->manifest_size - off;
				memcpy (dev->stream, dev->manifest + off, avail < MANIFEST_PAGE ? avail : MANIFEST_PAGE);
			}
			dev->stream_size = MANIFEST_PAGE;
			dev->blocksize = BLOCK_PLAIN;
			dev->manifest_page++;
		} else {
			char path[4096];
			snprintf (path, sizeof (path), "%s/%08x.lre", dev->lredir, address);
			dev->stream = load (path, &dev->stream_size);
			if (dev->stream == NULL) {
				// Empty dive: a block of zero bits starts with the end marker.
				dev->stream = calloc (1, BLOCK_LRE);
				dev->stream_size = BLOCK_LRE;
			}
			dev->blocksize = BLOCK_LRE;
			if (dev->nrequested < MAX_REQUESTS)
				dev->requested[dev->nrequested++] = address;
		}
		const unsigned char rsp[] = {0x75, 0x10, compressed ? 0x92 : 0x82};
		respond (dev, rsp, sizeof (rsp));
		return;
	}
	case 0x36: { // download block
		unsigned char rsp[2 + 256] = {0x76, cmd[1]};
		size_t chunk = dev->stream_size - dev->stream_offset;
		if (dev->stream == NULL || chunk == 0) {
			const unsigned char nak[] = {0x7F, 0x36, 0x24};
			respond (dev, nak, sizeof (nak));
			return;
		}
		if (chunk > dev->blocksize)
			chunk = dev->blocksize;
		memcpy (rsp + 2, dev->stream + dev->stream_offset, chunk);
		dev->stream_offset += chunk;
		respond (dev, rsp, 2 + chunk);
		return;
	}
	case 0x37: { // download quit
		const unsigned char rsp[] = {0x77, 0x00};
		respond (dev, rsp, sizeof (rsp));
		return;
	}
	default:
		fprintf (stderr, "petrel: unexpected command %02x (len %zu)\n", cmd[0], len);
		exit (2);
	}
}

static dc_status_t
cb_write (void *userdata, const void *data, size_t size, size_t *actual)
{
	petrel_t *dev = userdata;
	const unsigned char *p = data;

	// Every BLE write from libdc carries the 2-byte [nframes, index] header.
	for (size_t i = 2; i < size; ++i) {
		unsigned char c = p[i];
		if (c == END) {
			if (dev->rxlen) {
				handle (dev, dev->rx, dev->rxlen);
				dev->rxlen = 0;
			}
			continue;
		}
		if (c == ESC) {
			dev->escaped = 1;
			continue;
		}
		if (dev->escaped) {
			c = (c == ESC_END) ? END : (c == ESC_ESC) ? ESC : c;
			dev->escaped = 0;
		}
		dev->rx[dev->rxlen++] = c;
	}

	if (actual)
		*actual = size;
	return DC_STATUS_SUCCESS;
}

static dc_status_t
cb_read (void *userdata, void *data, size_t size, size_t *actual)
{
	petrel_t *dev = userdata;

	if (dev->nextframe >= dev->nframes) {
		dev->nframes = dev->nextframe = 0;
		if (actual)
			*actual = 0;
		return DC_STATUS_TIMEOUT;
	}

	size_t n = dev->framelen[dev->nextframe];
	if (n > size)
		n = size;
	memcpy (data, dev->frames[dev->nextframe], n);
	dev->nextframe++;
	if (dev->nextframe >= dev->nframes)
		dev->nframes = dev->nextframe = 0;

	if (actual)
		*actual = n;
	return DC_STATUS_SUCCESS;
}

static dc_status_t
cb_ok (void *userdata)
{
	(void) userdata;
	return DC_STATUS_SUCCESS;
}

static dc_status_t
cb_timeout (void *userdata, int timeout)
{
	(void) userdata;
	(void) timeout;
	return DC_STATUS_SUCCESS;
}

static dc_status_t
cb_sleep (void *userdata, unsigned int ms)
{
	(void) userdata;
	(void) ms;
	return DC_STATUS_SUCCESS;
}

static dc_status_t
cb_purge (void *userdata, dc_direction_t direction)
{
	(void) userdata;
	(void) direction;
	return DC_STATUS_SUCCESS;
}

static dc_status_t
cb_configure (void *userdata, unsigned int baudrate, unsigned int databits, dc_parity_t parity, dc_stopbits_t stopbits, dc_flowcontrol_t flowcontrol)
{
	(void) userdata;
	(void) baudrate;
	(void) databits;
	(void) parity;
	(void) stopbits;
	(void) flowcontrol;
	return DC_STATUS_SUCCESS;
}

static int
cb_dive (const unsigned char *data, unsigned int size, const unsigned char *fingerprint, unsigned int fsize, void *userdata)
{
	(void) data;
	(void) size;
	(void) fingerprint;
	(void) fsize;
	(void) userdata;
	return 1;
}

int
main (int argc, char *argv[])
{
	if (argc < 3) {
		fprintf (stderr, "usage: %s <manifest.bin> <lre-dir> [--delete N]... [--fingerprint N]\n", argv[0]);
		return 1;
	}

	petrel_t *dev = calloc (1, sizeof (petrel_t));
	dev->manifest = load (argv[1], &dev->manifest_size);
	dev->lredir = argv[2];
	if (dev->manifest == NULL) {
		fprintf (stderr, "cannot read %s\n", argv[1]);
		return 1;
	}

	int fp_record = -1;
	for (int i = 3; i < argc; ++i) {
		if (strcmp (argv[i], "--delete") == 0 && i + 1 < argc) {
			size_t r = strtoul (argv[++i], NULL, 0);
			dev->manifest[r * RECORD_SIZE + 0] = 0x5A;
			dev->manifest[r * RECORD_SIZE + 1] = 0x23;
		} else if (strcmp (argv[i], "--fingerprint") == 0 && i + 1 < argc) {
			fp_record = (int) strtol (argv[++i], NULL, 0);
		}
	}

	dc_context_t *context = NULL;
	dc_context_new (&context);
	dc_context_set_loglevel (context, DC_LOGLEVEL_ERROR);

	dc_descriptor_t *descriptor = NULL, *current = NULL;
	dc_iterator_t *iterator = NULL;
	dc_descriptor_iterator_new (&iterator, context);
	while (dc_iterator_next (iterator, &current) == DC_STATUS_SUCCESS) {
		if (strcmp (dc_descriptor_get_vendor (current), "Shearwater") == 0 &&
			strcmp (dc_descriptor_get_product (current), "Petrel 3") == 0) {
			descriptor = current;
			break;
		}
		dc_descriptor_free (current);
	}
	dc_iterator_free (iterator);
	if (descriptor == NULL) {
		fprintf (stderr, "no Petrel 3 descriptor\n");
		return 1;
	}

	const dc_custom_cbs_t cbs = {
		.set_timeout = cb_timeout,
		.configure = cb_configure,
		.read = cb_read,
		.write = cb_write,
		.purge = cb_purge,
		.sleep = cb_sleep,
		.close = cb_ok,
	};
	dc_iostream_t *iostream = NULL;
	dc_status_t rc = dc_custom_open (&iostream, context, DC_TRANSPORT_BLE, &cbs, dev);
	if (rc != DC_STATUS_SUCCESS) {
		fprintf (stderr, "dc_custom_open: %d\n", rc);
		return 1;
	}

	dc_device_t *device = NULL;
	rc = dc_device_open (&device, context, descriptor, iostream);
	if (rc != DC_STATUS_SUCCESS) {
		fprintf (stderr, "dc_device_open: %d\n", rc);
		return 1;
	}

	if (fp_record >= 0)
		dc_device_set_fingerprint (device, dev->manifest + fp_record * RECORD_SIZE + 4, 4);

	rc = dc_device_foreach (device, cb_dive, NULL);
	printf ("dc_device_foreach: status %d\n", rc);

	// Compare the valid manifest records with what libdc downloaded.
	unsigned int expected = 0, missing = 0;
	for (size_t off = 0; off + RECORD_SIZE <= dev->manifest_size; off += RECORD_SIZE) {
		const unsigned char *r = dev->manifest + off;
		unsigned int header = (r[0] << 8) | r[1];
		if (header == 0x5A23)
			continue;
		if (header != 0xA5C4)
			break;
		if (fp_record >= 0 && off == (size_t) fp_record * RECORD_SIZE)
			break;
		expected++;
		unsigned int address = BASE_ADDR + be32 (r + 20);
		unsigned int number = (r[2] << 8) | r[3];
		int found = 0;
		for (size_t i = 0; i < dev->nrequested; ++i) {
			if (dev->requested[i] == address)
				found = 1;
		}
		if (!found) {
			printf ("NOT DOWNLOADED: manifest record %zu, dive #%u, address %08x\n", off / RECORD_SIZE, number, address);
			missing++;
		}
	}
	printf ("valid new dives in manifest: %u, downloaded by libdc: %zu, missing: %u\n", expected, dev->nrequested, missing);

	dc_device_close (device);
	dc_iostream_close (iostream);
	dc_descriptor_free (descriptor);
	dc_context_free (context);
	return missing ? 3 : 0;
}
