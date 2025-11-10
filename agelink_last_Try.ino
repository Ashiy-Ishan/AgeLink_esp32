/*
 * AgeLink: ESP32 Medication Reminder System
 * This firmware manages a medication reminder schedule pulled from Firebase,
 * controls LEDs and an LCD display for user alerts, plays WAV audio alerts
 * via an I2S DAC (MAX98355A), and handles button inputs for medicine
 * confirmation and SOS emergency calls via a SIM800L module.
 * This version includes BLE provisioning if config.json is not found.
 */

// --- 0. Core Libraries ---
#include <WiFi.h>
#include <FirebaseESP32.h>
#include <time.h>
#include <Wire.h> 
#include <LiquidCrystal_I2C.h>
#include "FS.h"
#include "LittleFS.h" // Using LittleFS for ESP32
#include <cmath>
#include <ArduinoJson.h> 

// --- NEW: BLE Provisioning Libraries ---
#include <BLEDevice.h>
#include <BLEUtils.h>
#include <BLEServer.h>

// --- ESP8266Audio Library Includes (Works for ESP32) ---
#include "AudioFileSourceLittleFS.h"
#include "AudioGeneratorWAV.h" 
#include "AudioOutputI2S.h"
// ----------------------------------------

// --- Firebase Add-ons ---
#include "addons/TokenHelper.h" 
// **********************************


// --- 1. WiFi and Firebase Credentials (CHANGED from #define to variables) ---
String wifi_ssid = "";
String wifi_password = "";
String user_id = "";
String firebase_host = "";
String firebase_auth = "";
const char* hardcoded_device_id = "Age_link_11.11"; // Hard-coded device ID

// Paths will be constructed after loading config
String rtdb_schedule_path = "";
String rtdb_confirm_path = "";
String rtdb_emergency_path = "";
String rtdb_device_path = ""; // NEW: Path for device settings

// --- NEW: BLE Provisioning UUIDs ---
// These MUST match your mobile app
#define SERVICE_UUID        "4FAFC201-1FB5-459E-8FCC-C5C9C331914B"
#define CHARACTERISTIC_UUID "BEB5483E-36E1-4688-B7F5-EA07361B26A8"

// --- 2. Component Pin Definitions ---
// LEDs
#define LED_GREEN 14
#define LED_ORANGE 12
#define LED_RED 13

// Buttons
#define BUTTON_MED 33 // Medicine Button (Input Pullup)
#define BUTTON_SOS 32 // SOS Button (Input Pullup)

// SIM800L (Serial2)
#define RX2_PIN 16
#define TX2_PIN 17

// MAX98355A I2S Audio Pins
#define I2S_DOUT 19 // Data Out
#define I2S_LRC 25  // Left/Right Clock (Word Select)
#define I2S_BCLK 26 // Bit Clock

// LCD (I2C)
#define I2C_SDA 21
#define I2C_SCL 22
#define LCD_COLUMNS 16
#define LCD_ROWS 2
#define LCD_I2C_ADDRESS 0x27// FIX: Changed to 0x3F to solve NACK errors (was 0x27)

// --- 3. State and Timing Variables ---
enum ReminderState { IDLE, GREEN_ACTIVE, ORANGE_ACTIVE, RED_ACTIVE, CONFIRMED, MISSED }; 
ReminderState currentState = IDLE;
unsigned long stateChangeTime = 0;       // Time the current state was entered
unsigned long lastDBCheckTime = 0;       // For throttling Firebase checks
const long DB_CHECK_INTERVAL_MS = 10 * 1000; // Check DB every 10 seconds
unsigned long lastScheduleSaveTime = 0;    // NEW: Timer for saving schedule
const long SCHEDULE_SAVE_INTERVAL_MS = 20 * 60 * 1000; // NEW: 20 minutes
unsigned long lastSosPressTime = 0;       // For SOS button debounce
const long SOS_DEBOUNCE_DELAY = 1000;  // 1 second debounce for SOS
const long ALARM_BEEP_DURATION_MS = 5 * 1000; // 5s (Assuming WAV files are ~5s)
// const long LONG_WAIT_MS = 120 * 1000;  // 2 minutes (NO LONGER USED)
const long SHORT_WAIT_MS = 60 * 1000; // 1 minute

String currentMedicineName = "";
// NEW: Struct and array to hold multiple contacts
#define MAX_CONTACTS 5 // Store up to 5 emergency contacts
struct EmergencyContact {
  String name;
  String phone;
};
EmergencyContact contacts[MAX_CONTACTS];
int contactCount = 0; // Number of contacts actually loaded

float currentVolume = 0.3; // NEW: Global var for volume (0.0 to 1.0, 1.0 is 100%)

String nextMedicineTime = "--:--"; // Stores the next upcoming medicine time
String nextMedicineName = "None";  // NEW: Stores the name of the next medicine
String lastConfirmedTime = ""; // NEW: Fix for confirmation loop

// NEW: Timer for non-blocking WiFi reconnect
unsigned long lastWifiCheck = 0;

// NEW: Timer for Factory Reset
unsigned long greenButtonPressTime = 0; // NEW: Timer for single-button reset
bool isResetting = false;

// NTP Time Configuration
const char* ntpServer = "pool.ntp.org";
const long gmtOffset_sec = 19800; // GMT +5:30 (India/Sri Lanka)
const int daylightOffset_sec = 0; // No daylight saving
struct tm timeinfo;
unsigned long lastTimeLog = 0;
const unsigned long logInterval = 10000; // Log time every 10s

// --- 4. Firebase & Audio Objects ---
FirebaseData fbdo;
FirebaseConfig config;
FirebaseAuth auth;
LiquidCrystal_I2C lcd(LCD_I2C_ADDRESS, LCD_COLUMNS, LCD_ROWS);

// NEW: Global variables to track LCD state and prevent flicker
String lcdLine1_last = "";
String lcdLine2_last = "";

// --- NEW: BLE Global Flags ---
bool deviceConnected = false;
bool configComplete = false;
bool offlineMode = true; // NEW: Flag to track if we are in Offline SOS mode

// REMOVED: WiFi Connection Flags
// bool wifiJustConnected = false;
// bool wifiJustDisconnected = false;

// ESP8266Audio Objects (using pointers)
AudioOutputI2S *out = nullptr;
AudioFileSourceLittleFS *file = nullptr;
AudioGeneratorWAV *audio = nullptr; 

// --- 5. Audio Debugging Callbacks (Corrected Signatures) ---

/**
 * @brief Metadata callback for ESP8266Audio.
 * @param data User-defined pointer (unused here).
 * @param name Metadata key (e.g., "sample_rate").
 * @param isStream (Unused).
 * @param value Metadata value.
 */
void audio_metadata_cb(void *data, const char *name, bool isStream, const char *value) {
    // Serial.print("[AUDIO METADATA] "); // Removed spam
    // Serial.print(name);
    // Serial.print(" = ");
    // Serial.println(value);
}

/**
 * @brief Generic status callback for ESP8266Audio.
 * @param data User-defined pointer (unused here).
 * @param type Status code.
 * @param info Status message string.
 */
void audio_status_cb(void *data, int type, const char *info) {
    // Serial.print("[AUDIO STATUS] Type: "); // Removed spam
    // Serial.print(type);
    // Serial.print(", Info: ");
    // Serial.println(info);
}

/**
 * @brief File status callback, primarily for EOF (End of File).
 * @param data User-defined pointer (unused here).
 * @param type Status code.
 * @param info Status message string (e.g., "EOF").
 */
void file_status_cb(void *data, int type, const char *info) {
    Serial.print("[FILE EOF/STATUS] "); // This one is useful
    Serial.println(info);
    // Important: After EOF, stop the audio generator.
    if (audio) {
        // Serial.println("[AUDIO LOOP] Playback finished via EOF callback."); // Removed spam
        audio->stop();
    }
}

// --- 6. Function Prototypes ---
void initNTP();
String getCurrentTimeFormatted();
bool checkScheduledTime(String currentTime); // MODIFIED: Returns true if alarm triggers
void setLEDs(bool green, bool orange, bool red);
void handleConfirmation(String state);
void handleMissed(String medicineName); // NEW: Function to log missed events
void startAlarmSequence(ReminderState phase);
void initI2S(); 
void initLCD();
void updateLCD(String line1, String line2);
void fetchEmergencyContact(); 
// void makeCall(String phoneNumber); // REMOVED - Logic is now in executeSosSequence
void executeSosSequence(); // NEW: Handles the multi-call sequence
String sendATCommand(String command, long timeout_ms, bool fullResponse); // MODIFIED
void playWavFile(const char* filename);
bool loadConfiguration(); // NEW: Function prototype
void fetchDeviceSettings(); // NEW: Function prototype
void startBLEProvisioning(); // NEW: Function prototype
bool saveConfiguration(std::string data); // FIX: Was std.string, changed to std::string
// void WiFiEvent(WiFiEvent_t event); // REMOVED: WiFi event handler
bool saveScheduleToFile(); // NEW: Save schedule to LittleFS
bool saveContactsToFile(); // NEW: Save contacts to LittleFS
bool loadContactsFromFile(); // NEW: Load contacts from LittleFS
bool loadScheduleFromFile(); // NEW: Load schedule from LittleFS
void deleteConfigurationFiles(); // NEW: Factory reset function
void audio_loop_helper(); // NEW: Helper function to keep audio running


