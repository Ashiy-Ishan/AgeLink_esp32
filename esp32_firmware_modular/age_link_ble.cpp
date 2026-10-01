#include "age_link_ble.h"
#include "age_link_types.h"
#include "age_link_config.h"
#include "age_link_storage.h"
#include "age_link_hardware.h"

#include <BLEDevice.h>
#include <BLEUtils.h>
#include <BLEServer.h>

class AgeLinkServerCallbacks : public BLEServerCallbacks {
    void onConnect(BLEServer* pServer) override {
        deviceConnected = true;
        Serial.println(F("[BLE] Mobile client connected."));
    }

    void onDisconnect(BLEServer* pServer) override {
        deviceConnected = false;
        Serial.println(F("[BLE] Mobile client disconnected."));
        if (!configComplete) {
            BLEDevice::startAdvertising();
            Serial.println(F("[BLE] Restarted BLE advertising."));
        }
    }
};

class AgeLinkCharacteristicCallbacks : public BLECharacteristicCallbacks {
    void onWrite(BLECharacteristic *pCharacteristic) override {
        String value_arduino = pCharacteristic->getValue();
        std::string value_std = value_arduino.c_str();

        if (value_std.length() > 0) {
            Serial.println(F("****************************************"));
            Serial.println(F("[BLE] Provisioning Data Received:"));
            Serial.println(value_std.c_str());
            Serial.println(F("****************************************"));

            // Check for factory reset command
            if (value_std.find("delete_config") != std::string::npos) {
                Serial.println(F("[BLE] Factory Reset command recognized!"));
                updateLCD("RESETTING...", "Erasing files...");
                deleteConfigurationFiles();
                delay(2000);
                ESP.restart();
                return;
            }

            // Attempt to parse and save configuration
            if (saveConfiguration(value_std)) {
                Serial.println(F("[BLE] Configuration saved successfully!"));
                configComplete = true;
            } else {
                Serial.println(F("[BLE] ERROR: Failed to parse/save config from BLE."));
            }
        }
    }
};

void startBLEProvisioning() {
    Serial.println(F("[BLE] Starting BLE Provisioning Server..."));

    BLEDevice::init(BLE_DEVICE_NAME);
    BLEServer *pServer = BLEDevice::createServer();
    pServer->setCallbacks(new AgeLinkServerCallbacks());

    BLEService *pService = pServer->createService(BLE_SERVICE_UUID);

    BLECharacteristic *pCharacteristic = pService->createCharacteristic(
        BLE_CHARACTERISTIC_UUID,
        BLECharacteristic::PROPERTY_WRITE
    );
    pCharacteristic->setCallbacks(new AgeLinkCharacteristicCallbacks());

    pService->start();

    BLEAdvertising *pAdvertising = BLEDevice::getAdvertising();
    pAdvertising->addServiceUUID(BLE_SERVICE_UUID);
    pAdvertising->setScanResponse(true);
    pAdvertising->setMinPreferred(0x06);
    pAdvertising->setMinPreferred(0x12);
    BLEDevice::startAdvertising();

    Serial.println(F("[BLE] Server active. Advertising as AgeLink-Setup..."));
}

void runBLEProvisioningMode() {
    Serial.println(F("[PROVISIONING] Entering Provisioning Mode. Awaiting BLE config..."));
    updateLCD("App Setup Req.", "Open AgeLink App");
    startBLEProvisioning();

    unsigned long lastBlinkToggle = millis();
    bool ledState = false;

    while (!configComplete) {
        if (millis() - lastBlinkToggle >= 800) {
            lastBlinkToggle = millis();
            ledState = !ledState;
            setLEDs(ledState, ledState, ledState);
        }
        delay(20); // Yield to FreeRTOS watchdog
    }

    setLEDs(false, false, false);
    Serial.println(F("[PROVISIONING] Config received! Restarting device in 3s..."));
    updateLCD("Config Received", "Restarting...");
    delay(3000);
    ESP.restart();
}
