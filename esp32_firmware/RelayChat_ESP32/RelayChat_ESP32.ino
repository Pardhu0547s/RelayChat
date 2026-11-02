#include <WiFi.h>
#include <esp_now.h>
#include <esp_wifi.h>
#include <NimBLEDevice.h>
#include "esp_mac.h"

#define DEVICE_NAME "RelayChat_ESP32"

// UUIDs matching Flutter app
#define SERVICE_UUID        "6E400001-B5A3-F393-E0A9-E50E24DCCA9E"
#define CHARACTERISTIC_RX   "6E400002-B5A3-F393-E0A9-E50E24DCCA9E"
#define CHARACTERISTIC_TX   "6E400003-B5A3-F393-E0A9-E50E24DCCA9E"

#define LED_PIN   2

#define MAGIC_BYTE 0xAA
#define VERSION    0x01
#define HEADER_SIZE 72

// Frame Types
#define FRAME_TEXT     0x00
#define FRAME_ACK      0x01
#define FRAME_HELLO    0x02
#define FRAME_VOICE    0x03
#define FRAME_IMAGE    0x04
#define FRAME_LOCATION 0x05
#define FRAME_NACK     0x06
#define FRAME_SOS      0x07

// ESP-NOW Wi-Fi Channel (both nodes must match channel 1)
#define ESPNOW_WIFI_CHANNEL 1

NimBLECharacteristic* txCharacteristic = nullptr;

volatile bool deviceConnected = false;
uint8_t nodeId[16] = {0};           // 16-byte UUID representation
uint8_t connectedPhoneId[16] = {0}; // Learned from incoming BLE frames
uint8_t broadcastMac[6] = {0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF};

// Deduplication
const int MAX_SEEN = 100;
uint8_t seenIds[MAX_SEEN][16];
int seenIdx = 0;

// Packet counters for diagnostics
uint32_t espNowRxCount = 0;
uint32_t espNowTxCount = 0;
uint32_t bleRxCount = 0;
uint32_t bleTxCount = 0;
unsigned long lastHeartbeat = 0;

const char* getFrameTypeName(uint8_t type) {
    switch (type) {
        case FRAME_TEXT:     return "TEXT";
        case FRAME_ACK:      return "ACK";
        case FRAME_HELLO:    return "HELLO";
        case FRAME_VOICE:    return "VOICE";
        case FRAME_IMAGE:    return "IMAGE";
        case FRAME_LOCATION: return "LOCATION";
        case FRAME_NACK:     return "NACK";
        case FRAME_SOS:      return "SOS";
        default:             return "UNKNOWN";
    }
}

void printUuidShort(const uint8_t* uuid) {
    for (int i = 0; i < 4; i++) {
        Serial.printf("%02X", uuid[i]);
    }
}

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

void blinkLed(int ms = 30) {
    digitalWrite(LED_PIN, HIGH);
    delay(ms);
    digitalWrite(LED_PIN, deviceConnected ? HIGH : LOW);
}

// Forward declaration
void routeFrame(uint8_t* frame, size_t len, const char* source);

