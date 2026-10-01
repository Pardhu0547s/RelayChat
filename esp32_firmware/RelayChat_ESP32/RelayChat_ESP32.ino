#include <NimBLEDevice.h>
#include <SPI.h>
#include <LoRa.h>
#include "esp_mac.h"

#define DEVICE_NAME "RelayChat_ESP32"

// UUIDs
#define SERVICE_UUID        "6E400001-B5A3-F393-E0A9-E50E24DCCA9E"
#define CHARACTERISTIC_RX   "6E400002-B5A3-F393-E0A9-E50E24DCCA9E"
#define CHARACTERISTIC_TX   "6E400003-B5A3-F393-E0A9-E50E24DCCA9E"

// VSPI Pins for LoRa SX1278 Ra-02
#define LORA_SCK  18
#define LORA_MISO 19
#define LORA_MOSI 23
#define LORA_CS   5
#define LORA_RST  14
#define LORA_DIO0 26

#define LED_PIN   2

#define MAGIC_BYTE 0xAA
#define VERSION    0x01
#define HEADER_SIZE 72

NimBLECharacteristic* txCharacteristic;

SemaphoreHandle_t loraMutex;

bool deviceConnected = false;
uint8_t nodeId[16] = {0};       // 16-byte UUID representation
uint8_t connectedPhoneId[16] = {0}; // Learned from incoming frames

// Deduplication
const int MAX_SEEN = 100;
uint8_t seenIds[MAX_SEEN][16];
int seenIdx = 0;

bool isDuplicate(const uint8_t* id) {
    for (int i = 0; i < MAX_SEEN; i++) {
        if (memcmp(seenIds[i], id, 16) == 0) return true;
    }
    return false;
}

void markSeen(const uint8_t* id) {
    memcpy(seenIds[seenIdx], id, 16);
    seenIdx = (seenIdx + 1) % MAX_SEEN;
}

void generateNodeId() {
    uint8_t mac[6];
    esp_read_mac(mac, ESP_MAC_WIFI_STA);
    // Pad MAC with arbitrary data to make a 16-byte unique ID
    memset(nodeId, 0, 16);
    nodeId[0] = 0xEE; // Indicate ESP32 node
    memcpy(nodeId + 1, mac, 6);
}

bool isBroadcast(const uint8_t* uuid) {
    for (int i = 0; i < 16; i++) {
        if (uuid[i] != 0) return false;
    }
    return true;
}

void routeFrame(uint8_t* frame, size_t len, const char* source) {
    if (len < HEADER_SIZE) return;
    if (frame[0] != MAGIC_BYTE || frame[1] != VERSION) return;
    
    uint8_t* msgId = frame + 53;
    
    if (isDuplicate(msgId)) {
        Serial.println("  🔄 Duplicate, dropped.");
        return;
    }
    markSeen(msgId);

    // Learn connected phone's ID
    if (strcmp(source, "BLE") == 0) {
        uint8_t* origin = frame + 5;
        memcpy(connectedPhoneId, origin, 16);
    }

    uint8_t type = frame[2];
    uint8_t hop = frame[3];
    uint8_t ttl = frame[4];
    uint8_t* receiver = frame + 37;

    if (ttl <= 0) {
        Serial.println("  ⏭️ TTL=0, dropping.");
        return;
    }

    // Update routing fields
    frame[3] = hop + 1;
    frame[4] = ttl - 1;
    memcpy(frame + 21, nodeId, 16); // Set 'Via'

    if (strcmp(source, "BLE") == 0) {
        Serial.print("  🌐 BLE -> LoRa (");
        Serial.print(len);
        Serial.println(" bytes)");
        
        LoRa.beginPacket();
        LoRa.write(frame, len);
        LoRa.endPacket();
        LoRa.receive(); // return to RX mode so we do not miss packets
        Serial.println("  ✅ LoRa packet sent");
    } 
    else if (strcmp(source, "LoRa") == 0) {
        bool forUs = deviceConnected && 
                     (memcmp(receiver, connectedPhoneId, 16) == 0 || 
                      isBroadcast(receiver));
        
        if (forUs) {
            Serial.println("  📱 LoRa -> BLE (delivering to phone)");
            
            // Inject RSSI into the new header byte before sending to phone
            frame[71] = (uint8_t)(LoRa.packetRssi() & 0xFF);
            
            txCharacteristic->setValue(frame, len);
            txCharacteristic->notify();
        }
        
        // Re-broadcast unless it was strictly for our phone and delivered
        if (memcmp(receiver, connectedPhoneId, 16) != 0 || !deviceConnected) {
            Serial.println("  🌐 Re-broadcasting on LoRa");
            LoRa.beginPacket();
            LoRa.write(frame, len);
            LoRa.endPacket();
            LoRa.receive(); // return to RX mode so we do not miss packets
        }
    }
}

//----------------------------------------
// BLE Callbacks
//----------------------------------------
class ServerCallbacks : public NimBLEServerCallbacks {
    void onConnect(NimBLEServer* pServer, NimBLEConnInfo& connInfo) override {
        deviceConnected = true;
        digitalWrite(LED_PIN, HIGH);
        Serial.println("📱 Phone Connected via BLE");
    }