// --- NEW: BLE Callback Handlers ---

/**
 * @brief Handles BLE server connect/disconnect events.
 */
class MyServerCallbacks: public BLEServerCallbacks {
    void onConnect(BLEServer* pServer) {
      deviceConnected = true;
      Serial.println("BLE Client Connected");
    }

    void onDisconnect(BLEServer* pServer) {
      deviceConnected = false;
      Serial.println("BLE Client Disconnected");
      // Optional: Start advertising again if disconnected before config is done
      if (!configComplete) {
          BLEDevice::startAdvertising();
          Serial.println("Restarted advertising");
      }
    }
};

/**
 * @brief Handles data writes from the mobile app.
 */
class MyCharacteristicCallbacks: public BLECharacteristicCallbacks {
    void onWrite(BLECharacteristic *pCharacteristic) {
      String value_arduino = pCharacteristic->getValue(); // Get as Arduino String
      std::string value_std = value_arduino.c_str();      // FIX: Convert to std::string (was std.string)

      if (value_std.length() > 0) {
        Serial.println("*********");
        Serial.println("Received BLE Data:");
        Serial.println(value_std.c_str());
        Serial.println("*********");

        // NEW: Check for factory reset command
        if (value_std.find("delete_config") != std::string::npos) {
            Serial.println("Factory Reset command received!");
            updateLCD("RESETTING...", "Erasing files...");
            deleteConfigurationFiles();
            delay(2000);
            ESP.restart();
            return; // Don't try to save
        }

        // Try to save the configuration
        if (saveConfiguration(value_std)) { // Pass the std::string
            Serial.println("Configuration saved successfully!");
            configComplete = true; // Signal the main loop to restart
        } else {
            Serial.println("ERROR: Failed to save configuration from BLE data.");
            // Optional: You could notify the app of failure here
        }
      }
    }
};


// -----------------------------------------------------------------------------
//  SETUP
// -----------------------------------------------------------------------------
void setup() {
    Serial.begin(115200);

    // Initialize Pins
    pinMode(LED_GREEN, OUTPUT);
    pinMode(LED_ORANGE, OUTPUT);
    pinMode(LED_RED, OUTPUT);
    pinMode(BUTTON_MED, INPUT_PULLUP);
    pinMode(BUTTON_SOS, INPUT_PULLUP);
    setLEDs(false, false, false); // All LEDs off

    // 0. Initialize File System (Crucial for audio files)
    if(!LittleFS.begin(true)){ // true = format if mount failed
        Serial.println("LittleFS Mount Failed! Cannot play WAV files.");
        delay(3000);
    } else {
        Serial.println("LittleFS Mounted Successfully.");
        // List files for debugging (Optional, but helpful)
        File root = LittleFS.open("/");
        File file_list = root.openNextFile();
        while(file_list){
            // Serial.print("FS File: "); // Removed spam
            // Serial.println(file_list.name());
            file_list = root.openNextFile();
        }
        root.close();
    }

    // 1. Initialize I2S Audio (MOVED TO TOP)
    initI2S(); 
    // Play power up sound for testing
    // playWavFile("/age_link_powerring up.wav"); // MOVED: Will play only if WiFi connects

    // 2. Initialize LCD
    initLCD();
    updateLCD("System Booting", "Loading Config...");
    delay(1000);

    // 3. Load Configuration from JSON
    if (loadConfiguration()) {
        // --- Config file exists, proceed with normal boot ---
        Serial.println("Configuration loaded successfully from LittleFS.");
        updateLCD("Config OK", "SIM800L Init...");
    } else {
        // --- Config file NOT found, enter BLE Provisioning Mode ---
        Serial.println("FATAL ERROR: Could not load config.json");
        Serial.println("Entering BLE Provisioning Mode...");
        updateLCD("App Setup Req.", "Open AgeLink App");
       
        startBLEProvisioning();

        // Wait here until the app sends the config
        while (!configComplete) {
            // Blink all LEDs slowly (800ms on, 800ms off)
            setLEDs(true, true, true);
            delay(800); // Slower "normal" blink
            setLEDs(false, false, false);
            delay(800); // Slower "normal" blink
        }

        // --- Config has been received and saved ---
        Serial.println("Configuration Received via BLE!");
        updateLCD("Config Received", "Restarting...");
        delay(3000);
        ESP.restart(); // Restart the device to apply the new config
    }

    // --- Normal Boot Sequence (only runs if config was loaded) ---

    // 4. Initialize SIM800L Serial Communication
    Serial2.begin(9600, SERIAL_8N1, RX2_PIN, TX2_PIN);
    Serial.println("Waiting for SIM800L...");
    delay(1000); // Give module time to boot
   
    // --- SIM800L Sanity Checks (REMOVED FOR FASTER BOOT) ---
    // ...

    // 5. Connect to Wi-Fi (CHANGED to use variables)
   
    // REMOVED: WiFi event handler
    // WiFi.onEvent(WiFiEvent);
   
    Serial.print("Connecting to WiFi..");
    updateLCD("Connecting WiFi", wifi_ssid);
    // playWavFile("/wifi_connecting.wav"); // FIX: REMOVED this line. It conflicts with WiFi.begin()
    WiFi.begin(wifi_ssid.c_str(), wifi_password.c_str()); // .c_str() FIX
   
    // NEW: Wait 30 seconds for WiFi, then decide if we are in Offline Mode
    unsigned long wifiConnectStart = millis();
    while (WiFi.status() != WL_CONNECTED && millis() - wifiConnectStart < 30000) { // 30s timeout
        // audio_loop_helper(); // FIX: REMOVED. Do not play audio during WiFi connect.
        delay(500);
        Serial.print(".");
    }

    // 6. Initialize Firebase RTDB (CHANGED to use variables)
    config.host = firebase_host;
    config.signer.tokens.legacy_token = firebase_auth.c_str(); // Using Legacy Auth - .c_str() FIX
    Firebase.begin(&config, &auth);
    Firebase.reconnectWiFi(true);

    if (WiFi.status() == WL_CONNECTED) {
      Serial.println("\nWiFi connection successful. Proceeding...");
      offlineMode = false;

      // NEW: Manually run connection tasks
      Serial.println("Running tasks for WiFi connection...");
      if (Firebase.ready() && rtdb_device_path != "") {
          Firebase.setBool(fbdo, rtdb_device_path + "/device_active", true);
          Firebase.setString(fbdo, rtdb_device_path + "/device_id", hardcoded_device_id); // Upload device ID
      }
      playWavFile("/age_link_powerring up.wav"); // MOVED HERE: Play power-up sound
      playWavFile("/wifi_connected.wav");
      updateLCD("WiFi Connected", "NTP Sync...");

      // FIX: Wait for audio to FINISH before starting NTP
      Serial.println("Waiting for 'wifi_connected' audio to finish...");
      while (audio && audio->isRunning()) {
          audio_loop_helper();
          delay(50); // Be a good citizen
      }
      Serial.println("Audio finished, proceeding to NTP.");

    } else {
      Serial.println("\nWiFi connection FAILED. Entering OFFLINE MODE.");
      offlineMode = true;
      updateLCD("OFFLINE MODE", "SOS Only");
      // FIX: Try to load contacts from file. If it fails, use the fallback.
      if (!loadContactsFromFile()) {
          Serial.println("Could not load contacts from file. Using fallback.");
          // Fallback if file load failed
          contacts[0].name = "Emergency";
          contacts[0].phone = "0763777417"; // Generic Fallback number
          contactCount = 1; // We have one fallback contact
          Serial.println(">>> Using FALLBACK emergency contact: " + contacts[0].name + " / " + contacts[0].phone);
      }
      // loadScheduleFromFile(); // REMOVED: Do not check schedule in offline mode
    }

    // 7. Initialize NTP Time (Only if online)
    if (!offlineMode) {
      initNTP();
      updateLCD("Time Sync OK", "Data Fetching...");
    }

    // 8. Fetch Emergency Contact (and store it)
    // We fetch contacts *after* deciding on offline mode.
    // If online, we fetch from Firebase. If offline, we just loaded from file (or fallback).
    if (!offlineMode) {
      fetchEmergencyContact();
      saveContactsToFile(); // Save a copy for offline use
    }
   
    // 9. Initial Schedule Check
    if (!offlineMode) {
      Serial.println("Running initial schedule check...");
      checkScheduledTime(getCurrentTimeFormatted()); // This call is fine, we just ignore the 'true'
      updateLCD("Ready!", "Next: " + nextMedicineTime);
    }
    delay(2000);
}


