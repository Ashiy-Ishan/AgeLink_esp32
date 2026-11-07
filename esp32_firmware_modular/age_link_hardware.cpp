#include "age_link_hardware.h"
#include "age_link_types.h"

// Instantiate LCD object
LiquidCrystal_I2C lcd(LCD_I2C_ADDRESS, LCD_COLUMNS, LCD_ROWS);

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
    Wire.begin(I2C_SDA, I2C_SCL);
    delay(100);
    lcd.init();
    lcd.backlight();
    lcd.clear();
    Serial.println(F("[HARDWARE] LCD display initialized successfully."));
}

void updateLCD(const String& line1, const String& line2) {
    String line1_trimmed = line1.substring(0, LCD_COLUMNS);
    String line2_trimmed = line2.substring(0, LCD_COLUMNS);

    if (line1_trimmed == lcdLine1_last && line2_trimmed == lcdLine2_last) {
        return; // Prevent screen flickering if content has not changed
    }

    // Refresh display to eliminate bus transient noise/corruption
    lcd.init();
    lcd.backlight();
    lcd.clear();

    lcd.setCursor(0, 0);
    lcd.print(line1_trimmed);
    lcdLine1_last = line1_trimmed;

    lcd.setCursor(0, 1);
    lcd.print(line2_trimmed);
    lcdLine2_last = line2_trimmed;
}

void forceRefreshLCD(const String& line1, const String& line2) {
    lcdLine1_last = "";
    lcdLine2_last = "";
    updateLCD(line1, line2);
}

void clearLCD() {
    lcdLine1_last = "";
    lcdLine2_last = "";
    lcd.clear();
}
