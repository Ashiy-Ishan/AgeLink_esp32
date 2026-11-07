#pragma once

#include <Arduino.h>
#include "age_link_config.h"

// =============================================================================
// SIM800L Cellular Modem & Emergency Calling Engine
// =============================================================================

/**
 * @brief Initializes Serial2 communication with the SIM800L module.
 */
void initSIM();

/**
 * @brief Sends an AT command to SIM800L and collects the response string.
 * @param command AT command to send (without carriage return/newline).
 * @param timeout_ms Response timeout in milliseconds.
 * @param fullResponse Whether to log the full response to Serial.
 * @return Response string received from SIM800L.
 */
String sendATCommand(const String& command, unsigned long timeout_ms, bool fullResponse = false);

/**
 * @brief Executes the automated emergency SOS calling sequence.
 * Iterates through emergency contacts, dials via SIM800L, monitors call status,
 * plays voice feedback over I2S audio, and listens for user cancellation.
 */
void executeSosSequence();
