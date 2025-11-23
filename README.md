# UART File Transfer for ESP32

ESP32デバイス（M5StickC Plus2）とPC間でUART経由でファイル転送を行うコンポーネントです。

## 概要

- **プロトコル**: COBS (Consistent Overhead Byte Stuffing) エンコーディング + CRC32チェックサム
- **ファイルシステム**: FatFs (Flash上のDrive 1: パーティション 0x210000)
- **通信速度**: 115200 baud
- **チャンクサイズ**: 1KB
- **UART**: UART0 (GPIO1=TX, GPIO3=RX)

## 機能

- ディレクトリ操作 (cd, ls)
- ファイル操作 (get, put, rm)
- デバイス制御 (reboot)
- 同期コマンド (sync)

## ESP32側の設定

### プロジェクトへの組み込み

1. このコンポーネントを `components/uart-file-transfer/` に配置

2. main/CMakeLists.txt に依存関係を追加:
```cmake
idf_component_register(
  SRCS "main.c"
  REQUIRES uart-file-transfer
)
```

3. main.c でfs_proxyタスクを起動:
```c
#include "uart_file_transfer.h"

void app_main(void) {
    fs_proxy_create_task();
}
```

### GPIO37ボタンによる起動モード切り替え（オプション）

M5StickC Plus2のButtonAを押しながら起動すると、UARTファイル転送モードになります：

```c
#include "uart_file_transfer.h"
#include "driver/gpio.h"

#define BUTTON_GPIO 37

void app_main(void) {
    gpio_config_t io_conf = {
        .pin_bit_mask = (1ULL << BUTTON_GPIO),
        .mode = GPIO_MODE_INPUT,
        .pull_up_en = GPIO_PULLUP_DISABLE,  // GPIO37は入力専用、外部プルアップが必要
        .pull_down_en = GPIO_PULLDOWN_DISABLE,
    };
    gpio_config(&io_conf);
    vTaskDelay(pdMS_TO_TICKS(100));

    if (gpio_get_level(BUTTON_GPIO) == 0) {  // ボタン押下時（Active Low）
        fs_proxy_create_task();
        while(1) vTaskDelay(pdMS_TO_TICKS(100));  // UARTモードで待機
    }

    // 通常起動処理
}
```

### ログレベル設定

fs_proxy.c の `FS_PROXY_LOG_LEVEL` で制御:
```c
#define FS_PROXY_LOG_LEVEL ESP_LOG_INFO  // NONE, ERROR, WARN, INFO, DEBUG, VERBOSE
```

## PC側クライアント

### 必要なもの

- Ruby 3.0以上
- シリアルポートアクセス権限

### インストール

特別なインストールは不要。Rubyが実行できればそのまま使えます。

### 使い方

#### インタラクティブシェル

```bash
ruby components/uart-file-transfer/client/transfer_client.rb --port /dev/ttyACM0 shell
```

シェルコマンド:
```
ls [path]          # ディレクトリ一覧表示
cd <path>          # ディレクトリ移動
pwd                # カレントディレクトリ表示
get <remote> [local]   # ファイルダウンロード
put <local> <remote>   # ファイルアップロード
rm <path>          # ファイル/ディレクトリ削除
reboot             # ESP32再起動
exit               # シェル終了
```

例:
```bash
> ls /
> cd /data
> put local_file.txt /data/remote_file.txt
> get /data/remote_file.txt downloaded.txt
> reboot
```

#### コマンドライン（ワンショット）

```bash
# ファイルアップロード
ruby components/uart-file-transfer/client/transfer_client.rb --port /dev/ttyACM0 put local.txt /remote.txt

# ファイルダウンロード
ruby components/uart-file-transfer/client/transfer_client.rb --port /dev/ttyACM0 get /remote.txt local.txt

# ディレクトリ一覧
ruby components/uart-file-transfer/client/transfer_client.rb --port /dev/ttyACM0 ls /

# 再起動
ruby components/uart-file-transfer/client/transfer_client.rb --port /dev/ttyACM0 reboot
```

