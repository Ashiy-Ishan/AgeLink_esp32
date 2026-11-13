#include "age_link_network.h"
#include "age_link_types.h"
#include "age_link_config.h"
#include "age_link_storage.h"
#include "age_link_hardware.h"
#include "age_link_audio.h"
#include "age_link_scheduler.h"

#include <addons/TokenHelper.h>
#include <ArduinoJson.h>
#include <algorithm>
#include <deque>
#include <sys/time.h>
#include <vector>

// Firebase Objects Definition
FirebaseData fbdo;
FirebaseConfig fbConfig;
FirebaseAuth fbAuth;

struct ScheduledDose {
    String key;
    String name;
    String dosage;
    String time;
    String date;
    time_t dueMinute;
    std::vector<String> nearbyLabels;
};

static ScheduledDose activeDose;
static std::deque<ScheduledDose> pendingDoses;
static constexpr int NEARBY_DOSE_MINUTES = 10;

static int minutesSinceMidnight(const String& time) {
    return time.substring(0, 2).toInt() * 60 + time.substring(3).toInt();
}
static constexpr time_t EARLIEST_VALID_TIME = 1704067200; // 2024-01-01 UTC
static constexpr unsigned long CLOCK_SYNC_WAIT_MS = 15000;
static constexpr unsigned long CLOCK_RETRY_INTERVAL_MS = 60000;
static unsigned long ntpStartedAt = 0;
static unsigned long clockFallbackAt = 0;
static bool triedClockFallback = false;

void initWiFi() {
    Serial.print(F("[WIFI] Connecting to SSID: "));
    Serial.println(wifi_ssid);
    showOLED("WI-FI", "Connecting", wifi_ssid);

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

        initNTP();

        if (Firebase.ready() && !rtdb_device_path.isEmpty()) {
            Firebase.setBool(fbdo, rtdb_device_path + "/device_active", true);
            Firebase.setString(fbdo, rtdb_device_path + "/device_id", hardcoded_device_id);
        }

        playWavFile(SOUND_WIFI_CONNECTED);
        showOLED("WI-FI", "Connected", "Syncing clock");

    }
}

void initNTP() {
    configTime(GMT_OFFSET_SEC, DAYLIGHT_OFFSET_SEC, NTP_SERVER,
               "time.google.com", "time.cloudflare.com");
    ntpStartedAt = millis();
    triedClockFallback = false;
    Serial.println(F("[CLOCK] Requested network time from three NTP servers."));
}

bool updateLocalTime() {
    const time_t now = time(nullptr);
    return now >= EARLIEST_VALID_TIME && localtime_r(&now, &timeinfo) != nullptr;
}

bool clockSyncDelayed() {
    return millis() - ntpStartedAt >= CLOCK_SYNC_WAIT_MS;
}

void retryClockSync() {
    if (WiFi.status() != WL_CONNECTED || !clockSyncDelayed() ||
        (triedClockFallback && millis() - clockFallbackAt < CLOCK_RETRY_INTERVAL_MS)) {
        return;
    }

    triedClockFallback = true;
    Serial.println(F("[CLOCK] NTP still pending. Trying Firebase server time."));
    if (!rtdb_device_path.isEmpty() && Firebase.ready()) {
        if (Firebase.setTimestamp(fbdo, rtdb_device_path + "/clock_sync_ms")) {
            const double milliseconds = fbdo.doubleData();
            if (milliseconds >= EARLIEST_VALID_TIME * 1000.0 &&
                milliseconds < 4102444800000.0) { // 2100-01-01 UTC
                const timeval serverTime = {static_cast<time_t>(milliseconds / 1000.0), 0};
                // NTP may have completed while Firebase was responding.
                if (!updateLocalTime() && settimeofday(&serverTime, nullptr) == 0) {
                    Serial.println(F("[CLOCK] Synchronized using Firebase server time."));
                }
            }
        } else {
            Serial.print(F("[CLOCK] Firebase time request failed: "));
            Serial.println(fbdo.errorReason());
        }
    }
    clockFallbackAt = millis();
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
    fbConfig.time_zone = GMT_OFFSET_SEC / 3600.0f;
    fbConfig.daylight_offset = DAYLIGHT_OFFSET_SEC / 60.0f;

    Firebase.begin(&fbConfig, &fbAuth);
    Firebase.reconnectWiFi(true);

    if (WiFi.status() == WL_CONNECTED && !rtdb_device_path.isEmpty()) {
        Firebase.setBool(fbdo, rtdb_device_path + "/device_active", true);
        Firebase.setString(fbdo, rtdb_device_path + "/device_id", hardcoded_device_id);
    }
}

