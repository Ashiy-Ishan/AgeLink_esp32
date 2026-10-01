#include "age_link_sim.h"
#include "age_link_types.h"
#include "age_link_audio.h"
#include "age_link_hardware.h"
#include "age_link_config.h"

void initSIM() {
    Serial.println(F("[SIM800L] Initializing UART2 communication..."));
    Serial2.begin(SIM800L_BAUD, SERIAL_8N1, RX2_PIN, TX2_PIN);
    delay(1000); // Allow modem internal voltage regulators to stabilize
    Serial.println(F("[SIM800L] UART2 ready."));
}

String sendATCommand(const String& command, unsigned long timeout_ms, bool fullResponse) {
    while (Serial2.available()) {
        Serial2.read(); // Flush stale RX bytes
    }

    Serial2.println(command);
    Serial.print(F("-> SIM800L TX: "));
    Serial.println(command);

    String response;
    response.reserve(128); // Optimize to reduce heap reallocations

    unsigned long startTime = millis();
    while (millis() - startTime < timeout_ms) {
        while (Serial2.available()) {
            char c = (char)Serial2.read();
            response += c;
        }
        delay(5); // Small yield
    }

    response.trim();
    if (fullResponse) {
        Serial.print(F("<- SIM800L RX (Full): "));
        Serial.println(response);
    }
    return response;
}

void executeSosSequence() {
    if (contactCount == 0) {
        Serial.println(F("[SOS] ERROR: No emergency contacts configured in memory."));
        updateLCD("SOS ERROR:", "No Contacts");
        delay(3000);
        return;
    }

    // Play SOS alarm voice prompt
    playWavFile(SOUND_EMERGENCY);

    bool callCancelled = false;
    bool callAnswered  = false;
    unsigned long sosStartTime = millis();

    // 5-second initial sound window: user can cancel by pressing SOS button
    while (millis() - sosStartTime < SOS_CANCEL_WINDOW_MS) {
        audioLoop();
        if (isSosButtonPressed() && (millis() - sosStartTime > SOS_DEBOUNCE_DELAY_MS)) {
            Serial.println(F("[SOS] Cancelled by user during initial alert."));
            callCancelled = true;
            break;
        }
        delay(40);
    }

    // Dial loop through all loaded emergency contacts
    while (!callCancelled && !callAnswered) {
        for (int i = 0; i < contactCount && !callCancelled && !callAnswered; i++) {
            const String& name  = contacts[i].name;
            const String& phone = contacts[i].phone;

            Serial.print(F("[SOS] Dialing Contact "));
            Serial.print(i + 1);
            Serial.print(F("/"));
            Serial.print(contactCount);
            Serial.print(F(": "));
            Serial.print(name);
            Serial.print(F(" ("));
            Serial.print(phone);
            Serial.println(F(")"));

            updateLCD("CALLING: " + name, phone);

            // Flush buffer and send ATD dial command
            while (Serial2.available()) Serial2.read();
            Serial2.print(F("ATD"));
            Serial2.print(phone);
            Serial2.println(F(";"));

            String response;
            response.reserve(64);
            bool callFailed = false;

            unsigned long callStartTime = millis();
            while (millis() - callStartTime < SOS_CALL_TIMEOUT_MS) {
                audioLoop();

                // User cancellation check
                if (isSosButtonPressed()) {
                    Serial.println(F("[SOS] User cancelled call while dialing."));
                    callCancelled = true;
                    break;
                }

                if (Serial2.available()) {
                    char c = (char)Serial2.read();
                    response += c;
                    if (response.indexOf("BUSY") != -1) {
                        Serial.println(F("[SIM800L] Line is BUSY."));
                        callFailed = true;
                        break;
                    }
                    if (response.indexOf("NO CARRIER") != -1) {
                        Serial.println(F("[SIM800L] Call FAILED (No Carrier)."));
                        callFailed = true;
                        break;
                    }
                    if (response.indexOf("ERROR") != -1) {
                        Serial.println(F("[SIM800L] Call FAILED (SIM Error)."));
                        callFailed = true;
                        break;
                    }
                }
                delay(40);
            }

            // Always hang up call after timeout or failure
            Serial.println(F("[SIM800L] Hanging up call via ATH..."));
            sendATCommand("ATH", 3000, false);

            if (callCancelled) {
                break;
            }

            if (callFailed) {
                playWavFile(SOUND_EMERGENCY_INFORMED);
                updateLCD("Call Failed:", name);

                unsigned long failDelayStart = millis();
                while (millis() - failDelayStart < 2000) {
                    audioLoop();
                    delay(40);
                }
            } else {
                Serial.println(F("[SOS] Call connected or rang out for duration."));
                callAnswered = true;
            }

            // Inter-call pause
            if (i < contactCount - 1 && !callCancelled && !callAnswered) {
                Serial.println(F("[SOS] Pausing 2s before dialing next contact..."));
                updateLCD("Next Contact...", "");

                unsigned long pauseStart = millis();
                while (millis() - pauseStart < 2000) {
                    audioLoop();
                    if (isSosButtonPressed()) {
                        Serial.println(F("[SOS] Cancelled during inter-call pause."));
                        callCancelled = true;
                        break;
                    }
                    delay(40);
                }
            }
        } // End of contact list iteration

        if (!callCancelled && !callAnswered) {
            Serial.println(F("[SOS] Completed round of all contacts. Cycling back..."));
            updateLCD("Restarting", "Call List...");

            unsigned long cycleDelayStart = millis();
            while (millis() - cycleDelayStart < 2000) {
                audioLoop();
                delay(40);
            }
        }
    }

    // Terminating audio feedback and display status
    if (callCancelled) {
        Serial.println(F("[SOS] Completed SOS sequence: User CANCELLED."));
        playWavFile(SOUND_SOS_CALL_CANCEL);
        updateLCD("SOS", "CANCELLED");
    } else if (callAnswered) {
        Serial.println(F("[SOS] Completed SOS sequence: Contact INFORMED."));
        playWavFile(SOUND_EMERGENCY_INFORMED);
        updateLCD("SOS Calls", "Finished.");
    }

    unsigned long finalDelayStart = millis();
    while (millis() - finalDelayStart < 3000) {
        audioLoop();
        delay(40);
    }

    lastSosPressTime = millis();
}