### デバッグモード

transfer_client.rb の `DEBUG_MODE` を `true` に設定すると詳細ログが出力されます:
```ruby
DEBUG_MODE = true  # デバッグログ有効
```

## プロトコル仕様

### フレーム構造

```
[COBS encoded data] + 0x00 delimiter
```

COBS decoded data:
```
[cmd:1][len_hi:1][len_lo:1][JSON params][binary data][CRC32:4]
```

- `cmd`: コマンドコード (0x01, 0x11, 0x12, 0x13, 0x21, 0x22, 0x31)
- `len`: JSON部分の長さ（big-endian, 16bit）
- `JSON params`: コマンドパラメータ（JSON形式）
- `binary data`: バイナリデータ（PUTコマンド時のみ）
- `CRC32`: チェックサム（big-endian, 全データ対象）

### コマンドコード

| コード | コマンド | 説明 |
|--------|----------|------|
| 0x01   | SYNC     | 同期・接続確認 |
| 0x11   | CD       | ディレクトリ移動 |
| 0x12   | LS       | ディレクトリ一覧 |
| 0x13   | RM       | ファイル削除 |
| 0x21   | GET      | ファイル読み込み |
| 0x22   | PUT      | ファイル書き込み |
| 0x31   | REBOOT   | 再起動 |
| 0x00   | RESP     | レスポンス |

### レスポンスフォーマット

成功:
```json
{"ok": true}
```

エラー:
```json
{"ok": false, "err": "error message"}
```

LS応答:
```json
{"ok": true, "entries": [{"n": "name", "t": "f", "s": 1234}, ...]}
```
- `n`: ファイル/ディレクトリ名
- `t`: タイプ (`"f"` = ファイル, `"d"` = ディレクトリ)
- `s`: サイズ（バイト）

GET応答:
```json
{"ok": true, "eof": false, "bin": 1024}
```
+ バイナリデータ（1024バイト）

## トラブルシューティング

### 接続できない

1. シリアルポートのパーミッション確認:
```bash
sudo chmod 666 /dev/ttyACM0
# または
sudo usermod -a -G dialout $USER  # 再ログイン必要
```

2. ポート名の確認:
```bash
ls /dev/tty*
```

3. ESP32が起動メッセージ `UFTE_READY` を出力しているか確認

### 転送が失敗する

- CRCエラー: ケーブル品質を確認、ボーレートを下げる
- タイムアウト: チャンクサイズを小さくする（現在1KB）
- メモリ不足: ESP32側のログレベルを下げる

### ファイルが見つからない

- FatFsパスは `1:/` で始まります（Drive 1）
- 絶対パス指定を推奨: `/data/file.txt`
- ディレクトリが存在するか `ls` で確認

## 技術仕様

### メモリ使用量

- タスクスタックサイズ: 8KB
- UARTバッファ: 2KB (RX) + 2KB (TX)
- フレームバッファ: 2KB (最大)
- 動的確保: 各コマンド実行時に必要量を確保し、完了後に解放

### 制限事項

- 最大ファイルサイズ: FatFsの制限に準拠（4GB）
- 最大パス長: 256バイト
- 最大JSONパラメータ長: 512バイト
- 同時接続数: 1（UART0のみ使用）
- リトライ機能: なし（通信エラー時は即失敗）

## ライセンス

このコンポーネントは R2P2-ESP32 プロジェクトの一部です。

## 参考

- [COBS (Consistent Overhead Byte Stuffing)](https://en.wikipedia.org/wiki/Consistent_Overhead_Byte_Stuffing)
- [FatFs - Generic FAT Filesystem Module](http://elm-chan.org/fsw/ff/)
- [ESP-IDF UART Driver](https://docs.espressif.com/projects/esp-idf/en/latest/esp32/api-reference/peripherals/uart.html)
