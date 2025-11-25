# UART File Transfer for ESP32

A component for transferring files between ESP32 devices (M5StickC Plus2) and PC via UART.

## Overview

- **Protocol**: COBS (Consistent Overhead Byte Stuffing) encoding + CRC32 checksum
- **File System**: FatFs (Flash Drive 1: Partition 0x210000)
- **Baud Rate**: 115200 baud
- **Chunk Size**: 1024 bytes (fixed, ESP32 firmware limit)
- **UART**: UART0 (GPIO1=TX, GPIO3=RX)

## Features

- Directory operations (cd, ls)
- File operations (get, put, rm)
- Device control (reboot)
- Synchronization (sync)

## ESP32 Configuration

### Integration into Project

1. Place this component in `components/esp32_uart_file_transfer/`

2. Add dependency to `main/CMakeLists.txt`:
```cmake
idf_component_register(
  SRCS "main.c"
  REQUIRES esp32_uart_file_transfer
)
```

3. Start fs_proxy task in `main.c`:
```c
#include "uart_file_transfer.h"

void app_main(void) {
    fs_proxy_create_task();
}
```

### Optional: GPIO37 Button Boot Mode Switch

Press M5StickC Plus2's ButtonA during boot to enter UART file transfer mode:

```c
#include "uart_file_transfer.h"
#include "driver/gpio.h"

#define BUTTON_GPIO 37

void app_main(void) {
    gpio_config_t io_conf = {
        .pin_bit_mask = (1ULL << BUTTON_GPIO),
        .mode = GPIO_MODE_INPUT,
        .pull_up_en = GPIO_PULLUP_DISABLE,  // GPIO37 is input-only, requires external pullup
        .pull_down_en = GPIO_PULLDOWN_DISABLE,
    };
    gpio_config(&io_conf);
    vTaskDelay(pdMS_TO_TICKS(100));

    if (gpio_get_level(BUTTON_GPIO) == 0) {  // Button pressed (Active Low)
        fs_proxy_create_task();
        while(1) vTaskDelay(pdMS_TO_TICKS(100));  // Wait in UART mode
    }

    // Normal boot process
}
```

### Log Level Configuration

Control logging in `fs_proxy.c` via `FS_PROXY_LOG_LEVEL`:
```c
#define FS_PROXY_LOG_LEVEL ESP_LOG_INFO  // NONE, ERROR, WARN, INFO, DEBUG, VERBOSE
```

## PC Client

### Requirements

- Ruby 3.0 or later
- Serial port access permissions

### Installation

No special installation required. Just run with Ruby.

### Usage

#### Interactive Shell

```bash
ruby components/esp32_uart_file_transfer/client/transfer_client.rb --port /dev/ttyACM0 shell
```

Shell commands:
```
ls [path]              # List directory
cd <path>              # Change directory
pwd                    # Print working directory
get <remote> [local]   # Download file
put <local> <remote>   # Upload file
rm <path>              # Remove file/directory
reboot                 # Reboot ESP32
exit                   # Exit shell
```

Example:
```bash
> ls /
> cd /data
> put local_file.txt /data/remote_file.txt
> get /data/remote_file.txt downloaded.txt
> reboot
```

#### Command Line (One-shot)

```bash
# Upload file
ruby components/esp32_uart_file_transfer/client/transfer_client.rb --port /dev/ttyACM0 transfer up local.txt /remote.txt

# Download file
ruby components/esp32_uart_file_transfer/client/transfer_client.rb --port /dev/ttyACM0 transfer down /remote.txt local.txt

# List directory
ruby components/esp32_uart_file_transfer/client/transfer_client.rb --port /dev/ttyACM0 remote ls /

# Reboot
ruby components/esp32_uart_file_transfer/client/transfer_client.rb --port /dev/ttyACM0 remote reboot
```

### Debug Mode

Set `DEBUG_MODE` to `true` in `transfer_client.rb` for detailed logging:
```ruby
DEBUG_MODE = true  # Enable debug logs
```

## Testing

See [test/README.md](test/README.md) for detailed test documentation.

## Troubleshooting

### Connection Issues

1. Check serial port permissions:
```bash
sudo chmod 666 /dev/ttyACM0
# or
sudo usermod -a -G dialout $USER  # Requires re-login
```

2. Verify port name:
```bash
ls /dev/tty*
```

### Transfer Failures

- **CRC Error**: Check cable quality, try lower baud rate

## TODO

Implement retry mechanism: None (currently, if it fails immediately on communication error)


## References

- [COBS (Consistent Overhead Byte Stuffing)](https://en.wikipedia.org/wiki/Consistent_Overhead_Byte_Stuffing)
- [FatFs - Generic FAT Filesystem Module](http://elm-chan.org/fsw/ff/)
- [ESP-IDF UART Driver](https://docs.espressif.com/projects/esp-idf/en/latest/esp32/api-reference/peripherals/uart.html)
