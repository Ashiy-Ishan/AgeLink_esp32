#pragma once

#include <Arduino.h>

// =============================================================================
// AgeLink Hardware Pin Configurations
// =============================================================================

// Status LEDs
constexpr uint8_t LED_GREEN   = 14;
constexpr uint8_t LED_ORANGE  = 12;
constexpr uint8_t LED_RED     = 13;

// User Buttons (Active LOW, configured as INPUT_PULLUP)
constexpr uint8_t BUTTON_MED  = 7; // Medicine Confirmation Button
constexpr uint8_t BUTTON_SOS  = 10; // Emergency SOS Button

// SIM800L Cellular Modem (Serial2)
constexpr uint8_t RX2_PIN     = 16;
constexpr uint8_t TX2_PIN     = 17;

// MAX98357A / MAX98355A I2S DAC Audio Pins
constexpr uint8_t I2S_DOUT    = 6; // Serial Data Out
constexpr uint8_t I2S_LRC     = 5; // Left/Right Word Select Clock
constexpr uint8_t I2S_BCLK    = 4; // Continuous Bit Clock

// 128x64 OLED (I2C)
constexpr uint8_t I2C_SDA     = 8;
constexpr uint8_t I2C_SCL     = 9;
constexpr uint8_t OLED_I2C_ADDRESS = 0x3C;
constexpr bool OLED_IS_SH1106 = true; // Set false for an SSD1306 OLED.

// Baud Rates
constexpr uint32_t SERIAL_DEBUG_BAUD = 115200;
constexpr uint32_t SIM800L_BAUD      = 9600;

// =============================================================================
// BLE Provisioning UUIDs & Parameters
// =============================================================================
extern const char* const BLE_SERVICE_UUID;
extern const char* const BLE_CHARACTERISTIC_UUID;
extern const char* const BLE_DEVICE_NAME;

// =============================================================================
// Timing and Limits Constants
// =============================================================================
constexpr unsigned long DB_CHECK_INTERVAL_MS      = 10UL * 1000UL;      // 10s check interval
constexpr unsigned long ALARM_BEEP_DURATION_MS     = 5UL * 1000UL;       // ~5s playback duration
constexpr unsigned long SHORT_WAIT_MS              = 60UL * 1000UL;      // 60s per reminder stage
constexpr unsigned long WIFI_CONNECT_TIMEOUT_MS    = 30UL * 1000UL;      // 30s connection timeout
constexpr unsigned long WIFI_RETRY_INTERVAL_MS     = 30UL * 1000UL;      // 30s retry interval
constexpr unsigned long TIME_LOG_INTERVAL_MS       = 10UL * 1000UL;      // 10s console log interval
constexpr unsigned long FACTORY_RESET_HOLD_MS      = 5000UL;             // 5s hold to reset
constexpr unsigned long SOS_CALL_TIMEOUT_MS        = 40000UL;            // 40s ring timeout
constexpr unsigned long SOS_CANCEL_WINDOW_MS       = 3000UL;             // Initial SOS cancellation window


// =============================================================================
// Audio File Paths in LittleFS
// =============================================================================
extern const char* const SOUND_POWER_UP;
extern const char* const SOUND_WIFI_CONNECTED;
extern const char* const SOUND_WIFI_CONNECTING;
extern const char* const SOUND_FIRST_REMINDER;
extern const char* const SOUND_SECOND_REMINDER;
extern const char* const SOUND_FINAL_REMINDER;
extern const char* const SOUND_MEDICINE_CONFIRM;
extern const char* const SOUND_MEDICINE_MISSED;
extern const char* const SOUND_EMERGENCY;
extern const char* const SOUND_EMERGENCY_INFORMED;
extern const char* const SOUND_SOS_CALL_CANCEL;

// NTP Parameters
extern const char* const NTP_SERVER;
constexpr long GMT_OFFSET_SEC    = 19800; // GMT +5:30 (Sri Lanka / India)
constexpr int DAYLIGHT_OFFSET_SEC = 0;

void printSystemConfig();
