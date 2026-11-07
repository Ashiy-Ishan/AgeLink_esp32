#pragma once

#include <Arduino.h>
#include "age_link_config.h"
#include "age_link_types.h"

// =============================================================================
// Reminder State Machine & Event Scheduler
// =============================================================================

/**
 * @brief Activates the LEDs, LCD text, and voice alert for a reminder escalation tier.
 * @param phase Stage to activate (GREEN_ACTIVE, ORANGE_ACTIVE, or RED_ACTIVE).
 */
void startAlarmSequence(ReminderState phase);

/**
 * @brief Runs periodic checks for long-press factory reset on the Medicine button.
 */
void checkFactoryResetButton();

/**
 * @brief Evaluates SOS button press and invokes emergency sequence if debounced.
 */
void checkSosButton();

/**
 * @brief Main execution function for the reminder state machine.
 * Evaluates active countdowns, escalations, confirmations, and idle displays.
 */
void runSchedulerStateMachine();
