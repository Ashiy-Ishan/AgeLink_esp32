
import { initializeApp, applicationDefault } from "firebase-admin/app";
import { getDatabase } from "firebase-admin/database";
import { getMessaging } from "firebase-admin/messaging";

const DATABASE_URL =
  "https://agelink-f4680-default-rtdb.asia-southeast1.firebasedatabase.app";

const NOTIFICATION_CHANNEL = "agelink_medication_alerts";

initializeApp({
  credential: applicationDefault(),
  databaseURL: DATABASE_URL,
});

const database = getDatabase();
const messaging = getMessaging();

const userListeners = new Map();
const processedEvents = new Set();

function isTakenState(state) {
  return ["Green", "Orange", "Red"].includes(state);
}

function makeNotification(data) {
  const state = String(data.reminder_state ?? "Missed");
  const isTaken = isTakenState(state);

  return {
    state,
    title: isTaken
      ? "Medication Confirmed"
      : "Missed Medication Alert",
    body: isTaken
      ? "A medication dose has been confirmed. Open AgeLink to view the details."
      : "A medication dose may have been missed. Open AgeLink to review.",
  };
}

async function sendNotification(userId, notificationId, record) {
  const eventKey = `${userId}/${notificationId}`;

  if (processedEvents.has(eventKey)) {
    return;
  }

  processedEvents.add(eventKey);

  if (
    !record ||
    typeof record !== "object" ||
    Array.isArray(record)
  ) {
    return;
  }

  const tokensSnapshot = await database
    .ref(`pushTokens/${userId}`)
    .get();

  if (!tokensSnapshot.exists()) {
    console.log(`No registered device for user ${userId}`);
    return;
  }

  const storedDevices = tokensSnapshot.val();

  if (
    !storedDevices ||
    typeof storedDevices !== "object"
  ) {
    return;
  }

  const devices = Object.entries(storedDevices).filter(
    ([, token]) =>
      typeof token === "string" &&
      token.trim().length > 0
  );

  if (devices.length === 0) {
    return;
  }

  const notification = makeNotification(record);

  console.log(
    `Sending ${notification.state} alert for user ${userId}`
  );

  for (let start = 0; start < devices.length; start += 500) {
    const batch = devices.slice(start, start + 500);
    const tokens = batch.map(([, token]) => token);

    const response = await messaging.sendEachForMulticast({
      tokens,

      notification: {
        title: notification.title,
        body: notification.body,
      },

      data: {
        type: "medication_activity",
        userId: String(userId),
        notificationId: String(notificationId),
        reminderState: notification.state,
      },

      android: {
        priority: "high",
        ttl: 3600000,

        notification: {
          channelId: NOTIFICATION_CHANNEL,
          priority: "high",
          defaultSound: true,
          visibility: "private",
          color: "#1E88E5",
        },
      },
    });

    console.log(
      `Delivered: ${response.successCount}, Failed: ${response.failureCount}`
    );

    for (let index = 0; index < response.responses.length; index++) {
      const result = response.responses[index];

      if (result.success) {
        continue;
      }

      const errorCode = result.error?.code;

      console.error("FCM error:", errorCode);

      if (
        errorCode ===
          "messaging/registration-token-not-registered" ||
        errorCode ===
          "messaging/invalid-registration-token"
      ) {
        const [deviceId, oldToken] = batch[index];

        try {
          const tokenRef = database.ref(
            `pushTokens/${userId}/${deviceId}`
          );

          await tokenRef.transaction(
            (currentToken) =>
              currentToken === oldToken
                ? null
                : undefined,
            undefined,
            false
          );
        } catch (error) {
          console.error("Token cleanup failed:", error);
        }
      }
    }
  }
}

async function watchUser(userId) {
  if (userListeners.has(userId)) {
    return;
  }

  const confirmationRef = database.ref(
    `reminders/${userId}/confirmation`
  );

  userListeners.set(userId, {
    ref: confirmationRef,
    callback: null,
  });

  try {
    const initialSnapshot = await confirmationRef.get();
    const existingIds = new Set();

    initialSnapshot.forEach((child) => {
      existingIds.add(child.key);
    });

    if (!userListeners.has(userId)) {
      return;
    }

    const onNewConfirmation = (snapshot) => {
      const notificationId = snapshot.key;

      if (!notificationId) {
        return;
      }

      if (existingIds.has(notificationId)) {
        return;
      }

      sendNotification(
        userId,
        notificationId,
        snapshot.val()
      ).catch((error) => {
        console.error(
          `Notification error for ${userId}/${notificationId}:`,
          error
        );
      });
    };

    confirmationRef.on(
      "child_added",
      onNewConfirmation,
      (error) => {
        console.error(
          `Confirmation listener error for ${userId}:`,
          error
        );
      }
    );

    userListeners.set(userId, {
      ref: confirmationRef,
      callback: onNewConfirmation,
    });

    console.log(`Watching medication records for ${userId}`);
  } catch (error) {
    userListeners.delete(userId);
    console.error(`Failed to watch user ${userId}:`, error);
  }
}

function stopWatchingUser(userId) {
  const listener = userListeners.get(userId);

  if (!listener) {
    return;
  }

  if (listener.callback) {
    listener.ref.off("child_added", listener.callback);
  }

  userListeners.delete(userId);

  console.log(`Stopped watching ${userId}`);
}

const remindersRef = database.ref("reminders");

remindersRef.on(
  "child_added",
  (snapshot) => {
    if (snapshot.key) {
      watchUser(snapshot.key).catch(console.error);
    }
  },
  (error) => {
    console.error("Reminders listener error:", error);
  }
);

remindersRef.on(
  "child_removed",
  (snapshot) => {
    if (snapshot.key) {
      stopWatchingUser(snapshot.key);
    }
  }
);

console.log("AgeLink Notification Server started");
console.log("Firebase project: agelink-f4680");
console.log("Listening for new medication confirmation records");

async function shutdown() {
  console.log("Stopping AgeLink notification server");

  remindersRef.off();

  for (const userId of userListeners.keys()) {
    stopWatchingUser(userId);
  }

  process.exit(0);
}

process.on("SIGINT", shutdown);
process.on("SIGTERM", shutdown);