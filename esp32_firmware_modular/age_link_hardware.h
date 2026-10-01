#pragma once

#include <Arduino.h>
#include <Wire.h>
#include <LiquidCrystal_I2C.h>
#include "age_link_config.h"

// =============================================================================
// Hardware & Display Peripherals Manager
// =============================================================================

extern LiquidCrystal_I2C lcd;

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

/**
 * @brief Initializes the I2C bus and the 16x2 LCD display.
 */
void initLCD();

/**
 * @brief Updates the LCD text conditionally to eliminate flicker and glitching.
 * @param line1 Top row text (trimmed to 16 characters).
 * @param line2 Bottom row text (trimmed to 16 characters).
 */
void updateLCD(const String& line1, const String& line2);

/**
 * @brief Forces a clear and redraw of both LCD lines.
 */
void forceRefreshLCD(const String& line1, const String& line2);

/**
 * @brief Clears LCD display buffer.
 */
void clearLCD();
