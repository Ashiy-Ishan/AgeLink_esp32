#include <WiFi.h>
#include <FirebaseESP32.h>
#include <time.h>
#include "AudioTools.h"
#include "driver/i2s.h"
#include "addons/TokenHelper.h"
#include <cmath> // Required for sinf() function
#include <Wire.h>
#include <LiquidCrystal_I2C.h> // Library for I2C LCD

// --- 1. WiFi and Firebase Credentials ---
#define WIFI_SSID "M.Sanka"
#define WIFI_PASSWORD "07685851311"
#define FIREBASE_HOST "agelink-f4680-default-rtdb.asia-southeast1.firebasedatabase.app"
#define FIREBASE_AUTH "iVNn4iHyjp2TizXHcx0QgrwGyEboJba8pxuDVLGm"
#define USER_ID "1SCOyVZCC9cz62oxWAtPbi4pWzt1"
#define RTDB_SCHEDULE_PATH "/reminders/" USER_ID "/schedule"
#define RTDB_CONFIRM_PATH "/reminders/" USER_ID "/confirmation"
#define RTDB_EMERGENCY_PATH "/reminders/" USER_ID "/emergency_contact"

// --- 2. Component Pin Definitions ---
#define LED_GREEN     14
#define LED_ORANGE    12
#define LED_RED       13
#define BUTTON_MED    33 // Medicine Button
#define BUTTON_SOS    32 // SOS Button

// SIM800L / Serial2 Pins
#define RX2_PIN 16
#define TX2_PIN 17

// MAX98355A I2S Pins
#define I2S_DOUT      19
#define I2S_LRC       25 // LRCLK (Word Select)
#define I2S_BCLK      26 // Bit Clock

// LCD Definitions
#define I2C_SDA 21
#define I2C_SCL 22
#define LCD_COLUMNS 16
#define LCD_ROWS 2
#define LCD_I2C_ADDRESS 0x27

// --- 3. State and Timing Variables ---
enum ReminderState { IDLE, GREEN_ACTIVE, ORANGE_ACTIVE, RED_ACTIVE, CONFIRMED, MISSED, SOS_ACTIVE, SOS_INFORMED };
ReminderState currentState = IDLE;
unsigned long stateChangeTime = 0;
unsigned long lastDBCheckTime = 0;
const long DB_CHECK_INTERVAL_MS = 60 * 1000; // Check DB every minute

// SOS Button Long Press and Call Management Variables
unsigned long sosPressStartTime = 0;
unsigned long callStartTime = 0;
bool isCalling = false; // Is a call currently attempting to connect or in progress?

// --- SOS Loop Control Variables ---
bool isSOSLoopActive = false;
unsigned long lastCallEndTime = 0;
unsigned long sosStopPressStartTime = 0; // For the 5s stop check

// Reminder Timing
const long ALARM_BEEP_DURATION_MS = 5 * 1000; // 5 seconds LED active time
const long SOS_INITIATE_HOLD = 3000;         // 3 seconds to INITIATE the SOS call loop
const long SOS_STOP_HOLD_DURATION = 5000;    // 5 seconds to STOP the SOS call loop
const long SOS_CALL_DURATION = 10000;        // 10 seconds per call
const long SOS_RECALL_DELAY = 10000;         // 10 seconds delay between calls
const long LONG_WAIT_MS = 120 * 1000;        // 2 minutes wait (Green -> Orange, Red -> Missed)
const long SHORT_WAIT_MS = 60 * 1000;        // 1 minute wait (Orange -> Red)

String currentMedicineName = "";
String emergencyNumber = "";

// Time Variables
const char* ntpServer = "pool.ntp.org";
const long  gmtOffset_sec = 19800; // GMT +5:30 (India/Sri Lanka)
const int   daylightOffset_sec = 0;
struct tm timeinfo;
unsigned long lastTimeLog = 0;
const unsigned long logInterval = 10000;

// Firebase & Audio Objects
FirebaseData fbdo;
FirebaseConfig config;
FirebaseAuth auth;
LiquidCrystal_I2C lcd(LCD_I2C_ADDRESS, LCD_COLUMNS, LCD_ROWS);