// -----------------------------------------------------------------------------
//  MAIN LOOP
// -----------------------------------------------------------------------------
void loop() {
    // --- 0. HARDWARE LOCK ---
    // If we are resetting, do nothing else.
    if (isResetting) return;

    // --- 1. ALWAYS RUN AUDIO ---
    // This MUST be called every loop, before anything else, to prevent stutters.
    audio_loop_helper();

    // --- 2. HANDLE WIFI CONNECTION (NON-BLOCKING) ---
    if (WiFi.status() != WL_CONNECTED) {
        offlineMode = true; // We are now offline
        // WiFi is disconnected. Only try to reconnect every 30 seconds to save power.
        if (millis() - lastWifiCheck > 30000) { // 30-second reconnect timer
            Serial.println("WiFi Disconnected. Attempting to reconnect...");
           
            // NEW: Set status to false
            if (Firebase.ready() && rtdb_device_path != "") {
                Firebase.setBool(fbdo, rtdb_device_path + "/device_active", false);
            }
            updateLCD("WiFi LOST", "SOS Only Mode");
            // FIX: Try to load contacts from file. If it fails, use the fallback.
            if (!loadContactsFromFile()) {
                Serial.println("Could not load contacts from file. Using fallback.");
                // Fallback if file load failed
                contacts[0].name = "Emergency";
                contacts[0].phone = "0763777417"; // Generic Fallback number
                contactCount = 1; // We have one fallback contact
                Serial.println(">>> Using FALLBACK emergency contact: " + contacts[0].name + " / " + contacts[0].phone);
            }

            WiFi.reconnect();
            lastWifiCheck = millis();
        }
    } else if (WiFi.status() == WL_CONNECTED && offlineMode) {
      // We just reconnected!
      Serial.println("WiFi reconnected!");
      offlineMode = false;
      lastWifiCheck = millis();
     
      // Manually run connection tasks
      Serial.println("Running tasks for WiFi connection...");
      if (Firebase.ready() && rtdb_device_path != "") {
          Firebase.setBool(fbdo, rtdb_device_path + "/device_active", true);
          Firebase.setString(fbdo, rtdb_device_path + "/device_id", hardcoded_device_id); // Upload device ID
      }
      playWavFile("/wifi_connected.wav");
      updateLCD("WiFi Connected", "NTP Sync...");
     
      // FIX: Wait for audio to FINISH before starting NTP
      Serial.println("Waiting for 'wifi_connected' audio to finish...");
      while (audio && audio->isRunning()) {
          audio_loop_helper();
          delay(50); // Be a good citizen
      }
      Serial.println("Audio finished, proceeding to NTP.");

      // Re-sync time
      initNTP();
     
      // Re-download contacts and schedule
      fetchEmergencyContact();
      saveContactsToFile();
      checkScheduledTime(getCurrentTimeFormatted());
    }

    // --- 3. REMOVED WIFI EVENT FLAGS ---
    // if (wifiJustConnected) { ... }
    // if (wifiJustDisconnected) { ... }


    // --- 4. MAIN LOGIC (Only runs if NOT in provisioning mode) ---

    // 4a. Handle Offline Mode (SOS Only)
    if (offlineMode) {
        updateLCD("OFFLINE MODE", "SOS Only");
       
        // Handle SOS Button (Independent of state machine)
        if (digitalRead(BUTTON_SOS) == LOW) { // Button is pressed (LOW)
            if (millis() - lastSosPressTime > (SOS_DEBOUNCE_DELAY * 5)) { // 5s debounce
                lastSosPressTime = millis(); // Reset debounce timer
                Serial.println("\n--- SOS BUTTON TRIGGERED (OFFLINE) ---");
                executeSosSequence(); 
                Serial.println("--- SOS Trigger Complete (OFFLINE) ---");
                lastSosPressTime = millis();
            }
        }
        delay(50); // Small delay
        return; // Do not run the rest of the loop
    }

    // 4b. Handle Online Mode (Full Functionality)
    if (!Firebase.ready()) {
        Serial.println("Firebase not ready!");
        delay(1000);
        return;
    }

    // 1. Update Current Time
    if (!getLocalTime(&timeinfo)) {
        Serial.println("Failed to obtain time");
        return; // Skip this loop iteration if time fails
    }
    String currentTime = getCurrentTimeFormatted();

    // --- Time Logging and Idle LCD Update ---
    if (millis() - lastTimeLog >= logInterval) {
        lastTimeLog = millis();
        // Serial.print("Device Time is: "); // Removed spam
        // Serial.println(currentTime);
    }
   
    // Update LCD based on state (only if idle, missed)
    if (currentState == IDLE || currentState == MISSED) {
        if (currentState == MISSED) {
            // This state now has a timeout, see below
            updateLCD("Medication", "MISSED!");
        } else {
            // NEW: Show current time, volume, and next med time + name
            String volStr = "Vol:" + String((int)(currentVolume * 100));
            String line1 = currentTime;
            while(line1.length() + volStr.length() < LCD_COLUMNS) {
              line1 += " ";
            }
            line1 += volStr;
            String line2 = nextMedicineName + ":" + nextMedicineTime;
           
            updateLCD(line1, line2);
        }
    } 
    // ----------------------------------------

    // 2. State Machine Logic
    unsigned long timeElapsed = millis() - stateChangeTime;
   
    // --- Common Logic for Active States (GREEN, ORANGE, RED) ---
    if (currentState == GREEN_ACTIVE || currentState == ORANGE_ACTIVE || currentState == RED_ACTIVE) {
       
        // --- Confirmation Check (Button Pressed) ---
        if (digitalRead(BUTTON_MED) == LOW) { // Button is pressed (LOW)
            String confirmedState;
            if (currentState == GREEN_ACTIVE) confirmedState = "Green";
            else if (currentState == ORANGE_ACTIVE) confirmedState = "Orange";
            else confirmedState = "Red";

            handleConfirmation(confirmedState);
            currentState = CONFIRMED;
            stateChangeTime = millis(); // Reset timer for confirmed display
            Serial.println("Medicine Confirmed. Transition to CONFIRMED display.");
        }
    }

    // --- State-Specific Transitions ---
    switch (currentState) {
        case IDLE: 
            // Check scheduled time only once every 10 seconds
            if (millis() - lastDBCheckTime >= DB_CHECK_INTERVAL_MS) {
                lastDBCheckTime = millis();
                audio->stop(); // FIX: Stop any audio before Firebase calls
               
                // MODIFIED: Check if an alarm was triggered
                bool alarmWasTriggered = checkScheduledTime(currentTime); 
               
                if (!alarmWasTriggered) { // Only fetch settings if no alarm was triggered
                    fetchDeviceSettings(); // NEW: Check for volume/status updates
                }
            }
           
            // --- NEW: Factory Reset Logic (Hold Green Button) ---
            if (digitalRead(BUTTON_MED) == LOW) {
                if (greenButtonPressTime == 0) {
                    greenButtonPressTime = millis();
                    Serial.println("Reset timer started...");
                } else if (millis() - greenButtonPressTime > 5000) {
                    isResetting = true; // Lock the loop
                    Serial.println("\n--- FACTORY RESET TRIGGERED (GREEN BTN) ---");
                    updateLCD("FACTORY RESET", "Erasing files...");
                   
                    // NEW: No sound during reset
                    // playWavFile("/emegency_informed.wav"); 

                    // Non-blocking delay
                    unsigned long resetStartTime = millis();
                    while(millis() - resetStartTime < 3000) {
                        audio_loop_helper(); // Keep audio running (if any)
                        delay(50);
                    }
                    deleteConfigurationFiles();
                    Serial.println("Restarting device...");
                    ESP.restart();
                }
            } else {
                greenButtonPressTime = 0; // Reset timer if button is released
            }
            // --- END OF NEW RESET LOGIC ---
            break;

        case GREEN_ACTIVE:
            // Transition to ORANGE after 5s WAV duration + 60s wait (65s total)
            if (timeElapsed >= (ALARM_BEEP_DURATION_MS + SHORT_WAIT_MS)) { // FIX: Changed from LONG_WAIT_MS
                currentState = ORANGE_ACTIVE;
                stateChangeTime = millis();
                startAlarmSequence(ORANGE_ACTIVE);
            }
            break;

        case ORANGE_ACTIVE:
            // Transition to RED after 5s WAV duration + 60s wait (65s total)
            if (timeElapsed >= (ALARM_BEEP_DURATION_MS + SHORT_WAIT_MS)) {
                currentState = RED_ACTIVE;
                stateChangeTime = millis();
                startAlarmSequence(RED_ACTIVE);
            }
            break;

        case RED_ACTIVE:
            // Transition to MISSED after 5s WAV duration + 60s wait (65s total)
            if (timeElapsed >= (ALARM_BEEP_DURATION_MS + SHORT_WAIT_MS)) { // FIX: Changed from LONG_WAIT_MS
                Serial.println("Red wait expired. Logging as MISSED.");
                currentState = MISSED;
                stateChangeTime = millis(); // NEW: Start timer for MISSED display
                
                // NEW: Call the handleMissed function to push a new entry to Firebase
                handleMissed(currentMedicineName); 
                
                // REMOVED: Firebase.setString(fbdo, rtdb_schedule_path + "/current_status", "MISSED"); 
                // REMOVED: playWavFile("/medicine_missed.wav"); // Moved to handleMissed()
                
                setLEDs(false, false, false); // Turn off red light
            }
            break;

        case MISSED: // NEW: Separate case with 30s timeout
            // FIX: DO NOT check database during this state.
            // This allows the "medicine_missed.wav" sound to play without
            // being cut off by the `audio->stop()` in the DB check.
            if (millis() - stateChangeTime >= 30000) { // 30 second display
                Serial.println("Missed display timeout. Returning to IDLE.");
                currentState = IDLE;
                lastDBCheckTime = millis(); // Reset DB timer now that we are IDLE
            }
            // REMOVED: Database check
            // if (millis() - lastDBCheckTime >= DB_CHECK_INTERVAL_MS) { ... }
           
            // --- NEW: Factory Reset Logic (Hold Green Button) ---
            if (digitalRead(BUTTON_MED) == LOW) {
                if (greenButtonPressTime == 0) {
                    greenButtonPressTime = millis();
                    Serial.println("Reset timer started...");
                } else if (millis() - greenButtonPressTime > 5000) {
                    isResetting = true; // Lock the loop
                    Serial.println("\n--- FACTORY RESET TRIGGERED (GREEN BTN) ---");
                    updateLCD("FACTORY RESET", "Erasing files...");
                   
                    // NEW: No sound during reset
                    // playWavFile("/emegency_informed.wav");

                    // Non-blocking delay
                    unsigned long resetStartTime = millis();
                    while(millis() - resetStartTime < 3000) {
                        audio_loop_helper(); // Keep audio running (if any)
                        delay(50);
                    }
                    deleteConfigurationFiles();
                    Serial.println("Restarting device...");
                    ESP.restart();
                }
            } else {
                greenButtonPressTime = 0; // Reset timer if button is released
            }
            // --- END OF NEW RESET LOGIC ---
            break;

        case CONFIRMED:
            // Stay in confirmed state for 5s display then transition back to IDLE
            if (millis() - stateChangeTime >= 5000) { // 5 second display
                Serial.println("Confirmed display timeout. Returning to IDLE.");
                currentState = IDLE;
                setLEDs(false, false, false); // Turn off all lights
            }
            break;
    }

    // 3. Handle SOS Button (Independent of state machine)
    if (digitalRead(BUTTON_SOS) == LOW) { // Button is pressed (LOW)
        // Check for debounce AND that an alarm is not active
        if (millis() - lastSosPressTime > (SOS_DEBOUNCE_DELAY * 5)) { // 5s debounce
            lastSosPressTime = millis(); // Reset debounce timer
           
            Serial.println("\n--- SOS BUTTON TRIGGERED (ONLINE) ---");
            // NEW: Call the function that dials all numbers
            executeSosSequence(); 
            Serial.println("--- SOS Trigger Complete (ONLINE) ---");
           
            // Revert LCD state (will be updated by main loop)
            stateChangeTime = millis(); 
            lastTimeLog = millis(); // Force time update
            lastSosPressTime = millis(); // Re-set debounce timer to prevent immediate re-trigger
        }
    }
   
    // 4. REMOVED: Old Factory Reset Logic
    // if (digitalRead(BUTTON_MED) == LOW && digitalRead(BUTTON_SOS) == LOW) { ... }

    delay(50); // Short delay for loop stability
}

