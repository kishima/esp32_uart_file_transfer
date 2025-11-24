require_relative '../test_helper'

class TestRemoteCommands < Minitest::Test
  include TestHelper

  def setup
    super
    @client = create_client
    wait_and_sync(@client)
    setup_remote_test_dir(@client)
  end

  def teardown
    cleanup_remote_test_dir(@client)
    @client.close
    super
  end

  # === cd (Change Directory) Tests ===

  def test_r_cd_to_flash
    result = @client.r_cd("/flash")
    assert_equal true, result
  end

  def test_r_cd_to_root
    result = @client.r_cd("/")
    assert_equal true, result
  end

  def test_r_cd_to_invalid_directory
    assert_raises(RuntimeError) do
      @client.r_cd("/nonexistent_directory")
    end
  end

  # === ls (List Directory) Tests ===

  def test_r_ls_flash_directory
    entries = @client.r_ls("/flash")

    assert_kind_of Array, entries
    # Flash should exist and likely have some entries
    refute_empty entries, "Flash directory should have at least some entries"

    # Check entry format
    first_entry = entries.first
    assert first_entry.key?("n"), "Entry should have 'n' (name) key"
    assert first_entry.key?("t"), "Entry should have 't' (type) key"
    assert first_entry.key?("s"), "Entry should have 's' (size) key"
  end

  def test_r_ls_root_directory
    entries = @client.r_ls("/")

    assert_kind_of Array, entries
    refute_empty entries, "Root directory should have entries"

    # Should contain at least 'flash' directory
    flash_entry = entries.find { |e| e["n"] == "flash" }
    refute_nil flash_entry, "Root should contain 'flash' directory"
    assert_equal "d", flash_entry["t"], "flash should be a directory"
  end

  def test_r_ls_current_directory
    @client.r_cd("/flash")
    entries = @client.r_ls(".")

    assert_kind_of Array, entries
  end

  def test_r_ls_nonexistent_directory
    assert_raises(RuntimeError) do
      @client.r_ls("/nonexistent")
    end
  end

  def test_r_ls_shows_uploaded_file
    # Upload a test file
    local_file = fixture_path("small_text.txt")
    remote_file = "/flash/test_ls_file.txt"
    @client.put(local_file, remote_file)

    # List directory
    entries = @client.r_ls("/flash")

    # Find our file
    file_entry = entries.find { |e| e["n"] == "test_ls_file.txt" }
    refute_nil file_entry, "Uploaded file should appear in ls"
    assert_equal "f", file_entry["t"], "Entry should be a file"
    assert file_entry["s"] > 0, "File size should be greater than 0"
  end

  # === rm (Remove) Tests ===

  def test_r_rm_file
    # Upload a file first
    local_file = fixture_path("small_text.txt")
    remote_file = "/flash/test_rm_file.txt"
    @client.put(local_file, remote_file)

    # Verify it exists
    assert_remote_file_exists(@client, remote_file)

    # Remove it
    result = @client.r_rm(remote_file)
    assert_equal true, result

    # Verify it's gone
    refute_remote_file_exists(@client, remote_file)
  end

  def test_r_rm_nonexistent_file
    assert_raises(RuntimeError) do
      @client.r_rm("/flash/nonexistent_file.txt")
    end
  end

  def test_r_rm_multiple_files
    # Upload multiple files
    3.times do |i|
      local_file = fixture_path("small_text.txt")
      remote_file = "/flash/test_rm_multi_#{i}.txt"
      @client.put(local_file, remote_file)
    end

    # Remove them one by one
    3.times do |i|
      remote_file = "/flash/test_rm_multi_#{i}.txt"
      @client.r_rm(remote_file)
      refute_remote_file_exists(@client, remote_file)
    end
  end

  # === Host commands (local operations) ===

  def test_h_cd_changes_directory
    original_dir = Dir.pwd

    begin
      temp_dir = temp_path("test_dir")
      FileUtils.mkdir_p(temp_dir)

      @client.h_cd(temp_dir)
      assert_equal temp_dir, Dir.pwd
    ensure
      Dir.chdir(original_dir)
    end
  end

  def test_h_ls_lists_files
    # Create test directory with files
    test_dir = temp_path("test_ls_dir")
    FileUtils.mkdir_p(test_dir)
    File.write(File.join(test_dir, "file1.txt"), "test")
    File.write(File.join(test_dir, "file2.txt"), "test")

    # Capture output
    output = capture_io do
      @client.h_ls(test_dir)
    end

    assert_match(/file1\.txt/, output.join)
    assert_match(/file2\.txt/, output.join)
  end

  # === Integration: Workflow Tests ===

  def test_workflow_cd_ls_upload_ls_rm
    # Change to flash directory
    @client.r_cd("/flash")

    # List initial state
    initial_entries = @client.r_ls(".")
    initial_count = initial_entries.length

    # Upload a file
    local_file = fixture_path("small_text.txt")
    remote_file = "/flash/test_workflow.txt"
    @client.put(local_file, remote_file)

    # List again (should have one more entry)
    after_upload = @client.r_ls(".")
    assert_equal initial_count + 1, after_upload.length

    # Verify file is there
    assert_remote_file_exists(@client, remote_file)

    # Remove the file
    @client.r_rm(remote_file)

    # List final state (should be back to initial count)
    final_entries = @client.r_ls(".")
    assert_equal initial_count, final_entries.length
  end

  def test_workflow_upload_multiple_ls_rm_all
    files = []

    # Upload 5 test files
    5.times do |i|
      local_file = fixture_path("small_text.txt")
      remote_file = "/flash/test_multi_#{i}.txt"
      @client.put(local_file, remote_file)
      files << remote_file
    end

    # List and verify all are there
    entries = @client.r_ls("/flash")
    files.each do |remote_file|
      filename = File.basename(remote_file)
      assert entries.any? { |e| e["n"] == filename },
             "File #{filename} should exist"
    end

    # Remove all
    files.each do |remote_file|
      @client.r_rm(remote_file)
    end

    # Verify all are gone
    final_entries = @client.r_ls("/flash")
    files.each do |remote_file|
      filename = File.basename(remote_file)
      refute final_entries.any? { |e| e["n"] == filename },
             "File #{filename} should be removed"
    end
  end
end
