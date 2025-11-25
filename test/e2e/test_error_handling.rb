require_relative '../test_helper'

class TestErrorHandling < Minitest::Test
  include TestHelper

  def setup
    super
    @client = create_client(timeout: 5.0)
    # wait_and_sync(@client)  # Disabled: beacon not enabled in firmware
    setup_remote_test_dir(@client)
  end

  def teardown
    cleanup_remote_test_dir(@client)
    @client.close rescue nil
    super
  end

  # === COBS Protocol Tests ===
  # Note: CRC, timeout, and protocol error tests moved to unit tests

  def test_cobs_decode_error_handling
    # Test COBS decoder with invalid data
    invalid_data = "\x00\x00\x00"  # Invalid COBS

    assert_raises(RuntimeError) do
      COBS.decode(invalid_data)
    end
  end

  def test_cobs_encode_decode_roundtrip
    # Test that COBS codec works correctly
    test_data = "Hello\x00World\x00Test\x00Data"

    encoded = COBS.encode(test_data)
    decoded = COBS.decode(encoded)

    assert_equal test_data, decoded
  end

  # === File Operation Error Tests ===

  def test_upload_to_invalid_path
    local_file = fixture_path("small_text.txt")
    invalid_remote = "/nonexistent_dir/test.txt"

    assert_raises(RuntimeError) do
      @client.put(local_file, invalid_remote)
    end
  end

  def test_download_nonexistent_file
    remote_file = "/home/file_that_does_not_exist.txt"
    local_file = temp_path("should_not_exist.txt")

    # Ensure local file doesn't exist before test
    File.delete(local_file) if File.exist?(local_file)

    assert_raises(RuntimeError) do
      @client.get(remote_file, local_file)
    end

    # Note: Client may create empty file before detecting error
    # Just verify the operation raised an error
  end

  def test_remove_nonexistent_file
    assert_raises(RuntimeError) do
      @client.r_rm("/home/nonexistent_file.txt")
    end
  end

  def test_ls_nonexistent_directory
    assert_raises(RuntimeError) do
      @client.r_ls("/nonexistent_directory")
    end
  end

  def test_cd_to_invalid_directory
    assert_raises(RuntimeError) do
      @client.r_cd("/invalid/path/to/nowhere")
    end
  end

  # === Local File Error Tests ===

  def test_upload_nonexistent_local_file
    nonexistent_local = temp_path("does_not_exist.txt")
    remote_file = "/home/test.txt"

    assert_raises(Errno::ENOENT) do
      @client.put(nonexistent_local, remote_file)
    end
  end

  def test_download_to_invalid_local_path
    # Upload a file first
    local_file = fixture_path("small_text.txt")
    remote_file = "/home/test_download_err.txt"
    @client.put(local_file, remote_file)

    # Try to download to invalid path
    invalid_local = "/invalid/path/that/does/not/exist/file.txt"

    assert_raises(Errno::ENOENT) do
      @client.get(remote_file, invalid_local)
    end
  end

  # === Connection Error Tests ===

  def test_operations_after_close
    @client.close

    assert_raises(IOError, Errno::EBADF) do
      @client.r_ls("/home")
    end
  end

  def test_reconnection_after_error
    # Close and reopen
    @client.close

    @client = create_client
    # wait_and_sync(@client)  # Disabled: beacon not enabled in firmware

    # Should work after reconnection
    entries = @client.r_ls("/home")
    assert_kind_of Array, entries
  end

  # === Data Integrity Tests ===

  def test_upload_download_data_integrity_with_special_bytes
    # Create file with special bytes that might cause issues
    special_data = [0x00, 0xFF, 0x0D, 0x0A, 0x1A].pack("C*") * 100
    local_file = temp_path("special_bytes.bin")
    File.binwrite(local_file, special_data)

    remote_file = "/home/test_special_bytes.bin"
    downloaded = temp_path("special_bytes_downloaded.bin")

    # Upload
    @client.put(local_file, remote_file)

    # Download
    @client.get(remote_file, downloaded)

    # Verify
    assert_files_equal(local_file, downloaded)
  end

  def test_large_file_transfer_integrity
    # Use the 500KB fixture
    local_file = fixture_path("large_binary.bin")
    remote_file = "/home/test_integrity_large.bin"
    downloaded = temp_path("integrity_large.bin")

    # Upload
    @client.put(local_file, remote_file, chunk: 1024)

    # Download
    @client.get(remote_file, downloaded, chunk: 1024)

    # Verify every byte matches
    assert_files_equal(local_file, downloaded)

    # Also verify size
    assert_equal File.size(local_file), File.size(downloaded)
  end

  # === Recovery Tests ===

  def test_sync_after_garbage_data
    # Send some garbage to the port
    garbage = "\xFF\xFE\xFD\xFC" * 10
    @client.instance_variable_get(:@sp).write(garbage)
    @client.instance_variable_get(:@sp).flush

    # Wait for server to process and reject garbage
    sleep 1.0

    # Clear receive buffer
    @client.instance_variable_get(:@rx).clear

    # Reconnect to ensure clean state
    @client.close
    @client = create_client
    setup_remote_test_dir(@client)

    # Should be able to execute commands after reconnect
    entries = @client.r_ls("/home")
    assert_kind_of Array, entries
  end

  # === Stress Tests ===

  def test_rapid_sequential_operations
    # Perform many operations in quick succession
    10.times do |i|
      local_file = fixture_path("small_text.txt")
      remote_file = "/home/test_rapid_#{i}.txt"

      @client.put(local_file, remote_file)
      entries = @client.r_ls("/home")
      assert_remote_file_exists(@client, remote_file)
      @client.r_rm(remote_file)
    end
  end

  def test_multiple_large_file_transfers
    large_file = fixture_path("large_binary.bin")

    3.times do |i|
      remote_file = "/home/test_multi_large_#{i}.bin"
      @client.put(large_file, remote_file, chunk: 1024)
      assert_remote_file_exists(@client, remote_file)
      @client.r_rm(remote_file)
    end
  end
end
