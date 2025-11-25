require_relative '../test_helper'

class TestFileTransfer < Minitest::Test
  include TestHelper

  def setup
    super
    @client = create_client
    # wait_and_sync(@client)  # Disabled: beacon not enabled in firmware
    setup_remote_test_dir(@client)
  end

  def teardown
    cleanup_remote_test_dir(@client)
    @client.close
    super
  end

  # === Upload Tests ===

  def test_upload_small_text_file
    local_file = fixture_path("small_text.txt")
    remote_file = "/home/test_small.txt"

    @client.put(local_file, remote_file)

    assert_remote_file_exists(@client, remote_file)

    # Verify by downloading back
    downloaded = temp_path("downloaded_small.txt")
    @client.get(remote_file, downloaded)
    assert_files_equal(local_file, downloaded)
  end

  def test_upload_large_binary_file
    local_file = fixture_path("large_binary.bin")
    remote_file = "/home/test_large.bin"

    @client.put(local_file, remote_file, chunk: 2048)

    assert_remote_file_exists(@client, remote_file)

    # Verify size
    entries = @client.r_ls("/home")
    entry = entries.find { |e| e["n"] == "test_large.bin" }
    assert_equal File.size(local_file), entry["s"], "File size should match"
  end

  def test_upload_with_custom_chunk_size
    local_file = fixture_path("small_text.txt")
    remote_file = "/home/test_chunk.txt"

    # Test with different chunk sizes
    [512, 2048].each do |chunk_size|
      @client.put(local_file, remote_file, chunk: chunk_size)
      assert_remote_file_exists(@client, remote_file)
      @client.r_rm(remote_file)
    end
  end

  # === Download Tests ===

  def test_download_small_file
    # First upload a file
    local_file = fixture_path("small_text.txt")
    remote_file = "/home/test_download.txt"
    @client.put(local_file, remote_file)

    # Download it
    downloaded = temp_path("downloaded.txt")
    @client.get(remote_file, downloaded)

    assert_files_equal(local_file, downloaded)
  end

  def test_download_large_binary_file
    # First upload a large file
    local_file = fixture_path("large_binary.bin")
    remote_file = "/home/test_download_large.bin"
    @client.put(local_file, remote_file, chunk: 2048)

    # Download it
    downloaded = temp_path("downloaded_large.bin")
    @client.get(remote_file, downloaded, chunk: 2048)

    assert_files_equal(local_file, downloaded)
  end

  def test_download_nonexistent_file
    remote_file = "/home/nonexistent_file.txt"
    downloaded = temp_path("should_not_exist.txt")

    # Ensure local file doesn't exist before test
    File.delete(downloaded) if File.exist?(downloaded)

    assert_raises(RuntimeError) do
      @client.get(remote_file, downloaded)
    end

    # Note: Client may create empty file before detecting error
    # Just verify the operation raised an error
  end

  # === Round-trip Tests ===

  def test_upload_download_round_trip_small
    # Create temporary file
    temp_upload = temp_path("upload_test.txt")
    File.write(temp_upload, "Round trip test\n" * 100)

    remote_file = "/home/test_roundtrip.txt"
    temp_download = temp_path("download_test.txt")

    # Upload
    @client.put(temp_upload, remote_file)

    # Download
    @client.get(remote_file, temp_download)

    # Verify
    assert_files_equal(temp_upload, temp_download)
  end

  def test_upload_download_round_trip_100kb
    local_file = fixture_path("large_binary.bin")
    remote_file = "/home/test_roundtrip_large.bin"
    downloaded = temp_path("roundtrip_large.bin")

    # Upload 100KB file with larger chunk size for speed
    @client.put(local_file, remote_file, chunk: 2048)

    # Download it back with larger chunk size
    @client.get(remote_file, downloaded, chunk: 2048)

    # Verify checksum
    assert_files_equal(local_file, downloaded)
  end

  # === Overwrite Tests ===

  def test_overwrite_existing_file
    local_file1 = fixture_path("small_text.txt")

    # Create second file with different content
    local_file2 = temp_path("different.txt")
    File.write(local_file2, "Different content\n" * 50)

    remote_file = "/home/test_overwrite.txt"

    # Upload first file
    @client.put(local_file1, remote_file)

    # Upload second file (overwrite)
    @client.put(local_file2, remote_file)

    # Download and verify it's the second file
    downloaded = temp_path("overwritten.txt")
    @client.get(remote_file, downloaded)
    assert_files_equal(local_file2, downloaded)
  end

  # === Transfer wrapper tests ===

  def test_transfer_up_direction
    local_file = fixture_path("small_text.txt")
    remote_file = "/home/test_transfer_up.txt"

    @client.transfer("up", local: local_file, remote: remote_file)

    assert_remote_file_exists(@client, remote_file)
  end

  def test_transfer_down_direction
    # First upload
    local_file = fixture_path("small_text.txt")
    remote_file = "/home/test_transfer_down.txt"
    @client.put(local_file, remote_file)

    # Then download via transfer
    downloaded = temp_path("transfer_down.txt")
    @client.transfer("down", local: downloaded, remote: remote_file)

    assert_files_equal(local_file, downloaded)
  end

  def test_transfer_invalid_direction
    assert_raises(RuntimeError) do
      @client.transfer("invalid", local: "test.txt", remote: "/home/test.txt")
    end
  end
end
