#pragma once

#include <Arduino.h>
#include <string>
#include <vector>

struct EmergencyContact;

// =============================================================================
// LittleFS Storage Operations
// =============================================================================

/**
 * @brief Mounts LittleFS file system (formats automatically if corrupted).
 * @return true if mounted successfully, false otherwise.
 */
bool initStorage();

/**
 * @brief Prints all files present on LittleFS for system diagnostics.
 */
void printStorageFiles();

/**
 * @brief Loads Wi-Fi, user, and Firebase credentials from /config.json.
 * @return true on success and valid data, false otherwise.
 */
bool loadConfiguration();

/**
 * @brief Saves raw JSON received via BLE to /config.json and updates runtime credentials.
 * @param data JSON string payload from mobile app.
 * @return true if parsed and saved successfully.
 */
bool saveConfiguration(const std::string& data);

/**
 * @brief Saves the supplied emergency contacts array to /contacts.json.
 * @return true on success.
 */
bool saveContactsToFile(const std::vector<EmergencyContact>& updated);

/**
 * @brief Loads saved emergency contacts from /contacts.json into memory.
 * @return true if at least one contact was loaded.
 */
bool loadContactsFromFile();

/**
 * @brief Saves schedule JSON payload from Firebase to /schedule.json.
 * @param scheduleJson JSON string containing medication schedules.
 * @return true on success.
 */
bool saveScheduleToFile(const String& scheduleJson);

/**
 * @brief Reads the cached schedule from /schedule.json.
 * @return Schedule JSON, or an empty string if unavailable.
 */
String loadScheduleFromFile();

/**
 * @brief Deletes /config.json, /contacts.json, and /schedule.json for factory reset.
 */
void deleteConfigurationFiles();