// -----------------------------------------------------------------------------
// SIM800L / SOS CALL Functions
// -----------------------------------------------------------------------------

/**
 * @brief Helper function to keep audio running during blocking loops
 */
void audio_loop_helper() {
    if (audio && audio->isRunning()) {
        if (!audio->loop()) {
            audio->stop();
        }
    }
}

/**
 * @brief Sends an AT command to Serial2 (SIM800L) and waits for a response.
 * @param command The AT command to send (without \r\n).
 * @param timeout_ms How long to wait for a response.
 * @param fullResponse Whether to print the full response (for debugging)
 * @return The full response from the module as a String.
 */
String sendATCommand(String command, long timeout_ms, bool fullResponse = false) {
    String response = "";
    while(Serial2.available()) Serial2.read(); // Clear RX buffer

    Serial2.println(command); // Send the command
    Serial.print("-> SIM800L TX: ");
    Serial.println(command);

    unsigned long timeout = millis();
    while (millis() - timeout < timeout_ms) {
        if (Serial2.available()) {
            response += (char)Serial2.read(); 
        }
    }
   
    response.trim(); // Clean up whitespace
    if (fullResponse) {
      Serial.print("<- SIM800L RX (Full): ");
      Serial.println(response);
    }
    return response;
}

/**
 * @brief NEW: Dials all emergency contacts one by one.
 * Plays sound, dials, waits 20s, hangs up, and repeats for all contacts.
 * Can be cancelled by pressing the SOS button again.
 * This function is now NON-BLOCKING for audio.
 */
void executeSosSequence() {
    // 1. Check if we have any contacts loaded
    if (contactCount == 0) {
        Serial.println("SOS ERROR: No emergency contacts loaded.");
        updateLCD("SOS ERROR:", "No Contacts");
        delay(3000);
        return;
    }

    // 2. Play the SOS sound once at the very beginning
    playWavFile("/emegency.wav");
   
    bool callCancelled = false;
    bool callAnswered = false; // NEW: Flag to stop looping if answered
    unsigned long sosStartTime = millis(); // Used to ignore the first button press
   
    // Wait for sound to play (approx 5s) before starting to dial
    // Also check for a cancel press during this time
    while(millis() - sosStartTime < 5000) {
        audio_loop_helper(); // FIX: Keep audio playing
        if (digitalRead(BUTTON_SOS) == LOW && (millis() - sosStartTime > SOS_DEBOUNCE_DELAY)) {
            Serial.println("SOS Cancelled during initial sound.");
            callCancelled = true;
            break;
        }
        delay(50);
    }

    // 3. Loop through all contacts REPEATEDLY until cancelled or answered
    while (!callCancelled && !callAnswered) {
       
        for (int i = 0; i < contactCount && !callCancelled && !callAnswered; i++) {
            String name = contacts[i].name;
            String phone = contacts[i].phone;

            Serial.println("Dialing Contact " + String(i + 1) + "/" + String(contactCount) + ": " + name + " (" + phone + ")");
            updateLCD("CALLING: " + name, phone);

            // 4. Send the dial command
            while(Serial2.available()) Serial2.read(); // Clear buffer
            Serial2.println("ATD" + phone + ";");
            Serial.println("-> SIM800L TX: ATD" + phone + ";");

            String response = "";
            bool callFailed = false; // NEW: Flag for this specific call
           
            unsigned long callStartTime = millis();
            while(millis() - callStartTime < 40000) { // 20 second timeout
                audio_loop_helper(); // Keep audio playing
               
                // Check for cancel press
                if (digitalRead(BUTTON_SOS) == LOW) {
                    Serial.println("SOS Cancelled during call.");
                    callCancelled = true;
                    break; // Break from 20-second wait loop
                }

                // Check for SIM800L responses
                if (Serial2.available()) {
                    char c = Serial2.read();
                    response += c;
                    if (response.indexOf("BUSY") != -1) {
                        Serial.println("Call is BUSY.");
                        callFailed = true;
                        break;
                    }
                    if (response.indexOf("NO CARRIER") != -1) {
                        Serial.println("Call FAILED (No Carrier).");
                        callFailed = true;
                        break;
                    }
                    if (response.indexOf("ERROR") != -1) {
                        Serial.println("Call FAILED (SIM Error).");
                        callFailed = true;
                        break;
                    }
                }
                delay(50); // Small delay
            } // End of 20-second wait loop
           
            // 5. We are out of the 20s loop. Hang up.
            Serial.println("Hanging up call...");
            sendATCommand("ATH", 3000, false); // Send Hang Up command
           
            if (callCancelled) break; // Don't process this call, just exit

            if (callFailed) {
                // Call was BUSY or FAILED. Play sound and try next contact.
                playWavFile("/emegency_informed.wav"); // Play "call declined/busy" sound
                updateLCD("Call Failed:", name);
                // Non-blocking delay for 2s
                unsigned long failDelayStart = millis();
                while(millis() - failDelayStart < 2000) {
                  audio_loop_helper();
                  delay(50);
                }
            } else {
                // Call was not busy and did not fail. This means it was ANSWERED (or rang for 20s).
                Serial.println("Call was ANSWERED (or 20s timeout).");
                callAnswered = true; // Set flag to stop the main loop
                // playWavFile("/emegency_informed.wav"); // Play sound to inform user
            }

            // 6. Pause briefly before dialing the next number (if there is one)
            if (i < contactCount - 1 && !callCancelled && !callAnswered) {
                Serial.println("Pausing 2s before next call...");
                updateLCD("Next Contact...", "");
               
                unsigned long pauseStartTime = millis();
                while(millis() - pauseStartTime < 2000) { // Wait 2 seconds
                    audio_loop_helper(); // FIX: Keep audio playing
                    // Check for cancel press
                    if (digitalRead(BUTTON_SOS) == LOW) {
                        Serial.println("SOS Cancelled during pause.");
                        callCancelled = true;
                        break;
                    }
                    delay(100);
                }
            }
        } // End of FOR loop (one cycle of all contacts)
       
        if (!callCancelled && !callAnswered) {
          Serial.println("Finished one call cycle. Restarting list...");
          updateLCD("Restarting", "Call List...");
          // Non-blocking delay for 2s
          unsigned long cycleDelayStart = millis();
          while(millis() - cycleDelayStart < 2000) {
            audio_loop_helper();
            delay(50);
          }
        }
       
    } // End of WHILE loop

    // 7. Show final status
    if (callCancelled) {
        Serial.println("Finished SOS sequence (CANCELLED).");
        playWavFile("/sos_call_cancel.wav"); 
        updateLCD("SOS", "CANCELLED");
    } else if (callAnswered) {
        Serial.println("Finished all SOS calls (ANSWERED/INFORMED).");
        playWavFile("/emegency_informed.wav"); // CHANGED: Use informed sound
        updateLCD("SOS Calls", "Finished.");
    }
   
    // FIX: Replace delay with a non-blocking loop
    unsigned long finalDelayStart = millis();
    while(millis() - finalDelayStart < 3000) {
      audio_loop_helper();
      delay(50);
    }

    lastSosPressTime = millis(); // Set debounce to prevent immediate re-trigger
}