// --- 4. TONE GENERATION SETUP ---
#define SAMPLE_RATE 16000
#define TONE_FREQUENCY 800

// Audio Variables for Volume Control and Patterns
float maxAmplitude = 32767.0; // Max amplitude for 16-bit audio
float currentVolume = 0.01;   // Start at 50% volume (0.0 to 1.0)
int16_t TONE_BUFFER_SHORT[8000]; // Buffer for 500ms tone (16KB)
int16_t TONE_BUFFER_LONG[24000];  // Buffer for 1500ms tone (48KB)
int SAMPLES_SHORT = 0;
int SAMPLES_LONG = 0;

// --- 5. Function Prototypes ---
void initNTP();
void setVolume(float vol);
void writeTone(int16_t* buffer, int num_samples);
void generateToneBuffers();
void playBeepPattern();
void playSOSPatterm();
String getCurrentTimeFormatted();
void checkScheduledTime(String currentTime);
void setLEDs(bool green, bool orange, bool red);
void handleConfirmation(String state);
void playBeep();
void startAlarmSequence(ReminderState phase);
void initI2S();
void initLCD();
void updateLCD(String line1, String line2);
void fetchEmergencyContact();
bool makeCall(String phoneNumber);
void hangUpCall();
String sendATCommand(String command, long timeout_ms);
void monitorSIM800L_URCs();
void transitionToInformed();


void setup() {
    Serial.begin(115200);

    // Initialize Pins
    pinMode(LED_GREEN, OUTPUT);
    pinMode(LED_ORANGE, OUTPUT);
    pinMode(LED_RED, OUTPUT);
    pinMode(BUTTON_MED, INPUT_PULLUP);
    pinMode(BUTTON_SOS, INPUT_PULLUP);
    setLEDs(false, false, false);

    // 1. Initialize SIM800L Serial Communication (Serial2)
    Serial2.begin(9600, SERIAL_8N1, RX2_PIN, TX2_PIN);
    delay(100);
    Serial.println("--- SIM800L Initialization (Serial2 @ 9600) ---");
    updateLCD("SIM800L Check", "Starting...");

    // A. Check basic module responsiveness
    String simResponse = sendATCommand("AT", 3000);
    if (simResponse.indexOf("OK") != -1) {
        Serial.println("SIM800L: BASIC CHECK OK.");
    } else {
        Serial.println("SIM800L ERROR: No 'OK' response. Check power/wiring.");
    }
    delay(1000);

    // B. Check Network Registration Status
    updateLCD("SIM800L Check", "Network Status...");
    simResponse = sendATCommand("AT+CREG?", 5000);
    if (simResponse.indexOf("+CREG: 0,1") != -1 || simResponse.indexOf("+CREG: 0,5") != -1) {
        Serial.println("SIM800L: REGISTERED TO NETWORK (0,1 or 0,5).");
    } else {
        Serial.println("SIM800L WARNING: NOT REGISTERED. Check SIM/Signal.");
    }
    delay(1000);

    // C. Check Signal Quality
    updateLCD("SIM800L Check", "Signal Quality...");
    simResponse = sendATCommand("AT+CSQ", 5000);
    if (simResponse.indexOf("+CSQ:") != -1) {
        int start = simResponse.indexOf("+CSQ:") + 6;
        int end = simResponse.indexOf(',', start);
        String rssiStr = simResponse.substring(start, end);
        Serial.print("SIM800L: SIGNAL QUALITY (RSSI): ");
        Serial.println(rssiStr);
        updateLCD("Signal Check", "RSSI: " + rssiStr);
    } else {
        Serial.println("SIM800L ERROR: Could not get signal quality.");
    }
    delay(2000);

    // 2. Initialize LCD
    initLCD();
    updateLCD("LCD TEST", "OK");
    delay(1000);

    // 3. Connect to Wi-Fi
    Serial.print("Connecting to WiFi..");
    updateLCD("Starting...", "Connecting WiFi");
    WiFi.begin(WIFI_SSID, WIFI_PASSWORD);
    while (WiFi.status() != WL_CONNECTED) {
        delay(500);
        Serial.print(".");
    }
    Serial.println("\nWiFi connected.");
    updateLCD("WiFi Connected", "NTP Initializing");

    // 4. Initialize Firebase RTDB
    config.host = FIREBASE_HOST;
    config.signer.tokens.legacy_token = FIREBASE_AUTH;
    Firebase.begin(&config, &auth);
    Firebase.reconnectWiFi(true);

    // 5. Initialize NTP Time
    initNTP();
    updateLCD("Time Sync OK", "Data Fetching");

    // 6. Fetch Emergency Contact
    fetchEmergencyContact();
    updateLCD("Ready!", "SOS Contact: " + emergencyNumber);
    delay(2000);

    // 7. Generate the patterned audio buffers
    generateToneBuffers();

    // 8. Initialize I2S Audio
    initI2S();
}


