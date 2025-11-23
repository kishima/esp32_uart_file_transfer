idf_component_register(
    SRCS "src/fs_proxy.c"
    INCLUDE_DIRS "include"
    PRIV_REQUIRES
        esp_driver_uart
        picoruby-esp32
        spi_flash
        esp_timer
)
