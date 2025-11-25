require 'minitest/autorun'
require 'minitest/reporters'
require 'timeout'

# Use progress reporter for cleaner output
Minitest::Reporters.use! Minitest::Reporters::ProgressReporter.new

# Mock SerialPort for unit testing
class MockSerialPort
  attr_reader :written_data
  attr_accessor :read_queue, :read_timeout

  def initialize(port, baud_rate, data_bits = nil, stop_bits = nil, parity = nil)
    @port = port
    @baud_rate = baud_rate
    @written_data = []
    @read_queue = []
    @read_timeout = 1.0
    @closed = false
  end

  def write(data)
    raise IOError, "Port is closed" if @closed
    @written_data << data
    data.bytesize
  end

  def read(length)
    raise IOError, "Port is closed" if @closed

    # If read_queue has data, return it
    if @read_queue.any?
      data = @read_queue.shift
      return data if data.is_a?(Exception)
      return data
    end

    # Otherwise simulate timeout
    sleep @read_timeout
    nil
  end

  def read_nonblock(length)
    raise IOError, "Port is closed" if @closed

    if @read_queue.any?
      data = @read_queue.shift
      raise data if data.is_a?(Exception)
      return data
    end

    raise IO::WaitReadable
  end

  def flush
    # No-op for mock
  end

  def close
    @closed = true
  end

  def closed?
    @closed
  end

  # Helper method to enqueue response data
  def enqueue_response(data)
    @read_queue << data
  end

  # Helper method to enqueue an exception
  def enqueue_error(exception)
    @read_queue << exception
  end

  # Helper to get last written packet
  def last_written
    @written_data.last
  end

  # Helper to clear written data
  def clear_written
    @written_data.clear
  end
end

# COBS encoder/decoder (from transfer_client.rb)
module COBS
  def self.encode(data)
    result = []
    code_index = 0
    code = 1

    result << 0  # Placeholder

    data.each_byte do |byte|
      if byte == 0
        result[code_index] = code
        code = 1
        code_index = result.length
        result << 0
      else
        result << byte
        code += 1
        if code == 0xFF
          result[code_index] = code
          code = 1
          code_index = result.length
          result << 0
        end
      end
    end

    result[code_index] = code
    result.pack('C*')
  end

  def self.decode(data)
    raise RuntimeError, "Invalid COBS data" if data.nil? || data.empty?

    bytes = data.unpack('C*')
    result = []
    i = 0

    while i < bytes.length
      code = bytes[i]
      raise RuntimeError, "Invalid COBS code: #{code}" if code == 0 && i != bytes.length - 1

      i += 1

      (1...code).each do |j|
        break if i >= bytes.length
        result << bytes[i]
        i += 1
      end

      result << 0 if code < 0xFF && i < bytes.length
    end

    result.pop if result.last == 0  # Remove trailing zero
    result.pack('C*')
  end
end

module UnitTestHelper
  # Test timeout (10 seconds for unit tests, faster than E2E)
  TEST_TIMEOUT = 10

  # Create a mock client with a mock serial port
  def create_mock_client
    require_relative '../client/transfer_client'

    # Create mock serial port
    mock_sp = MockSerialPort.new('/dev/mock', 115200)

    # Create client and inject mock
    client = SerialClient.allocate
    client.instance_variable_set(:@sp, mock_sp)
    client.instance_variable_set(:@rx, [])
    client.instance_variable_set(:@timeout_s, 1.0)

    client
  end

  # Build a valid protocol frame
  def build_frame(code, json_data)
    json_str = json_data.to_json
    body = [code].pack("C") + [json_str.bytesize].pack("n") + json_str
    crc = Zlib.crc32(body)
    raw = body + [crc].pack("N")
    COBS.encode(raw) + "\x00"
  end

  # Build a frame with bad CRC
  def build_bad_crc_frame(code, json_data)
    json_str = json_data.to_json
    body = [code].pack("C") + [json_str.bytesize].pack("n") + json_str
    bad_crc = 0xDEADBEEF  # Invalid CRC
    raw = body + [bad_crc].pack("N")
    COBS.encode(raw) + "\x00"
  end

  # Build a short frame (too short to be valid)
  def build_short_frame
    raw = "AB"  # Less than minimum 5 bytes
    COBS.encode(raw) + "\x00"
  end

  # Build a frame with invalid JSON
  def build_invalid_json_frame(code)
    invalid_json = "{invalid json"
    body = [code].pack("C") + [invalid_json.bytesize].pack("n") + invalid_json
    crc = Zlib.crc32(body)
    raw = body + [crc].pack("N")
    COBS.encode(raw) + "\x00"
  end
end

# Add timeout to all test methods automatically
module Minitest
  class Runnable
    alias_method :original_run, :run

    def run
      if self.class.name =~ /Test/
        Timeout.timeout(UnitTestHelper::TEST_TIMEOUT) do
          original_run
        end
      else
        original_run
      end
    rescue Timeout::Error
      self.failures << Minitest::UnexpectedError.new(
        RuntimeError.new("Test exceeded #{UnitTestHelper::TEST_TIMEOUT} second timeout")
      )
      self
    end
  end
end
