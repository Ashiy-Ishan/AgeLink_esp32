#include "age_link_network.h"
#include "age_link_types.h"
#include "age_link_config.h"
#include "age_link_storage.h"
#include "age_link_hardware.h"
#include "age_link_audio.h"
#include "age_link_scheduler.h"

#include <addons/TokenHelper.h>

// Firebase Objects Definition
FirebaseData fbdo;
FirebaseConfig fbConfig;
FirebaseAuth fbAuth;

void initWiFi() {
    Serial.print(F("[WIFI] Connecting to SSID: "));
    Serial.println(wifi_ssid);
    updateLCD("Connecting WiFi", wifi_ssid);

    WiFi.begin(wifi_ssid.c_str(), wifi_password.c_str());

    unsigned long wifiConnectStart = millis();
    while (WiFi.status() != WL_CONNECTED && (millis() - wifiConnectStart < WIFI_CONNECT_TIMEOUT_MS)) {
        delay(500);
        Serial.print(F("."));
    }
    Serial.println();

    if (WiFi.status() == WL_CONNECTED) {
        Serial.println(F("[WIFI] Connected successfully!"));
        offlineMode = false;
    } else {
        Serial.println(F("[WIFI] Connection failed. Entering OFFLINE MODE."));
        offlineMode = true;
    }
}

void handleWiFiReconnect() {
    if (WiFi.status() != WL_CONNECTED) {
        offlineMode = true;

        if (millis() - lastWifiCheck > WIFI_RETRY_INTERVAL_MS) {
            Serial.println(F("[WIFI] Connection lost. Attempting non-blocking reconnect..."));

            if (Firebase.ready() && !rtdb_device_path.isEmpty()) {
                Firebase.setBool(fbdo, rtdb_device_path + "/device_active", false);
            }

            updateLCD("WiFi LOST", "SOS Only Mode");

            if (!loadContactsFromFile()) {
                contacts[0].name  = "Emergency";
                contacts[0].phone = "0763777417";
                contactCount      = 1;
                Serial.println(F("[WIFI] Using FALLBACK emergency contact in offline mode."));
            }

            WiFi.reconnect();
            lastWifiCheck = millis();
        }
    } else if (WiFi.status() == WL_CONNECTED && offlineMode) {
        Serial.println(F("[WIFI] Connection restored! Transitioning to ONLINE MODE."));
        offlineMode   = false;
        lastWifiCheck = millis();

        if (Firebase.ready() && !rtdb_device_path.isEmpty()) {
            Firebase.setBool(fbdo, rtdb_device_path + "/device_active", true);
            Firebase.setString(fbdo, rtdb_device_path + "/device_id", hardcoded_device_id);
        }

        playWavFile(SOUND_WIFI_CONNECTED);
        updateLCD("WiFi Connected", "NTP Sync...");

        waitForAudioToFinish(5000);

        initNTP();
        fetchEmergencyContact();
        saveContactsToFile();
        checkScheduledTime(getCurrentTimeFormatted());
    }
}

void initNTP() {
    configTime(GMT_OFFSET_SEC, DAYLIGHT_OFFSET_SEC, NTP_SERVER);
    Serial.println(F("[NTP] Synchronizing system clock with NTP server..."));

    while (!getLocalTime(&timeinfo)) {
        Serial.print(F("."));
        audioLoop();
        delay(500);
    }
    Serial.println(F("\n[NTP] Time synchronization completed successfully."));
}

bool updateLocalTime() {
    return getLocalTime(&timeinfo);
}

String getCurrentTimeFormatted() {
    char timeStr[6]; // Format: "HH:MM\0"
    strftime(timeStr, sizeof(timeStr), "%H:%M", &timeinfo);
    return String(timeStr);
}

void initFirebase() {
    Serial.println(F("[FIREBASE] Initializing Realtime Database connection..."));
    fbConfig.host = firebase_host;
    fbConfig.signer.tokens.legacy_token = firebase_auth.c_str();

    Firebase.begin(&fbConfig, &fbAuth);
    Firebase.reconnectWiFi(true);

    if (WiFi.status() == WL_CONNECTED && !rtdb_device_path.isEmpty()) {
        Firebase.setBool(fbdo, rtdb_device_path + "/device_active", true);
        Firebase.setString(fbdo, rtdb_device_path + "/device_id", hardcoded_device_id);
    }
}