/**
 * @brief Plays the specified WAV file from LittleFS using ESP8266Audio.
 * @param filename The path to the WAV file (e.g., "/filename.wav").
 */
void playWavFile(const char* filename) {
    Serial.print("Attempting to play [ESP8266Audio]: ");
    Serial.println(filename);

    // 1. Stop any currently playing audio
    if (audio && audio->isRunning()) {
        Serial.println("Stopping previous audio...");
        audio->stop();
    }
   
    // Safety check for initialization
    if (!file || !audio || !out) {
        Serial.println("ERROR: Audio system not initialized. Cannot play.");
        return;
    }

    // 2. Open the file and start playback
    if (file->open(filename)) {
        Serial.println("SUCCESS: File opened in LittleFS.");
        // Start the generator, linking the file source to the I2S output
        if (audio->begin(file, out)) {
            Serial.println("WAV file playback started.");
        } else {
            Serial.println("ERROR: audio->begin() failed.");
        }
    } else {
        Serial.print("ERROR: Could not open file in LittleFS: ");
        Serial.println(filename);
    }
}


// -----------------------------------------------------------------------------
// Configuration & BLE Functions
// -----------------------------------------------------------------------------

/**
 * @brief Saves received JSON data to /config.json and sets global vars.
 * @param data The JSON string received from BLE.
 * @return true on success, false on failure.
 */
bool saveConfiguration(std::string data) {
    Serial.println("Attempting to parse and save new configuration...");

    // 1. Parse the JSON to check if it's valid and set global vars
    StaticJsonDocument<1024> doc;
    DeserializationError error = deserializeJson(doc, data);

    if (error) {
        Serial.print("Failed to parse config string, error: ");
        Serial.println(error.c_str());
        return false;
    }

    // Copy values from the JSON document to global variables
    wifi_ssid = doc["ssid"].as<String>();
    wifi_password = doc["pass"].as<String>();
    user_id = doc["user_id"].as<String>();
    firebase_host = doc["fb_host"].as<String>();
    firebase_auth = doc["fb_auth"].as<String>();

    // Validate
    if (wifi_ssid.length() == 0 || user_id.length() == 0 || firebase_host.length() == 0) {
        Serial.println("ERROR: Parsed JSON is missing required fields (ssid, user_id, fb_host).");
        return false;
    }

    // 2. Save the raw JSON string to LittleFS
    File configFile = LittleFS.open("/config.json", "w");
    if (!configFile) {
        Serial.println("Failed to open /config.json for writing");
        return false;
    }

    configFile.print(data.c_str());
    configFile.close();

    Serial.println("Successfully saved new config to /config.json");

    // 3. Construct dynamic paths (so they are ready for next boot)
    rtdb_schedule_path = "/reminders/" + user_id + "/schedule";
    rtdb_confirm_path = "/reminders/" + user_id + "/confirmation";
    rtdb_emergency_path = "/appData/" + user_id + "/emergencyContacts"; // FIX: Corrected to appData
    rtdb_device_path = "/reminders/" + user_id + "/device"; // NEW

    return true;
}


/**
 * @brief Starts the BLE Server for provisioning.
 */
void startBLEProvisioning() {
    Serial.println("Starting BLE Provisioning Server...");
   
    // 1. Initialize BLE
    BLEDevice::init("AgeLink-Setup");

    // 2. Create the BLE Server
    BLEServer *pServer = BLEDevice::createServer();
    pServer->setCallbacks(new MyServerCallbacks());

    // 3. Create the BLE Service
    BLEService *pService = pServer->createService(SERVICE_UUID);

    // 4. Create the BLE Characteristic
    BLECharacteristic *pCharacteristic = pService->createCharacteristic(
                                         CHARACTERISTIC_UUID,
                                         BLECharacteristic::PROPERTY_WRITE
                                       );
    pCharacteristic->setCallbacks(new MyCharacteristicCallbacks());

    // 5. Start the service
    pService->start();

    // 6. Start Advertising
    BLEAdvertising *pAdvertising = BLEDevice::getAdvertising();
    pAdvertising->addServiceUUID(SERVICE_UUID);
    pAdvertising->setScanResponse(true);
    pAdvertising->setMinPreferred(0x06); // functions changing values automatically
    pAdvertising->setMinPreferred(0x12);
    BLEDevice::startAdvertising();
   
    Serial.println("BLE Server started. Waiting for app connection...");
}


// NEW: Function to load configuration from /config.json
/**
 * @brief Loads WiFi and Firebase credentials from /config.json in LittleFS.
 * @return true on success, false on failure.
 */
bool loadConfiguration() {
    Serial.println("Mounting LittleFS to read configuration...");
    if (!LittleFS.begin(true)) {
        Serial.println("Failed to mount file system");
        return false;
    }

    File configFile = LittleFS.open("/config.json", "r");
    if (!configFile) {
        Serial.println("Failed to open /config.json");
        return false;
    }

    // --- NEW: Read file content to a string for printing ---
    String configFileContent = "";
    while (configFile.available()) {
        configFileContent += (char)configFile.read();
    }
   
    Serial.println("--- Reading /config.json ---");
    Serial.println(configFileContent);
    Serial.println("----------------------------");
    // --- END OF NEW PRINTING CODE ---

    // Allocate a buffer to store the file content
    StaticJsonDocument<1024> doc; 

    // Deserialize the JSON document from the string
    DeserializationError error = deserializeJson(doc, configFileContent);
    if (error) {
        Serial.print("Failed to parse config file, error: ");
        Serial.println(error.c_str());
        configFile.close();
        return false;
    }

    // Copy values from the JSON document to global variables
    wifi_ssid = doc["ssid"].as<String>();
    wifi_password = doc["pass"].as<String>();
    user_id = doc["user_id"].as<String>();
    firebase_host = doc["fb_host"].as<String>();
    firebase_auth = doc["fb_auth"].as<String>();

    configFile.close();

    // --- Validate loaded data ---
    if (wifi_ssid.length() == 0) {
        Serial.println("ERROR: 'ssid' not found in config.json");
        return false;
    }
     if (user_id.length() == 0) {
        Serial.println("ERROR: 'user_id' not found in config.json");
        return false;
    }
    if (firebase_host.length() == 0) {
        Serial.println("ERROR: 'fb_host' not found in config.json");
        return false;
    }

    Serial.println("--- Configuration Loaded ---");
    Serial.println("SSID: " + wifi_ssid);
    Serial.println("User ID: " + user_id);
    Serial.println("FB Host: " + firebase_host);
    Serial.println("----------------------------");

    // --- Construct dynamic paths ---
    rtdb_schedule_path = "/reminders/" + user_id + "/schedule";
    rtdb_confirm_path = "/reminders/" + user_id + "/confirmation";
    rtdb_emergency_path = "/appData/" + user_id + "/emergencyContacts"; // FIX: Corrected to appData
    rtdb_device_path = "/reminders/" + user_id + "/device"; // NEW

    return true;
}