void loop() {
    if (!Firebase.ready()) return;

    // 1. Update Current Time
    if (!getLocalTime(&timeinfo)) {
        Serial.println("Failed to obtain time");
    }
    String currentTime = getCurrentTimeFormatted();

    // --- Time Logging ---
    if (millis() - lastTimeLog >= logInterval) {
        lastTimeLog = millis();
        Serial.print("Device Time is: ");
        Serial.println(currentTime);
    }

    // 2. Check for URCs (Unsolicited Result Codes) from SIM800L
    monitorSIM800L_URCs();

    // ----------------------------------------
    // 3. State Machine Logic
    unsigned long currentMillis = millis();
    unsigned long timeElapsed = currentMillis - stateChangeTime;

    // --- Common Logic for Active States (GREEN, ORANGE, RED) ---
    if (currentState == GREEN_ACTIVE || currentState == ORANGE_ACTIVE || currentState == RED_ACTIVE) {
        if (digitalRead(BUTTON_MED) == LOW) {
            String confirmedState;
            if (currentState == GREEN_ACTIVE) confirmedState = "Green";
            else if (currentState == ORANGE_ACTIVE) confirmedState = "Orange";
            else confirmedState = "Red";

            handleConfirmation(confirmedState);
            currentState = CONFIRMED;
            setLEDs(false, false, false);
            Serial.println("Medicine Confirmed. Transition to CONFIRMED display.");
        }
    }

    switch (currentState) {
        case IDLE:
        case MISSED:
            // Check scheduled time only once every minute
            if (currentMillis - lastDBCheckTime >= DB_CHECK_INTERVAL_MS) {
                lastDBCheckTime = currentMillis;
                checkScheduledTime(currentTime);
            }
            break;

        case GREEN_ACTIVE:
            if (timeElapsed >= (ALARM_BEEP_DURATION_MS + LONG_WAIT_MS)) {
                Serial.println("Green wait expired (125s). Transition to ORANGE (Second Reminder).");
                currentState = ORANGE_ACTIVE;
                stateChangeTime = currentMillis;
                startAlarmSequence(ORANGE_ACTIVE);
            }
            break;

        case ORANGE_ACTIVE:
            if (timeElapsed >= (ALARM_BEEP_DURATION_MS + SHORT_WAIT_MS)) {
                Serial.println("Orange wait expired (65s). Transition to RED (Final Reminder).");
                currentState = RED_ACTIVE;
                stateChangeTime = currentMillis;
                startAlarmSequence(RED_ACTIVE);
            }
            break;

        case RED_ACTIVE:
            if (timeElapsed >= (ALARM_BEEP_DURATION_MS + LONG_WAIT_MS)) {
                Serial.println("Red wait expired (125s). Logging as MISSED.");
                currentState = MISSED;
                Firebase.setString(fbdo, (String)RTDB_SCHEDULE_PATH + "/current_status", "MISSED");
                setLEDs(false, false, false);
            }
            break;

        case CONFIRMED:
            if (currentMillis - stateChangeTime >= 5000) {
                Serial.println("Confirmed display timeout. Returning to IDLE.");
                currentState = IDLE;
                setLEDs(false, false, false);
            }
            break;

        case SOS_ACTIVE:
            // --- 3a. Call Duration Check (10 seconds) ---
            if (isCalling) {
                if (currentMillis - callStartTime >= SOS_CALL_DURATION) {
                    Serial.println("Call duration (10s) expired. Hanging up to prepare for recall.");
                    hangUpCall();
                    lastCallEndTime = currentMillis;
                    updateLCD("SOS Calling Loop", "Delay 10s...");
                }
            }
            // --- 3b. Recall Delay Check (10 seconds) ---
            else if (!isCalling && currentMillis - lastCallEndTime >= SOS_RECALL_DELAY) {
                // Only make a call if the loop is still active
                if (isSOSLoopActive && makeCall(emergencyNumber)) {
                    // Call was initiated successfully, isCalling is true
                    updateLCD("SOS Calling Loop", emergencyNumber);
                    // Play SOS pattern briefly
                } else if (!isSOSLoopActive) {
                    // Loop was stopped by URC monitor (INFORMED)
                    // Do nothing, state will transition from SOS_INFORMED
                }
                else {
                    // Failed to initiate call (e.g., SIM error). Delay 5s and try again.
                    lastCallEndTime = currentMillis - (SOS_RECALL_DELAY - 5000); // Wait only 5s
                    updateLCD("SOS Call Fail", "Retrying...");
                }
            }
            break;

        case SOS_INFORMED:
            // Stay in informed state for 10s display then transition back to IDLE
            if (currentMillis - stateChangeTime >= 10000) {
                Serial.println("INFORMED display timeout. Returning to IDLE.");
                currentState = IDLE;
            }
            break;
    }


    // 4. Handle SOS Button (Initiate 3s hold, Stop 5s hold)
    int sosButtonState = digitalRead(BUTTON_SOS);

    if (sosButtonState == LOW) {
        // Button is currently pressed

        if (sosPressStartTime == 0) {
            sosPressStartTime = currentMillis;
            sosStopPressStartTime = currentMillis; // Start 5s timer as well
        }

        // --- 4a. Check for 5-Second STOP (Active only if loop is running) ---
        if (isSOSLoopActive && (currentMillis - sosStopPressStartTime >= SOS_STOP_HOLD_DURATION)) {
            Serial.println("\n--- SOS BUTTON HELD (5s): LOOP STOP REQUESTED ---");
            isSOSLoopActive = false;
            hangUpCall();
            currentState = IDLE;
            updateLCD("SOS", "STOPPED!");
            delay(2000);
            sosStopPressStartTime = currentMillis; // Prevents re-triggering
            sosPressStartTime = currentMillis;     // Prevents re-triggering
        }

        // --- 4b. Check for 3-Second INITIATION (Active only if loop is not running) ---
        else if (!isSOSLoopActive && (currentMillis - sosPressStartTime >= SOS_INITIATE_HOLD)) {

            if (sosPressStartTime != currentMillis) { // Avoid continuous re-triggering

                // INITIATE the continuous calling loop
                if (emergencyNumber.length() > 7) {
                    Serial.println("\n--- SOS BUTTON HELD (3s): CALL LOOP INITIATE ---");
                    isSOSLoopActive = true;
                    currentState = SOS_ACTIVE;
                    lastCallEndTime = 0; // Force immediate first call
                    updateLCD("SOS Activated!", "First Call Soon");
                    // Reset to prevent re-triggering on the same press
                    sosPressStartTime = currentMillis;
                } else {
                    Serial.println("ERROR: Emergency contact missing. Cannot start SOS.");
                    updateLCD("SOS ERROR", "Missing Contact");
                    delay(2000);
                    sosPressStartTime = 0; // Reset for next press
                }
            }
        }

    } else {
        // Button is currently HIGH (released)
        sosPressStartTime = 0;      // Reset 3s timer
        sosStopPressStartTime = 0;  // Reset 5s timer
    }

    // 5. Update LCD for non-alarm, non-call states
    if (currentState == IDLE || currentState == MISSED) {
        if (currentState == MISSED) {
            updateLCD("Medication", "MISSED!");
        } else {
            updateLCD("Current Time:", currentTime);
        }
    } else if (currentState == CONFIRMED) {
        // Handled in switch block
    } else if (currentState == SOS_INFORMED) {
        updateLCD("EMERGENCY", "INFORMED!");
    }

    delay(50);
}

