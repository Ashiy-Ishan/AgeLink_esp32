#pragma once

#include <Arduino.h>
#include <WiFi.h>
#include <FirebaseESP32.h>
#include "age_link_config.h"

// =============================================================================
// Network, Wi-Fi, NTP & Firebase RTDB Manager
// =============================================================================

extern FirebaseData fbdo;
extern FirebaseConfig fbConfig;
extern FirebaseAuth fbAuth;

/**
 * @brief Attempts initial Wi-Fi connection with configured credentials.
 * Handles fallback to OFFLINE MODE if connection times out.
 */
void initWiFi();

/**
 * @brief Periodically monitors Wi-Fi link status and manages non-blocking reconnection.
 */
void handleWiFiReconnect();

/**
 * @brief Configures SNTP client and blocks safely until valid UTC/local time is synced.
 */
void initNTP();

/**
 * @brief Updates local struct tm timeinfo.
 * @return true if time is valid, false otherwise.
 */
bool updateLocalTime();

/**
 * @brief Formats current local time as HH:MM string.
 * @return String formatted as "HH:MM".
 */
String getCurrentTimeFormatted();

/**
 * @brief Initializes Firebase Realtime Database SDK client.
 */
void initFirebase();

/**
 * @brief Reads remote device configurations (such as audio volume) from Firebase RTDB.
 */
void fetchDeviceSettings();

/**
 * @brief Downloads user emergency contacts from Firebase and syncs to local storage.
 */
void fetchEmergencyContact();

/**
 * @brief Compares current local time against daily medication schedule.
 * Triggers alarm transition if time matches.
 * @param currentTime Current time in HH:MM format.
 * @return true if an alarm was activated during this check, false otherwise.
 */
bool checkScheduledTime(const String& currentTime);

/**
 * @brief Pushes medicine ingestion confirmation record to Firebase RTDB.
 * @param state Alarm escalation level when confirmed ("Green", "Orange", "Red").
 */
void handleConfirmation(const String& state);

/**
 * @brief Pushes a missed dose incident record to Firebase RTDB.
 * @param medicineName Name of missed prescription drug.
 */
void handleMissed(const String& medicineName);
