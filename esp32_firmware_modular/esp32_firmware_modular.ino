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

    // 4. Initialize LCD Display
    initLCD();
    updateLCD("System Booting", "Loading Config...");
    delay(1000);

    // 5. Load Stored Credentials & Configuration
    if (loadConfiguration()) {
        Serial.println(F("[SETUP] Configuration loaded successfully from LittleFS."));
        updateLCD("Config OK", "SIM800L Init...");
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

    // 9. Online Initialization Sequence
    if (!offlineMode) {
        playWavFile(SOUND_POWER_UP);
        playWavFile(SOUND_WIFI_CONNECTED);
        updateLCD("WiFi Connected", "NTP Sync...");

        waitForAudioToFinish(5000);

        initNTP();
        updateLCD("Time Sync OK", "Data Fetching...");

        fetchEmergencyContact();
        saveContactsToFile();

        Serial.println(F("[SETUP] Performing initial schedule evaluation..."));
        checkScheduledTime(getCurrentTimeFormatted());
        updateLCD("Ready!", "Next: " + nextMedicineTime);
    } else {
        // Fallback for offline mode
        updateLCD("OFFLINE MODE", "SOS Only");
        if (!loadContactsFromFile()) {
            contacts[0].name  = "Emergency";
            contacts[0].phone = "0763777417";
            contactCount      = 1;
            Serial.println(F("[SETUP] Fallback offline emergency contact activated."));
        }
    }

    delay(1500);
}

void loop() {
    // 0. Hardware Lock during factory reset wipe
    if (isResetting) {
        return;
    }

    // 1. Process Audio Pipeline (Highest non-blocking priority)
    audioLoop();

    // 2. Wi-Fi Status Check & Background Reconnection
    handleWiFiReconnect();

    // 3. OFFLINE MODE Execution Branch
    if (offlineMode) {
        updateLCD("OFFLINE MODE", "SOS Only");
        checkSosButton();
        delay(40);
        return;
    }

    // 4. ONLINE MODE Execution Branch
    if (!Firebase.ready()) {
        delay(500);
        return;
    }

    // Update local clock time
    if (!updateLocalTime()) {
        return;
    }

    String currentTime = getCurrentTimeFormatted();

    // Periodic time logging
    if (millis() - lastTimeLog >= TIME_LOG_INTERVAL_MS) {
        lastTimeLog = millis();
    }

    // 5. Update Idle / Missed Screen on LCD
    if (currentState == IDLE || currentState == MISSED) {
        if (currentState == MISSED) {
            updateLCD("Medication", "MISSED!");
        } else {
            String volStr = "Vol:" + String((int)(currentVolume * 100));
            String line1  = currentTime;
            while (line1.length() + volStr.length() < LCD_COLUMNS) {
                line1 += " ";
            }
            line1 += volStr;
            String line2  = nextMedicineName + ":" + nextMedicineTime;
            updateLCD(line1, line2);
        }
    }

    // 6. Reminder State Machine & Ingestion Timers
    runSchedulerStateMachine();

    // 7. Check Emergency SOS Button
    checkSosButton();

    delay(40);
}