//----------------------------------------
// ESP-NOW Callbacks
//----------------------------------------
#if defined(ESP_ARDUINO_VERSION_MAJOR) && (ESP_ARDUINO_VERSION >= ESP_ARDUINO_VERSION_VAL(3, 0, 0))
void onDataRecv(const esp_now_recv_info_t *info, const uint8_t *data, int len) {
    const uint8_t* mac = info->src_addr;
#else
void onDataRecv(const uint8_t *mac, const uint8_t *data, int len) {
#endif
    if (len < HEADER_SIZE) return;
    
    // Copy data to local buffer for safe modification
    uint8_t buffer[256];
    if (len > 255) len = 255;
    memcpy(buffer, data, len);

    espNowRxCount++;
    blinkLed(20);

    Serial.printf("\n📡 ESP-NOW RX: %d bytes from %02X:%02X:%02X:%02X:%02X:%02X\n",
                  len, mac[0], mac[1], mac[2], mac[3], mac[4], mac[5]);

    routeFrame(buffer, len, "ESP-NOW");
}


//----------------------------------------
// Frame Routing
//----------------------------------------
void routeFrame(uint8_t* frame, size_t len, const char* source) {
    if (len < HEADER_SIZE) {
        Serial.printf("  ❌ Frame too short (%d < %d bytes)\n", len, HEADER_SIZE);
        return;
    }
    if (frame[0] != MAGIC_BYTE || frame[1] != VERSION) {
        Serial.printf("  ❌ Bad magic/version (0x%02X 0x%02X)\n", frame[0], frame[1]);
        return;
    }
    
    uint8_t* msgId = frame + 53;
    if (isDuplicate(msgId)) {
        Serial.println("  🔄 Duplicate frame, dropped.");
        return;
    }
    markSeen(msgId);

    uint8_t type = frame[2];
    uint8_t hop = frame[3];
    uint8_t ttl = frame[4];
    uint8_t* origin = frame + 5;
    uint8_t* receiver = frame + 37;

    // Learn connected phone's ID from incoming BLE frames
    if (strcmp(source, "BLE") == 0) {
        memcpy(connectedPhoneId, origin, 16);
    }

    Serial.printf("  📦 [%s] Type: %s (0x%02X) | Hop: %d, TTL: %d | Origin: ", 
                  source, getFrameTypeName(type), type, hop, ttl);
    printUuidShort(origin);
    Serial.print("... | Target: ");
    if (isBroadcast(receiver)) {
        Serial.print("BROADCAST");
    } else {
        printUuidShort(receiver);
        Serial.print("...");
    }
    Serial.printf(" | Len: %d\n", len);

    if (ttl <= 0) {
        Serial.println("  ⏭️ TTL expired (0), dropping.");
        return;
    }

    // Update routing fields
    frame[3] = hop + 1;
    frame[4] = ttl - 1;
    memcpy(frame + 21, nodeId, 16); // Set 'Via' to our Node ID

    if (strcmp(source, "BLE") == 0) {
        bleRxCount++;
        Serial.printf("  🌐 BLE -> ESP-NOW Broadcast (%d bytes)...\n", len);
        
        esp_err_t res = esp_now_send(broadcastMac, frame, len);
        if (res == ESP_OK) {
            espNowTxCount++;
            blinkLed(20);
            Serial.println("  ✅ ESP-NOW packet transmitted");
        } else {
            Serial.printf("  ❌ ESP-NOW send failed: %d\n", res);
        }
    } 
    else if (strcmp(source, "ESP-NOW") == 0) {
        bool isBroadcastReceiver = isBroadcast(receiver);
        bool phoneIdLearned = !isBroadcast(connectedPhoneId);
        bool isTargetedToUs = phoneIdLearned && (memcmp(receiver, connectedPhoneId, 16) == 0);
        
        // Deliver to connected phone if broadcast, or addressed to phone, or phone ID not yet registered
        bool forUs = deviceConnected && (isBroadcastReceiver || isTargetedToUs || !phoneIdLearned);
        
        if (forUs) {
            Serial.printf("  📱 ESP-NOW -> BLE Phone (delivering %d bytes)...\n", len);
            
            // Set nominal RSSI byte for phone distance estimation (-42 dBm typical 2.4GHz close range)
            frame[71] = (uint8_t)(-42);
            
            if (txCharacteristic != nullptr) {
                txCharacteristic->setValue(frame, len);
                bool notified = txCharacteristic->notify();
                if (notified) {
                    bleTxCount++;
                    Serial.println("  📲 BLE notification delivered to phone");
                } else {
                    Serial.println("  ⚠️ BLE notify returned false (phone not subscribed to notifications yet)");
                }
            }
        }
        
        // Mesh re-broadcasting rules:
        // 1. Never re-broadcast HELLO beacons (local discovery only).
        // 2. Never re-broadcast frames originated by our own phone.
        // 3. Re-broadcast only if packet has TTL remaining and is not strictly addressed to us.
        bool isHello = (type == FRAME_HELLO);
        bool fromOurPhone = phoneIdLearned && (memcmp(origin, connectedPhoneId, 16) == 0);

        if (!isHello && !fromOurPhone && frame[4] > 0 && (!isTargetedToUs || !deviceConnected)) {
            Serial.println("  🌐 Re-broadcasting on ESP-NOW mesh...");
            esp_err_t res = esp_now_send(broadcastMac, frame, len);
            if (res == ESP_OK) {
                espNowTxCount++;
                Serial.println("  ✅ Mesh re-broadcast sent");
            }
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
        Serial.printf("📱 Phone Connected via BLE (Address: %s, MTU: %d)\n",
                      connInfo.getAddress().toString().c_str(), connInfo.getMTU());
    }

    void onDisconnect(NimBLEServer* pServer, NimBLEConnInfo& connInfo, int reason) override {
        deviceConnected = false;
        digitalWrite(LED_PIN, LOW);
        memset(connectedPhoneId, 0, 16);
        Serial.printf("❌ Phone Disconnected (Reason: %d). Restarting BLE advertising...\n", reason);
        NimBLEDevice::startAdvertising();
    }
};

const size_t RX_BUFFER_SIZE = 2048;
uint8_t rxBuffer[RX_BUFFER_SIZE];
size_t rxBufferLen = 0;

class RXCallbacks : public NimBLECharacteristicCallbacks {
    void onWrite(NimBLECharacteristic* pCharacteristic, NimBLEConnInfo& connInfo) override {
        NimBLEAttValue val = pCharacteristic->getValue();
        size_t valLen = val.length();
        const uint8_t* valData = val.data();
        if (valLen == 0 || valData == nullptr) return;

        if (rxBufferLen + valLen > RX_BUFFER_SIZE) {
            Serial.println("  ⚠️ BLE buffer overflow, resetting");
            rxBufferLen = 0;
        }

        memcpy(rxBuffer + rxBufferLen, valData, valLen);
        rxBufferLen += valLen;

        while (rxBufferLen >= HEADER_SIZE) {
            // Find magic byte
            size_t magicIdx = 0;
            while (magicIdx < rxBufferLen && rxBuffer[magicIdx] != MAGIC_BYTE) {
                magicIdx++;
            }

            if (magicIdx > 0) {
                rxBufferLen -= magicIdx;
                memmove(rxBuffer, rxBuffer + magicIdx, rxBufferLen);
                if (rxBufferLen < HEADER_SIZE) break;
            }

            if (rxBuffer[1] != VERSION) {
                // Bad version, discard byte and resync
                rxBufferLen--;
                memmove(rxBuffer, rxBuffer + 1, rxBufferLen);
                continue;
            }

            uint16_t payloadLen = rxBuffer[69] | (rxBuffer[70] << 8);
            size_t totalFrameLen = HEADER_SIZE + payloadLen;

            if (totalFrameLen > RX_BUFFER_SIZE) {
                rxBufferLen--;
                memmove(rxBuffer, rxBuffer + 1, rxBufferLen);
                continue;
            }

            if (rxBufferLen < totalFrameLen) {
                // Incomplete frame, wait for more chunks
                break;
            }

            // Full frame ready
            routeFrame(rxBuffer, totalFrameLen, "BLE");

            rxBufferLen -= totalFrameLen;
            if (rxBufferLen > 0) {
                memmove(rxBuffer, rxBuffer + totalFrameLen, rxBufferLen);
            }
        }
    }
};

//----------------------------------------
// Interactive Serial Console & Diagnostics
//----------------------------------------
void printStatus() {
    uint8_t mac[6];
    esp_read_mac(mac, ESP_MAC_WIFI_STA);

    Serial.println();
    Serial.println("┌──────────────────────────────────────────────┐");
    Serial.println("│        RelayChat ESP32 (ESP-NOW Mode)        │");
    Serial.println("├──────────────────────────────────────────────┤");
    Serial.printf("│ Node ID:        ");
    printUuidShort(nodeId);
    Serial.println("...                         │");
    Serial.printf("│ Wi-Fi MAC:      %02X:%02X:%02X:%02X:%02X:%02X              │\n",
                  mac[0], mac[1], mac[2], mac[3], mac[4], mac[5]);
    Serial.printf("│ Wi-Fi Channel:  %d                            │\n", ESPNOW_WIFI_CHANNEL);
    Serial.printf("│ BLE State:      %-29s│\n", deviceConnected ? "CONNECTED 📱" : "WAITING / ADVERTISING 📡");
    Serial.printf("│ Phone ID:       ");
    if (isBroadcast(connectedPhoneId)) {
        Serial.println("NOT REGISTERED YET           │");
    } else {
        printUuidShort(connectedPhoneId);
        Serial.println("...                         │");
    }
    Serial.println("├──────────────────────────────────────────────┤");
    Serial.printf("│ Packet Stats:                                │\n");
    Serial.printf("│   ESP-NOW TX: %-6d  ESP-NOW RX: %-6d    │\n", espNowTxCount, espNowRxCount);
    Serial.printf("│   BLE     TX: %-6d  BLE     RX: %-6d    │\n", bleTxCount, bleRxCount);
    Serial.println("└──────────────────────────────────────────────┘");
    Serial.println();
}

void sendTestBeacon() {
    Serial.println("🚀 Sending ESP-NOW Test Beacon...");
    uint8_t testFrame[HEADER_SIZE + 14];
    memset(testFrame, 0, sizeof(testFrame));
    
    testFrame[0] = MAGIC_BYTE;
    testFrame[1] = VERSION;
    testFrame[2] = FRAME_HELLO;
    testFrame[3] = 0; // Hop
    testFrame[4] = 8; // TTL
    
    memcpy(testFrame + 5, nodeId, 16);  // Origin = Node
    memcpy(testFrame + 21, nodeId, 16); // Via = Node
    // Receiver = all 0s (Broadcast)
    
    // Generate random message ID
    for (int i = 0; i < 16; i++) testFrame[53 + i] = (uint8_t)random(0, 256);
    
    const char* beaconName = "ESP32_Now_Node";
    uint16_t plen = strlen(beaconName);
    testFrame[69] = (uint8_t)(plen & 0xFF);
    testFrame[70] = (uint8_t)((plen >> 8) & 0xFF);
    memcpy(testFrame + HEADER_SIZE, beaconName, plen);
    
    esp_err_t res = esp_now_send(broadcastMac, testFrame, sizeof(testFrame));
    if (res == ESP_OK) {
        espNowTxCount++;
        blinkLed(80);
        Serial.println("✅ Test Beacon sent over ESP-NOW!");
    } else {
        Serial.printf("❌ Send failed: %d\n", res);
    }
}

void handleSerialCommand() {
    if (!Serial.available()) return;
    char c = Serial.read();
    if (c == '\r' || c == '\n') return;
    
    switch (c) {
        case 't':
        case 'T':
            sendTestBeacon();
            break;
        case 's':
        case 'S':
            printStatus();
            break;
        case '?':
        case 'h':
        case 'H':
            Serial.println();
            Serial.println("Commands:");
            Serial.println("  t - Send ESP-NOW Test Beacon (checks RF between 2 nodes)");
            Serial.println("  s - Show node status and packet statistics");
            Serial.println("  ? - Show this help menu");
            Serial.println();
            break;
        default:
            break;
    }
}

//----------------------------------------
// Setup
//----------------------------------------
void setup() {
    Serial.begin(115200);
    
    pinMode(LED_PIN, OUTPUT);
    digitalWrite(LED_PIN, LOW);
    
    delay(500);
    generateNodeId();

    Serial.println();
    Serial.println("==================================================");
    Serial.println("   RelayChat ESP32 (High-Speed ESP-NOW Mode)      ");
    Serial.println("==================================================");

    // --- Wi-Fi & ESP-NOW Setup ---
    WiFi.mode(WIFI_STA);
    WiFi.disconnect();
    
    // Lock to Channel 1 for maximum stability
    esp_wifi_set_channel(ESPNOW_WIFI_CHANNEL, WIFI_SECOND_CHAN_NONE);

    if (esp_now_init() != ESP_OK) {
        Serial.println("❌ ESP-NOW init FAILED!");
        while (1) {
            digitalWrite(LED_PIN, !digitalRead(LED_PIN));
            delay(150);
        }
    }
    Serial.println("✅ ESP-NOW initialized (2.4 GHz High Speed, Zero Wiring)");

    esp_now_register_recv_cb(onDataRecv);

    // Add Broadcast Peer
    esp_now_peer_info_t peerInfo = {};
    memset(&peerInfo, 0, sizeof(peerInfo));
    memcpy(peerInfo.peer_addr, broadcastMac, 6);
    peerInfo.channel = ESPNOW_WIFI_CHANNEL;
    peerInfo.encrypt = false;

    if (esp_now_add_peer(&peerInfo) != ESP_OK) {
        Serial.println("❌ Failed to add broadcast peer!");
    } else {
        Serial.println("✅ ESP-NOW Broadcast peer registered (FF:FF:FF:FF:FF:FF)");
    }

    // --- NimBLE Setup ---
    NimBLEDevice::init(DEVICE_NAME);
    NimBLEDevice::setMTU(512);
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

    Serial.println("✅ BLE advertising started as 'RelayChat_ESP32'");
    Serial.println("--------------------------------------------------");
    Serial.println("Type 't' in Serial Monitor to send an ESP-NOW test beacon");
    Serial.println("Type 's' to view full node status");
    Serial.println("==================================================");
    printStatus();
}

//----------------------------------------
// Loop
//----------------------------------------
void loop() {
    handleSerialCommand();

    // Periodic Heartbeat every 10 seconds
    unsigned long now = millis();
    if (now - lastHeartbeat >= 10000) {
        lastHeartbeat = now;
        Serial.printf("[Heartbeat] BLE: %s | Phone: ", 
                      deviceConnected ? "Connected 📱" : "Advertising 📡");
        if (isBroadcast(connectedPhoneId)) {
            Serial.print("None");
        } else {
            printUuidShort(connectedPhoneId);
            Serial.print("...");
        }
        Serial.printf(" | ESP-NOW TX: %d, RX: %d\n", espNowTxCount, espNowRxCount);
    }
    
    delay(5); // Yield
}