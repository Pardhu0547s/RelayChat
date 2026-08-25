#include <NimBLEDevice.h>

#define DEVICE_NAME "RelayChat_ESP32"

// UUIDs
#define SERVICE_UUID        "6E400001-B5A3-F393-E0A9-E50E24DCCA9E"
#define CHARACTERISTIC_RX   "6E400002-B5A3-F393-E0A9-E50E24DCCA9E"
#define CHARACTERISTIC_TX   "6E400003-B5A3-F393-E0A9-E50E24DCCA9E"

NimBLECharacteristic* txCharacteristic;

// Client connection status
bool deviceConnected = false;

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

class RXCallbacks : public NimBLECharacteristicCallbacks {

    void onWrite(NimBLECharacteristic* pCharacteristic, NimBLEConnInfo& connInfo) override {

        std::string value = pCharacteristic->getValue();

        if (!value.empty()) {

            Serial.print("Received: ");
            Serial.println(value.c_str());

            String reply = "ACK: ";
            reply += value.c_str();

            txCharacteristic->setValue(reply.c_str());
            txCharacteristic->notify();

            Serial.print("Sent: ");
            Serial.println(reply);
        }
    }
};
//----------------------------------------
// Setup
//----------------------------------------

void setup() {

    Serial.begin(115200);

    Serial.println();
    Serial.println("===============================");
    Serial.println(" RelayChat ESP32");
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