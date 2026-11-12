#include <Arduino.h>
#include <ESP_I2S.h>
#include <math.h>

constexpr int I2S_BCLK = 4;
constexpr int I2S_WS = 5;
constexpr int I2S_DOUT = 6;
constexpr int MODEM_RX = 16;
constexpr int MODEM_TX = 17;

constexpr uint32_t SAMPLE_RATE = 16000;
constexpr uint32_t MODEM_TIMEOUT_MS = 2000;
I2SClass speaker;
bool speakerReady;

void playBeep() {
  if (!speakerReady) {
    Serial.println("I2S initialization failed.");
    return;
  }

  // Interleave identical left and right samples for either amplifier channel.
  int16_t samples[160 * 2];
  for (uint32_t block = 0; block < 50; ++block) {
    for (uint32_t frame = 0; frame < 160; ++frame) {
      const uint32_t index = block * 160 + frame;
      const float phase = 2.0f * PI * 880.0f * index / SAMPLE_RATE;
      const int16_t sample = static_cast<int16_t>(3000.0f * sinf(phase));
      samples[2 * frame] = sample;
      samples[2 * frame + 1] = sample;
    }
    if (speaker.write(samples, sizeof(samples)) != sizeof(samples)) {
      Serial.println("I2S write failed.");
      return;
    }
  }
  memset(samples, 0, sizeof(samples));
  speaker.write(samples, sizeof(samples));
  Serial.println("Speaker tone sent. Listen for a short beep.");
}

bool modemCommand(const char* command) {
  Serial.print("\n> ");
  Serial.println(command);
  Serial2.print(command);
  Serial2.write('\r');

  String line;
  const uint32_t started = millis();
  while (millis() - started < MODEM_TIMEOUT_MS) {
    while (Serial2.available()) {
      const char ch = static_cast<char>(Serial2.read());
      if (ch == '\r') {
        continue;
      }
      if (ch != '\n') {
        line += ch;
        continue;
      }
      line.trim();
      if (line.length() == 0) {
        continue;
      }
      Serial.println(line);
      if (line == "OK") {
        return true;
      }
      if (line == "ERROR" || line.startsWith("+CME ERROR:")) {
        return false;
      }
      line = "";
    }
    delay(1);
  }
  Serial.println("Timed out waiting for modem response.");
  return false;
}

void testModem() {
  while (Serial2.available()) {
    Serial2.read();
  }
  // Retry AT for modules that are still starting or detecting the baud rate.
  for (int attempt = 0; attempt < 3; ++attempt) {
    if (modemCommand("AT")) {
      modemCommand("AT+CPIN?");
      modemCommand("AT+CSQ");
      modemCommand("AT+CREG?");
      return;
    }
    delay(300);
  }
  Serial.println("No AT response. Check modem power, UART wiring and baud rate.");
}

void setup() {
  Serial.begin(115200);
  Serial2.begin(9600, SERIAL_8N1, MODEM_RX, MODEM_TX);

  speaker.setPins(I2S_BCLK, I2S_WS, I2S_DOUT);
  speakerReady = speaker.begin(
      I2S_MODE_STD, SAMPLE_RATE, I2S_DATA_BIT_WIDTH_16BIT, I2S_SLOT_MODE_STEREO);

  delay(2000);
  Serial.println("\nAgeLink speaker and SIM800L test");
  Serial.println("Send b to replay the beep or s to rerun the SIM test.");
  playBeep();
  testModem();
}

void loop() {
  if (Serial.available()) {
    const char command = static_cast<char>(Serial.read());
    if (command == 'b' || command == 'B') {
      playBeep();
    } else if (command == 's' || command == 'S') {
      testModem();
    }
  }
  delay(10);
}
