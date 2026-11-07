#include "age_link_config.h"

// BLE Strings
const char* const BLE_SERVICE_UUID        = "4FAFC201-1FB5-459E-8FCC-C5C9C331914B";
const char* const BLE_CHARACTERISTIC_UUID = "BEB5483E-36E1-4688-B7F5-EA07361B26A8";
const char* const BLE_DEVICE_NAME         = "AgeLink-Setup";

// Audio File Paths
const char* const SOUND_POWER_UP          = "/age_link_powerring up.wav";
const char* const SOUND_WIFI_CONNECTED    = "/wifi_connected.wav";
const char* const SOUND_WIFI_CONNECTING   = "/wifi_connecting.wav";
const char* const SOUND_FIRST_REMINDER    = "/first_reminder.wav";
const char* const SOUND_SECOND_REMINDER   = "/second_reminder.wav";
const char* const SOUND_FINAL_REMINDER    = "/final_reminder.wav";
const char* const SOUND_MEDICINE_CONFIRM  = "/medicine_confirm.wav";
const char* const SOUND_MEDICINE_MISSED   = "/medicine_missed.wav";
const char* const SOUND_EMERGENCY         = "/emegency.wav";
const char* const SOUND_EMERGENCY_INFORMED= "/emegency_informed.wav";
const char* const SOUND_SOS_CALL_CANCEL   = "/sos_call_cancel.wav";

// NTP Server
const char* const NTP_SERVER              = "pool.ntp.org";

void printSystemConfig() {
    Serial.println(F("========================================"));
    Serial.println(F("       AgeLink System Configuration     "));
    Serial.println(F("========================================"));
    Serial.print(F("LED Pins (G/O/R): "));
    Serial.print(LED_GREEN); Serial.print(F("/"));
    Serial.print(LED_ORANGE); Serial.print(F("/"));
    Serial.println(LED_RED);
    Serial.print(F("Button Pins (Med/SOS): "));
    Serial.print(BUTTON_MED); Serial.print(F("/"));
    Serial.println(BUTTON_SOS);
    Serial.print(F("I2S Pins (BCLK/LRC/DOUT): "));
    Serial.print(I2S_BCLK); Serial.print(F("/"));
    Serial.print(I2S_LRC); Serial.print(F("/"));
    Serial.println(I2S_DOUT);
    Serial.print(F("I2C Pins (SDA/SCL): "));
    Serial.print(I2C_SDA); Serial.print(F("/"));
    Serial.println(I2C_SCL);
    Serial.print(F("SIM800L (RX/TX): "));
    Serial.print(RX2_PIN); Serial.print(F("/"));
    Serial.println(TX2_PIN);
    Serial.println(F("========================================"));
}
