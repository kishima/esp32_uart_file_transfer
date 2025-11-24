# UART File Transfer E2E Tests

このディレクトリには、ESP32 UARTファイル転送プロトコルの実機E2Eテストが含まれています。

## セットアップ

### 1. 依存関係のインストール

```bash
cd components/esp32_uart_file_transfer
bundle install
```

### 2. ESP32デバイスの準備

- ESP32デバイスにファームウェアをフラッシュ
- デバイスをUSB経由で接続
- シリアルポートのパスを確認（例: `/dev/ttyUSB0`, `/dev/ttyACM0`）

### 3. シリアルポートの権限設定（Linux）

```bash
sudo usermod -a -G dialout $USER
# ログアウト/ログインが必要
```

または一時的に：

```bash
sudo chmod 666 /dev/ttyUSB0
```

## テストの実行

### 全テスト実行

```bash
TEST_SERIAL_PORT=/dev/ttyUSB0 rake test
```

### 個別テスト実行

```bash
# ファイル転送テストのみ
TEST_SERIAL_PORT=/dev/ttyUSB0 rake test:file_transfer

# リモートコマンドテストのみ
TEST_SERIAL_PORT=/dev/ttyUSB0 rake test:remote_commands

# エラーハンドリングテストのみ
TEST_SERIAL_PORT=/dev/ttyUSB0 rake test:error_handling
```

### テスト情報の表示

```bash
rake info
```

## テストカバレッジ

### test/e2e/test_file_transfer.rb

ファイル転送機能のテスト：

- **アップロード**: 小サイズ/500KBファイル、カスタムチャンクサイズ
- **ダウンロード**: 小/大ファイル、存在しないファイル
- **ラウンドトリップ**: アップロード→ダウンロード検証
- **上書き**: 既存ファイルの上書き
- **transfer()ラッパー**: up/down方向の転送

### test/e2e/test_remote_commands.rb

リモートコマンドのテスト：

- **cd**: ディレクトリ移動（/flash, /, 無効なパス）
- **ls**: ディレクトリ一覧（/, /flash, カレント, 無効なパス）
- **rm**: ファイル削除（単一/複数、存在しないファイル）
- **ホストコマンド**: h_cd, h_ls
- **ワークフロー**: cd→ls→upload→ls→rm の統合テスト

### test/e2e/test_error_handling.rb

エラーハンドリングのテスト：

- **タイムアウト**: 同期タイムアウト、レスポンスタイムアウト
- **CRCエラー**: COBS デコードエラー検出
- **プロトコルエラー**: 不正なフレーム、短いフレーム
- **ファイル操作エラー**: 無効なパス、存在しないファイル
- **ローカルファイルエラー**: 存在しないファイル、無効なパス
- **接続エラー**: クローズ後の操作、再接続
- **データ整合性**: 特殊バイト、大ファイルの整合性
- **リカバリ**: ガベージデータ後の復帰
- **ストレステスト**: 連続操作、複数大ファイル転送

## テストフィクスチャ

### test/fixtures/test_files/

- `small_text.txt`: 小サイズのテキストファイル（数百バイト）
- `large_binary.bin`: 500KBのバイナリファイル

テスト実行時、一時ファイルは `test/tmp/` に作成され、テスト終了後に自動削除されます。

## トラブルシューティング

### "TEST_SERIAL_PORT not set" エラー

環境変数 `TEST_SERIAL_PORT` を設定してください：

```bash
export TEST_SERIAL_PORT=/dev/ttyUSB0
rake test
```

### シリアルポートアクセスエラー

- ポートが正しいか確認: `ls -l /dev/ttyUSB*`
- 権限を確認: `groups` でdialoutグループに所属しているか確認
- デバイスが接続されているか確認: `dmesg | tail`

### 同期エラー（"Failed to detect server beacon"）

- ESP32が正しく起動しているか確認
- ファームウェアが正しくフラッシュされているか確認
- シリアルモニタなどで他のプログラムがポートを使用していないか確認
- ボーレートが一致しているか確認（デフォルト: 115200）

### テストがハング

- タイムアウト設定を調整: `create_client(timeout: 20.0)`
- デバッグモードを有効化: `transfer_client.rb` の `DEBUG_MODE = true`
- ESP32をリセットしてからテスト再実行

## 開発者向け

### 新しいテストの追加

1. 適切なテストファイルに追加（または新規作成）
2. `TestHelper` モジュールのヘルパーメソッドを活用
3. `setup` でクライアント作成・同期
4. `teardown` でクリーンアップ
5. アサーションは明確に記述

### テストヘルパーメソッド

`TestHelper` モジュール（`test/test_helper.rb`）には以下が含まれます：

- `create_client(timeout:)`: テスト用クライアント作成
- `wait_and_sync(client)`: デバイスと同期
- `file_checksum(path)`: SHA256チェックサム計算
- `fixture_path(filename)`: フィクスチャファイルのパス取得
- `temp_path(filename)`: 一時ファイルのパス取得
- `assert_files_equal(path1, path2)`: ファイル内容の比較
- `assert_remote_file_exists(client, path)`: リモートファイル存在確認
- `setup_remote_test_dir(client)`: リモートテスト環境セットアップ
- `cleanup_remote_test_dir(client)`: リモートテストファイルクリーンアップ

### コーディング規約

- Minitest標準のアサーションを使用
- テストメソッド名: `test_<動作>_<条件>`
- 各テストは独立して実行可能にする
- セットアップ/ティアダウンで状態をクリーンに保つ

## ライセンス

このテストスイートは親プロジェクトと同じライセンスです。