// -----------------------------------------------------------------------------
// SIM800L / SOS CALL Functions
// -----------------------------------------------------------------------------

/**
 * @brief Handles the transition to SOS_INFORMED state, stops the loop, and plays audio.
 */
void transitionToInformed() {
    Serial.println("Contact established/terminated by recipient. Transitioning to INFORMED.");
    // Ensure the loop is stopped and call is terminated
    hangUpCall(); // Ensure call is terminated if it was still running
    isSOSLoopActive = false;
    isCalling = false;
    currentState = SOS_INFORMED;
    stateChangeTime = millis();
    updateLCD("EMERGENCY", "INFORMED!");
    playBeep(); // Play a short confirmation beep
}

/**
 * @brief Continuously reads from Serial2 for Unsolicited Result Codes (URCs)
 * to detect remote hangup or answer.
 */
void monitorSIM800L_URCs() {
    while (Serial2.available()) {
        String line = Serial2.readStringUntil('\n');
        line.trim();

        if (line.length() > 0) {
            Serial.print("URC Received: ");
            Serial.println(line);

            // This logic MUST only run if the continuous loop is active
            if (isSOSLoopActive) {

                // 1. Detect call answered (CONNECT URC)
                if (line.indexOf("CONNECT") != -1) {
                    // CONNECT means the remote end has answered the call.
                    transitionToInformed();
                    return; // URC handled
                }

                // 2. Detect call terminated by remote party (NO CARRIER URC)
                // If a call was actively in progress (isCalling=true) and we get NO CARRIER,
                // it implies the connection was terminated by the remote end.
                if (isCalling && line.indexOf("NO CARRIER") != -1) {
                    transitionToInformed();
                    return; // URC handled
                }
            }

            // General NO CARRIER handling to reset isCalling state (important for the 10s hangup)
            if (line.indexOf("NO CARRIER") != -1) {
                isCalling = false;
                callStartTime = 0;
            }

            // SIM800L often sends 'OK' or 'RING' URCs, which are ignored here
        }
    }
}

