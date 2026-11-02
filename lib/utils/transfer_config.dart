/// Tuning for chunked transfers (images) over LoRa.
///
/// A LoRa packet carries at most 255 bytes: 72 (frame header) + 20 (chunk header)
/// leaves 163 bytes of data, so 160 is the practical maximum chunk size.
///
/// Airtime for a 252-byte packet at SF7 / 125 kHz is ~394 ms, so a 480 ms pace keeps the
/// sender's radio busy without queueing packets inside the ESP32.
///
/// FAST RADIO: set [fastRadio] to true AND set LORA_BANDWIDTH to 250E3 in the firmware on
/// BOTH nodes. Airtime halves, so the same 5-second target fits about twice as many bytes
/// (a clearer image). The price is ~3 dB less range.
class TransferConfig {
  static const bool espNowMode = true;
  static const bool fastRadio = false;

  /// Chunk size is 156 bytes: 72 (frame header) + 20 (chunk header) = 248 bytes,
  /// fitting within ESP-NOW's 250-byte max payload and LoRa's 255-byte max payload.
  static const int chunkDataBytes = 156;
  static const int maxChunks = 128;
  static const int paceMs = espNowMode ? 80 : (fastRadio ? 260 : 480);
  static const Duration chunkPacing = Duration(milliseconds: paceMs);

  /// Goal: an image is fully shown on the other phone in about this long.
  static const int targetSeconds = 5;

  /// Time reserved for the phone to prepare (fold) the image before sending.
  static const int prepareMs = 500;

  /// Largest image blob that fits budget (~2500 bytes for fast ESP-NOW transfer).
  static const int imageBudgetBytes = 2500;

  static int packetsFor(int bytes) => (bytes / chunkDataBytes).ceil();

  /// Rough time to transmit [bytes] when nothing is lost.
  static int estimateSeconds(int bytes) =>
      (packetsFor(bytes) * paceMs / 1000).ceil();

  static const int maxBlobBytes = chunkDataBytes * maxChunks;
}
