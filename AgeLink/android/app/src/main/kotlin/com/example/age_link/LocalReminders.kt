package com.example.age_link

import android.app.AlarmManager
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import org.json.JSONArray
import java.util.Calendar
import java.util.TimeZone

internal object LocalReminders {
    private const val CHANNEL = "agelink_local_reminders"
    private const val PREFS = "agelink_local_reminders"
    private const val OWNER = "owner"
    private const val DOSES = "doses"
    private const val NEXT = "next"
    private const val TRIGGER = "trigger"
    private const val TEST = "com.example.age_link.TEST_REMINDER"
    private const val LAST_DELIVERY = "last_delivery"
    private const val DAY_MS = 86_400_000L
    private val zone = TimeZone.getTimeZone("Asia/Colombo")

    private data class Dose(val minute: Int, val name: String)
    private fun prefs(context: Context) = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
    private fun alarms(context: Context) = requireNotNull(context.getSystemService(AlarmManager::class.java))
    private fun notifications(context: Context) = requireNotNull(context.getSystemService(NotificationManager::class.java))

    fun status(context: Context): Map<String, Any> {
        createChannel(context)
        val manager = notifications(context)
        val channelEnabled = Build.VERSION.SDK_INT < 26 ||
            manager.getNotificationChannel(CHANNEL)?.importance != NotificationManager.IMPORTANCE_NONE
        return mapOf(
            "notifications" to (manager.areNotificationsEnabled() && channelEnabled),
            "exact" to canScheduleExact(context),
            "doses" to doses(context).size,
            "next" to prefs(context).getLong(NEXT, 0),
            "lastDelivery" to prefs(context).getLong(LAST_DELIVERY, 0)
        )
    }

    private fun canScheduleExact(context: Context) =
        Build.VERSION.SDK_INT < 31 || alarms(context).canScheduleExactAlarms()

    fun begin(context: Context, owner: String) {
        if (prefs(context).getString(OWNER, null) != owner) {
            clear(context)
            prefs(context).edit().putString(OWNER, owner).apply()
        }
        refresh(context, keepPending = true)
    }

    fun replace(context: Context, owner: String, json: String) {
        val storage = prefs(context)
        if (storage.getString(OWNER, null) != owner || storage.getString(DOSES, null) == json) return
        storage.edit().putString(DOSES, json).remove(NEXT).apply()
        refresh(context)
    }

    fun clear(context: Context) {
        prefs(context).edit().clear().commit()
        alarms(context).cancel(deliveryIntent(context, 0))
        alarms(context).cancel(testIntent(context))
        val manager = notifications(context)
        for (notification in manager.activeNotifications) {
            if (notification.tag?.startsWith("agelink-dose:") == true) {
                manager.cancel(notification.tag, notification.id)
            }
        }
    }

    fun refresh(context: Context, keepPending: Boolean = false) {
        val now = System.currentTimeMillis()
        val schedule = doses(context)
        val pending = prefs(context).getLong(NEXT, 0)
        // Keep a recently due alarm if Android deferred an inexact delivery.
        val next = if (keepPending && pending > now - DAY_MS &&
            schedule.any { it.minute == minuteAt(pending) }) {
            pending
        } else {
            nextAt(schedule, now)
        }
        arm(context, next)
    }

    fun deliver(context: Context, intent: Intent) {
        if (intent.action == TEST) {
            if (prefs(context).getString(OWNER, null) != null) {
                post(context, "AgeLink test reminder", "Phone reminders are working.",
                     "agelink-dose:test")
            }
            return
        }
        val expected = intent.getLongExtra(TRIGGER, 0)
        val storage = prefs(context)
        if (expected == 0L || storage.getLong(NEXT, 0) != expected) return
        val now = System.currentTimeMillis()
        if (now < expected) {
            arm(context, expected)
            return
        }

        val schedule = doses(context)
        var due = if (now - expected < DAY_MS) expected else nextAt(schedule, now - DAY_MS)
        // Claim this delivery before posting so a duplicate broadcast cannot replay it.
        storage.edit().remove(NEXT).commit()
        var posted = false
        while (due != 0L && due <= now) {
            val minute = minuteAt(due)
            val time = "%02d:%02d".format(java.util.Locale.ROOT, minute / 60, minute % 60)
            schedule.filter { it.minute == minute }.forEachIndexed { index, dose ->
                if (post(context, dose.name.ifBlank { "Medication reminder" },
                         "Scheduled for $time", "agelink-dose:$due:$index")) {
                    posted = true
                }
            }
            due = nextAt(schedule, due)
        }
        if (posted) storage.edit().putLong(LAST_DELIVERY, now).apply()
        arm(context, due)
    }

    fun test(context: Context) {
        val current = status(context)
        check(current["notifications"] == true) { "Enable AgeLink notifications first." }
        check(current["exact"] == true) { "Allow Alarms & reminders first." }
        check(prefs(context).getString(OWNER, null) != null) { "Sign in to AgeLink first." }
        alarms(context).setAlarmClock(
            AlarmManager.AlarmClockInfo(System.currentTimeMillis() + 5000, openApp(context)),
            testIntent(context)
        )
    }