    void onDisconnect(NimBLEServer* pServer, NimBLEConnInfo& connInfo, int reason) override {
        deviceConnected = false;
        digitalWrite(LED_PIN, LOW);
        memset(connectedPhoneId, 0, 16);
        Serial.println("❌ Phone Disconnected");
        NimBLEDevice::startAdvertising();
    }
};

const size_t RX_BUFFER_SIZE = 2048;
uint8_t rxBuffer[RX_BUFFER_SIZE];
size_t rxBufferLen = 0;

class RXCallbacks : public NimBLECharacteristicCallbacks {
    void onWrite(NimBLECharacteristic* pCharacteristic, NimBLEConnInfo& connInfo) override {
        std::string value = pCharacteristic->getValue();
        if (value.empty()) return;

        if (rxBufferLen + value.length() > RX_BUFFER_SIZE) {
            Serial.println("  ⚠️ Buffer overflow, clearing");
            rxBufferLen = 0;
        }

        memcpy(rxBuffer + rxBufferLen, value.data(), value.length());
        rxBufferLen += value.length();

        while (rxBufferLen >= HEADER_SIZE) {
            // Find magic byte
            size_t magicIdx = 0;
            while (magicIdx < rxBufferLen && rxBuffer[magicIdx] != MAGIC_BYTE) {
                magicIdx++;
            }

            if (magicIdx > 0) {
                // Shift buffer to magic byte
                rxBufferLen -= magicIdx;
                memmove(rxBuffer, rxBuffer + magicIdx, rxBufferLen);
                if (rxBufferLen < HEADER_SIZE) break;
            }

            if (rxBuffer[1] != VERSION) {
                // Bad version, consume magic byte
                rxBufferLen--;
                memmove(rxBuffer, rxBuffer + 1, rxBufferLen);
                continue;
            }

            uint16_t payloadLen = rxBuffer[69] | (rxBuffer[70] << 8);
            size_t totalFrameLen = HEADER_SIZE + payloadLen;

            if (totalFrameLen > RX_BUFFER_SIZE) {
                // Insane payload length, drop magic byte and resync
                rxBufferLen--;
                memmove(rxBuffer, rxBuffer + 1, rxBufferLen);
                continue;
            }

            if (rxBufferLen < totalFrameLen) {
                // Wait for more chunks
                break;
            }

            // We have a full frame!
            xSemaphoreTake(loraMutex, portMAX_DELAY);
            routeFrame(rxBuffer, totalFrameLen, "BLE");
            xSemaphoreGive(loraMutex);

            // Remove processed frame from buffer
            rxBufferLen -= totalFrameLen;
            if (rxBufferLen > 0) {
                memmove(rxBuffer, rxBuffer + totalFrameLen, rxBufferLen);
            }
        }
    }
};

//----------------------------------------
// Setup
//----------------------------------------
void setup() {
    Serial.begin(115200);
    
    pinMode(LED_PIN, OUTPUT);
    digitalWrite(LED_PIN, LOW);
    
    delay(500);
    
    loraMutex = xSemaphoreCreateMutex();
    
    generateNodeId();

    Serial.println();
    Serial.println("================================");
    Serial.println("  RelayChat LoRa Node (Binary Protocol)");
    Serial.println("================================");

    // --- LoRa ---
    SPI.begin(LORA_SCK, LORA_MISO, LORA_MOSI, LORA_CS);
    LoRa.setPins(LORA_CS, LORA_RST, LORA_DIO0);
    
    if (!LoRa.begin(433E6)) {
        Serial.println("❌ LoRa init FAILED!");
        while (1);
    }
    LoRa.enableCrc();
    Serial.println("✅ LoRa initialized (433 MHz, CRC Enabled)");

    // --- BLE ---
    NimBLEDevice::init(DEVICE_NAME);
    NimBLEDevice::setMTU(512); // Negotiate larger MTU with Android
    NimBLEServer* server = NimBLEDevice::createServer();
    server->setCallbacks(new ServerCallbacks());
    
    NimBLEService* service = server->createService(SERVICE_UUID);
    
    txCharacteristic = service->createCharacteristic(
        CHARACTERISTIC_TX, NIMBLE_PROPERTY::NOTIFY
    );
    
    NimBLECharacteristic* rxCharacteristic = service->createCharacteristic(
        CHARACTERISTIC_RX, 
        NIMBLE_PROPERTY::WRITE | NIMBLE_PROPERTY::WRITE_NR
    );
    rxCharacteristic->setCallbacks(new RXCallbacks());
    
    service->start();

    NimBLEAdvertising* advertising = NimBLEDevice::getAdvertising();
    advertising->addServiceUUID(SERVICE_UUID);
    advertising->start();

    Serial.println("✅ BLE advertising started");
    Serial.println("================================");
    Serial.println("Ready. Waiting for phone + LoRa...");
}

//----------------------------------------
// Loop
//----------------------------------------
void loop() {
    xSemaphoreTake(loraMutex, portMAX_DELAY);
    int packetSize = LoRa.parsePacket();
    if (packetSize) {
        Serial.print("📡 LoRa RX: ");
        Serial.print(packetSize);
        Serial.println(" bytes");

        uint8_t buffer[256]; // LoRa SX1278 max is 255
        int len = 0;
        while (LoRa.available() && len < 255) {
            buffer[len++] = LoRa.read();
        }

        routeFrame(buffer, len, "LoRa");
    }
    xSemaphoreGive(loraMutex);
    
    delay(5); // Yield to let the BLE task grab the mutex
}