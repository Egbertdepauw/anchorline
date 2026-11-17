#!/usr/bin/env python3
#
# Anchorline: the <stem>.combined.txt this writes is the trace format that
# LibdcRecording.parse reads (packages/libdivecomputer/lib/src/recording/
# recording.dart), so a Subsurface or libdivecomputer log can be replayed
# against the vendored libdivecomputer with LibdcDownload.replay. The Petrel 3
# fixture test/fixtures/raw/subsurface2.combined.txt was made with it; see
# packages/libdivecomputer/test/download_test.dart.
"""
extract_libdc_log.py  (v2 - more flexible)

Extract raw byte streams from a libdivecomputer logfile.

Handles multiple format variants:
  - Hex on lines following the header (one row or many), space-separated
  - Hex on the same line as "data="
  - Hex separated by spaces, colons, dashes, or nothing
  - Optional ASCII gutter "|...|" on the right
  - "Read:" / "Write:" / "READ:" / "WRITE:" / "INFO: Read:" headers

Writes:
  <stem>.read.bin   - everything received from the dive computer
  <stem>.write.bin  - everything sent to the dive computer
  <stem>.combined.txt - human-readable transcript

Usage:
    python3 extract_libdc_log.py path/to/subsurface.log [-o out_stem] [--debug]
"""

import argparse
import re
import sys
from pathlib import Path

# Header line: optional [timestamp], optional INFO:, then Read/Write, optional size,
# optional "data=" possibly followed by inline hex.
HEADER_RE = re.compile(
    r"""
    ^\s*
    (?:\[[^\]]*\]\s*)?           # optional [timestamp]
    (?:INFO:\s*)?                # optional INFO:
    (?P<direction>Read|Write|READ|WRITE|read|write)
    \s*:\s*
    (?:size\s*=\s*(?P<size>\d+))?
    [^=]*?                       # anything up to data= (non-greedy)
    (?:data\s*=\s*(?P<inline>.*))?
    $
    """,
    re.VERBOSE,
)

HEX_PAIR_RE = re.compile(r"[0-9a-fA-F]{2}")
GUTTER_RE = re.compile(r"\s*\|.*\|?\s*$")


def looks_like_hex_row(line: str) -> bool:
    s = GUTTER_RE.sub("", line).strip()
    if not s:
        return False
    if not HEX_PAIR_RE.search(s):
        return False
    cleaned = re.sub(r"[0-9a-fA-F\s:\-,]", "", s)
    return cleaned == ""


def extract_hex_bytes(text: str) -> bytes:
    s = GUTTER_RE.sub("", text)
    pairs = HEX_PAIR_RE.findall(s)
    return bytes(int(p, 16) for p in pairs)


def extract(log_path: Path, out_stem: Path, debug: bool = False) -> dict:
    reads = bytearray()
    writes = bytearray()
    transcript_lines = []

    current_dir = None
    current_expected = None
    current_buf = bytearray()

    headers_seen = 0
    hex_rows_consumed = 0

    def flush():
        nonlocal current_dir, current_expected, current_buf
        if current_dir is None:
            return
        if current_buf:
            if current_dir == "R":
                reads.extend(current_buf)
            else:
                writes.extend(current_buf)
            transcript_lines.append(
                f"{current_dir} ({len(current_buf)} bytes): "
                + " ".join(f"{b:02x}" for b in current_buf)
            )
        current_dir = None
        current_expected = None
        current_buf = bytearray()

    with log_path.open("r", encoding="utf-8", errors="replace") as f:
        for raw in f:
            line = raw.rstrip("\n")

            m = HEADER_RE.match(line)
            if m:
                flush()
                headers_seen += 1
                d = m.group("direction").lower()
                current_dir = "R" if d.startswith("r") else "W"
                size = m.group("size")
                current_expected = int(size) if size is not None else None
                current_buf = bytearray()

                inline = m.group("inline")
                if inline:
                    these = extract_hex_bytes(inline)
                    if these:
                        current_buf.extend(these)
                        hex_rows_consumed += 1
                        if (
                            current_expected is not None
                            and len(current_buf) >= current_expected
                        ):
                            current_buf = current_buf[:current_expected]
                            flush()
                continue

            if current_dir is not None and looks_like_hex_row(line):
                these = extract_hex_bytes(line)
                if these:
                    current_buf.extend(these)
                    hex_rows_consumed += 1
                    if (
                        current_expected is not None
                        and len(current_buf) >= current_expected
                    ):
                        current_buf = current_buf[:current_expected]
                        flush()
                continue

            if current_dir is not None:
                flush()

    flush()

    if debug:
        print(f"[debug] header lines matched: {headers_seen}", file=sys.stderr)
        print(f"[debug] hex row chunks consumed: {hex_rows_consumed}", file=sys.stderr)

    out_stem.parent.mkdir(parents=True, exist_ok=True)
    read_path = out_stem.with_suffix(".read.bin")
    write_path = out_stem.with_suffix(".write.bin")
    transcript_path = out_stem.with_suffix(".combined.txt")

    read_path.write_bytes(reads)
    write_path.write_bytes(writes)
    transcript_path.write_text("\n".join(transcript_lines) + "\n", encoding="utf-8")

    return {
        "read_bytes": len(reads),
        "write_bytes": len(writes),
        "packets": len(transcript_lines),
        "headers_seen": headers_seen,
        "hex_rows_consumed": hex_rows_consumed,
        "read_path": read_path,
        "write_path": write_path,
        "transcript_path": transcript_path,
    }


def main():
    ap = argparse.ArgumentParser(
        description=__doc__,
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    ap.add_argument("logfile", type=Path)
    ap.add_argument("-o", "--output-stem", type=Path, default=None)
    ap.add_argument("--debug", action="store_true")
    args = ap.parse_args()

    if not args.logfile.exists():
        print(f"error: {args.logfile} does not exist", file=sys.stderr)
        sys.exit(1)

    stem = args.output_stem or args.logfile.with_suffix("")
    result = extract(args.logfile, stem, debug=args.debug)

    print(f"Parsed {result['packets']} packets "
          f"(headers seen: {result['headers_seen']}, "
          f"hex chunks: {result['hex_rows_consumed']})")
    print(f"  Read  : {result['read_bytes']:>9} bytes -> {result['read_path']}")
    print(f"  Write : {result['write_bytes']:>9} bytes -> {result['write_path']}")
    print(f"  Trace : {result['transcript_path']}")


if __name__ == "__main__":
    main()
