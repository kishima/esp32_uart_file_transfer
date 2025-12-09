# Protocol Specification

## Overview

This protocol implements a robust serial file transfer system over UART, designed for embedded systems (ESP32). It uses COBS (Consistent Overhead Byte Stuffing) encoding for reliable framing, CRC32 for error detection, and supports both JSON metadata and binary data transfer.

**Key Features:**
- Delimiter-based framing with COBS encoding (eliminates in-band 0x00 bytes)
- CRC32 integrity checking
- Mixed JSON + binary payload support
- File system operations (cd, ls, rm)
- Chunked file transfer (get/put)
- Device management (reboot)

## Physical Layer

**Default Settings:**
- Baud rate: 115200
- Data bits: 8
- Stop bits: 1
- Parity: None
- Flow control: Hardware (RTS/CTS) recommended
- Mode: Raw binary (no echo, no line processing)

**Important:** The serial port must be configured in raw binary mode to prevent the OS from mangling binary data. On Linux/Unix, this is done using `stty`:
```bash
stty -F /dev/ttyUSB0 115200 raw -echo -echoe -echok -echoctl -echoke -onlcr -opost -isig -icanon -iexten
```

## Frame Structure

### Wire Format
```
[COBS encoded packet] + 0x00
```

The frame delimiter is a single null byte (`0x00`). COBS encoding ensures that no `0x00` bytes appear in the encoded data, making this delimiter unambiguous.

### COBS Encoded Packet (Before Delimiter)

The packet is COBS-encoded to eliminate all `0x00` bytes from the payload, allowing reliable framing.

**COBS Encoding Rules:**
- Replaces all `0x00` bytes with overhead codes
- Overhead byte indicates distance to next zero (or end of segment)
- Maximum segment length: 254 bytes (0xFF indicates no zero in segment)
- Adds ~0.4% overhead on average

### Decoded Packet Structure

After COBS decoding, the packet has this structure:

```
┌──────┬──────────┬──────────┬─────────────────┬─────────────┬─────────┐
│ CMD  │ LEN_HI   │ LEN_LO   │   JSON PARAMS   │ BINARY DATA │  CRC32  │
│ (1B) │   (1B)   │   (1B)   │   (variable)    │ (optional)  │  (4B)   │
└──────┴──────────┴──────────┴─────────────────┴─────────────┴─────────┘
```

**Field Descriptions:**

1. **CMD (1 byte)**: Command code
   - Identifies the operation to perform
   - See "Command Codes" section below

2. **LEN (2 bytes, big-endian)**: JSON section length
   - 16-bit unsigned integer (0-65535)
   - Specifies byte count of JSON params section only
   - Binary data length is NOT included in this field
   - Binary data length is indicated in the JSON params (`"bin"` field for responses)

3. **JSON PARAMS (variable length)**: Command parameters
   - UTF-8 encoded JSON object
   - Length specified by LEN field
   - Must be valid JSON (parsing errors result in `{"ok":false,"err":"bad_json"}`)

4. **BINARY DATA (optional, variable length)**:
   - Raw binary data for file transfers
   - Only present in PUT commands (request) and GET commands (response)
   - Length is implicit: `total_body_length - 3 - json_length`
   - For GET responses, length is explicitly specified in JSON `"bin"` field

5. **CRC32 (4 bytes, big-endian)**: Integrity check
   - CRC-32 checksum (IEEE 802.3 polynomial)
   - Covers all preceding bytes (CMD + LEN + JSON + BINARY)
   - Computed using standard zlib CRC32 algorithm
   - Mismatches result in "CRC error" rejection

### Packet Building Algorithm (Transmit)

```
1. Build body:
   body = [CMD (1B)] + [JSON_LEN (2B BE)] + [JSON data] + [binary data (optional)]

2. Compute CRC:
   crc = CRC32(body) as 4 bytes big-endian

3. Create raw packet:
   raw = body + crc

4. COBS encode:
   encoded = COBS_ENCODE(raw)

5. Add delimiter:
   frame = encoded + 0x00

6. Transmit frame over UART
```

### Packet Parsing Algorithm (Receive)