/**
 * @brief Sends an AT command to the SIM800L module and captures the response.
 */
String sendATCommand(String command, long timeout_ms) {
    String response = "";

    // Clear buffer before sending command
    while(Serial2.available()) Serial2.read();

    Serial2.println(command);
    Serial.print("-> SIM800L TX: ");
    Serial.println(command);

    unsigned long timeout = millis();
    while (millis() - timeout < timeout_ms) {
        if (Serial2.available()) {
            response += (char)Serial2.read();
        }
    }

    response.trim();
    Serial.print("<- SIM800L RX (Full): ");
    Serial.println(response);
    return response;
}

/**
 * @brief Fetches the emergency contact number from Firebase Realtime Database.
 */
void fetchEmergencyContact() {
    Serial.println("Fetching emergency contact...");
    emergencyNumber = "";

    if (Firebase.get(fbdo, RTDB_EMERGENCY_PATH)) {

        if (fbdo.dataType() == "json") {
            FirebaseJsonData result;
            FirebaseJson json = fbdo.jsonString();

            if (json.get(result, "contact_number")) {
                emergencyNumber = result.stringValue;
                emergencyNumber.trim();
                Serial.println("Firebase successfully retrieved number from 'contact_number' field.");
            } else {
                Serial.println("RTDB Read ERROR: JSON object found, but 'contact_number' field is missing or invalid.");
            }
        } else {
            Serial.print("RTDB Read ERROR: Data type is not a JSON object, it is: ");
            Serial.println(fbdo.dataType());
            Serial.println("Ensure 'emergency_contact' contains { 'contact_number': '...' }.");
        }
    } else {
        Serial.println("RTDB Read ERROR: Failed to read emergency path. Reason: " + fbdo.errorReason());
    }

    if (emergencyNumber.length() < 7) {
        Serial.print("Number is invalid or empty (length < 7). Current value: ");
        Serial.println(emergencyNumber);

        emergencyNumber = "0112345678"; // Fallback number
        Serial.println(">>> Using FALLBACK emergency number: " + emergencyNumber);
    } else {
          Serial.println(">>> Using Firebase emergency number: " + emergencyNumber);
    }
}

