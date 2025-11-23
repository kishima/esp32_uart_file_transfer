#pragma once

#include "esp_err.h"

#ifdef __cplusplus
extern "C" {
#endif

/**
 * @brief Create and start the file system proxy task
 *
 * This function initializes the UART interface and creates a FreeRTOS task
 * that handles file system operations via UART protocol.
 *
 * @return ESP_OK on success, or an error code on failure
 */
esp_err_t fs_proxy_create_task(void);

#ifdef __cplusplus
}
#endif