bool fetchEmergencyContact() {
    const bool received = Firebase.get(fbdo, rtdb_emergency_path);
    if (!received && fbdo.httpCode() != FIREBASE_ERROR_PATH_NOT_EXIST) {
        Serial.print(F("[FIREBASE] Could not read emergency contacts: "));
        Serial.println(fbdo.errorReason());
        return false;
    }

    JsonDocument doc;
    if (received) {
        const DeserializationError error = deserializeJson(doc, fbdo.payload());
        if (error || (!doc.is<JsonObject>() && !doc.is<JsonArray>() && !doc.isNull())) {
            Serial.println(F("[FIREBASE] Invalid emergency contact list."));
            return false;
        }
    }

    std::vector<EmergencyContact> updated;
    const auto addContact = [&updated](JsonVariantConst item) {
        String phone = normalizeEmergencyPhone(item["phone"].as<String>());
        if (phone.isEmpty()) return;
        String name = item["name"] | "";
        name.trim();
        updated.push_back({name.isEmpty() ? String("Emergency contact") : name, phone});
    };
    if (doc.is<JsonObject>()) {
        for (JsonPairConst entry : doc.as<JsonObjectConst>()) addContact(entry.value());
    } else {
        for (JsonVariantConst entry : doc.as<JsonArrayConst>()) addContact(entry);
    }

    bool changed = contacts.size() != updated.size();
    for (size_t i = 0; !changed && i < updated.size(); ++i) {
        changed = contacts[i].name != updated[i].name || contacts[i].phone != updated[i].phone;
    }
    if (changed) {
        contacts.swap(updated);
        saveContactsToFile();
    }
    Serial.printf("[FIREBASE] Synced %u emergency contacts.\n",
                  static_cast<unsigned int>(contacts.size()));
    return true;
}

