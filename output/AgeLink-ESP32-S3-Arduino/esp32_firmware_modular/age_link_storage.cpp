#include "age_link_storage.h"
#include "age_link_types.h"
#include "age_link_config.h"

#include <FS.h>
#include <LittleFS.h>
#include <ArduinoJson.h>

bool initStorage() {
    Serial.println(F("[STORAGE] Initializing LittleFS..."));
    if (!LittleFS.begin(true)) {
        Serial.println(F("[STORAGE] ERROR: LittleFS mount failed!"));
        return false;
    }
    Serial.println(F("[STORAGE] LittleFS mounted successfully."));
    return true;
}

void printStorageFiles() {
    File root = LittleFS.open("/");
    if (!root || !root.isDirectory()) {
        Serial.println(F("[STORAGE] Failed to open root directory."));
        return;
    }
    Serial.println(F("[STORAGE] File list on LittleFS:"));
    File file = root.openNextFile();
    while (file) {
        Serial.print(F("  - "));
        Serial.print(file.name());
        Serial.print(F(" ("));
        Serial.print(file.size());
        Serial.println(F(" bytes)"));
        file = root.openNextFile();
    }
    root.close();
}

bool loadConfiguration() {
    Serial.println(F("[STORAGE] Reading /config.json..."));
    if (!LittleFS.exists("/config.json")) {
        Serial.println(F("[STORAGE] /config.json does not exist."));
        return false;
    }

    File configFile = LittleFS.open("/config.json", "r");
    if (!configFile) {
        Serial.println(F("[STORAGE] Failed to open /config.json for reading."));
        return false;
    }

    StaticJsonDocument<1024> doc;
    DeserializationError error = deserializeJson(doc, configFile);
    configFile.close();

    if (error) {
        Serial.print(F("[STORAGE] JSON parse error in /config.json: "));
        Serial.println(error.c_str());
        return false;
    }

    wifi_ssid     = doc["ssid"].as<String>();
    wifi_password = doc["pass"].as<String>();
    user_id       = doc["user_id"].as<String>();
    firebase_host = doc["fb_host"].as<String>();
    firebase_auth = doc["fb_auth"].as<String>();

    if (wifi_ssid.isEmpty() || user_id.isEmpty() || firebase_host.isEmpty()) {
        Serial.println(F("[STORAGE] ERROR: Missing essential fields in config.json."));
        return false;
    }

    // Construct Firebase RTDB endpoint paths
    rtdb_schedule_path  = "/reminders/" + user_id + "/schedule";
    rtdb_confirm_path   = "/reminders/" + user_id + "/confirmation";
    rtdb_emergency_path = "/appData/" + user_id + "/emergencyContacts";
    rtdb_device_path    = "/reminders/" + user_id + "/device";

    Serial.println(F("[STORAGE] Configuration loaded successfully."));
    Serial.print(F("  SSID: "));    Serial.println(wifi_ssid);
    Serial.print(F("  User ID: ")); Serial.println(user_id);
    Serial.print(F("  FB Host: ")); Serial.println(firebase_host);
    return true;
}

bool saveConfiguration(const std::string& data) {
    Serial.println(F("[STORAGE] Parsing and saving new configuration..."));

    StaticJsonDocument<1024> doc;
    DeserializationError error = deserializeJson(doc, data);
    if (error) {
        Serial.print(F("[STORAGE] Failed to parse config JSON: "));
        Serial.println(error.c_str());
        return false;
    }

    wifi_ssid     = doc["ssid"].as<String>();
    wifi_password = doc["pass"].as<String>();
    user_id       = doc["user_id"].as<String>();
    firebase_host = doc["fb_host"].as<String>();
    firebase_auth = doc["fb_auth"].as<String>();

    if (wifi_ssid.isEmpty() || user_id.isEmpty() || firebase_host.isEmpty()) {
        Serial.println(F("[STORAGE] ERROR: Incomplete config received from BLE."));
        return false;
    }

    File configFile = LittleFS.open("/config.json", "w");
    if (!configFile) {
        Serial.println(F("[STORAGE] Failed to open /config.json for writing."));
        return false;
    }

    configFile.print(data.c_str());
    configFile.close();

    // Update dynamic paths
    rtdb_schedule_path  = "/reminders/" + user_id + "/schedule";
    rtdb_confirm_path   = "/reminders/" + user_id + "/confirmation";
    rtdb_emergency_path = "/appData/" + user_id + "/emergencyContacts";
    rtdb_device_path    = "/reminders/" + user_id + "/device";

    Serial.println(F("[STORAGE] Successfully saved configuration to /config.json."));
    return true;
}

