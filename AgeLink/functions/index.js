const {createHash} = require("node:crypto");
const {initializeApp} = require("firebase-admin/app");
const {getDatabaseWithUrl} = require("firebase-admin/database");
const {FieldValue, Timestamp, getFirestore} = require("firebase-admin/firestore");
const {getMessaging} = require("firebase-admin/messaging");
const {defineString} = require("firebase-functions/params");
const {HttpsError, onCall} = require("firebase-functions/v2/https");
const {onSchedule} = require("firebase-functions/v2/scheduler");
const logger = require("firebase-functions/logger");

initializeApp();
const firestore = getFirestore();
const databaseUrl = defineString("REMINDER_DATABASE_URL");
const devices = firestore.collection("reminderPushDevices");
const deliveries = firestore.collection("reminderPushDeliveries");
const region = "asia-southeast1";
const localClock = new Intl.DateTimeFormat("en-CA", {
  timeZone: "Asia/Colombo", hourCycle: "h23",
  year: "numeric", month: "2-digit", day: "2-digit", hour: "2-digit", minute: "2-digit",
});

function hash(value) {
  return createHash("sha256").update(value).digest("hex");
}

exports.updateReminderPushDevice = onCall({region}, async (request) => {
  if (!request.auth) throw new HttpsError("unauthenticated", "Sign in to AgeLink.");
  const {token, enabled, uid} = request.data ?? {};
  if (uid !== request.auth.uid) throw new HttpsError("permission-denied", "Account changed.");
  if (typeof token !== "string" || token.length === 0 || token.length > 4096 ||
      typeof enabled !== "boolean") {
    throw new HttpsError("invalid-argument", "Invalid notification registration.");
  }

  const ref = devices.doc(hash(token));
  if (enabled) {
    await ref.set({uid, token, updatedAt: FieldValue.serverTimestamp()});
  } else {
    await firestore.runTransaction(async (transaction) => {
      const device = await transaction.get(ref);
      if (device.get("uid") === uid) transaction.delete(ref);
    });
  }
  return {ok: true};
});

function scheduledSlot(scheduleTime) {
  const parts = Object.fromEntries(localClock.formatToParts(new Date(scheduleTime))
      .filter(({type}) => type !== "literal").map(({type, value}) => [type, value]));
  return {date: `${parts.year}-${parts.month}-${parts.day}`, time: `${parts.hour}:${parts.minute}`};
}

function isDue(dose, time) {
  return typeof dose?.time === "string" && dose.time.trim().padStart(5, "0") === time;
}

async function sendDose(device, uid, key, slot) {
  const id = hash(JSON.stringify([uid, key, slot.date, slot.time, device.id]));
  const delivery = deliveries.doc(id);
  // Reserve before sending so duplicate scheduler events do not send twice.
  // The lease lets a retry recover an interrupted attempt.
  const claimed = await firestore.runTransaction(async (transaction) => {
    const current = await transaction.get(delivery);
    const now = Date.now();
    if (current.get("sentAt")) return false;
    if (current.get("leaseUntil")?.toMillis() > now) throw new Error("Delivery lease is active.");
    transaction.set(delivery, {
      leaseUntil: Timestamp.fromMillis(now + 45000),
      expiresAt: Timestamp.fromMillis(now + 7 * 86400000),
    });
    return true;
  });
  if (!claimed) return;

  const currentDevice = await device.ref.get();
  if (currentDevice.get("uid") !== uid || currentDevice.get("token") !== device.get("token")) {
    await delivery.delete();
    return;
  }

  try {
    await getMessaging().send({
      token: device.get("token"),
      notification: {title: "AgeLink reminder", body: `A medicine is due at ${slot.time}.`},
      data: {kind: "dose_reminder", ownerUid: uid},
      android: {
        priority: "high",
        ttl: 180000,
        notification: {tag: id, sound: "default", visibility: "private"},
      },
    });
  } catch (error) {
    await delivery.delete();
    if (error.code === "messaging/registration-token-not-registered" ||
        error.code === "messaging/invalid-registration-token") {
      await firestore.runTransaction(async (transaction) => {
        const latest = await transaction.get(device.ref);
        if (latest.updateTime?.isEqual(device.updateTime)) transaction.delete(device.ref);
      });
      return;
    }
    throw error;
  }
  await delivery.update({sentAt: FieldValue.serverTimestamp()});
}

exports.sendScheduledDoseReminders = onSchedule({
  region,
  schedule: "* * * * *",
  timeZone: "Asia/Colombo",
  retryCount: 3,
  maxRetrySeconds: 180,
  minBackoffSeconds: 15,
  maxInstances: 1,
  concurrency: 1,
  timeoutSeconds: 120,
}, async (event) => {
  const slot = scheduledSlot(event.scheduleTime);
  const registrations = await devices.get();
  const owners = new Map();
  for (const device of registrations.docs) {
    const uid = device.get("uid");
    if (!owners.has(uid)) owners.set(uid, []);
    owners.get(uid).push(device);
  }

  const database = getDatabaseWithUrl(databaseUrl.value());
  let failed = false;
  const entries = [...owners];
  for (let i = 0; i < entries.length; i += 10) {
    const results = await Promise.allSettled(entries.slice(i, i + 10).map(async ([uid, phones]) => {
      const snapshot = await database.ref(`reminders/${uid}/schedule/med_times`).get();
      let firstError;
      for (const [key, dose] of Object.entries(snapshot.val() ?? {})) {
        if (!isDue(dose, slot.time)) continue;
        for (const phone of phones) {
          try {
            await sendDose(phone, uid, key, slot);
          } catch (error) {
            firstError ??= error;
          }
        }
      }
      if (firstError) throw firstError;
    }));
    for (const result of results) {
      if (result.status === "rejected") {
        failed = true;
        logger.warn("Reminder delivery failed", {code: result.reason?.code ?? "unknown"});
      }
    }
  }
  if (failed) throw new Error("Some scheduled reminders need retry.");
});