/**
 * @brief Initiates a voice call to the specified phone number via the SIM800L module.
 * @return True if the dial command was successfully sent, false otherwise.
 */
bool makeCall(String phoneNumber) {
    if (isCalling) {
        Serial.println("WARNING: Already in a calling state.");
        return true;
    }
    if (phoneNumber.length() < 7) {
        Serial.println("ERROR: Invalid emergency number. Cannot make call.");
        updateLCD("SOS ERROR:", "Invalid number");
        return false;
    }

    String command = "ATD" + phoneNumber + ";";

    Serial.println("Attempting to dial: " + phoneNumber);
    String response = sendATCommand(command, 15000);

    if (response.indexOf("OK") != -1) {
        // Play the SOS pattern upon successful dialing
        playSOSPatterm();

        Serial.println("SUCCESS: Dial command successfully sent to SIM800L.");
        isCalling = true;
        callStartTime = millis();
        return true;
    } else {
        Serial.println("FAILURE: SIM800L did not return 'OK' after dial command. (Power Issue?)");
        isCalling = false;
        callStartTime = 0;
        return false;
    }
}

/**
 * @brief Terminates any active call using the ATH command.
 */
void hangUpCall() {
    if (!isCalling) return; // Prevent hanging up when no call is active

    Serial.println("Attempting to HANG UP call (ATH).");
    String response = sendATCommand("ATH", 5000);

    // After ATH, the SIM800L often sends a "NO CARRIER" URC.
    // We update state variables here, and the URC monitor handles the general case.
    isCalling = false;
    callStartTime = 0;
    // Clearing the serial buffer here to ensure no lingering "NO CARRIER" is read immediately after
    while(Serial2.available()) Serial2.read();
}


// -----------------------------------------------------------------------------
// I2S and Audio Functions
// -----------------------------------------------------------------------------

/**
 * @brief Initializes the ESP32 I2S peripheral using raw ESP-IDF calls.
 */
void initI2S() {
    // 1. I2S Configuration
    i2s_config_t i2s_config = {
        .mode = (i2s_mode_t)(I2S_MODE_MASTER | I2S_MODE_TX),
        .sample_rate = SAMPLE_RATE,
        .bits_per_sample = I2S_BITS_PER_SAMPLE_16BIT,
        .channel_format = I2S_CHANNEL_FMT_ONLY_LEFT, // Mono
        .communication_format = I2S_COMM_FORMAT_STAND_I2S,
        .intr_alloc_flags = 0,
        .dma_buf_count = 8,
        .dma_buf_len = 1024,
        .use_apll = false,
        .tx_desc_auto_clear = true
    };
    i2s_driver_install(I2S_NUM_0, &i2s_config, 0, NULL);

    // 2. I2S Pin Assignment
    i2s_pin_config_t pin_config = {
        .bck_io_num = I2S_BCLK,
        .ws_io_num = I2S_LRC,
        .data_out_num = I2S_DOUT,
        .data_in_num = I2S_PIN_NO_CHANGE
    };
    i2s_set_pin(I2S_NUM_0, &pin_config);
    Serial.println("I2S Driver installed for MAX98355A.");
}

/**
 * @brief Sets the global volume (amplitude scalar).
 * @param vol The volume level (0.0 to 1.0).
 */
void setVolume(float vol) {
    if (vol < 0.0) vol = 0.0;
    if (vol > 1.0) vol = 1.0;
    currentVolume = vol;
    Serial.printf("Volume set to %.1f%%\n", currentVolume * 100);
}

/**
 * @brief Helper function to write a tone buffer to the I2S peripheral.
 */
void writeTone(int16_t* buffer, int num_samples) {
    size_t bytes_written = 0;
    i2s_write(I2S_NUM_0, buffer, num_samples * sizeof(int16_t), &bytes_written, portMAX_DELAY);
}

/**
 * @brief Pre-calculates sine wave tones of two different durations for patterned audio.
 */