```
1. Accumulate bytes until 0x00 delimiter found

2. Extract frame (bytes before delimiter)

3. COBS decode:
   raw = COBS_DECODE(frame)
   # IMPORTANT: After COBS decode, the total length of 'raw' is known.
   # This is how we determine the body length - it's implicit from framing.

4. Verify minimum length (5 bytes: 1 cmd + 2 len + 0 json + 4 crc)
   if raw.length < 5:
     ERROR: "Short frame"

5. Split packet using fixed CRC position:
   body = raw[0...-4]              # Everything except last 4 bytes
   crc_received = raw[-4..-1]      # Last 4 bytes
   # Body length is now known: body.length = raw.length - 4

6. Verify CRC:
   crc_computed = CRC32(body)
   if crc_received != crc_computed:
     ERROR: "CRC error"

7. Parse body structure:
   cmd = body[0]                   # 1 byte
   json_len = body[1..2] as big-endian uint16  # 2 bytes
   json_data = body[3 ... 3+json_len]

   # Binary data length is implicit:
   binary_len = body.length - 3 - json_len
   binary_data = body[3+json_len ... end]  # Remaining bytes after JSON

8. Parse JSON:
   params = JSON_PARSE(json_data)

   # For GET responses, verify binary length matches JSON metadata:
   if params has "bin" field:
     expected_binary_length = params["bin"]
     if binary_len != expected_binary_length:
       WARNING: "Binary length mismatch"
     # Use the actual extracted binary_data from step 7
```

**Key insight on length determination:**
- **No explicit body length field exists in the protocol**
- Body length is determined by: `decoded_packet_length - 4 (CRC size)`
- Binary data length is determined by: `body_length - 3 (header) - json_length`
- The delimiter (0x00) + COBS decoding provides unambiguous framing
- This design eliminates the need for a separate length field, simplifying the protocol

## COBS Encoding Details

**Consistent Overhead Byte Stuffing (COBS)** is a framing algorithm that encodes data to eliminate a specific byte value (0x00 in this case).

### Encoding Process

```ruby
def encode(data)
  out = ""
  code_index = 0
  out << 0x00  # placeholder for first code byte
  code = 1

  data.each_byte do |b|
    if b == 0x00
      out[code_index] = code      # write distance to this zero
      code_index = out.length
      out << 0x00                 # new placeholder
      code = 1
    else
      out << b
      code += 1
      if code == 0xFF             # max segment length reached
        out[code_index] = code
        code_index = out.length
        out << 0x00
        code = 1
      end
    end
  end

  out[code_index] = code          # final code
  out
end
```

### Decoding Process

```ruby
def decode(data)
  out = ""
  i = 0

  while i < data.length
    code = data[i]
    raise "COBS decode error" if code == 0
    i += 1

    # Copy (code - 1) bytes
    (code - 1).times do
      out << data[i]
      i += 1
    end

    # Add zero if not at end and not max segment
    out << 0x00 if code < 0xFF && i < data.length
  end

  out
end
```

### COBS Properties

- **Overhead**: 1 byte per 254 bytes (worst case: 1 byte per byte for all-zero data)
- **No 0x00 in output**: Guaranteed, allowing unambiguous framing
- **Deterministic**: Same input always produces same output
- **Self-synchronizing**: Single frame corruption doesn't affect subsequent frames

## Command Codes

| Code | Command | Description | JSON Params | Binary Data |
|------|---------|-------------|-------------|-------------|
| 0x11 | CD      | Change remote working directory | `{"path": "/dir"}` | None |
| 0x12 | LS      | List directory contents | `{"path": "/dir"}` | None |
| 0x13 | RM      | Remove file or directory | `{"path": "/file"}` | None |
| 0x21 | GET     | Read file chunk | `{"path": "/file", "off": 0}` | None (request)<br>Present (response) |
| 0x22 | PUT     | Write file chunk | `{"path": "/file", "off": 0}` | Present (request)<br>None (response) |
| 0x31 | REBOOT  | Reboot device | `{}` | None |
| 0x00 | RESP    | Response (server to client) | Varies by command | Optional |

### Command Details

