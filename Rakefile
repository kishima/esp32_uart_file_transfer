require 'rake/testtask'

# Default task
task default: :test

# Run all tests
desc "Run all E2E tests"
task test: ["test:e2e"]

namespace :test do
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
end

# Info task
desc "Show test information"
task :info do
  puts "UART File Transfer E2E Tests"
  puts "=" * 50
  puts ""
  puts "Usage:"
  puts "  TEST_SERIAL_PORT=/dev/ttyUSB0 rake test"
  puts ""
  puts "Available tasks:"
  puts "  rake test                    - Run all E2E tests"
  puts "  rake test:file_transfer      - Run file transfer tests only"
  puts "  rake test:remote_commands    - Run remote command tests only"
  puts "  rake test:error_handling     - Run error handling tests only"
  puts ""
  puts "Requirements:"
  puts "  - ESP32 device must be connected and running firmware"
  puts "  - TEST_SERIAL_PORT environment variable must be set"
  puts "  - Run 'bundle install' first to install dependencies"
  puts ""
  puts "Examples:"
  puts "  TEST_SERIAL_PORT=/dev/ttyUSB0 rake test"
  puts "  TEST_SERIAL_PORT=/dev/ttyACM0 rake test:file_transfer"
  puts ""
end
