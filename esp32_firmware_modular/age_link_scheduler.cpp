#include "age_link_scheduler.h"
#include "age_link_types.h"
#include "age_link_config.h"
#include "age_link_hardware.h"
#include "age_link_audio.h"
#include "age_link_network.h"
#include "age_link_storage.h"
#include "age_link_sim.h"

void startAlarmSequence(ReminderState phase) {
    const char* soundToPlay = nullptr;
    Serial.print(F("[ALARM] Escalating alarm tier to: "));

    switch (phase) {
        case GREEN_ACTIVE:
            Serial.println(F("GREEN (Tier 1 - First Reminder)"));
            setLEDs(true, false, false);
            updateLCD("TIME TO TAKE:", currentMedicineName);
            soundToPlay = SOUND_FIRST_REMINDER;
            break;

        case ORANGE_ACTIVE:
            Serial.println(F("ORANGE (Tier 2 - Second Reminder)"));
            setLEDs(false, true, false);
            updateLCD("SECOND REMINDER:", currentMedicineName);
            soundToPlay = SOUND_SECOND_REMINDER;
            break;

        case RED_ACTIVE:
            Serial.println(F("RED (Tier 3 - Final Reminder)"));
            setLEDs(false, false, true);
            updateLCD("FINAL REMINDER:", currentMedicineName);
            soundToPlay = SOUND_FINAL_REMINDER;
            break;

        default:
            break;
    }

    if (soundToPlay != nullptr) {
        playWavFile(soundToPlay);
    }
}

void checkFactoryResetButton() {
    if (isMedButtonPressed()) {
        if (greenButtonPressTime == 0) {
            greenButtonPressTime = millis();
            Serial.println(F("[SYSTEM] Factory reset hold timer started..."));
        } else if (millis() - greenButtonPressTime > FACTORY_RESET_HOLD_MS) {
            isResetting = true;
            Serial.println(F("\n[SYSTEM] --- FACTORY RESET TRIGGERED BY BUTTON ---"));
            updateLCD("FACTORY RESET", "Erasing files...");

            unsigned long resetStartTime = millis();
            while (millis() - resetStartTime < 3000) {
                audioLoop();
                delay(40);
            }

            deleteConfigurationFiles();
            Serial.println(F("[SYSTEM] Configuration deleted. Restarting ESP32..."));
            ESP.restart();
        }
    } else {
        greenButtonPressTime = 0;
    }
}

void checkSosButton() {
    if (isSosButtonPressed()) {
        if (millis() - lastSosPressTime > (SOS_DEBOUNCE_DELAY_MS * 5)) {
            lastSosPressTime = millis();
            Serial.println(F("\n[SOS] --- EMERGENCY SOS BUTTON PRESSED ---"));
            executeSosSequence();
            Serial.println(F("[SOS] --- Emergency SOS sequence completed ---"));

            stateChangeTime  = millis();
            lastTimeLog      = millis();
            lastSosPressTime = millis();
        }
    }
}

void runSchedulerStateMachine() {
    unsigned long timeElapsed = millis() - stateChangeTime;

    // 1. Ingestion Confirmation Check for Active Alarm States
    if (currentState == GREEN_ACTIVE || currentState == ORANGE_ACTIVE || currentState == RED_ACTIVE) {
        if (isMedButtonPressed()) {
            String confirmedStateStr;
            if (currentState == GREEN_ACTIVE)       confirmedStateStr = "Green";
            else if (currentState == ORANGE_ACTIVE) confirmedStateStr = "Orange";
            else                                    confirmedStateStr = "Red";

            handleConfirmation(confirmedStateStr);
            currentState    = CONFIRMED;
            stateChangeTime = millis();
            Serial.println(F("[ALARM] Medicine confirmed by user. Entering CONFIRMED state."));
            return;
        }
    }

    // 2. State-Specific Timeouts and Transitions
    switch (currentState) {
        case IDLE: {
            if (millis() - lastDBCheckTime >= DB_CHECK_INTERVAL_MS) {
                lastDBCheckTime = millis();
                stopAudio();

                String currentTime = getCurrentTimeFormatted();
                bool alarmTriggered = checkScheduledTime(currentTime);
                if (!alarmTriggered) {
                    fetchDeviceSettings();
                }
            }
            checkFactoryResetButton();
            break;
        }

        case GREEN_ACTIVE: {
            if (timeElapsed >= (ALARM_BEEP_DURATION_MS + SHORT_WAIT_MS)) {
                currentState    = ORANGE_ACTIVE;
                stateChangeTime = millis();
                startAlarmSequence(ORANGE_ACTIVE);
            }
            break;
        }

        case ORANGE_ACTIVE: {
            if (timeElapsed >= (ALARM_BEEP_DURATION_MS + SHORT_WAIT_MS)) {
                currentState    = RED_ACTIVE;
                stateChangeTime = millis();
                startAlarmSequence(RED_ACTIVE);
            }
            break;
        }

        case RED_ACTIVE: {
            if (timeElapsed >= (ALARM_BEEP_DURATION_MS + SHORT_WAIT_MS)) {
                Serial.println(F("[ALARM] Red tier expired without confirmation. Logging MISSED dose."));
                currentState    = MISSED;
                stateChangeTime = millis();
                handleMissed(currentMedicineName);
                setLEDs(false, false, false);
            }
            break;
        }

        case MISSED: {
            if (millis() - stateChangeTime >= 30000) { // 30s display banner
                Serial.println(F("[ALARM] Missed banner expired. Returning to IDLE."));
                currentState    = IDLE;
                lastDBCheckTime = millis();
            }
            checkFactoryResetButton();
            break;
        }

        case CONFIRMED: {
            if (millis() - stateChangeTime >= 5000) { // 5s confirmation banner
                Serial.println(F("[ALARM] Confirmation display complete. Returning to IDLE."));
                currentState = IDLE;
                setLEDs(false, false, false);
            }
            break;
        }
    }
}
