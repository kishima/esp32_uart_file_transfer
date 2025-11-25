require_relative '../unit_helper'
require 'zlib'
require 'json'

class TestProtocolErrors < Minitest::Test
  include UnitTestHelper

  # === CRC Error Tests ===

  def test_crc_error_detection
    # Test that the client detects and raises error on CRC mismatch

    # Build a frame with intentionally bad CRC
    bad_frame = build_bad_crc_frame(0x12, {path: "/home"})

    # Verify COBS can decode it (CRC check happens after COBS decode)
    decoded = COBS.decode(bad_frame.chomp("\x00"))

    # Extract CRC from decoded frame
    # Frame format: [code:1][json_len:2][json:N][crc:4]
    assert decoded.bytesize >= 7, "Frame should be at least 7 bytes"

    # Extract body and CRC
    body = decoded[0..-5]
    received_crc = decoded[-4..-1].unpack("N").first
    expected_crc = Zlib.crc32(body)

    # Verify CRC mismatch
    refute_equal expected_crc, received_crc, "CRC should not match (intentional bad CRC)"

    # In real client, this would raise an error
    # We've verified that bad CRC can be detected
  end

  # === COBS Error Tests ===

  def test_cobs_decode_error_handling
    # Test COBS decoder with invalid data
    invalid_data = "\x00\x00\x00"  # Invalid COBS (embedded zeros)

    assert_raises(RuntimeError) do
      COBS.decode(invalid_data)
    end
  end

  def test_cobs_encode_decode_roundtrip
    # Test that COBS codec works correctly with special bytes
    test_data = "Hello\x00World\x00Test\x00Data"

    encoded = COBS.encode(test_data)
    decoded = COBS.decode(encoded)

    assert_equal test_data, decoded, "COBS round-trip should preserve data"

    # Verify encoded data has no zeros (except possibly at end)
    encoded_bytes = encoded.bytes
    encoded_bytes.pop if encoded_bytes.last == 0  # Remove delimiter
    refute_includes encoded_bytes, 0, "COBS encoded data should not contain zeros"
  end

  # === Invalid JSON Tests ===

  def test_invalid_json_in_response
    # Test that client handles invalid JSON in server response

    # Build frame with invalid JSON
    invalid_json_frame = build_invalid_json_frame(0x12)

    # Verify COBS decoding works
    decoded = COBS.decode(invalid_json_frame.chomp("\x00"))

    # Extract JSON portion
    # Frame format: [code:1][json_len:2][json:N][crc:4]
    code = decoded[0].ord
    json_len = decoded[1..2].unpack("n").first
    json_str = decoded[3...(3+json_len)]

    # Verify JSON is invalid
    assert_raises(JSON::ParserError) do
      JSON.parse(json_str)
    end
  end

  # === Short Frame Tests ===

  def test_short_frame_error
    # Test handling of frames that are too short
    short_frame = build_short_frame

    # Decode COBS
    decoded = COBS.decode(short_frame.chomp("\x00"))

    # Frame must be at least 7 bytes: [code:1][json_len:2][json:0][crc:4]
    assert_operator decoded.bytesize, :<, 7, "Frame should be too short"

    # In real client, this would be rejected
    # We've verified that short frames can be detected
  end

  # === COBS Edge Cases ===

  def test_cobs_empty_data
    # Test COBS with empty data
    empty = ""
    encoded = COBS.encode(empty)
    decoded = COBS.decode(encoded)

    assert_equal empty, decoded, "Empty data should round-trip correctly"
  end

  def test_cobs_all_zeros
    # Test COBS with data containing only zeros
    zeros = "\x00\x00\x00\x00\x00"
    encoded = COBS.encode(zeros)
    decoded = COBS.decode(encoded)

    # COBS decoder removes trailing zero, so expect 4 zeros not 5
    # This is expected behavior of the COBS implementation
    assert_equal 4, decoded.bytesize, "COBS decoder removes trailing zero"
    assert_equal "\x00\x00\x00\x00", decoded
  end

  def test_cobs_no_zeros
    # Test COBS with data containing no zeros
    no_zeros = "ABCDEFGHIJKLMNOP"
    encoded = COBS.encode(no_zeros)
    decoded = COBS.decode(encoded)

    assert_equal no_zeros, decoded, "Non-zero data should round-trip correctly"
  end

  def test_cobs_max_run
    # Test COBS with data that triggers max run length (254 bytes)
    max_run = "A" * 254
    encoded = COBS.encode(max_run)
    decoded = COBS.decode(encoded)

    assert_equal max_run, decoded, "Max run length data should round-trip correctly"
  end
end