#### 0x11 - CD (Change Directory)

Changes the current working directory on the remote device.

**Request:**
```json
{"path": "/absolute/or/relative/path"}
```

**Response (success):**
```json
{"ok": true}
```

**Response (error):**
```json
{"ok": false, "err": "directory not found"}
```

#### 0x12 - LS (List Directory)

Lists contents of a directory.

**Request:**
```json
{"path": "/directory/path"}
```
- `path`: Can be absolute or relative to current working directory
- Use `"."` for current directory

**Response (success):**
```json
{
  "ok": true,
  "entries": [
    {"n": "file1.txt", "t": "f", "s": 1234},
    {"n": "subdir", "t": "d", "s": 0},
    {"n": "file2.bin", "t": "f", "s": 5678}
  ]
}
```

**Entry fields:**
- `n`: Name (string)
- `t`: Type - `"f"` (file) or `"d"` (directory)
- `s`: Size in bytes (0 for directories)

**Response (error):**
```json
{"ok": false, "err": "directory not found"}
```

#### 0x13 - RM (Remove)

Removes a file or directory.

**Request:**
```json
{"path": "/file/or/directory/path"}
```

**Response (success):**
```json
{"ok": true}
```

**Response (error):**
```json
{"ok": false, "err": "file not found"}
```

#### 0x21 - GET (Read File)

Reads a chunk of a file. Used iteratively to download entire files.

**Chunking Strategy:**
- Client requests data at specific byte offsets
- Server responds with available data (up to its buffer limit)
- Client increments offset by received byte count
- Process repeats until `eof` flag is true

**Request:**
```json
{"path": "/file/path", "off": 0}
```
- `path`: File path (absolute or relative)
- `off`: Byte offset to start reading from (0-based)

**Response (success):**
```json
{"ok": true, "eof": false, "bin": 1024}
```
+ **Binary data**: 1024 bytes of file content

**Response fields:**
- `ok`: Success flag
- `eof`: End-of-file flag
  - `false`: More data available (make another GET request with updated offset)
  - `true`: This is the last chunk (file is complete)
  - Note: `eof` can be `true` even with `bin` > 0 (last chunk with data)
- `bin`: Number of binary data bytes following the JSON
  - Can be 0 if file is empty or offset is at EOF
  - Actual chunk size determined by server's available buffer

**Download Algorithm (Client Implementation):**
```ruby
def download(remote_path, local_path)
  File.open(local_path, "wb") do |file|
    offset = 0
    loop do
      # Request chunk at current offset
      response = GET(remote_path, offset)

      raise "Download failed" unless response.ok

      # Write received data (if any)
      if response.binary_data && !response.binary_data.empty?
        file.write(response.binary_data)
        offset += response.binary_data.bytesize
      end

      # Check for end-of-file
      break if response.eof
    end
  end
end
```

**Chunking Characteristics:**
1. **Client-driven**: Client controls chunk size via request frequency
2. **Offset-based**: Each request specifies exact byte position
3. **Stateless**: Server doesn't maintain session state between requests
4. **Resumable**: Client can resume from any offset after interruption
5. **Variable size**: Server may return less data than requested

**Example Download Session:**
```
Request 1:  {"path": "/file.bin", "off": 0}
Response 1: {"ok": true, "eof": false, "bin": 1024} + 1024 bytes

Request 2:  {"path": "/file.bin", "off": 1024}
Response 2: {"ok": true, "eof": false, "bin": 1024} + 1024 bytes

Request 3:  {"path": "/file.bin", "off": 2048}
Response 3: {"ok": true, "eof": true, "bin": 512} + 512 bytes

Total downloaded: 2560 bytes
```

**Response (error):**
```json
{"ok": false, "err": "file not found"}
```

**Error cases:**
- File doesn't exist: `{"ok": false, "err": "file not found"}`
- Read permission denied: `{"ok": false, "err": "read failed"}`
- Invalid offset (beyond EOF): Server may return `{"ok": true, "eof": true, "bin": 0}`

#### 0x22 - PUT (Write File)

Writes a chunk of data to a file. Used iteratively to upload entire files.

