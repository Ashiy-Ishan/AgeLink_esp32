#include <Arduino.h>
#include <LittleFS.h>
#include <AudioFileSourceLittleFS.h>
#include <AudioGeneratorWAV.h>
#include <AudioOutputI2S.h>

constexpr int BCLK = 4;
constexpr int LRC = 5;
constexpr int DOUT = 6;

const char* const prompts[] = {
  "/age_link_powerring up.wav",
  "/wifi_connecting.wav",
  "/wifi_connected.wav",
  "/first_reminder.wav",
  "/second_reminder.wav",
  "/final_reminder.wav",
  "/medicine_confirm.wav",
  "/medicine_missed.wav",
  "/emegency.wav",
  "/emegency_informed.wav",
  "/sos_call_cancel.wav"
};

AudioOutputI2S speaker;
bool filesystemReady = false;

void playAllPrompts() {
  unsigned int opened = 0;

  for (const char* path : prompts) {
    Serial.printf("\nTesting %s\n", path);
    AudioFileSourceLittleFS file;
    if (!file.open(path)) {
      Serial.println("Missing or unreadable file.");
      continue;
    }

    AudioGeneratorWAV wav;
    if (!wav.begin(&file, &speaker)) {
      Serial.println("WAV playback could not start.");
      continue;
    }

    ++opened;
    while (wav.isRunning()) {
      if (!wav.loop()) {
        wav.stop();
      }
      yield();
    }
    delay(400);
  }

  Serial.printf("\nStarted playback for %u of %u files.\n", opened,
                static_cast<unsigned int>(sizeof(prompts) / sizeof(prompts[0])));
  Serial.println("Confirm you heard every prompt. Send P to play them again.");
}

void setup() {
  Serial.begin(115200);
  speaker.SetPinout(BCLK, LRC, DOUT);
  speaker.SetGain(0.2f);
  filesystemReady = LittleFS.begin(false);

  delay(1000);
  if (filesystemReady) {
    Serial.println("LittleFS mounted. Send P to play all 11 prompts.");
  } else {
    Serial.println("LittleFS mount failed. Upload data/ and reset the board.");
  }
}

void loop() {
  if (Serial.available()) {
    const int command = Serial.read();
    if (command == 'P' || command == 'p') {
      if (filesystemReady) {
        playAllPrompts();
      } else {
        Serial.println("Upload LittleFS, then reset the board.");
      }
    }
  }
  delay(10);
}
