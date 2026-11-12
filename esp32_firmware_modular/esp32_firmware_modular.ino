/**
 * @file esp32_firmware_modular.ino
 * @brief AgeLink ESP32 Medication Reminder & Emergency SOS System
 * @version 2.0 (Refactored & Modular Architecture)
 */

#include <Arduino.h>

#include "age_link_config.h"
#include "age_link_types.h"
#include "age_link_storage.h"
#include "age_link_hardware.h"
#include "age_link_audio.h"
#include "age_link_ble.h"
#include "age_link_sim.h"
#include "age_link_network.h"
#include "age_link_scheduler.h"

void setup() {
    // 0. Initialize Serial Debug Console
    Serial.begin(SERIAL_DEBUG_BAUD);
    delay(200);
    printSystemConfig();

    // 1. Initialize GPIO, LEDs, and Buttons
    initHardware();

    // 2. Initialize LittleFS File System
    if (!initStorage()) {
        Serial.println(F("[SETUP] LittleFS initialization encountered errors."));
        delay(2000);
    }
    printStorageFiles();

    // 3. Initialize I2S Audio Driver
    initAudio();

    // 4. Initialize the OLED
    initOLED();
    showOLED("AGELINK", "Starting", "Loading settings");
    delay(1000);

    // 5. Load Stored Credentials & Configuration
    if (loadConfiguration()) {
        Serial.println(F("[SETUP] Configuration loaded successfully from LittleFS."));
        showOLED("AGELINK", "Starting", "Checking modem");
    } else {
        Serial.println(F("[SETUP] Configuration missing or invalid. Launching BLE Provisioning..."));
        runBLEProvisioningMode();
        // Control does not reach here as ESP.restart() is called upon receiving config
    }

    // 6. Initialize SIM800L Cellular Modem
    initSIM();

    // 7. Initialize Wi-Fi Connection
    initWiFi();

    // 8. Initialize Firebase RTDB Connection
    initFirebase();

    loadContactsFromFile();
    initNTP();
    playWavFile(offlineMode ? SOUND_POWER_UP : SOUND_WIFI_CONNECTED);
}

void loop() {
    if (isResetting) {
        return;
    }

    audioLoop();
    checkSosButton();
    handleWiFiReconnect();

    static bool contactsSynced = false;
    if (offlineMode || !Firebase.ready()) {
        contactsSynced = false;
    } else if (!contactsSynced) {
        fetchEmergencyContact();
        contactsSynced = true;
    }

    if (!updateLocalTime()) {
        showOLED("CLOCK NOT SET", "Waiting", "Connect to Wi-Fi", "SOS available");
        checkFactoryResetButton();
        delay(40);
        return;
    }

    String currentTime = getCurrentTimeFormatted();

    // Periodic time logging
    if (millis() - lastTimeLog >= TIME_LOG_INTERVAL_MS) {
        lastTimeLog = millis();
    }

    if (currentState == IDLE) {
        const bool wifiConnected = WiFi.status() == WL_CONNECTED;
        showHomeOLED(currentTime, nextMedicineTime, nextMedicineName,
                     wifiConnected, wifiConnected ? WiFi.RSSI() : 0);
    } else if (currentState == MISSED) {
        showOLED("DOSE MISSED", "No response", currentMedicineName);
    }

    // 6. Reminder State Machine & Ingestion Timers
    runSchedulerStateMachine();

    delay(40);
}
