#include "age_link_sim.h"
#include "age_link_types.h"
#include "age_link_audio.h"
#include "age_link_hardware.h"
#include "age_link_network.h"
#include <stdio.h>

namespace {
enum class SosStage { Idle, Countdown, Dialing, HangingUp, Retry, Result };
enum class CallResult { Unanswered, Answered, Cancelled };

SosStage stage = SosStage::Idle;
CallResult result = CallResult::Unanswered;
unsigned long stageStarted = 0;
unsigned long lastCallQuery = 0;
size_t contactIndex = 0;
uint8_t hangupAttempts = 0;
String modemLine;
bool callQueryPending = false;
bool beginHangup = false;

void enter(SosStage next) {
    stage = next;
    stageStarted = millis();
}

bool sosPressed() {
    static bool raw = false;
    static bool stable = false;
    static unsigned long changed = 0;
    const bool pressed = isSosButtonPressed();
    if (raw != pressed) {
        raw = pressed;
        changed = millis();
    }
    if (stable == raw || millis() - changed < 35) return false;
    stable = raw;
    return stable;
}

void finish(const char* headline, const char* detail = "", const char* sound = nullptr) {
    stopAudio();
    showOLED("SOS", headline, detail);
    if (sound) playWavFile(sound);
    enter(SosStage::Result);
}

void dialContact() {
    const auto& contact = contacts[contactIndex];
    showOLED("SOS", "Calling...", contact.name, "Press SOS to cancel");
    while (Serial2.available()) Serial2.read();
    modemLine = "";
    result = CallResult::Unanswered;
    callQueryPending = false;
    beginHangup = false;
    Serial2.print("ATD");
    Serial2.print(contact.phone);
    Serial2.print(";\r");
    enter(SosStage::Dialing);
    lastCallQuery = stageStarted;
}

void hangUp() {
    while (Serial2.available()) Serial2.read();
    modemLine = "";
    ++hangupAttempts;
    Serial2.print("ATH\r");
    enter(SosStage::HangingUp);
}

void finishHangup(bool confirmed) {
    if (result == CallResult::Answered) {
        if (confirmed) {
            finish("Confirmed", contacts[contactIndex].name.c_str(), SOUND_EMERGENCY_INFORMED);
        } else {
            finish("Call answered", "Hang-up not verified");
        }
    } else if (result == CallResult::Cancelled) {
        if (confirmed) {
            finish("Cancelled", "", SOUND_SOS_CALL_CANCEL);
        } else {
            finish("Retry stopped", "Hang-up not verified");
        }
    } else {
        contactIndex = (contactIndex + 1) % contacts.size();
        showOLED("SOS", "Retrying", contacts[contactIndex].name, "Press SOS to cancel");
        enter(SosStage::Retry);
    }
}

void readModem() {
    while (Serial2.available()) {
        const char c = static_cast<char>(Serial2.read());
        if (c != '\n') {
            if (c != '\r' && modemLine.length() < 160) modemLine += c;
            continue;
        }
        modemLine.trim();

        if (stage == SosStage::HangingUp) {
            if (modemLine == "OK" || modemLine == "NO CARRIER") {
                finishHangup(true);
                modemLine = "";
                return;
            }
        } else {
            int direction;
            int status;
            int mode;
            if (sscanf(modemLine.c_str(), "+CLCC: %*d,%d,%d,%d", &direction, &status, &mode) == 3 &&
                direction == 0 && status == 0 && mode == 0 && result != CallResult::Cancelled) {
                result = CallResult::Answered;
                beginHangup = true;
                showOLED("SOS", "Call answered", "Hanging up...");
            } else if (modemLine == "BUSY" || modemLine == "NO ANSWER" ||
                       modemLine == "NO CARRIER" || modemLine == "NO DIALTONE" ||
                       modemLine.startsWith("+CME ERROR:") ||
                       (modemLine == "ERROR" && !callQueryPending)) {
                beginHangup = true;
            }
            if (modemLine == "OK" || modemLine == "ERROR") callQueryPending = false;
        }
        modemLine = "";
    }
}
}  // namespace

void initSIM() {
    Serial2.begin(SIM800L_BAUD, SERIAL_8N1, RX2_PIN, TX2_PIN);
    delay(1000);
    Serial.println(F("[SIM800L] UART2 ready."));
}

bool updateSOS() {
    const bool pressed = sosPressed();
    const unsigned long elapsed = millis() - stageStarted;

    switch (stage) {
        case SosStage::Idle:
            if (!pressed) return false;
            contactIndex = 0;
            playWavFile(SOUND_EMERGENCY);
            showOLED("SOS", "Calling in 3s", "Press SOS to cancel");
            enter(SosStage::Countdown);
            break;

        case SosStage::Countdown:
            if (pressed) {
                finish("Cancelled", "", SOUND_SOS_CALL_CANCEL);
            } else if (elapsed >= SOS_CANCEL_WINDOW_MS) {
                if (contacts.empty()) {
                    const bool synced = WiFi.status() == WL_CONNECTED && Firebase.ready() &&
                                        fetchEmergencyContact();
                    if (!synced) {
                        finish("No saved numbers", "Check Wi-Fi and app");
                    } else if (contacts.empty()) {
                        finish("No contacts", "Add one in the app");
                    }
                }
                if (!contacts.empty()) dialContact();
            } else {
                const unsigned long seconds = (SOS_CANCEL_WINDOW_MS - elapsed + 999) / 1000;
                showOLED("SOS", "Calling in " + String(seconds) + "s", "Press SOS to cancel");
            }
            break;

        case SosStage::Dialing:
            if (pressed && result != CallResult::Answered) {
                result = CallResult::Cancelled;
                beginHangup = true;
            }
            readModem();
            if (elapsed >= SOS_CALL_TIMEOUT_MS) beginHangup = true;
            if (beginHangup && (!callQueryPending || millis() - lastCallQuery >= 250)) {
                hangupAttempts = 0;
                hangUp();
            } else if (!beginHangup && millis() - lastCallQuery >= 1000) {
                Serial2.print("AT+CLCC\r");
                callQueryPending = true;
                lastCallQuery = millis();
            }
            break;

        case SosStage::HangingUp:
            if (pressed && result == CallResult::Unanswered) {
                result = CallResult::Cancelled;
            }
            readModem();
            if (stage == SosStage::HangingUp && elapsed >= 1000) {
                if (hangupAttempts < 2) hangUp();
                else finishHangup(false);
            }
            break;

        case SosStage::Retry:
            if (pressed) finish("Cancelled", "", SOUND_SOS_CALL_CANCEL);
            else if (elapsed >= 2000) dialContact();
            break;

        case SosStage::Result:
            if (elapsed >= 3000 && !isAudioPlaying()) {
                enter(SosStage::Idle);
                return false;
            }
            break;
    }
    return true;
}
