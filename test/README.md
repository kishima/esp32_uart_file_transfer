# UART File Transfer Test Suite

This directory contains the test suite for ESP32 UART file transfer protocol, including both unit tests and end-to-end (E2E) tests.

## Setup

### 1. Install Dependencies

```bash
cd components/esp32_uart_file_transfer
bundle install
```

### 2. Prepare ESP32 Device

- Flash firmware to ESP32 device
- Connect device via USB
- Identify serial port path (e.g., `/dev/ttyUSB0`, `/dev/ttyACM0`)

### 3. Serial Port Permissions (Linux)

```bash
sudo usermod -a -G dialout $USER
# Logout/login required
```

Or temporarily:

```bash
sudo chmod 666 /dev/ttyUSB0
```

## Running Tests

### Run All Tests (Unit + E2E)

```bash
TEST_SERIAL_PORT=/dev/ttyUSB0 rake test
```

### Run Unit Tests Only (No Hardware Required)

```bash
rake test:unit
```

### Run E2E Tests Only

```bash
TEST_SERIAL_PORT=/dev/ttyUSB0 rake test:e2e
```

### Run Individual Test Suites

```bash
# File transfer tests only
TEST_SERIAL_PORT=/dev/ttyUSB0 rake test:file_transfer

# Remote command tests only
TEST_SERIAL_PORT=/dev/ttyUSB0 rake test:remote_commands

# Error handling tests only
TEST_SERIAL_PORT=/dev/ttyUSB0 rake test:error_handling

# Protocol error unit tests
rake test:protocol_errors

# Timeout unit tests
rake test:timeout
```

### Display Test Information

```bash
rake info
```

## Test Coverage

### Unit Tests (test/unit/)

Mock-based tests that run without hardware:

#### test/unit/test_protocol_errors.rb

Protocol error handling tests:

- **CRC Errors**: CRC mismatch detection
- **COBS Errors**: Invalid COBS data, decode errors
- **Invalid JSON**: Malformed JSON in responses
- **Short Frames**: Frames that are too short
- **COBS Edge Cases**: Empty data, all zeros, no zeros, max run length

#### test/unit/test_timeout.rb

Timeout behavior tests:

- **Fast Operations**: Operations that complete within timeout
- **Slow Operations**: Operations that exceed timeout
- **Timeout Configuration**: Custom timeout values

### E2E Tests (test/e2e/)

Hardware-based tests that require ESP32 device:

#### test/e2e/test_file_transfer.rb

File transfer functionality tests:

- **Upload**: Small/100KB files with 1024-byte chunks
- **Download**: Small/large files, nonexistent file handling
- **Round-trip**: Upload→Download verification with checksum
- **Overwrite**: Overwriting existing files
- **transfer() Wrapper**: up/down direction transfers

#### test/e2e/test_remote_commands.rb

Remote command tests:

- **cd**: Directory navigation (/home, /, invalid paths)
- **ls**: Directory listing (/, /home, current dir, invalid paths)
- **rm**: File deletion (single/multiple, nonexistent files)
- **Host Commands**: h_cd, h_ls
- **Workflows**: Integrated cd→ls→upload→ls→rm sequences

#### test/e2e/test_error_handling.rb

Error handling and recovery tests:

- **COBS Protocol**: COBS decode error handling
- **File Operations**: Invalid paths, nonexistent files
- **Local File Errors**: Nonexistent local files, invalid paths
- **Connection Errors**: Operations after close, reconnection
- **Data Integrity**: Special bytes (0x00, 0xFF, etc.), large file integrity
- **Stress Tests**: Rapid sequential operations, multiple large file transfers

## Test Fixtures

### test/fixtures/test_files/

- `small_text.txt`: Small text file (few hundred bytes)
- `large_binary.bin`: 100KB binary file

Temporary files are created in `test/tmp/` during test execution and automatically cleaned up after tests complete.

## Troubleshooting

### "TEST_SERIAL_PORT not set" Error

Set the `TEST_SERIAL_PORT` environment variable:

```bash
export TEST_SERIAL_PORT=/dev/ttyUSB0
rake test
```

### Serial Port Access Error

- Verify port exists: `ls -l /dev/ttyUSB*`
- Check permissions: `groups` (verify dialout group membership)
- Check device connection: `dmesg | tail`

### Sync Error ("Failed to detect server beacon")

- Verify ESP32 is powered on and running
- Verify firmware is correctly flashed
- Close any serial monitors or other programs using the port
- Verify baud rate matches (default: 115200)

### Tests Hang

- Adjust timeout: `create_client(timeout: 20.0)`
- Enable debug mode: Set `DEBUG_MODE = true` in `transfer_client.rb`
- Reset ESP32 and re-run tests
- Tests have automatic 30-second timeout per test

### CRC Mismatch Errors

- Verify chunk size is set to 1024 bytes (ESP32 firmware limit)
- Check serial cable quality
- Try lower baud rate if issues persist

## Test Architecture

### Test Helper (`test/test_helper.rb`)

The `TestHelper` module provides:

- `create_client(timeout:)`: Create test client instance
- `wait_and_sync(client)`: Synchronize with device
- `file_checksum(path)`: Calculate SHA256 checksum
- `fixture_path(filename)`: Get fixture file path
- `temp_path(filename)`: Get temporary file path
- `assert_files_equal(path1, path2)`: Compare file contents
- `assert_remote_file_exists(client, path)`: Verify remote file exists
- `refute_remote_file_exists(client, path)`: Verify remote file doesn't exist
- `setup_remote_test_dir(client)`: Setup remote test environment
- `cleanup_remote_test_dir(client)`: Cleanup remote test files

### Unit Test Helper (`test/unit_helper.rb`)

The `UnitTestHelper` module provides:

- `MockSerialPort`: Mock serial port for testing without hardware
- `build_frame(code, obj)`: Build protocol frames for testing
- `build_bad_crc_frame(code, obj)`: Build frames with intentional CRC errors
- `build_invalid_json_frame(code)`: Build frames with invalid JSON
- `build_short_frame()`: Build frames that are too short

### Coding Conventions

- Use Minitest standard assertions
- Test method naming: `test_<action>_<condition>`
- Each test should be independently executable
- Keep state clean with setup/teardown
- Use descriptive assertions with custom messages

### Adding New Tests

1. Add to appropriate test file (or create new one)
2. Use `TestHelper` or `UnitTestHelper` methods
3. For E2E tests: Create client in `setup`, cleanup in `teardown`
4. For unit tests: Use mocks, no hardware required
5. Write clear, descriptive assertions

## Test Statistics

- **Total Tests**: 53 (12 unit + 41 E2E)
- **Unit Tests**: Run in <1 second
- **E2E Tests**: Run in ~5 minutes (depending on hardware)
- **Test Timeout**: 30 seconds per test
- **Chunk Size**: Fixed at 1024 bytes (ESP32 firmware limit)

## License

This test suite follows the same license as the parent project.