bool checkScheduledTime(const String& currentTime, bool allowStart) {
    static String schedule = loadScheduleFromFile();
    static time_t lastEvaluatedMinute = -1;
    static std::vector<String> queuedKeys;
    const bool cloudReady = allowStart && !offlineMode && Firebase.ready();
    const bool idle = allowStart && currentState == IDLE;
    tm evaluationTime = timeinfo;
    const time_t currentMinute = mktime(&evaluationTime) / 60;
    char scheduledDate[11];
    strftime(scheduledDate, sizeof(scheduledDate), "%Y-%m-%d", &evaluationTime);

    if (currentMinute != lastEvaluatedMinute) {
        queuedKeys.clear();
        lastEvaluatedMinute = currentMinute;
    }

    if (cloudReady && idle) {
        Firebase.setString(fbdo, rtdb_device_path + "/last_sync", currentTime);
        const bool received = Firebase.get(fbdo, rtdb_schedule_path + "/med_times");
        if (received || fbdo.httpCode() == FIREBASE_ERROR_PATH_NOT_EXIST) {
            const String downloaded = received && fbdo.dataType() == "json"
                ? fbdo.jsonString() : String("{}");
            if (downloaded != schedule) {
                JsonDocument incoming;
                if (!deserializeJson(incoming, downloaded) && incoming.is<JsonObject>()) {
                    if (saveScheduleToFile(downloaded)) {
                        Serial.println(F("[SCHEDULE] Updated offline backup."));
                    }
                    if (incoming.as<JsonObjectConst>().size() == 0) pendingDoses.clear();
                    schedule = downloaded;
                } else {
                    Serial.println(F("[SCHEDULE] Invalid Firebase schedule; using backup."));
                }
            }
        }
    }

    JsonDocument doc;
    if (!schedule.isEmpty() && deserializeJson(doc, schedule)) {
        Serial.println(F("[SCHEDULE] Invalid cached schedule."));
        doc.clear();
    }
    String earliestTime = "25:00";
    String earliestName = "None";
    String nextTime = "25:00";
    String nextName = "None";
    std::vector<std::pair<int, String>> nearby;

    for (JsonPairConst pair : doc.as<JsonObjectConst>()) {
        const String key = pair.key().c_str();
        const JsonObjectConst entry = pair.value().as<JsonObjectConst>();
        String medicineTime = entry["time"].as<String>();
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
        String medicineName = entry["name"] | "";
        medicineName.trim();
        if (medicineName.isEmpty()) medicineName = "Medicine";
        String dosage = entry["dosage"] | "";
        dosage.trim();

        if (medicineTime < earliestTime) {
            earliestTime = medicineTime;
            earliestName = medicineName;
        }
        if (medicineTime > currentTime && medicineTime < nextTime) {
            nextTime = medicineTime;
            nextName = medicineName;
        }
        const int offset = (minutesSinceMidnight(medicineTime) -
                            evaluationTime.tm_hour * 60 - evaluationTime.tm_min + 1440) % 1440;
        if (offset > 0 && offset <= NEARBY_DOSE_MINUTES) {
            nearby.emplace_back(offset, medicineTime + " " + medicineName);
        }
        if (medicineTime == currentTime) {
            bool alreadyQueued = false;
            for (const String& queuedKey : queuedKeys) {
                if (queuedKey == key) {
                    alreadyQueued = true;
                    break;
                }
            }
            if (!alreadyQueued) {
                pendingDoses.push_back({key, medicineName, dosage, medicineTime,
                                        scheduledDate, currentMinute, {}});
                queuedKeys.push_back(key);
            }
        }
    }

    std::stable_sort(nearby.begin(), nearby.end(),
                     [](const auto& first, const auto& second) { return first.first < second.first; });
    for (auto& dose : pendingDoses) {
        if (dose.dueMinute != currentMinute) continue;
        dose.nearbyLabels.clear();
        for (const auto& entry : nearby) dose.nearbyLabels.push_back(entry.second);
    }

    nextMedicineTime = nextTime != "25:00" ? nextTime : earliestTime;
    nextMedicineName = nextTime != "25:00" ? nextName : earliestName;
    if (nextMedicineTime == "25:00") {
        nextMedicineTime = "--:--";
    }

    if (!idle || pendingDoses.empty()) return false;

    activeDose = pendingDoses.front();
    pendingDoses.pop_front();
    currentMedicineName = activeDose.name;
    currentMedicineDosage = activeDose.dosage;
    currentMedicineTime = activeDose.time;
    // A dose queued during SOS may start after its nearby dose is already due.
    nearbyMedicineLabels.clear();
    if (activeDose.dueMinute == currentMinute) {
        nearbyMedicineLabels = std::move(activeDose.nearbyLabels);
    }
    currentState = GREEN_ACTIVE;
    stateChangeTime = millis();
    startAlarmSequence(GREEN_ACTIVE);
    if (cloudReady) {
        Firebase.setString(fbdo, rtdb_schedule_path + "/current_status", "ACTIVE");
    }
    return true;
}

static void addDoseIdentity(FirebaseJson& record) {
    record.set("dose_key", activeDose.key);
    record.set("scheduled_at", activeDose.time);
    record.set("scheduled_date", activeDose.date);
}

void handleConfirmation(const String& state) {
    showOLED("DOSE CONFIRMED", "Marked as taken", currentMedicineName);
    playWavFile(SOUND_MEDICINE_CONFIRM);

    unsigned long confirmStart = millis();
    while (millis() - confirmStart < 2000) {
        audioLoop();
        delay(40);
    }
    stopAudio();

    FirebaseJson confirmationJson;
    addDoseIdentity(confirmationJson);
    confirmationJson.set("confirmed_at", getCurrentTimeFormatted());
    confirmationJson.set("medicine_name", currentMedicineName);
    confirmationJson.set("reminder_state", state);
    confirmationJson.set("confirmed_at_timestamp/.sv", "timestamp");

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
    addDoseIdentity(missedJson);
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
