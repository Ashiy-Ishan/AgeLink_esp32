## Android medication reminders

The scheduled function reads each registered account's active schedule from
`reminders/<uid>/schedule/med_times` in Realtime Database. It sends one push
per dose in the scheduled minute, in the `Asia/Colombo` time zone.

Before deploying, review the existing Firestore rules. Client apps must have
no direct read or write access to `reminderPushDevices` or
`reminderPushDeliveries`. The callable and scheduled functions access those
collections through the Admin SDK. If a broad allow rule covers either
collection, narrow that rule first. Enable Firestore TTL on
`reminderPushDeliveries.expiresAt` to remove old delivery records.

From the `AgeLink` directory, sign in with the Firebase CLI and deploy only
these two functions. The Firebase project must support Cloud Functions and
Cloud Scheduler billing. When prompted for `REMINDER_DATABASE_URL`, enter the
project's Realtime Database URL.

```sh
firebase deploy --project agelink-f4680 --only functions:updateReminderPushDevice,functions:sendScheduledDoseReminders
```

Install the updated Android app, sign in, and allow notifications. Save a test
schedule a few minutes ahead, then background the app and confirm that each
scheduled dose produces its own notification. The phone needs an internet
connection. The ESP32 can be offline for this test.
