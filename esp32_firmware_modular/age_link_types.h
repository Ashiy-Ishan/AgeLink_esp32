#pragma once

#include <Arduino.h>
#include <time.h>
#include "age_link_config.h"

// =============================================================================
// Reminder State Machine Enumeration
// =============================================================================
enum ReminderState {
    IDLE,
    GREEN_ACTIVE,
    ORANGE_ACTIVE,
    RED_ACTIVE,
    CONFIRMED,
    MISSED
};

// =============================================================================
// Emergency Contact Structure
// =============================================================================
struct EmergencyContact {
    String name;
    String phone;
};

// =============================================================================
// Shared Global State Variables (Declared extern)
// =============================================================================
extern ReminderState currentState;
extern unsigned long stateChangeTime;
extern unsigned long lastDBCheckTime;
extern unsigned long lastScheduleSaveTime;
extern unsigned long lastSosPressTime;
extern unsigned long lastWifiCheck;
extern unsigned long greenButtonPressTime;
extern unsigned long lastTimeLog;

extern bool isResetting;
extern bool offlineMode;
extern bool deviceConnected;
extern bool configComplete;

extern String currentMedicineName;
extern EmergencyContact contacts[MAX_CONTACTS];
extern int contactCount;
extern float currentVolume;

extern String nextMedicineTime;
extern String nextMedicineName;
extern String lastConfirmedTime;

// Network & Firebase Credentials / Paths
extern String wifi_ssid;
extern String wifi_password;
extern String user_id;
extern String firebase_host;
extern String firebase_auth;
extern const char* hardcoded_device_id;

extern String rtdb_schedule_path;
extern String rtdb_confirm_path;
extern String rtdb_emergency_path;
extern String rtdb_device_path;

extern struct tm timeinfo;

// Helper Functions
const char* reminderStateToString(ReminderState state);
void resetRuntimeState();
