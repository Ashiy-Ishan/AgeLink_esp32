#pragma once

#include <Arduino.h>
#include "age_link_config.h"

// Forward declaration of ESP8266Audio classes to keep header clean
class AudioOutputI2S;
class AudioFileSourceLittleFS;
class AudioGeneratorWAV;

extern AudioOutputI2S *audioOut;
extern AudioFileSourceLittleFS *audioFile;
extern AudioGeneratorWAV *audioGen;

/**
 * @brief Initializes I2S audio driver and audio generator on MAX98357A.
 */
void initAudio();

/**
 * @brief Adjusts the I2S output volume gain.
 * @param volume Fractional gain from 0.0 (mute) to 1.0 (100%).
 */
void setAudioVolume(float volume);

/**
 * @brief Starts non-blocking playback of a WAV file stored in LittleFS.
 * @param filename File path in LittleFS (e.g., "/first_reminder.wav").
 */
void playWavFile(const char* filename);

/**
 * @brief Stops current audio playback safely.
 */
void stopAudio();

/**
 * @brief Checks if a WAV audio track is currently playing.
 * @return true if playing, false if idle/stopped.
 */
bool isAudioPlaying();

/**
 * @brief Core pump function required by ESP8266Audio to process I2S audio chunks.
 * Must be called frequently inside loop() and long-running routines.
 */
void audioLoop();

/**
 * @brief Safely yields and pumps audio until playback finishes or timeout expires.
 * @param timeoutMs Maximum wait time in milliseconds.
 */
void waitForAudioToFinish(unsigned long timeoutMs = 10000);
