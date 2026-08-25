#include <NimBLEDevice.h>
#include <ArduinoJson.h>
#include "esp_mac.h"

#define DEVICE_NAME "RelayChat_ESP32"

// UUIDs
#define SERVICE_UUID        "6E400001-B5A3-F393-E0A9-E50E24DCCA9E"
#define CHARACTERISTIC_RX   "6E400002-B5A3-F393-E0A9-E50E24DCCA9E"
#define CHARACTERISTIC_TX   "6E400003-B5A3-F393-E0A9-E50E24DCCA9E"

NimBLECharacteristic* txCharacteristic;

// Client connection status
bool deviceConnected = false;
String nodeId = "";

String generateNodeId() {
    uint8_t mac[6];
    esp_read_mac(mac, ESP_MAC_WIFI_STA);
    char id[15];
    sprintf(id, "RC_%02X%02X%02X", mac[3], mac[4], mac[5]);
    return String(id);
}

//----------------------------------------
// Server Callbacks
//----------------------------------------

class ServerCallbacks : public NimBLEServerCallbacks {

    void onConnect(NimBLEServer* pServer, NimBLEConnInfo& connInfo) override {
        deviceConnected = true;
        Serial.println("📱 Phone Connected");
    }

    void onDisconnect(NimBLEServer* pServer, NimBLEConnInfo& connInfo, int reason) override {
        deviceConnected = false;
        Serial.println("❌ Phone Disconnected");

        NimBLEDevice::startAdvertising();
        Serial.println("📡 Advertising Restarted");
    }
};

//----------------------------------------
// RX Callback
//----------------------------------------

std::string rxBuffer = "";

class RXCallbacks : public NimBLECharacteristicCallbacks {

    void onWrite(NimBLECharacteristic* pCharacteristic, NimBLEConnInfo& connInfo) override {

        std::string value = pCharacteristic->getValue();

        if (!value.empty()) {
            rxBuffer += value;

            // Try to parse the buffer as a complete JSON object
            JsonDocument doc;
            DeserializationError error = deserializeJson(doc, rxBuffer.c_str());

            if (error == DeserializationError::IncompleteInput) {
                // The JSON is cut off (BLE MTU chunking). Wait for the next chunk.
                return;
            } else if (error) {
                Serial.print("❌ JSON Parse Failed: ");
                Serial.println(error.c_str());
                rxBuffer.clear(); // Bad data, drop the buffer
                return;
            }

            // We successfully parsed a complete JSON object!
            Serial.print("Received: ");
            Serial.println(rxBuffer.c_str());
            rxBuffer.clear(); // Clear buffer for next message

            const char* msgType = doc["type"] | "";
            const char* msgId = doc["id"] | "";
            const char* sender = doc["sender"] | "";

            // If it's a text message, acknowledge it
            if (strcmp(msgType, "text") == 0) {
                JsonDocument replyDoc;
                replyDoc["version"] = 1;
                replyDoc["id"] = msgId; 
                replyDoc["type"] = "ack";
                replyDoc["status"] = "received";
                replyDoc["sender"] = nodeId;
                replyDoc["receiver"] = sender;
                replyDoc["timestamp"] = doc["timestamp"]; // Echo the exact timestamp from the phone

                String replyStr;
                serializeJson(replyDoc, replyStr);

                txCharacteristic->setValue(replyStr.c_str());
                txCharacteristic->notify();

                Serial.print("Sent ACK: ");
                Serial.println(replyStr);
            }
            // If it's a status request, reply with node info
            else if (strcmp(msgType, "status") == 0) {
                JsonDocument replyDoc;
                replyDoc["version"] = 1;
                replyDoc["type"] = "status";
                replyDoc["nodeId"] = nodeId;
                replyDoc["deviceName"] = "RelayChat ESP32";
                replyDoc["firmware"] = "1.0.0";
                replyDoc["hardware"] = "ESP32-WROOM-32";
                replyDoc["protocol"] = 1;
                
                JsonArray capabilities = replyDoc["capabilities"].to<JsonArray>();
                capabilities.add("BLE");
                
                String replyStr;
                serializeJson(replyDoc, replyStr);

                txCharacteristic->setValue(replyStr.c_str());
                txCharacteristic->notify();

                Serial.print("Sent Status: ");
                Serial.println(replyStr);
            }
        }
    }
};
//----------------------------------------
// Setup
//----------------------------------------

void setup() {

    Serial.begin(115200);

    nodeId = generateNodeId();

    Serial.println();
    Serial.println("===============================");
    Serial.print(" RelayChat ESP32 (");
    Serial.print(nodeId);
    Serial.println(")");
    Serial.println("===============================");

    NimBLEDevice::init(DEVICE_NAME);

    NimBLEServer* server = NimBLEDevice::createServer();
    server->setCallbacks(new ServerCallbacks());

    NimBLEService* service =
        server->createService(SERVICE_UUID);

    //------------------------------------
    // TX Characteristic
    //------------------------------------

    txCharacteristic =
        service->createCharacteristic(
            CHARACTERISTIC_TX,
            NIMBLE_PROPERTY::NOTIFY
        );

    //------------------------------------
    // RX Characteristic
    //------------------------------------

    NimBLECharacteristic* rxCharacteristic =
        service->createCharacteristic(
            CHARACTERISTIC_RX,
            NIMBLE_PROPERTY::WRITE |
            NIMBLE_PROPERTY::WRITE_NR
        );

    rxCharacteristic->setCallbacks(new RXCallbacks());

    service->start();

    NimBLEAdvertising* advertising =
        NimBLEDevice::getAdvertising();

    advertising->addServiceUUID(SERVICE_UUID);
    advertising->start();

    Serial.println("BLE Advertising Started");
    Serial.println("Waiting for phone...");
}

void loop() {

}