#include "age_link_hardware.h"
#include <U8x8lib.h>

static U8X8_SH1106_128X64_NONAME_HW_I2C sh1106(U8X8_PIN_NONE, I2C_SCL, I2C_SDA);
static U8X8_SSD1306_128X64_NONAME_HW_I2C ssd1306(U8X8_PIN_NONE, I2C_SCL, I2C_SDA);
static U8X8& display = OLED_IS_SH1106 ? static_cast<U8X8&>(sh1106) : static_cast<U8X8&>(ssd1306);

static String lcdLine1_last = "";
static String lcdLine2_last = "";

void initHardware() {
    pinMode(LED_GREEN, OUTPUT);
    pinMode(LED_ORANGE, OUTPUT);
    pinMode(LED_RED, OUTPUT);

    pinMode(BUTTON_MED, INPUT_PULLUP);
    pinMode(BUTTON_SOS, INPUT_PULLUP);

    setLEDs(false, false, false);
    Serial.println(F("[HARDWARE] GPIO pins and LEDs initialized."));
}

void setLEDs(bool green, bool orange, bool red) {
    digitalWrite(LED_GREEN, green ? HIGH : LOW);
    digitalWrite(LED_ORANGE, orange ? HIGH : LOW);
    digitalWrite(LED_RED, red ? HIGH : LOW);
}

bool isMedButtonPressed() {
    return (digitalRead(BUTTON_MED) == LOW);
}

bool isSosButtonPressed() {
    return (digitalRead(BUTTON_SOS) == LOW);
}

void initLCD() {
    display.setI2CAddress(OLED_I2C_ADDRESS << 1);
    display.begin();
    display.setFont(u8x8_font_chroma48medium8_r);
    clearLCD();
    Serial.println(F("[HARDWARE] OLED initialized."));
}

void updateLCD(const String& line1, const String& line2) {
    String line1_trimmed = line1.substring(0, LCD_COLUMNS);
    String line2_trimmed = line2.substring(0, LCD_COLUMNS);

    if (line1_trimmed == lcdLine1_last && line2_trimmed == lcdLine2_last) {
        return; // Prevent screen flickering if content has not changed
    }

    display.clearLine(1);
    display.drawString(0, 1, line1_trimmed.c_str());
    lcdLine1_last = line1_trimmed;

    display.clearLine(4);
    display.drawString(0, 4, line2_trimmed.c_str());
    lcdLine2_last = line2_trimmed;
}

void forceRefreshLCD(const String& line1, const String& line2) {
    clearLCD();
    updateLCD(line1, line2);
}

void clearLCD() {
    lcdLine1_last = "";
    lcdLine2_last = "";
    display.clearDisplay();
}
