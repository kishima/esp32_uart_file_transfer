require 'minitest/autorun'
require 'minitest/reporters'
require 'fileutils'
require 'digest'

# Use progress reporter for cleaner output
Minitest::Reporters.use! Minitest::Reporters::ProgressReporter.new

# Load the transfer client
require_relative '../client/transfer_client'

module TestHelper
  # Test configuration
  FIXTURES_DIR = File.expand_path("fixtures/test_files", __dir__)
  TEMP_DIR = File.expand_path("tmp", __dir__)

  # Get serial port from environment or skip tests
  def serial_port
    ENV['TEST_SERIAL_PORT'] || skip("TEST_SERIAL_PORT not set. Example: TEST_SERIAL_PORT=/dev/ttyUSB0")
  end

  # Setup temporary directory
  def setup
    super
    FileUtils.mkdir_p(TEMP_DIR)
  end

  # Cleanup temporary directory
  def teardown
    super
    FileUtils.rm_rf(TEMP_DIR) if File.exist?(TEMP_DIR)
  end

  # Create a serial client with test configuration
  def create_client(timeout: 10.0)
    SerialClient.new(
      port: serial_port,
      baud: 115200,
      rtscts: true,
      timeout_s: timeout
    )
  end

  # Wait for device to be ready and sync
  def wait_and_sync(client, retries: 3)
    client.sync(retries: retries, timeout: 10.0)
  end

  # Calculate file checksum
  def file_checksum(path)
    Digest::SHA256.file(path).hexdigest
  end

  # Generate random binary data
  def random_data(size)
    Random.new.bytes(size)
  end

  # Get fixture file path
  def fixture_path(filename)
    File.join(FIXTURES_DIR, filename)
  end

  # Get temp file path
  def temp_path(filename)
    File.join(TEMP_DIR, filename)
  end

  # Remote test directory (cleanup after tests)
  REMOTE_TEST_DIR = "/flash/test"

  # Setup remote test environment
  def setup_remote_test_dir(client)
    begin
      # Try to create test directory (may fail if exists)
      client.r_cd("/flash")
    rescue => e
      # Ignore errors, just ensure we're in /flash
    end
  end

  # Cleanup remote test files
  def cleanup_remote_test_dir(client)
    begin
      # Remove test files one by one
      entries = client.r_ls("/flash")
      entries.each do |entry|
        if entry["n"].start_with?("test_")
          client.r_rm("/flash/#{entry["n"]}")
        end
      end
    rescue => e
      # Ignore cleanup errors
      warn "Warning: Failed to cleanup remote test dir: #{e.message}"
    end
  end

  # Assert file contents match
  def assert_files_equal(path1, path2, msg = nil)
    assert_equal file_checksum(path1), file_checksum(path2),
                 msg || "Files #{path1} and #{path2} should have same content"
  end

  # Assert remote file exists
  def assert_remote_file_exists(client, remote_path, msg = nil)
    dir = File.dirname(remote_path)
    filename = File.basename(remote_path)
    entries = client.r_ls(dir)
    assert entries.any? { |e| e["n"] == filename },
           msg || "Remote file #{remote_path} should exist"
  end

  # Refute remote file exists
  def refute_remote_file_exists(client, remote_path, msg = nil)
    dir = File.dirname(remote_path)
    filename = File.basename(remote_path)
    entries = client.r_ls(dir)
    refute entries.any? { |e| e["n"] == filename },
           msg || "Remote file #{remote_path} should not exist"
  end
end
