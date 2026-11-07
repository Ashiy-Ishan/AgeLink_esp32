#pragma once

#include <Arduino.h>
#include "age_link_config.h"

// =============================================================================
// BLE Provisioning Service
// =============================================================================

/**
 * @brief Initializes BLE GATT server with AgeLink setup service and characteristic.
 */
void startBLEProvisioning();

/**
 * @brief Handles the BLE provisioning loop when configuration is missing.
 * Blinks LEDs, waits for mobile app provisioning data, saves config, and restarts.
 */
void runBLEProvisioningMode();
