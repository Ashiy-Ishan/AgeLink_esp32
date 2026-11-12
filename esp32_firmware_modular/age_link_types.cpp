#include "age_link_types.h"

// State and Timing Variables Definition
ReminderState currentState      = IDLE;
unsigned long stateChangeTime       = 0;
unsigned long lastDBCheckTime       = 0;
unsigned long lastWifiCheck         = 0;
unsigned long greenButtonPressTime  = 0;
unsigned long lastTimeLog           = 0;

bool isResetting     = false;
bool offlineMode     = true;
bool deviceConnected = false;
bool configComplete  = false;

String currentMedicineName = "";
String currentMedicineDosage;
String currentMedicineTime;
std::vector<String> nearbyMedicineLabels;
std::vector<EmergencyContact> contacts;
float currentVolume = 0.5f; // Match the app's default reminder volume.

String nextMedicineTime  = "--:--";
String nextMedicineName  = "None";

// Credentials and Paths
String wifi_ssid       = "";
String wifi_password   = "";
String user_id         = "";
String firebase_host   = "";
String firebase_auth   = "";
const char* hardcoded_device_id = "Age_link_11.11";

String rtdb_schedule_path  = "";
String rtdb_confirm_path   = "";
String rtdb_emergency_path = "";
String rtdb_device_path    = "";

struct tm timeinfo;

const char* reminderStateToString(ReminderState state) {
    switch (state) {
        case IDLE:          return "IDLE";
        case GREEN_ACTIVE:  return "GREEN_ACTIVE";
        case ORANGE_ACTIVE: return "ORANGE_ACTIVE";
        case RED_ACTIVE:    return "RED_ACTIVE";
        case CONFIRMED:     return "CONFIRMED";
        case MISSED:        return "MISSED";
        default:            return "UNKNOWN";
    }
}

void resetRuntimeState() {
    currentState = IDLE;
    stateChangeTime = 0;
    currentMedicineName = "";
    isResetting = false;
}

String normalizeEmergencyPhone(String number) {
    number.trim();
    number.replace(" ", "");
    number.replace("-", "");
    number.replace("(", "");
    number.replace(")", "");
    const size_t start = number.startsWith("+") ? 1 : 0;
    const size_t digits = number.length() - start;
    if (digits < 7 || digits > 15) return "";
    for (size_t i = start; i < number.length(); ++i) {
        if (!isDigit(number[i])) return "";
    }
    return number;
}
