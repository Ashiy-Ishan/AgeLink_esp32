#pragma once

#include <Arduino.h>
#include "age_link_config.h"

// =============================================================================
// Hardware & Display Peripherals Manager
// =============================================================================

/**
 * @brief Configures GPIO pin modes for status LEDs and input buttons.
 */
void initHardware();

/**
 * @brief Sets status of the three indicator LEDs.
 * @param green Status for green LED.
 * @param orange Status for orange LED.
 * @param red Status for red LED.
 */
void setLEDs(bool green, bool orange, bool red);

/**
 * @brief Reads the Medicine button state with active-LOW logic.
 * @return true if button is pressed, false otherwise.
 */
bool isMedButtonPressed();

/**
 * @brief Reads the SOS button state with active-LOW logic.
 * @return true if button is pressed, false otherwise.
 */
bool isSosButtonPressed();

// 128x64 OLED screens. Signal bars are based on Wi-Fi, not the modem.
void initOLED();
void showOLED(const String& title, const String& headline,
              const String& detail = "", const String& hint = "");
void showHomeOLED(const String& currentTime, const String& nextTime,
                  const String& medicineName, bool wifiConnected, int32_t wifiRssi);