void fetchDeviceSettings() {
    if (offlineMode) return;

    stopAudio();

    if (Firebase.getString(fbdo, rtdb_device_path)) {
        if (fbdo.dataType() == "json") {
            FirebaseJson json = fbdo.jsonString();
            FirebaseJsonData result;

            if (json.get(result, FPSTR("volume"))) {
                if (result.type == "float" || result.type == "int" || result.type == "double") {
                    float newVolume = result.floatValue;
                    if (newVolume < 0.0f) newVolume = 0.0f;
                    if (newVolume > 1.0f) newVolume = 1.0f;

                    if (abs(newVolume - currentVolume) > 0.01f) {
                        setAudioVolume(newVolume);
                        Serial.print(F("[FIREBASE] New audio volume applied: "));
                        Serial.println(currentVolume);
                    }
                }
            }
        }
    } else {
        Serial.print(F("[FIREBASE] Warning reading device settings: "));
        Serial.println(fbdo.errorReason());
    }
}

void fetchEmergencyContact() {
    Serial.println(F("[FIREBASE] Fetching emergency contacts..."));
    contactCount = 0;

    if (offlineMode) {
        if (!loadContactsFromFile()) {
            contacts[0].name  = "Emergency";
            contacts[0].phone = "0763777417";
            contactCount      = 1;
            Serial.println(F("[FIREBASE] Offline fallback contact loaded."));
        }
        return;
    }

    stopAudio();

    if (Firebase.getString(fbdo, rtdb_emergency_path)) {
        if (fbdo.dataType() == "json") {
            FirebaseJson json = fbdo.jsonString();
            size_t len = json.iteratorBegin();
            FirebaseJsonData result;

            for (size_t i = 0; i < len && contactCount < MAX_CONTACTS; i++) {
                String key, value;
                int type = 0;
                json.iteratorGet(i, type, key, value);

                FirebaseJson tempJson;
                tempJson.setJsonData(value);

                String tempPhone, tempName;
                if (tempJson.get(result, FPSTR("phone"))) {
                    tempPhone = result.stringValue;
                    tempPhone.trim();
                }
                if (tempJson.get(result, FPSTR("name"))) {
                    tempName = result.stringValue;
                    tempName.trim();
                }

                if (tempPhone.length() > 6 && !tempName.isEmpty()) {
                    contacts[contactCount].name  = tempName;
                    contacts[contactCount].phone = tempPhone;
                    Serial.print(F("[FIREBASE] Contact loaded: "));
                    Serial.print(tempName);
                    Serial.print(F(" -> "));
                    Serial.println(tempPhone);
                    contactCount++;
                }
            }
            json.iteratorEnd();
        }
    } else {
        Serial.print(F("[FIREBASE] Failed to read emergency contacts: "));
        Serial.println(fbdo.errorReason());
        loadContactsFromFile();
    }

    if (contactCount == 0) {
        contacts[0].name  = "Emergency";
        contacts[0].phone = "0763777417";
        contactCount      = 1;
        saveContactsToFile();
    }
}

