#include "age_link_audio.h"
#include "age_link_types.h"

#include <AudioFileSourceLittleFS.h>
#include <AudioGeneratorWAV.h>
#include <AudioOutputI2S.h>

// Audio Object Pointers
AudioOutputI2S *audioOut           = nullptr;
AudioFileSourceLittleFS *audioFile = nullptr;
AudioGeneratorWAV *audioGen        = nullptr;

// Internal Callbacks
static void audio_metadata_cb(void *data, const char *name, bool isStream, const char *value) {
    (void)data;
    (void)isStream;
    // Suppress verbose spam during normal operation
}

static void audio_status_cb(void *data, int type, const char *info) {
    (void)data;
    (void)type;
    (void)info;
    // Suppress verbose spam
}

static void file_status_cb(void *data, int type, const char *info) {
    (void)data;
    (void)type;
    Serial.print(F("[AUDIO] Status: "));
    Serial.println(info);
    if (audioGen) {
        audioGen->stop();
    }
}

void initAudio() {
    Serial.println(F("[AUDIO] Initializing I2S audio driver..."));

    audioOut = new AudioOutputI2S();
    audioOut->SetPinout(I2S_BCLK, I2S_LRC, I2S_DOUT);
    audioOut->begin();
    setAudioVolume(currentVolume);

    audioFile = new AudioFileSourceLittleFS();
    audioGen  = new AudioGeneratorWAV();

    audioGen->RegisterMetadataCB(audio_metadata_cb, nullptr);
    audioGen->RegisterStatusCB(audio_status_cb, nullptr);
    audioFile->RegisterStatusCB(file_status_cb, nullptr);

    Serial.println(F("[AUDIO] I2S MAX98357A driver initialized successfully."));
}

void setAudioVolume(float volume) {
    if (volume < 0.0f) volume = 0.0f;
    if (volume > 1.0f) volume = 1.0f;
    currentVolume = volume;
    if (audioOut) {
        audioOut->SetGain(currentVolume);
    }
}

void playWavFile(const char* filename) {
    if (!audioFile || !audioGen || !audioOut) {
        Serial.println(F("[AUDIO] ERROR: Audio system not initialized."));
        return;
    }

    if (audioGen->isRunning()) {
        audioGen->stop();
    }

    Serial.print(F("[AUDIO] Playing WAV: "));
    Serial.println(filename);

    if (audioFile->open(filename)) {
        if (!audioGen->begin(audioFile, audioOut)) {
            Serial.println(F("[AUDIO] ERROR: Failed to begin WAV audio generator."));
        }
    } else {
        Serial.print(F("[AUDIO] ERROR: Could not open WAV file: "));
        Serial.println(filename);
    }
}

void stopAudio() {
    if (audioGen && audioGen->isRunning()) {
        audioGen->stop();
    }
}

bool isAudioPlaying() {
    return (audioGen && audioGen->isRunning());
}

void audioLoop() {
    if (audioGen && audioGen->isRunning()) {
        if (!audioGen->loop()) {
            audioGen->stop();
        }
    }
}

void waitForAudioToFinish(unsigned long timeoutMs) {
    unsigned long start = millis();
    while (isAudioPlaying() && (millis() - start < timeoutMs)) {
        audioLoop();
        delay(20);
    }
}