/**
 * @brief Initializes the ESP32 I2S peripheral using ESP8266Audio.
 */
void initI2S() {
    // 1. Create I2S Output object
    out = new AudioOutputI2S();
   
    // 2. Configure I2S pins (BCLK, LRC, DOUT)
    out->SetPinout(I2S_BCLK, I2S_LRC, I2S_DOUT);
   
    // 3. Start I2S (This uses the default configuration)
    out->begin();
   
    // NEW: Set initial volume
    out->SetGain(currentVolume);

    // 4. Create the File Source and Audio Generator objects
    file = new AudioFileSourceLittleFS();
    audio = new AudioGeneratorWAV();

    // 5. Assign Callbacks (FIXED)
    audio->RegisterMetadataCB(audio_metadata_cb, nullptr);
    audio->RegisterStatusCB(audio_status_cb, nullptr);     
    file->RegisterStatusCB(file_status_cb, nullptr);

    Serial.println("ESP8266Audio I2S Driver initialized with debugging callbacks.");
}


/**
 * @brief NEW: Fetches device settings (like volume) from Firebase RTDB.
 */
void fetchDeviceSettings() {
    if (offlineMode) return; // Don't try to fetch if we're offline

    // Serial.println("Fetching device settings..."); // Removed spam
    audio->stop(); // FIX: Stop audio before Firebase calls to prevent noise

    if (Firebase.getString(fbdo, rtdb_device_path)) {
        if (fbdo.dataType() == "json") {
            FirebaseJson json = fbdo.jsonString();
            FirebaseJsonData result;

            // 1. Get the "volume" field
            if (json.get(result, FPSTR("volume"))) {
                if (result.type == "float" || result.type == "int" || result.type == "double") {
                    float newVolume = result.floatValue;
                    if (newVolume < 0.0) newVolume = 0.0;
                    if (newVolume > 1.0) newVolume = 1.0; // Cap at 1.0 (100%)
                   
                    if (newVolume != currentVolume) {
                        currentVolume = newVolume;
                        out->SetGain(currentVolume); // Set the new volume
                        Serial.println("Successfully set new volume: " + String(currentVolume));
                    } else {
                        // Serial.println("Volume is already set to: " + String(currentVolume)); // Removed spam
                    }
                } else {
                    Serial.println("RTDB Read WARNING: 'volume' field is not a number.");
                }
            } else {
                // Serial.println("RTDB Read WARNING: 'volume' field not found."); // Removed spam
            }
        } else {
            Serial.print("RTDB Read ERROR: Device settings path is not JSON, it is: ");
            Serial.println(fbdo.dataType());
        }
    } else {
        Serial.println("RTDB Read ERROR: Failed to read device settings path. Reason: " + fbdo.errorReason());
    }
}


/**
 * @brief Fetches all emergency contacts (name and number) from Firebase RTDB.
 */
void fetchEmergencyContact() {
    Serial.println("Fetching emergency contacts...");
    contactCount = 0; // Reset contact list

    if (offlineMode) {
      Serial.println("Offline mode. Skipping Firebase fetch.");
      // FIX: Try to load contacts from file. If it fails, use the fallback.
      if (!loadContactsFromFile()) {
          Serial.println("Could not load contacts from file. Using fallback.");
          // Fallback if file load failed
          contacts[0].name = "Emergency";
          contacts[0].phone = "0763777417"; // Generic Fallback number
          contactCount = 1; // We have one fallback contact
          Serial.println(">>> Using FALLBACK emergency contact: " + contacts[0].name + " / " + contacts[0].phone);
      }
      return;
    }

    audio->stop(); // FIX: Stop audio before Firebase calls to prevent noise

    // NEW LOGIC: Read the path as a JSON string to iterate
    if (Firebase.getString(fbdo, rtdb_emergency_path)) { // CHANGED
        if (fbdo.dataType() == "json") {
            FirebaseJson json = fbdo.jsonString();
            size_t len = json.iteratorBegin();
            FirebaseJsonData result; 

            // Loop through all contacts found, up to our max limit
            for (size_t i = 0; i < len && i < MAX_CONTACTS; i++) {
                String key = "";
                String value = "";
                int type = 0;
               
                // Get the contact object (e.g., "-OdXfmv_rAfs...")
                json.iteratorGet(i, type, key, value);
               
                FirebaseJson tempJson;
                tempJson.setJsonData(value);

                String tempName = "";
                String tempPhone = "";

                // Get the "phone" field
                if (tempJson.get(result, FPSTR("phone"))) {
                    tempPhone = result.stringValue; 
                    tempPhone.trim();
                } else {
                     Serial.println("RTDB Read WARNING: Contact missing 'phone' field.");
                }

                // Get the "name" field
                if (tempJson.get(result, FPSTR("name"))) {
                    tempName = result.stringValue; 
                    tempName.trim();
                } else {
                     Serial.println("RTDB Read WARNING: Contact missing 'name' field.");
                }

                // If we got both a valid name and phone, add to our list
                if (tempPhone.length() > 6 && tempName.length() > 0) {
                    contacts[contactCount].name = tempName;
                    contacts[contactCount].phone = tempPhone;
                    Serial.println("Loaded contact (" + String(contactCount+1) + "): " + contacts[contactCount].name + " / " + contacts[contactCount].phone);
                    contactCount++; // Increment the number of loaded contacts
                }
            }
            json.iteratorEnd();

            if (contactCount == 0) {
                 Serial.println("RTDB Read WARNING: emergencyContacts path is empty or contacts are invalid.");
            }

        } else {
            Serial.print("RTDB Read ERROR: Data type is not a JSON object, it is: ");
            Serial.println(fbdo.dataType());
        }
    } else {
        Serial.println("RTDB Read ERROR: Failed to read emergency path. Reason: " + fbdo.errorReason());
        Serial.println("Attempting to load contacts from file...");
        loadContactsFromFile(); // Load from backup
    }

    // Fallback if fetch failed AND file load failed
    if (contactCount == 0) { 
        contacts[0].name = "Emergency";
        contacts[0].phone = "0763777417"; // Generic Fallback number
        contactCount = 1; // We have one fallback contact
        Serial.println(">>> Using FALLBACK emergency contact: " + contacts[0].name + " / " + contacts[0].phone);
        saveContactsToFile(); // Save the fallback so it's available offline
    }
}


/**
 * @brief Executes the alarm sequence (LED, LCD, WAV) for a given phase.
 */
void startAlarmSequence(ReminderState phase) {
    const char* wav_file = nullptr; // Initialize to nullptr
    Serial.print("Starting Alarm Sequence: ");
   
    // Set LED and LCD for the active period (LED stays ON)
    if (phase == GREEN_ACTIVE) {
        Serial.println("GREEN (First Reminder)");
        setLEDs(true, false, false); // Green ON
        updateLCD("TIME TO TAKE:", currentMedicineName);
        wav_file = "/first_reminder.wav";
    } else if (phase == ORANGE_ACTIVE) {
        Serial.println("ORANGE (Second Reminder)");
        setLEDs(false, true, false); // Orange ON
        updateLCD("SECOND REMINDER:", currentMedicineName);
        wav_file = "/second_reminder.wav";
    } else if (phase == RED_ACTIVE) {
        Serial.println("RED (Final Reminder)");
        setLEDs(false, false, true); // Red ON
        updateLCD("FINAL REMINDER:", currentMedicineName);
        wav_file = "/final_reminder.wav"; 
    }
   
    // Execute the WAV file playback 
    if (wav_file) {
        playWavFile(wav_file);
        Serial.println("WAV playback initiated.");
    } else {
        Serial.println("ERROR: No WAV file specified for this phase.");
    }
}

// -----------------------------------------------------------------------------
// LCD Functions
// -----------------------------------------------------------------------------

/**
 * @brief Initializes the I2C LCD.
 */