    private fun doses(context: Context): List<Dose> {
        val json = JSONArray(prefs(context).getString(DOSES, null) ?: "[]")
        return (0 until json.length()).mapNotNull { index ->
            val entry = json.optJSONObject(index) ?: return@mapNotNull null
            val minute = entry.optInt("minute", -1)
            if (minute !in 0..1439) return@mapNotNull null
            Dose(minute, entry.optString("name"))
        }
    }

    private fun minuteAt(epochMillis: Long): Int = Calendar.getInstance(zone).run {
        timeInMillis = epochMillis
        get(Calendar.HOUR_OF_DAY) * 60 + get(Calendar.MINUTE)
    }

    private fun nextAt(doses: List<Dose>, after: Long): Long {
        val date = Calendar.getInstance(zone).apply { timeInMillis = after }
        var next = Long.MAX_VALUE
        for (dose in doses) {
            val candidate = (date.clone() as Calendar).apply {
                set(Calendar.HOUR_OF_DAY, dose.minute / 60)
                set(Calendar.MINUTE, dose.minute % 60)
                set(Calendar.SECOND, 0)
                set(Calendar.MILLISECOND, 0)
                if (timeInMillis <= after) add(Calendar.DAY_OF_MONTH, 1)
            }
            next = minOf(next, candidate.timeInMillis)
        }
        return if (next == Long.MAX_VALUE) 0 else next
    }

    private fun deliveryIntent(context: Context, trigger: Long): PendingIntent =
        PendingIntent.getBroadcast(
            context, 0,
            Intent(context, LocalReminderReceiver::class.java).putExtra(TRIGGER, trigger),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

    private fun testIntent(context: Context): PendingIntent = PendingIntent.getBroadcast(
        context, 1, Intent(context, LocalReminderReceiver::class.java).setAction(TEST),
        PendingIntent.FLAG_IMMUTABLE
    )

    private fun openApp(context: Context): PendingIntent =
        PendingIntent.getActivity(
            context, 0,
            Intent(context, MainActivity::class.java)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

    private fun arm(context: Context, next: Long) {
        val alarm = alarms(context)
        val operation = deliveryIntent(context, next)
        if (next == 0L) {
            alarm.cancel(operation)
            prefs(context).edit().remove(NEXT).apply()
            return
        }

        prefs(context).edit().putLong(NEXT, next).apply()
        val trigger = maxOf(next, System.currentTimeMillis() + 500)
        if (canScheduleExact(context)) {
            try {
                // A user-visible alarm clock can wake for doses less than 10 minutes apart.
                alarm.setAlarmClock(AlarmManager.AlarmClockInfo(trigger, openApp(context)), operation)
                return
            } catch (_: SecurityException) {
                // Android can revoke exact alarm access between the check and this call.
            }
        }
        alarm.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, trigger, operation)
    }

    private fun createChannel(context: Context) {
        if (Build.VERSION.SDK_INT >= 26) {
            val channel = NotificationChannel(CHANNEL, "Medication reminders", NotificationManager.IMPORTANCE_HIGH)
            channel.lockscreenVisibility = Notification.VISIBILITY_PRIVATE
            notifications(context).createNotificationChannel(channel)
        }
    }

    @Suppress("DEPRECATION")
    private fun post(context: Context, title: String, body: String, tag: String): Boolean {
        createChannel(context)
        val manager = notifications(context)
        if (!manager.areNotificationsEnabled() || (Build.VERSION.SDK_INT >= 26 &&
                manager.getNotificationChannel(CHANNEL)?.importance == NotificationManager.IMPORTANCE_NONE)) {
            return false
        }
        fun builder(): Notification.Builder =
            if (Build.VERSION.SDK_INT >= 26) Notification.Builder(context, CHANNEL)
            else Notification.Builder(context).setPriority(Notification.PRIORITY_HIGH)
                .setDefaults(Notification.DEFAULT_ALL)

        val public = builder().setSmallIcon(android.R.drawable.ic_popup_reminder)
            .setContentTitle("AgeLink reminder").setContentText("A medicine is scheduled.")
            .build()
        val reminder = builder().setSmallIcon(android.R.drawable.ic_popup_reminder)
            .setContentTitle(title)
            .setContentText(body)
            .setCategory(Notification.CATEGORY_REMINDER)
            .setVisibility(Notification.VISIBILITY_PRIVATE)
            .setPublicVersion(public)
            .setContentIntent(openApp(context))
            .setAutoCancel(true)
            .build()
        return try {
            manager.notify(tag, 0, reminder)
            true
        } catch (_: SecurityException) {
            false
        }
    }
}

class LocalReminderReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        LocalReminders.deliver(context, intent)
    }
}

class ReminderRescheduleReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        LocalReminders.refresh(
            context, keepPending = intent.action == AlarmManager.ACTION_SCHEDULE_EXACT_ALARM_PERMISSION_STATE_CHANGED
        )
    }
}
