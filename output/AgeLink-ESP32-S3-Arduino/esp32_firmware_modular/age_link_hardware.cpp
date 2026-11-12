#include "age_link_hardware.h"
#include <U8g2lib.h>

static U8G2_SH1106_128X64_NONAME_F_HW_I2C sh1106(
    U8G2_R0, U8X8_PIN_NONE, I2C_SCL, I2C_SDA);
static U8G2_SSD1306_128X64_NONAME_F_HW_I2C ssd1306(
    U8G2_R0, U8X8_PIN_NONE, I2C_SCL, I2C_SDA);
static U8G2& display = OLED_IS_SH1106
    ? static_cast<U8G2&>(sh1106) : static_cast<U8G2&>(ssd1306);

static constexpr uint8_t TEXT_X = 4;
static constexpr uint8_t TEXT_WIDTH = 120;

static void drawText(const String& text, uint8_t baseline) {
    if (display.getUTF8Width(text.c_str()) <= TEXT_WIDTH) {
        display.drawUTF8(TEXT_X, baseline, text.c_str());
        return;
    }

    String shortened = text;
    const uint8_t ellipsisWidth = display.getStrWidth("...");
    while (!shortened.isEmpty() &&
           display.getUTF8Width(shortened.c_str()) + ellipsisWidth > TEXT_WIDTH) {
        unsigned int last = shortened.length() - 1;
        while (last > 0 && (static_cast<uint8_t>(shortened[last]) & 0xC0) == 0x80) {
            --last;
        }
        shortened.remove(last);
    }
    shortened += "...";
    display.drawUTF8(TEXT_X, baseline, shortened.c_str());
}

static void drawHeader(const String& title) {
    display.clearBuffer();
    display.setFont(u8g2_font_6x10_tf);
    drawText(title, 10);
    display.drawHLine(TEXT_X, 14, TEXT_WIDTH);
}

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

void initOLED() {
    display.setI2CAddress(OLED_I2C_ADDRESS << 1);
    display.begin();
    Serial.println(F("[HARDWARE] OLED initialized."));
}

static void drawScreen(const String& title, const String& headline,
                       const String& detail, const String& hint,
                       bool home, uint8_t bars) {
    static String lastTitle;
    static String lastHeadline;
    static String lastDetail;
    static String lastHint;
    static bool lastHome = false;
    static uint8_t lastBars = 0;

    if (title == lastTitle && headline == lastHeadline &&
        detail == lastDetail && hint == lastHint && home == lastHome && bars == lastBars) {
        return;
    }

    drawHeader(title);
    if (home) {
        for (uint8_t i = 0; i < 4; ++i) {
            const uint8_t height = 2 + i * 2;
            const uint8_t x = 104 + i * 5;
            if (i < bars) {
                display.drawBox(x, 11 - height, 3, height);
            } else {
                display.drawHLine(x, 10, 3);
            }
        }
        display.setFont(u8g2_font_logisoso24_tn);
    } else {
        display.setFont(u8g2_font_helvB12_tf);
        if (display.getUTF8Width(headline.c_str()) > TEXT_WIDTH) {
            display.setFont(u8g2_font_helvB10_tf);
        }
    }
    drawText(headline, home ? 41 : 37);

    display.setFont(u8g2_font_6x10_tf);
    drawText(detail, 52);
    drawText(hint, 63);
    display.sendBuffer();

    lastTitle = title;
    lastHeadline = headline;
    lastDetail = detail;
    lastHint = hint;
    lastHome = home;
    lastBars = bars;
}

void showOLED(const String& title, const String& headline,
              const String& detail, const String& hint) {
    drawScreen(title, headline, detail, hint, false, 0);
}

void showHomeOLED(const String& currentTime, const String& nextTime,
                  const String& medicineName, bool wifiConnected, int32_t wifiRssi) {
    uint8_t bars = 0;
    if (wifiConnected) {
        bars = wifiRssi >= -55 ? 4 : wifiRssi >= -67 ? 3 : wifiRssi >= -75 ? 2 : 1;
    }

    const bool hasNextDose = nextTime.length() == 5 && nextTime != "--:--";
    const String detail = hasNextDose ? "Next dose " + nextTime : String("No dose scheduled");
    drawScreen(wifiConnected ? "AGELINK" : "WI-FI OFFLINE", currentTime,
               detail, hasNextDose ? medicineName : String(), true, bars);
}
