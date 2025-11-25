require 'rake/testtask'

# Default task
task default: :test

# Run all tests
desc "Run all tests (unit + E2E)"
task test: ["test:unit", "test:e2e"]

namespace :test do
  # Unit tests (no hardware required)
  desc "Run unit tests (no hardware required)"
  Rake::TestTask.new(:unit) do |t|
    t.libs << "test"
    t.test_files = FileList['test/unit/**/*_test.rb', 'test/unit/**/test_*.rb']
    t.warning = false
    t.verbose = true
  end

  # E2E tests
  desc "Run E2E tests (requires TEST_SERIAL_PORT environment variable)"
  Rake::TestTask.new(:e2e) do |t|
    t.libs << "test"
    t.test_files = FileList['test/e2e/**/*_test.rb', 'test/e2e/**/test_*.rb']
    t.warning = false
    t.verbose = true
  end

  # Individual test files
  desc "Run file transfer tests"
  task :file_transfer do
    ruby "-Itest test/e2e/test_file_transfer.rb"
  end

  desc "Run remote command tests"
  task :remote_commands do
    ruby "-Itest test/e2e/test_remote_commands.rb"
  end

  desc "Run error handling tests"
  task :error_handling do
    ruby "-Itest test/e2e/test_error_handling.rb"
  end

  desc "Run protocol error unit tests"
  task :protocol_errors do
    ruby "-Itest test/unit/test_protocol_errors.rb"
  end

  desc "Run timeout unit tests"
  task :timeout do
    ruby "-Itest test/unit/test_timeout.rb"
  end
end

# Info task
desc "Show test information"
task :info do
  puts "UART File Transfer Test Suite"
  puts "=" * 50
  puts ""
  puts "Usage:"
  puts "  rake test                       - Run all tests (unit + E2E)"
  puts "  rake test:unit                  - Run unit tests only (no hardware)"
  puts "  TEST_SERIAL_PORT=/dev/ttyUSB0 rake test:e2e  - Run E2E tests"
  puts ""
  puts "Available tasks:"
  puts "  Unit Tests (no hardware required):"
  puts "    rake test:unit               - Run all unit tests"
  puts "    rake test:protocol_errors    - Run protocol error tests"
  puts "    rake test:timeout            - Run timeout tests"
  puts ""
  puts "  E2E Tests (hardware required):"
  puts "    rake test:e2e                - Run all E2E tests"
  puts "    rake test:file_transfer      - Run file transfer tests only"
  puts "    rake test:remote_commands    - Run remote command tests only"
  puts "    rake test:error_handling     - Run error handling tests only"
  puts ""
  puts "Requirements:"
  puts "  Unit tests: None (run anywhere)"
  puts "  E2E tests:"
  puts "    - ESP32 device must be connected and running firmware"
  puts "    - TEST_SERIAL_PORT environment variable must be set"
  puts "    - Run 'bundle install' first to install dependencies"
  puts ""
  puts "Examples:"
  puts "  rake test:unit                                  # Unit tests only"
  puts "  TEST_SERIAL_PORT=/dev/ttyUSB0 rake test:e2e    # E2E tests"
  puts "  TEST_SERIAL_PORT=/dev/ttyACM0 rake test        # All tests"
  puts ""
end
