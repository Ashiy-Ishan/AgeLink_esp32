#include "age_link_scheduler.h"
#include "age_link_types.h"
#include "age_link_config.h"
#include "age_link_hardware.h"
#include "age_link_audio.h"
#include "age_link_network.h"
#include "age_link_storage.h"

static void showFirstReminder(const String& dose) {
    const size_t page = ((millis() - stateChangeTime) / 3000) %
                        (nearbyMedicineLabels.size() + 1);
    showOLED("MEDICINE DUE", currentMedicineName,
             page == 0 ? dose : "Next " + nearbyMedicineLabels[page - 1],
             "Green: confirm taken");
}

void startAlarmSequence(ReminderState phase) {
    const char* soundToPlay = nullptr;
    const String dose = currentMedicineDosage.isEmpty()
        ? "Due " + currentMedicineTime : "Dose: " + currentMedicineDosage;
    Serial.print(F("[ALARM] Escalating alarm tier to: "));

    switch (phase) {
        case GREEN_ACTIVE:
            Serial.println(F("GREEN (Tier 1 - First Reminder)"));
            setLEDs(true, false, false);
            showFirstReminder(dose);
            soundToPlay = SOUND_FIRST_REMINDER;
            break;

        case ORANGE_ACTIVE:
            Serial.println(F("ORANGE (Tier 2 - Second Reminder)"));
            setLEDs(false, true, false);
            showOLED("REPEAT REMINDER", currentMedicineName, dose, "Green: confirm taken");
            soundToPlay = SOUND_SECOND_REMINDER;
            break;

        case RED_ACTIVE:
            Serial.println(F("RED (Tier 3 - Final Reminder)"));
            setLEDs(false, false, true);
            showOLED("FINAL REMINDER", currentMedicineName, dose, "Green: confirm taken");
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
            showOLED("SETUP", "Factory reset", "Erasing settings");

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

void runSchedulerStateMachine() {
    const unsigned long timeElapsed = millis() - stateChangeTime;
    static bool medicineWasPressed = false;
    const bool medicinePressed = isMedButtonPressed();
    const bool medicineJustPressed = medicinePressed && !medicineWasPressed;
    medicineWasPressed = medicinePressed;

    // 1. Ingestion Confirmation Check for Active Alarm States
    if (currentState == GREEN_ACTIVE || currentState == ORANGE_ACTIVE || currentState == RED_ACTIVE) {
        if (medicineJustPressed) {
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

    if (millis() - lastDBCheckTime >= DB_CHECK_INTERVAL_MS) {
        lastDBCheckTime = millis();
        const bool alarmStarted = checkScheduledTime(getCurrentTimeFormatted());
        if (alarmStarted) return;
        if (currentState == IDLE && !isAudioPlaying() && !offlineMode && Firebase.ready()) {
            fetchDeviceSettings();
        }
    }

    // 2. State-Specific Timeouts and Transitions
    switch (currentState) {
        case IDLE: {
            checkFactoryResetButton();
            break;
        }

        case GREEN_ACTIVE: {
            if (!nearbyMedicineLabels.empty()) {
                showFirstReminder(currentMedicineDosage.isEmpty()
                    ? "Due " + currentMedicineTime : "Dose: " + currentMedicineDosage);
            }
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