void generateToneBuffers() {
    Serial.println("Generating patterned tone buffers...");

    // Set initial volume
    setVolume(0.1); // Start at 80% volume

    // --- 1. Short Tone (500ms) for SOS Dot / Standard Beep ---
    int shortDurationMs = 500;
    SAMPLES_SHORT = (SAMPLE_RATE * shortDurationMs) / 1000;

    for (int i = 0; i < SAMPLES_SHORT; i++) {
        float sample = sinf(2.0 * M_PI * TONE_FREQUENCY * i / SAMPLE_RATE);
        // Apply volume scaling here
        TONE_BUFFER_SHORT[i] = (int16_t)(sample * maxAmplitude * currentVolume);
    }

    // --- 2. Long Tone (1500ms) for SOS Dash ---
    int longDurationMs = 1500;
    SAMPLES_LONG = (SAMPLE_RATE * longDurationMs) / 1000;

    for (int i = 0; i < SAMPLES_LONG; i++) {
        float sample = sinf(2.0 * M_PI * TONE_FREQUENCY * i / SAMPLE_RATE);
        // Apply volume scaling here
        TONE_BUFFER_LONG[i] = (int16_t)(sample * maxAmplitude * currentVolume);
    }

    Serial.println("Tone buffers generation complete.");
}


/**
 * @brief Plays a single instance of the short tone buffer.
 */
void playBeep() {
    writeTone(TONE_BUFFER_SHORT, SAMPLES_SHORT);
}


/**
 * @brief Plays the standard reminder pattern: Beep-Beep-Beep (3 short tones with short pauses).
 */
void playBeepPattern() {
    Serial.println("Playing Standard Reminder Pattern (Beep-Beep-Beep).");
    const int pause_ms = 300;

    for (int i = 0; i < 3; i++) {
        writeTone(TONE_BUFFER_SHORT, SAMPLES_SHORT); // 500ms Beep
        if (i < 2) delay(pause_ms); // 300ms pause between beeps
    }
}

/**
 * @brief Plays the SOS Morse Code pattern (••• --- •••) using the short and long tones.
 */
void playSOSPatterm() {
    Serial.println("Playing SOS Pattern (••• --- •••).");
    const int dot_pause = 300;
    const int element_pause = 500;

    // S: 3 Dots
    for (int i = 0; i < 3; i++) {
        writeTone(TONE_BUFFER_SHORT, SAMPLES_SHORT); // Dot (500ms)
        delay(dot_pause);
    }

    delay(element_pause); // Pause between letter S and O

    // O: 3 Dashes
    for (int i = 0; i < 3; i++) {
        writeTone(TONE_BUFFER_LONG, SAMPLES_LONG); // Dash (1500ms)
        delay(dot_pause);
    }

    delay(element_pause); // Pause between letter O and S

    // S: 3 Dots
    for (int i = 0; i < 3; i++) {
        writeTone(TONE_BUFFER_SHORT, SAMPLES_SHORT); // Dot (500ms)
        delay(dot_pause);
    }
}


/**
 * @brief Executes the alarm sequence and sets the LED/LCD.
 */
void startAlarmSequence(ReminderState phase) {
    Serial.print("Starting Alarm Sequence: ");

    // Set LED and LCD for the active period (LED stays ON)
    if (phase == GREEN_ACTIVE) {
        Serial.println("GREEN (First Reminder)");
        setLEDs(true, false, false); // Green ON
        updateLCD("TIME TO TAKE:", currentMedicineName);
    } else if (phase == ORANGE_ACTIVE) {
        Serial.println("ORANGE (Second Reminder)");
        setLEDs(false, true, false); // Orange ON
        updateLCD("SECOND REMINDER:", currentMedicineName);
    } else if (phase == RED_ACTIVE) {
        Serial.println("RED (Final Reminder)");
        setLEDs(false, false, true); // Red ON
        updateLCD("FINAL REMINDER:", currentMedicineName);
    }

    // Execute the Beep-Beep-Beep pattern
    playBeepPattern();

    Serial.println("Beep pattern sequence complete.");
}

// -----------------------------------------------------------------------------
// LCD Functions
// -----------------------------------------------------------------------------

/**
 * @brief Initializes the I2C LCD display.
 */
