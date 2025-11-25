# Protocol Specification

## Frame Structure

```
[COBS encoded data] + 0x00 delimiter
```

COBS decoded data:
```
[cmd:1][len_hi:1][len_lo:1][JSON params][binary data][CRC32:4]
```

- `cmd`: Command code (0x01, 0x11, 0x12, 0x13, 0x21, 0x22, 0x31)
- `len`: JSON section length (big-endian, 16bit)
- `JSON params`: Command parameters (JSON format)
- `binary data`: Binary data (PUT command only)
- `CRC32`: Checksum (big-endian, covers all data)

## Command Codes

| Code | Command | Description |
|------|---------|-------------|
| 0x01 | SYNC    | Synchronization/connection check |
| 0x11 | CD      | Change directory |
| 0x12 | LS      | List directory |
| 0x13 | RM      | Remove file |
| 0x21 | GET     | Read file |
| 0x22 | PUT     | Write file |
| 0x31 | REBOOT  | Reboot device |
| 0x00 | RESP    | Response |

## Response Format

Success:
```json
{"ok": true}
```

Error:
```json
{"ok": false, "err": "error message"}
```

LS response:
```json
{"ok": true, "entries": [{"n": "name", "t": "f", "s": 1234}, ...]}
```
- `n`: File/directory name
- `t`: Type (`"f"` = file, `"d"` = directory)
- `s`: Size (bytes)

GET response:
```json
{"ok": true, "eof": false, "bin": 1024}
```
+ Binary data (1024 bytes)