**Chunking Strategy:**
- Client reads file in chunks and sends each chunk with offset
- Server writes data at specified offset
- Client increments offset by sent byte count
- Process repeats until all data is sent
- Final request with empty data signals completion

**Request:**
```json
{"path": "/file/path", "off": 0}
```
+ **Binary data**: File content chunk (variable length)

- `path`: Destination file path (created if doesn't exist)
- `off`: Byte offset to write at (0-based)
- Binary data length is implicit: `body_length - 3 - json_length`

**Response (success):**
```json
{"ok": true}
```

**Upload Algorithm (Client Implementation):**
```ruby
def upload(local_path, remote_path, chunk_size: 1024)
  File.open(local_path, "rb") do |file|
    offset = 0
    loop do
      # Read chunk from local file
      chunk = file.read(chunk_size) || ""

      # Send chunk (including final empty chunk)
      response = PUT(remote_path, offset, chunk)

      raise "Upload failed" unless response.ok

      # Update offset
      offset += chunk.bytesize

      # Exit after sending empty chunk (EOF marker)
      break if chunk.empty?
    end
  end
end
```

**Chunking Characteristics:**
1. **Client-driven**: Client controls chunk size
2. **Offset-based**: Each request specifies exact write position
3. **Stateless**: Server doesn't maintain upload session state
4. **Resumable**: Can resume upload from any offset
5. **Variable size**: Client can vary chunk size per request
6. **Termination signal**: Empty binary data indicates upload complete

**Example Upload Session:**
```
Request 1:  {"path": "/file.bin", "off": 0} + [1024 bytes]
Response 1: {"ok": true}

Request 2:  {"path": "/file.bin", "off": 1024} + [1024 bytes]
Response 2: {"ok": true}

Request 3:  {"path": "/file.bin", "off": 2048} + [512 bytes]
Response 3: {"ok": true}

Request 4:  {"path": "/file.bin", "off": 2560} + [0 bytes]  ← Completion signal
Response 4: {"ok": true}

Total uploaded: 2560 bytes
```

**Important Implementation Notes:**

1. **Final empty chunk**: Always send a PUT with empty binary data to signal completion
   - This allows server to finalize/close the file
   - Without this, server may not know transfer is complete

2. **File creation**: Server should create file if it doesn't exist
   - File is typically created on first PUT (offset 0)

3. **Offset handling**:
   - Offsets must be sequential for correct file assembly
   - Non-sequential writes depend on server implementation
   - Gaps in offsets may result in undefined behavior

4. **Overwrite behavior**:
   - Writing at offset 0 may truncate existing file (server-dependent)
   - For append operation, client must first GET file size

**Response (error):**
```json
{"ok": false, "err": "write failed"}
```

**Error cases:**
- Write permission denied: `{"ok": false, "err": "write failed"}`
- Disk full: `{"ok": false, "err": "write failed"}`
- Invalid path: `{"ok": false, "err": "write failed"}`
- File system error: `{"ok": false, "err": "write failed"}`

#### 0x31 - REBOOT (Reboot Device)

Reboots the remote device.

**Request:**
```json
{}
```

**Response (success):**
```json
{"ok": true}
```

**Note:** Device will reboot immediately. Connection will be lost.

## Chunked File Transfer

This protocol uses a stateless, offset-based chunking mechanism for reliable file transfers over UART.

### Design Principles

1. **Stateless**: Server doesn't maintain session state between requests
   - Each request is independent
   - No server-side file handles persist between chunks
   - Enables simple server implementation on embedded systems

2. **Offset-based**: Client specifies exact byte position for each operation
   - Enables resumable transfers after interruption
   - Supports random access to file content
   - Client maintains transfer state, not server

3. **Client-driven**: Client controls transfer flow
   - Client decides chunk size based on available memory
   - Client manages retry logic and error recovery
   - Server responds to each request independently

4. **Variable chunk size**: No fixed chunk size requirement
   - Client can adapt chunk size based on:
     - Available memory
     - Link quality (smaller chunks for unreliable connections)
     - Performance requirements
   - Default: 1024 bytes (good balance for most use cases)

### Download (GET) Flow

```
┌────────┐                                    ┌────────┐
│ Client │                                    │ Server │
└───┬────┘                                    └───┬────┘
    │                                             │
    │ GET(path="/file.bin", off=0)                │
    ├────────────────────────────────────────────>│
    │                                             │ Open file, seek to offset 0
    │                                             │ Read up to buffer_size bytes
    │                                             │
    │ {"ok":true,"eof":false,"bin":1024} + data   │
    │<────────────────────────────────────────────┤
    │                                             │
    │ Write 1024 bytes to local file              │
    │ offset += 1024                              │
    │                                             │
    │ GET(path="/file.bin", off=1024)             │
    ├────────────────────────────────────────────>│
    │                                             │ Open file, seek to offset 1024
    │                                             │ Read up to buffer_size bytes
    │                                             │
    │ {"ok":true,"eof":false,"bin":1024} + data   │
    │<────────────────────────────────────────────┤
    │                                             │
    │ Write 1024 bytes to local file              │
    │ offset += 1024                              │
    │                                             │
    │ GET(path="/file.bin", off=2048)             │
    ├────────────────────────────────────────────>│
    │                                             │ Open file, seek to offset 2048
    │                                             │ Read 512 bytes (EOF reached)
    │                                             │
    │ {"ok":true,"eof":true,"bin":512} + data     │
    │<────────────────────────────────────────────┤
    │                                             │
    │ Write 512 bytes to local file               │
    │ eof=true → transfer complete                │
    │                                             │
```

### Upload (PUT) Flow

```
┌────────┐                                    ┌────────┐
│ Client │                                    │ Server │
└───┬────┘                                    └───┬────┘
    │                                             │
    │ Read 1024 bytes from local file             │
    │ PUT(path="/file.bin", off=0) + 1024 bytes   │
    ├────────────────────────────────────────────>│
    │                                             │ Open/create file, seek to 0
    │                                             │ Write 1024 bytes
    │                                             │ Close file
    │ {"ok":true}                                 │
    │<────────────────────────────────────────────┤
    │                                             │
    │ offset += 1024                              │
    │ Read 1024 bytes from local file             │
    │ PUT(path="/file.bin", off=1024) + 1024 bytes│
    ├────────────────────────────────────────────>│
    │                                             │ Open file, seek to 1024
    │                                             │ Write 1024 bytes
    │                                             │ Close file
    │ {"ok":true}                                 │
    │<────────────────────────────────────────────┤
    │                                             │
    │ offset += 1024                              │
    │ Read 512 bytes (EOF)                        │
    │ PUT(path="/file.bin", off=2048) + 512 bytes │
    ├────────────────────────────────────────────>│
    │                                             │ Open file, seek to 2048
    │                                             │ Write 512 bytes
    │                                             │ Close file
    │ {"ok":true}                                 │
    │<────────────────────────────────────────────┤
    │                                             │
    │ offset += 512                               │
    │ Read 0 bytes (send completion signal)       │
    │ PUT(path="/file.bin", off=2560) + 0 bytes   │
    ├────────────────────────────────────────────>│
    │                                             │ Recognize completion
    │                                             │ Finalize file
    │ {"ok":true}                                 │
    │<────────────────────────────────────────────┤
    │                                             │
    │ Transfer complete                           │
    │                                             │
```

### Resume After Interruption

**Download Resume Example:**
```
# Transfer interrupted at offset 2048 (2048 bytes already downloaded)

# Client resumes by requesting from last known offset
GET(path="/file.bin", off=2048)

# Server responds with remaining data
Response: {"ok":true,"eof":true,"bin":512} + 512 bytes

# Total file size: 2560 bytes
# Already had: 2048 bytes
# Downloaded now: 512 bytes
```

**Upload Resume Example:**
```
# Transfer interrupted at offset 2048 (2048 bytes already uploaded)

# Client resumes by sending from last known offset
PUT(path="/file.bin", off=2048) + [remaining 512 bytes]
Response: {"ok":true}

PUT(path="/file.bin", off=2560) + [0 bytes]  # Completion signal
Response: {"ok":true}
```

### Chunk Size Recommendations

| Use Case | Chunk Size | Rationale |
|----------|------------|-----------|
| Default | 1024 bytes | Good balance of memory and performance |
| Embedded (low RAM) | 256-512 bytes | Minimizes server buffer requirements |
| High-speed | 2048-4096 bytes | Reduces protocol overhead |
| Unreliable link | 256-512 bytes | Smaller chunks = less retransmission on error |
| SD card | 512/2048 bytes | Match SD card sector sizes |

**Factors to consider:**
- **Server RAM**: Server must buffer entire chunk + protocol overhead
- **UART buffer**: USB-serial adapters typically have 4KB buffers
- **Protocol overhead**: COBS adds ~0.4%, JSON adds ~50 bytes, CRC adds 4 bytes
- **Latency**: Smaller chunks = more round-trips = slower transfer
- **Error rate**: Smaller chunks = less data lost on CRC error

### Error Recovery

**CRC Error During Download:**
```ruby
max_retries = 3
retries = 0

loop do
  begin
    response = GET(path, offset)
    # Success - move to next chunk
    offset += response.bin
    break if response.eof
    retries = 0  # Reset retry counter on success
  rescue CRCError => e
    retries += 1
    if retries > max_retries
      raise "Transfer failed: too many CRC errors"
    end
    # Retry same offset
  end
end
```

**Timeout During Upload:**
```ruby
timeout_retries = 0
max_timeout_retries = 3

loop do
  begin
    response = PUT(path, offset, chunk)
    offset += chunk.bytesize
    break if chunk.empty?
    timeout_retries = 0
  rescue TimeoutError => e
    timeout_retries += 1
    if timeout_retries > max_timeout_retries
      raise "Transfer failed: server not responding"
    end
    # Retry same chunk with same offset
  end
end
```

## Synchronization

Before communication, the client must synchronize with the server to ensure both sides are ready.

### Beacon Protocol

The server (ESP32) periodically transmits a beacon:

```
"UFTE" (4 ASCII bytes: 0x55 0x46 0x54 0x45)
```

This beacon is sent outside the normal framing protocol (not COBS-encoded, no CRC).

### Client Synchronization Procedure

```
1. Clear receive buffer (discard any stale data)

2. Listen for beacon with timeout (default: 6 seconds)

3. Scan incoming bytes for "UFTE" sequence

4. If beacon detected:
   - Clear receive buffer again
   - Synchronization complete

5. If timeout:
   - Retry (default: 3 attempts)
   - If all retries fail: error "Failed to detect server beacon"
```

**Implementation notes:**
- Beacon allows client to verify server is running before sending commands
- Client should NOT send SYNC command (0x01) - just wait for beacon
- Keeps last 50 bytes in scan buffer to detect beacon across chunk boundaries
- After sync, communication uses normal framed protocol

## Timing Considerations

### Transmission Delays

USB-serial adapters and embedded UARTs have buffering that requires careful timing:

**After writing frame:**
```
1. Flush write buffer: flush()

2. Calculate transmission time:
   tx_time_ms = (frame_bytes × 10 bits/byte ÷ baud_rate) × 2.0 safety_margin

   Example at 115200 baud:
   - 100 bytes → ~17ms
   - 1024 bytes → ~178ms

3. Wait for transmission to complete:
   sleep(tx_time_ms)
```

**Why this matters:**
- Data may be buffered in OS or USB-serial adapter
- `flush()` alone doesn't guarantee bits are on the wire
- Reading response too early can cause synchronization errors
- 2x safety margin accounts for flow control and hardware buffering

### Response Timeouts

Default timeout: 5000ms (5 seconds)

Adjust based on:
- Command type (file operations may be slower)
- Remote storage speed (SD card vs flash)
- File size (large transfers take longer)

## Error Handling

### Frame-Level Errors

| Error | Cause | Recovery |
|-------|-------|----------|
| Timeout waiting frame | No response within timeout period | Retry command or check connection |
| COBS decode error | Corrupted frame or invalid COBS data | Discard frame, wait for next delimiter |
| Short frame | Frame smaller than minimum (5 bytes) | Discard frame, protocol violation |
| CRC error | Data corruption during transmission | Discard frame, retry command |
| Connection closed (EOF) | Serial port closed or device disconnected | Reconnect and re-synchronize |

### Command-Level Errors

All command errors return:
```json
{"ok": false, "err": "error description"}
```

Common error messages:
- `"bad_json"`: JSON parsing failed
- `"file not found"`: File doesn't exist
- `"directory not found"`: Directory doesn't exist
- `"write failed"`: File write error (disk full, permission, etc.)
- `"read failed"`: File read error

### TTY Configuration Issues

**Symptom:** Random communication failures, corrupted data, stuck transfers

**Cause:** Serial port not in raw binary mode

**Solution:** Configure port with `stty` before opening:
```bash
# Linux
stty -F /dev/ttyUSB0 115200 raw -echo -echoe -echok -echoctl -echoke \
     -onlcr -opost -isig -icanon -iexten

# macOS
stty -f /dev/tty.usbserial 115200 raw -echo
```

This disables:
- Echo (`-echo`)
- Line editing (`-icanon`)
- Signal generation (`-isig`)
- Output post-processing (`-opost`, `-onlcr`)
- All special character processing

## Implementation Notes

### Client Implementation Checklist

- [ ] Configure TTY in raw binary mode before opening port
- [ ] Use binary mode for file operations (`"rb"`, `"wb"`)
- [ ] Force ASCII-8BIT encoding for all binary data in Ruby
- [ ] Implement COBS encode/decode correctly
- [ ] Use big-endian byte order for length and CRC fields
- [ ] Calculate transmission delays and wait appropriately
- [ ] Implement proper timeout handling
- [ ] Clear receive buffer before expecting response
- [ ] Handle partial frames (accumulate until delimiter)
- [ ] Verify CRC before processing response

### Server Implementation Checklist

- [ ] Transmit beacon periodically (every 1-2 seconds)
- [ ] Implement COBS encode/decode
- [ ] Verify CRC on received frames
- [ ] Handle chunked file transfers (GET/PUT)
- [ ] Validate JSON parsing
- [ ] Return proper error responses
- [ ] Implement all command codes
- [ ] Use binary-safe file I/O

## Example Session

### Download File

```
Client → Server:
  [COBS(0x21 + 0x001F + '{"path":"/data.bin","off":0}' + CRC)] + 0x00

Server → Client:
  [COBS(0x00 + 0x0020 + '{"ok":true,"eof":false,"bin":1024}' + [1024 bytes] + CRC)] + 0x00

Client → Server:
  [COBS(0x21 + 0x0022 + '{"path":"/data.bin","off":1024}' + CRC)] + 0x00

Server → Client:
  [COBS(0x00 + 0x001D + '{"ok":true,"eof":true,"bin":512}' + [512 bytes] + CRC)] + 0x00

Result: 1536 bytes downloaded
```

### List Directory

```
Client → Server:
  [COBS(0x12 + 0x000D + '{"path":"/"}' + CRC)] + 0x00

Server → Client:
  [COBS(0x00 + 0x0045 + '{"ok":true,"entries":[{"n":"config.txt","t":"f","s":256},{"n":"logs","t":"d","s":0}]}' + CRC)] + 0x00
```

### Upload File

```
Client → Server:
  [COBS(0x22 + 0x001F + '{"path":"/new.txt","off":0}' + [512 bytes] + CRC)] + 0x00

Server → Client:
  [COBS(0x00 + 0x000C + '{"ok":true}' + CRC)] + 0x00

Client → Server:
  [COBS(0x22 + 0x0021 + '{"path":"/new.txt","off":512}' + [0 bytes] + CRC)] + 0x00

Server → Client:
  [COBS(0x00 + 0x000C + '{"ok":true}' + CRC)] + 0x00

Result: 512 bytes uploaded
```

## References

- COBS Algorithm: [Wikipedia - COBS](https://en.wikipedia.org/wiki/Consistent_Overhead_Byte_Stuffing)
- CRC-32: IEEE 802.3 polynomial (0x04C11DB7)
- JSON: RFC 8259
- UART: Universal Asynchronous Receiver/Transmitter