void initLCD() {
    Wire.begin(I2C_SDA, I2C_SCL); 
    delay(100); 
    lcd.init();
    lcd.backlight();
    Serial.println("LCD Initialized (0x3F).");
}

/**
 * @brief Clears and updates both lines of the LCD. (NON-FLICKER + CORRUPTION FIX)
 * @param line1 Text for the first line.
 * @param line2 Text for the second line.
 */
void updateLCD(String line1, String line2) {
    // Trim to length
    String line1_trimmed = line1.substring(0, LCD_COLUMNS);
    String line2_trimmed = line2.substring(0, LCD_COLUMNS);

    // Check if the text has actually changed
    if (line1_trimmed == lcdLine1_last && line2_trimmed == lcdLine2_last) {
        // Nothing to update, just return. This prevents flicker.
        return; 
    }

    // --- SOFTWARE FIX FOR LCD CORRUPTION ---
    // This code only runs when the text has changed (e.g., once per minute or on state change)
    // Re-initializing the LCD just before writing clears any garbage.
    lcd.init();
    lcd.backlight();
    // --- END OF FIX ---

    // We still clear, but it only happens when text changes
    lcd.clear(); 

    // Update Line 1
    lcd.setCursor(0, 0);
    lcd.print(line1_trimmed);
    lcdLine1_last = line1_trimmed; // Store the new value

    // Update Line 2
    lcd.setCursor(0, 1);
    lcd.print(line2_trimmed);
    lcdLine2_last = line2_trimmed; // Store the new value
}

// -----------------------------------------------------------------------------
// Firebase and Time Functions
// -----------------------------------------------------------------------------

// REMOVED: Entire WiFiEvent() function
// /**
// * @brief NEW: Handles WiFi connect and disconnect events.
// ...
// */
// void WiFiEvent(WiFiEvent_t event) { ... }


/**
 * @brief Initializes NTP time sync.
 */
void initNTP() {
    configTime(gmtOffset_sec, daylightOffset_sec, ntpServer);
    Serial.println("Waiting for NTP time sync...");
    while (!getLocalTime(&timeinfo)) {
        Serial.print(".");
        audio_loop_helper(); // FIX: Keep audio playing during this loop
        delay(500);
    }
    Serial.println("\nNTP Time Initialized.");
}

/**
 * @brief Gets the current time as a "HH:MM" formatted String. (FIXED)
 * @return String e.g., "09:30" or "17:05".
 */
String getCurrentTimeFormatted() {
    char timeStr[6]; // "HH:MM\0"
    // Note: getLocalTime() must be called in loop() before this
    strftime(timeStr, sizeof(timeStr), "%H:%M", &timeinfo); // CHANGED to colon
    return String(timeStr);
}

/**
 * @brief Checks Firebase for a scheduled time matching the current time.
 * @param currentTime The "HH:MM" formatted time string.
 */
bool checkScheduledTime(String currentTime) { // MODIFIED: Returns bool
    if (currentState != IDLE && currentState != MISSED) {
        // Serial.println("DB Check skipped: Alarm sequence is currently active."); // Reduce spam
        return false; // MODIFIED
    }
   
    if (offlineMode) {
        // Serial.println("Offline mode. Skipping Firebase schedule check.");
        return false; // Don't check firebase if offline
    }

    Serial.print("Checking schedule and updating last_sync for time: "); // MODIFIED
    Serial.println(currentTime);
    
    // NEW: Update last_sync time to Firebase. This creates the path if it doesn't exist.
    Firebase.setString(fbdo, rtdb_device_path + "/last_sync", currentTime);
    
    audio->stop(); // FIX: Stop audio before Firebase calls to prevent noise

    String path = rtdb_schedule_path + "/med_times"; // CHANGED
   
    // NEW: Logic for finding the next time
    String nextTimeToday = "25:00"; // Earliest time found today (later than now)
    String earliestTimeOverall = "25:00"; // Earliest time in the whole list (for tomorrow)
    String nextNameToday = "None";
    String earliestNameOverall = "None";
    bool alarmTriggered = false; // Flag to prevent multiple alarms

    if (Firebase.getString(fbdo, path)) {
        // NEW: Save the schedule to a file for offline use (every 20 mins)
        if (millis() - lastScheduleSaveTime > SCHEDULE_SAVE_INTERVAL_MS) {
            File scheduleFile = LittleFS.open("/schedule.json", "w");
            if(scheduleFile) {
              scheduleFile.print(fbdo.stringData());
              scheduleFile.close();
              Serial.println("Successfully saved schedule to /schedule.json");
              lastScheduleSaveTime = millis(); // Reset the timer
            } else {
              Serial.println("Failed to open /schedule.json for writing");
            }
        }

        if (fbdo.dataType() == "json") {
            FirebaseJson json = fbdo.jsonString();
            size_t len = json.iteratorBegin();
            FirebaseJsonData result; 
            for (size_t i = 0; i < len; i++) {
                String key = "";
                String value = "";
                int type = 0;
                json.iteratorGet(i, type, key, value);
               
                // Each 'value' is a JSON object {"name": "...", "time": "..."}
                FirebaseJson tempJson;
                tempJson.setJsonData(value);
               
                String medicineTime = "";
                String medicineName = "";
               
                // Get the time
                if (tempJson.get(result, FPSTR("time"))) {
                    if (result.type == "string") {
                        medicineTime = result.stringValue; 
                        medicineTime.trim(); 
                        // Time Normalization Fix (e.g., "9:15" to "09:15")
                        if (medicineTime.length() == 4 && medicineTime[1] == ':') { // CHANGED to colon
                            medicineTime = "0" + medicineTime; 
                        }
                    } else {
                        Serial.println("WARNING: Time entry type is not a string. Skipping.");
                        medicineTime = "";
                    }
                }
               
                // Get the name
                if (tempJson.get(result, FPSTR("name"))) {
                    medicineName = result.stringValue; 
                    medicineName.trim();
                }
               
                // --- REMOVED Serial.print spam ---
               
                // --- START OF MODIFIED LOGIC ---

                if (medicineTime.isEmpty()) continue; // Skip if no time

                // 1. Check for earliest time overall (for "tomorrow" logic)
                if (medicineTime < earliestTimeOverall) {
                    earliestTimeOverall = medicineTime;
                    earliestNameOverall = medicineName; // Store name
                }

                // 2. Check for next time today
                if (medicineTime > currentTime && medicineTime < nextTimeToday) {
                    nextTimeToday = medicineTime;
                    nextNameToday = medicineName; // Store name
                }
               
                // 3. Check for exact match (ALARM TRIGGER)
                // Only trigger if an alarm hasn't already been triggered this cycle
                // AND it wasn't just confirmed this same minute
                if (currentTime.equals(medicineTime) && !alarmTriggered && currentTime != lastConfirmedTime) {
                    Serial.println("***** ALARM TRIGGERED! TIME MATCH CONFIRMED *****");
                   
                    currentMedicineName = medicineName;
                    currentState = GREEN_ACTIVE; // Start the alarm sequence
                    stateChangeTime = millis();  // Set the start time
                    startAlarmSequence(GREEN_ACTIVE); // Run the first alert
                   
                    // Update status in Firebase
                    Firebase.setString(fbdo, rtdb_schedule_path + "/current_status", "ACTIVE"); // CHANGED
                   
                    alarmTriggered = true; // Set flag
                    // DO NOT RETURN. We need to process the whole list for "next time".
                }
                // --- END OF MODIFIED LOGIC ---
            } // END OF FOR LOOP
            json.iteratorEnd();

            // --- NEW: Update the global nextMedicineTime variable ---
            if (nextTimeToday != "25:00") {
                // We found a time later today
                nextMedicineTime = nextTimeToday;
                nextMedicineName = nextNameToday;
            } else if (earliestTimeOverall != "25:00") {
                // No time later today, so the next time is the earliest one tomorrow
                nextMedicineTime = earliestTimeOverall;
                nextMedicineName = earliestNameOverall;
            } else {
                // No schedule found at all
                nextMedicineTime = "--:--";
                nextMedicineName = "None";
            }
            Serial.println("Next medicine time found: " + nextMedicineName + " (" + nextMedicineTime + ")");
            // --- END NEW ---

            if (alarmTriggered) {
                return true; // MODIFIED: Report that an alarm was triggered
            }

            // Serial.println("--- DB Check Complete (No match found) ---"); // Reduce spam
        } else { // THIS IS THE 'ELSE' FROM THE ERROR
            Serial.println("RTDB Read ERROR: med_times is not JSON. Reason: " + fbdo.errorReason());
            // loadScheduleFromFile(); // REMOVED: Do not load schedule in offline mode
        } 
    } else {
        Serial.println("RTDB Read ERROR: Failed to read med_times path. Reason: " + fbdo.errorReason());
        // loadScheduleFromFile(); // REMOVED: Do not load schedule in offline mode
    }

    return false; // MODIFIED: No alarm was triggered
}