void initLCD() {
    Wire.begin(I2C_SDA, I2C_SCL);
    delay(100);
    lcd.init();
    lcd.backlight();
    Serial.println("LCD Initialized (0x27).");
}

/**
 * @brief Updates the two lines of the LCD display.
 */
void updateLCD(String line1, String line2) {
    lcd.clear();
    lcd.setCursor(0, 0);
    lcd.print(line1.substring(0, LCD_COLUMNS));
    lcd.setCursor(0, 1);
    lcd.print(line2.substring(0, LCD_COLUMNS));
}

// -----------------------------------------------------------------------------
// Firebase and Time Functions
// -----------------------------------------------------------------------------

/**
 * @brief Initializes NTP time synchronization for the ESP32.
 */
void initNTP() {
    configTime(gmtOffset_sec, daylightOffset_sec, ntpServer);
    Serial.println("NTP Time Initialized.");
}

/**
 * @brief Gets the current time formatted as HH.MM (e.g., 09.30).
 */
String getCurrentTimeFormatted() {
    char timeStr[6];
    getLocalTime(&timeinfo);
    strftime(timeStr, sizeof(timeStr), "%H.%M", &timeinfo);
    return String(timeStr);
}

/**
 * @brief Checks the scheduled medicine times against the current time from Firebase.
 */
void checkScheduledTime(String currentTime) {
    // Only run if the state is not an active reminder or SOS
    if (currentState != IDLE && currentState != MISSED && currentState != SOS_INFORMED) return;

    String path = (String)RTDB_SCHEDULE_PATH + "/med_times";

    if (Firebase.getString(fbdo, path)) {
        if (fbdo.dataType() == "json") {
            FirebaseJson json = fbdo.jsonString();
            size_t len = json.iteratorBegin();

            FirebaseJsonData result;
            for (size_t i = 0; i < len; i++) {
                String key = "";
                String value = "";
                int type = 0;
                json.iteratorGet(i, type, key, value);
                FirebaseJson tempJson;
                tempJson.setJsonData(value);

                String medicineTime = "";
                String medicineName = "";

                if (tempJson.get(result, FPSTR("time"))) {
                    medicineTime = result.stringValue;
                    medicineTime.trim();
                }
                if (tempJson.get(result, FPSTR("name"))) {
                    medicineName = result.stringValue;
                }

                if (currentTime.equals(medicineTime)) {
                    Serial.println("*");
                    Serial.println("***** ALARM TRIGGERED! TIME MATCH CONFIRMED *****");
                    Serial.println("*");

                    currentMedicineName = medicineName;
                    currentState = GREEN_ACTIVE;
                    stateChangeTime = millis();
                    startAlarmSequence(GREEN_ACTIVE);

                    Firebase.setString(fbdo, (String)RTDB_SCHEDULE_PATH + "/current_status", "ACTIVE");
                    return;
                }
            }
            json.iteratorEnd();
        }
    } else {
        Serial.println("RTDB Read ERROR: Failed to read path. Reason: " + fbdo.errorReason());
    }
}

/**
 * @brief Sets the state of the three reminder LEDs.
 */
void setLEDs(bool green, bool orange, bool red) {
    digitalWrite(LED_GREEN, green ? HIGH : LOW);
    digitalWrite(LED_ORANGE, orange ? HIGH : LOW);
    digitalWrite(LED_RED, red ? HIGH : LOW);
}

/**
 * @brief Handles the confirmation button press by logging the event to Firebase.
 */
void handleConfirmation(String state) {
    FirebaseJson confirmationJson;
    confirmationJson.set("confirmed_at", getCurrentTimeFormatted());
    confirmationJson.set("medicine_name", currentMedicineName);
    confirmationJson.set("reminder_state", state);

    if (Firebase.set(fbdo, RTDB_CONFIRM_PATH, confirmationJson)) {
        Serial.println("Firebase Confirmation Updated successfully. State: " + state);
        Firebase.setString(fbdo, (String)RTDB_SCHEDULE_PATH + "/current_status", "CONFIRMED");
        stateChangeTime = millis();
        updateLCD("Confirmation:", "RECEIVED!");
    } else {
        Serial.println("Firebase Confirmation Failed: " + fbdo.errorReason());
    }
}
