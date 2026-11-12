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

        initNTP();
    }
}

void initNTP() {
    configTime(GMT_OFFSET_SEC, DAYLIGHT_OFFSET_SEC, NTP_SERVER);
    Serial.println(F("[NTP] Requested time synchronization."));
}

bool updateLocalTime() {
    return getLocalTime(&timeinfo, 0);
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

    if (Firebase.get(fbdo, rtdb_device_path)) {
        if (fbdo.dataType() == "json") {
            FirebaseJson json;
            json.setJsonData(fbdo.jsonString());
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
    if (Firebase.get(fbdo, rtdb_emergency_path)) {
        contactCount = 0;
        if (fbdo.dataType() == "json") {
            FirebaseJson json;
            json.setJsonData(fbdo.jsonString());
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
        saveContactsToFile();
    } else {
        Serial.print(F("[FIREBASE] Failed to read emergency contacts: "));
        Serial.println(fbdo.errorReason());
    }
}

bool checkScheduledTime(const String& currentTime) {
    if (currentState != IDLE && currentState != MISSED) {
        return false;
    }

    static String schedule = loadScheduleFromFile();
    static time_t lastAlarmMinute = -1;
    const bool cloudReady = !offlineMode && Firebase.ready();

    if (cloudReady) {
        Firebase.setString(fbdo, rtdb_device_path + "/last_sync", currentTime);
        if (Firebase.get(fbdo, rtdb_schedule_path + "/med_times")) {
            const String downloaded = fbdo.dataType() == "json" ? fbdo.jsonString() : String("{}");
            if (downloaded != schedule && saveScheduleToFile(downloaded)) {
                Serial.println(F("[SCHEDULE] Updated offline backup."));
            }
            schedule = downloaded;
        }
    }

    FirebaseJson json;
    if (!schedule.isEmpty()) {
        json.setJsonData(schedule);
    }
    size_t count = json.iteratorBegin();
    String earliestTime = "25:00";
    String earliestName = "None";
    String nextTime = "25:00";
    String nextName = "None";
    const time_t currentMinute = time(nullptr) / 60;
    bool alarmTriggered = false;

    for (size_t i = 0; i < count; i++) {
        String key, value;
        int type = 0;
        json.iteratorGet(i, type, key, value);
        FirebaseJson entry;
        entry.setJsonData(value);
        FirebaseJsonData result;
        if (!entry.get(result, "time") || result.type != "string") {
            continue;
        }
        String medicineTime = result.stringValue;
        medicineTime.trim();
        if (medicineTime.length() == 4 && medicineTime[1] == ':') {
            medicineTime = "0" + medicineTime;
        }
        if (medicineTime.length() != 5 || medicineTime[2] != ':' ||
            !isDigit(medicineTime[0]) || !isDigit(medicineTime[1]) ||
            !isDigit(medicineTime[3]) || !isDigit(medicineTime[4]) ||
            medicineTime.substring(0, 2).toInt() > 23 ||
            medicineTime.substring(3).toInt() > 59) {
            continue;
        }
        String medicineName = entry.get(result, "name") ? result.stringValue : String("Medicine");
        medicineName.trim();

        if (medicineTime < earliestTime) {
            earliestTime = medicineTime;
            earliestName = medicineName;
        }
        if (medicineTime > currentTime && medicineTime < nextTime) {
            nextTime = medicineTime;
            nextName = medicineName;
        }
        if (medicineTime == currentTime && currentMinute != lastAlarmMinute) {
            currentMedicineName = medicineName;
            currentState = GREEN_ACTIVE;
            stateChangeTime = millis();
            lastAlarmMinute = currentMinute;
            alarmTriggered = true;
            startAlarmSequence(GREEN_ACTIVE);
        }
    }
    json.iteratorEnd();

    nextMedicineTime = nextTime != "25:00" ? nextTime : earliestTime;
    nextMedicineName = nextTime != "25:00" ? nextName : earliestName;
    if (nextMedicineTime == "25:00") {
        nextMedicineTime = "--:--";
    }

    if (alarmTriggered && cloudReady) {
        Firebase.setString(fbdo, rtdb_schedule_path + "/current_status", "ACTIVE");
    }
    return alarmTriggered;
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

    updateLCD("Confirmation:", "RECEIVED!");
    if (offlineMode || !Firebase.ready()) {
        return;
    }

    if (Firebase.push(fbdo, rtdb_confirm_path, confirmationJson)) {
        Serial.print(F("[FIREBASE] Confirmation pushed successfully. State: "));
        Serial.println(state);
        Firebase.setString(fbdo, rtdb_schedule_path + "/current_status", "CONFIRMED");
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

    if (!offlineMode && Firebase.ready()) {
        if (Firebase.push(fbdo, rtdb_confirm_path, missedJson)) {
            Serial.println(F("[FIREBASE] MISSED dose event logged to Firebase."));
            Firebase.setString(fbdo, rtdb_schedule_path + "/current_status", "MISSED");
        } else {
            Serial.print(F("[FIREBASE] Failed pushing missed status: "));
            Serial.println(fbdo.errorReason());
        }
    }

    playWavFile(SOUND_MEDICINE_MISSED);
}
