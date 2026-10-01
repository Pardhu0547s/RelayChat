#include <SPI.h>
#include <LoRa.h>
#include "esp_mac.h"

// Standard VSPI Pins for LoRa SX1278 Ra-02 on ESP32
#define LORA_SCK  18
#define LORA_MISO 19
#define LORA_MOSI 23
#define LORA_CS   5
#define LORA_RST  14
#define LORA_DIO0 26

String myId;
unsigned long lastSendTime = 0;
int interval = 2000;

void setup() {
  Serial.begin(115200);
  delay(1000); // Wait for Serial to be ready

  // Read MAC address to give this node a unique name
  uint8_t mac[6];
  esp_read_mac(mac, ESP_MAC_WIFI_STA);
  char macStr[18];
  sprintf(macStr, "%02X:%02X:%02X:%02X:%02X:%02X", mac[0], mac[1], mac[2], mac[3], mac[4], mac[5]);
  myId = String(macStr);

  Serial.println("\n=================================");
  Serial.println("  LoRa Bidirectional Ping-Pong  ");
  Serial.println("  My MAC: " + myId);
  Serial.println("=================================");

  // Initialize SPI with custom pins
  SPI.begin(LORA_SCK, LORA_MISO, LORA_MOSI, LORA_CS);
  LoRa.setPins(LORA_CS, LORA_RST, LORA_DIO0);

  // Initialize LoRa at 433 MHz
  if (!LoRa.begin(433E6)) {
    Serial.println("❌ LoRa init failed. Check your wiring!");
    while (true);
  }
  
  // Enable CRC for payload integrity
  LoRa.enableCrc();
  
  Serial.println("✅ LoRa init succeeded!");
  Serial.println("Waiting to receive and send...\n");
}

void loop() {
  // 1. Try to parse incoming packet
  int packetSize = LoRa.parsePacket();
  if (packetSize) {
    String incoming = "";
    while (LoRa.available()) {
      incoming += (char)LoRa.read();
    }
    Serial.print("📥 RECEIVED [RSSI: ");
    Serial.print(LoRa.packetRssi());
    Serial.print("]: ");
    Serial.println(incoming);
  }

  // 2. Send outgoing packet periodically
  if (millis() - lastSendTime > interval) {
    String message = "HELLO from " + myId + " at " + String(millis());
    
    LoRa.beginPacket();
    LoRa.print(message);
    LoRa.endPacket();
    
    Serial.println("📤 SENT: " + message);
    lastSendTime = millis();
    
    // Add randomness (2s to 4s) to prevent the two boards from transmitting 
    // at the exact same time constantly and colliding over the air.
    interval = random(2000, 4000); 
  }
}