bool checkScheduledTime(const String& currentTime) {
    if (currentState != IDLE && currentState != MISSED) {
        return false;
    }

    if (offlineMode) {
        return false;
    }

    Serial.print(F("[SCHEDULE] Checking schedule for time: "));
    Serial.println(currentTime);

    // Keep server last_sync timestamp updated
    Firebase.setString(fbdo, rtdb_device_path + "/last_sync", currentTime);

    stopAudio();

    String path = rtdb_schedule_path + "/med_times";
    String nextTimeToday = "25:00";
    String earliestTimeOverall = "25:00";
    String nextNameToday = "None";
    String earliestNameOverall = "None";
    bool alarmTriggered = false;

    if (Firebase.getString(fbdo, path)) {
        // Save periodic offline backup of schedule
        if (millis() - lastScheduleSaveTime > SCHEDULE_SAVE_INTERVAL_MS) {
            saveScheduleToFile(fbdo.stringData());
            lastScheduleSaveTime = millis();
        }

        if (fbdo.dataType() == "json") {
            FirebaseJson json = fbdo.jsonString();
            size_t len = json.iteratorBegin();
            FirebaseJsonData result;

            for (size_t i = 0; i < len; i++) {
                String key, value;
                int type = 0;
                json.iteratorGet(i, type, key, value);

                FirebaseJson tempJson;
                tempJson.setJsonData(value);

                String medicineTime, medicineName;
                if (tempJson.get(result, FPSTR("time")) && result.type == "string") {
                    medicineTime = result.stringValue;
                    medicineTime.trim();
                    if (medicineTime.length() == 4 && medicineTime[1] == ':') {
                        medicineTime = "0" + medicineTime;
                    }
                }

                if (tempJson.get(result, FPSTR("name"))) {
                    medicineName = result.stringValue;
                    medicineName.trim();
                }

                if (medicineTime.isEmpty()) continue;

                if (medicineTime < earliestTimeOverall) {
                    earliestTimeOverall = medicineTime;
                    earliestNameOverall = medicineName;
                }

                if (medicineTime > currentTime && medicineTime < nextTimeToday) {
                    nextTimeToday = medicineTime;
                    nextNameToday = medicineName;
                }

                if (currentTime.equals(medicineTime) && !alarmTriggered && (currentTime != lastConfirmedTime)) {
                    Serial.println(F("*************************************************"));
                    Serial.println(F("[SCHEDULE] ALARM TRIGGERED! MATCHING TIME FOUND!"));
                    Serial.println(F("*************************************************"));

                    currentMedicineName = medicineName;
                    currentState        = GREEN_ACTIVE;
                    stateChangeTime     = millis();
                    startAlarmSequence(GREEN_ACTIVE);

                    Firebase.setString(fbdo, rtdb_schedule_path + "/current_status", "ACTIVE");
                    alarmTriggered = true;
                }
            }
            json.iteratorEnd();

            if (nextTimeToday != "25:00") {
                nextMedicineTime = nextTimeToday;
                nextMedicineName = nextNameToday;
            } else if (earliestTimeOverall != "25:00") {
                nextMedicineTime = earliestTimeOverall;
                nextMedicineName = earliestNameOverall;
            } else {
                nextMedicineTime = "--:--";
                nextMedicineName = "None";
            }

            Serial.print(F("[SCHEDULE] Next med: "));
            Serial.print(nextMedicineName);
            Serial.print(F(" ("));
            Serial.print(nextMedicineTime);
            Serial.println(F(")"));

            if (alarmTriggered) {
                return true;
            }
        }
    } else {
        Serial.print(F("[SCHEDULE] Error reading med_times: "));
        Serial.println(fbdo.errorReason());
    }

    return false;
}

void handleConfirmation(const String& state) {
    playWavFile(SOUND_MEDICINE_CONFIRM);

    unsigned long confirmStart = millis();
    while (millis() - confirmStart < 2000) {
        audioLoop();
        delay(40);
    }
    stopAudio();

    FirebaseJson confirmationJson;
    confirmationJson.set("confirmed_at", getCurrentTimeFormatted());
    confirmationJson.set("medicine_name", currentMedicineName);
    confirmationJson.set("reminder_state", state);
    confirmationJson.set("confirmed_at_timestamp/.sv", "timestamp");

    lastConfirmedTime = getCurrentTimeFormatted();

    if (Firebase.push(fbdo, rtdb_confirm_path, confirmationJson)) {
        Serial.print(F("[FIREBASE] Confirmation pushed successfully. State: "));
        Serial.println(state);
        Firebase.setString(fbdo, rtdb_schedule_path + "/current_status", "CONFIRMED");
        updateLCD("Confirmation:", "RECEIVED!");
    } else {
        Serial.print(F("[FIREBASE] Failed pushing confirmation: "));
        Serial.println(fbdo.errorReason());
    }
}

void handleMissed(const String& medicineName) {
    Serial.println(F("[FIREBASE] Logging MISSED dose event..."));
    stopAudio();

    FirebaseJson missedJson;
    missedJson.set("confirmed_at", getCurrentTimeFormatted());
    missedJson.set("medicine_name", medicineName);
    missedJson.set("reminder_state", "MISSED");
    missedJson.set("confirmed_at_timestamp/.sv", "timestamp");

    if (Firebase.push(fbdo, rtdb_confirm_path, missedJson)) {
        Serial.println(F("[FIREBASE] MISSED dose event logged to Firebase."));
        Firebase.setString(fbdo, rtdb_schedule_path + "/current_status", "MISSED");
    } else {
        Serial.print(F("[FIREBASE] Failed pushing missed status: "));
        Serial.println(fbdo.errorReason());
    }

    playWavFile(SOUND_MEDICINE_MISSED);
}