bool saveContactsToFile() {
    Serial.println(F("[STORAGE] Saving contacts to /contacts.json..."));
    File contactFile = LittleFS.open("/contacts.json", "w");
    if (!contactFile) {
        Serial.println(F("[STORAGE] Failed to open /contacts.json for writing."));
        return false;
    }

    JsonDocument doc;
    JsonArray array = doc.to<JsonArray>();
    for (const auto& contact : contacts) {
        JsonObject item = array.add<JsonObject>();
        item["name"] = contact.name;
        item["phone"] = contact.phone;
    }

    if (serializeJson(doc, contactFile) == 0) {
        Serial.println(F("[STORAGE] Failed to serialize contacts to /contacts.json."));
        contactFile.close();
        return false;
    }

    contactFile.close();
    Serial.println(F("[STORAGE] Successfully saved contacts to LittleFS."));
    return true;
}

bool loadContactsFromFile() {
    Serial.println(F("[STORAGE] Loading contacts from /contacts.json..."));
    if (!LittleFS.exists("/contacts.json")) {
        Serial.println(F("[STORAGE] /contacts.json not found."));
        return false;
    }

    File contactFile = LittleFS.open("/contacts.json", "r");
    if (!contactFile) {
        Serial.println(F("[STORAGE] Failed to open /contacts.json for reading."));
        return false;
    }

    JsonDocument doc;
    const DeserializationError error = deserializeJson(doc, contactFile);
    contactFile.close();
    if (error || !doc.is<JsonArray>()) {
        Serial.println(F("[STORAGE] Invalid cached emergency contacts."));
        return false;
    }

    contacts.clear();
    for (JsonObjectConst item : doc.as<JsonArrayConst>()) {
        String phone = normalizeEmergencyPhone(item["phone"].as<String>());
        if (phone.isEmpty()) continue;
        String name = item["name"] | "";
        contacts.push_back({name.isEmpty() ? String("Emergency contact") : name, phone});
    }

    Serial.printf("[STORAGE] Loaded %u emergency contacts.\n",
                  static_cast<unsigned int>(contacts.size()));
    return !contacts.empty();
}

bool saveScheduleToFile(const String& scheduleJson) {
    File scheduleFile = LittleFS.open("/schedule.json", "w");
    if (!scheduleFile) {
        Serial.println(F("[STORAGE] Failed to open /schedule.json for writing."));
        return false;
    }
    scheduleFile.print(scheduleJson);
    scheduleFile.close();
    Serial.println(F("[STORAGE] Saved schedule backup to /schedule.json."));
    return true;
}

String loadScheduleFromFile() {
    File scheduleFile = LittleFS.open("/schedule.json", "r");
    return scheduleFile ? scheduleFile.readString() : String();
}

void deleteConfigurationFiles() {
    Serial.println(F("[STORAGE] Erasing configuration files for Factory Reset..."));
    if (LittleFS.remove("/config.json")) {
        Serial.println(F("[STORAGE] Deleted /config.json"));
    }
    if (LittleFS.remove("/contacts.json")) {
        Serial.println(F("[STORAGE] Deleted /contacts.json"));
    }
    if (LittleFS.remove("/schedule.json")) {
        Serial.println(F("[STORAGE] Deleted /schedule.json"));
    }
    Serial.println(F("[STORAGE] Factory reset wipe complete."));
}