/**
 * @brief Sets the state of the three reminder LEDs.
 */
void setLEDs(bool green, bool orange, bool red) {
    digitalWrite(LED_GREEN, green ? HIGH : LOW);
    digitalWrite(LED_ORANGE, orange ? HIGH : LOW);
    digitalWrite(LED_RED, red ? HIGH : LOW);
} // <<< FIX: Added the missing closing brace here

/**
 * @brief Logs the confirmation to Firebase.
 * @param state The state at which confirmation happened ("Green", "Orange", "Red").
 */
void handleConfirmation(String state) {
    // 1. Play confirmation sounds
    playWavFile("/medicine_confirm.wav"); // Play first sound

    // NEW: Add a non-blocking delay to let the sound play
    // BEFORE we try to use Firebase (which causes a conflict).
    unsigned long confirmSoundStart = millis();
    while(millis() - confirmSoundStart < 2000) { // Wait for 2 seconds
        audio_loop_helper(); // Keep the audio playing
        delay(50);
    }
    // By now, the sound is finished, and audio->stop() has likely been called by the EOF callback.
    audio->stop(); // FIX: Force stop audio before Firebase
    Serial.println("Audio stopped, pushing confirmation to Firebase...");

    // 2. Send data to Firebase
    FirebaseJson confirmationJson;
    confirmationJson.set("confirmed_at", getCurrentTimeFormatted());
    confirmationJson.set("medicine_name", currentMedicineName);
    confirmationJson.set("reminder_state", state);
    // NEW: Add the Firebase Server Timestamp
    confirmationJson.set("confirmed_at_timestamp/.sv", "timestamp");

    // 3. NEW: Fix the re-trigger loop
    lastConfirmedTime = getCurrentTimeFormatted();

    // Pushes a new unique entry under the /confirmation path
    if (Firebase.push(fbdo, rtdb_confirm_path, confirmationJson)) { // CHANGED
        Serial.println("Firebase Confirmation PUSHED successfully. State: " + state);
        Firebase.setString(fbdo, rtdb_schedule_path + "/current_status", "CONFIRMED"); // CHANGED
        updateLCD("Confirmation:", "RECEIVED!");
    } else {
        Serial.println("Firebase Confirmation Failed: " + fbdo.errorReason());
    }
    // Note: stateChangeTime is set in the main loop when state transitions to CONFIRMED
}

/**
 * @brief NEW: Logs a MISSED event to Firebase.
 * @param medicineName The name of the medicine that was missed.
 */
void handleMissed(String medicineName) {
    Serial.println("Logging as MISSED to Firebase...");
    audio->stop(); // Ensure audio is stopped before Firebase call

    FirebaseJson missedJson;
    String currentTime = getCurrentTimeFormatted();

    missedJson.set("confirmed_at", currentTime);
    missedJson.set("medicine_name", medicineName);
    missedJson.set("reminder_state", "MISSED");
    // NEW: Add the Firebase Server Timestamp
    missedJson.set("confirmed_at_timestamp/.sv", "timestamp");

    // Pushes a new unique entry under the /confirmation path
    if (Firebase.push(fbdo, rtdb_confirm_path, missedJson)) {
        Serial.println("Firebase MISSED event PUSHED successfully.");
        // Also update the status for the app's dashboard
        Firebase.setString(fbdo, rtdb_schedule_path + "/current_status", "MISSED");
    } else {
        Serial.println("Firebase MISSED event push Failed: " + fbdo.errorReason());
    }

    // Play the missed sound *after* the Firebase push
    playWavFile("/medicine_missed.wav");
}


// -----------------------------------------------------------------------------
// NEW: Offline File Functions
// -----------------------------------------------------------------------------

/**
 * @brief Saves the current contact list to /contacts.json
 */
bool saveContactsToFile() {
    Serial.println("Saving emergency contacts to /contacts.json...");
    File contactFile = LittleFS.open("/contacts.json", "w");
    if (!contactFile) {
        Serial.println("Failed to open /contacts.json for writing");
        return false;
    }

    StaticJsonDocument<512> doc;
    JsonArray array = doc.to<JsonArray>();
    for (int i = 0; i < contactCount; i++) {
        JsonObject contact = array.createNestedObject();
        contact["name"] = contacts[i].name;
        contact["phone"] = contacts[i].phone;
    }

    if (serializeJson(doc, contactFile) == 0) {
        Serial.println("Failed to write to /contacts.json");
        contactFile.close();
        return false;
    }

    contactFile.close();
    Serial.println("Successfully saved contacts to file.");
    return true;
}

/**
 * @brief Loads the contact list from /contacts.json
 */
bool loadContactsFromFile() {
    Serial.println("Loading emergency contacts from /contacts.json...");
    File contactFile = LittleFS.open("/contacts.json", "r");
    if (!contactFile) {
        Serial.println("Failed to open /contacts.json for reading");
        return false;
    }

    StaticJsonDocument<512> doc;
    DeserializationError error = deserializeJson(doc, contactFile);
    if (error) {
        Serial.print("Failed to parse /contacts.json: ");
        Serial.println(error.c_str());
        contactFile.close();
        return false;
    }
    contactFile.close();

    JsonArray array = doc.as<JsonArray>();
    contactCount = 0;
    for (JsonObject contact : array) {
        if (contactCount >= MAX_CONTACTS) break;
        contacts[contactCount].name = contact["name"].as<String>();
        contacts[contactCount].phone = contact["phone"].as<String>();
        Serial.println("Loaded contact from file: " + contacts[contactCount].name);
        contactCount++;
    }
    Serial.println("Successfully loaded " + String(contactCount) + " contacts from file.");
    // FIX: Only return true if we actually loaded one or more contacts
    return (contactCount > 0);
}

/**
 * @brief Loads the schedule from /schedule.json (for display only)
 */
bool loadScheduleFromFile() {
    // THIS FUNCTION IS NO LONGER CALLED IN OFFLINE MODE
    // It is only used by checkScheduledTime if Firebase read fails
    // (which means we are online but Firebase had a temporary error)
    if (offlineMode) return false; 

    Serial.println("Loading schedule from /schedule.json as backup...");
    File scheduleFile = LittleFS.open("/schedule.json", "r");
    if (!scheduleFile) {
        Serial.println("Failed to open /schedule.json");
        return false;
    }

    StaticJsonDocument<1024> doc; // Use same size as in checkSchedule
    DeserializationError error = deserializeJson(doc, scheduleFile);
    if (error) {
        Serial.print("Failed to parse /schedule.json: ");
        Serial.println(error.c_str());
        scheduleFile.close();
        return false;
    }
    scheduleFile.close();
   
    // This is a simplified version of the logic in checkScheduledTime
    // It does not trigger alarms, it only finds the next time for the display
    String currentTime = getCurrentTimeFormatted();
    String nextTimeToday = "25:00"; 
    String earliestTimeOverall = "25:00";
    String nextNameToday = "None";
    String earliestNameOverall = "None";

    // We assume the file is a JSON object with keys like "-M...": { "name": "...", "time": "..." }
    if (doc.is<JsonObject>()) {
        for (JsonPair kv : doc.as<JsonObject>()) { // FIX: Changed JsonPairConst to JsonPair
            String medicineTime = kv.value()["time"].as<String>();
            String medicineName = kv.value()["name"].as<String>();
           
            if (medicineTime.isEmpty()) continue;

            // Time Normalization Fix (e.g., "9:15" to "09:15")
            if (medicineTime.length() == 4 && medicineTime[1] == ':') {
                medicineTime = "0" + medicineTime; 
            }

            if (medicineTime < earliestTimeOverall) {
                earliestTimeOverall = medicineTime;
                earliestNameOverall = medicineName;
            }
            if (medicineTime > currentTime && medicineTime < nextTimeToday) {
                nextTimeToday = medicineTime;
                nextNameToday = medicineName;
            }
        }
    }

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
    Serial.println("Offline Next medicine time: " + nextMedicineTime + " (" + nextMedicineName + ")");
    return true;
}


/**
 * @brief Deletes all configuration files for a factory reset.
 */
void deleteConfigurationFiles() {
    Serial.println("Deleting configuration files...");
    if (LittleFS.remove("/config.json")) {
        Serial.println("Deleted /config.json");
    }
    if (LittleFS.remove("/contacts.json")) {
        Serial.println("Deleted /contacts.json"); // FIX: Was Serial.Delted
    }
    if (LittleFS.remove("/schedule.json")) {
        Serial.println("Deleted /schedule.json");
    }
    Serial.println("File deletion complete.");
}
