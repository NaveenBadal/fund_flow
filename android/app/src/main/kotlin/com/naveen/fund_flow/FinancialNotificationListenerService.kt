package com.naveen.fund_flow

import android.app.Notification
import android.content.ComponentName
import android.content.Context
import android.os.Bundle
import android.provider.Settings
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import org.json.JSONArray
import org.json.JSONObject

class FinancialNotificationListenerService : NotificationListenerService() {
    override fun onListenerConnected() {
        super.onListenerConnected()
        activeNotifications?.forEach(::capture)
    }

    override fun onNotificationPosted(sbn: StatusBarNotification?) {
        sbn?.let(::capture)
    }

    private fun capture(sbn: StatusBarNotification) {
        if (!isCaptureEnabled(this)) return
        if (sbn.packageName == packageName) return
        val extras = sbn.notification.extras ?: return
        val title = firstNonBlank(
            extras.getCharSequence(Notification.EXTRA_CONVERSATION_TITLE),
            extras.getCharSequence(Notification.EXTRA_TITLE),
            extras.getCharSequence(Notification.EXTRA_TITLE_BIG),
        )
        val body = notificationBody(extras)
        if (body.isBlank()) return
        enqueue(
            this,
            JSONObject()
                .put("id", "${sbn.key}:${body.hashCode()}")
                .put("packageName", sbn.packageName)
                .put("title", title)
                .put("body", body)
                .put("postedAt", sbn.postTime),
        )
    }

    private fun notificationBody(extras: Bundle): String {
        val latestMessage = extras.getParcelableArray(Notification.EXTRA_MESSAGES)
            ?.lastOrNull()
            ?.let { it as? Bundle }
            ?.getCharSequence("text")
        val latestLine = extras.getCharSequenceArray(Notification.EXTRA_TEXT_LINES)
            ?.lastOrNull()
        return firstNonBlank(
            extras.getCharSequence(Notification.EXTRA_BIG_TEXT),
            latestMessage,
            extras.getCharSequence(Notification.EXTRA_TEXT),
            latestLine,
        )
    }

    private fun firstNonBlank(vararg values: CharSequence?): String =
        values.firstNotNullOfOrNull { value ->
            value?.toString()?.trim()?.takeIf(String::isNotBlank)
        }.orEmpty()

    companion object {
        private const val preferencesName = "fund_flow_notification_capture"
        private const val queueKey = "pending_events"
        private const val enabledKey = "capture_enabled"
        private const val maxQueueSize = 200
        private val queueLock = Any()

        fun isAccessEnabled(context: Context): Boolean {
            val enabled = Settings.Secure.getString(
                context.contentResolver,
                "enabled_notification_listeners",
            ).orEmpty()
            val component = ComponentName(
                context,
                FinancialNotificationListenerService::class.java,
            )
            return enabled.split(':').any {
                ComponentName.unflattenFromString(it) == component
            }
        }

        fun setCaptureEnabled(context: Context, enabled: Boolean) {
            context.getSharedPreferences(preferencesName, MODE_PRIVATE)
                .edit()
                .putBoolean(enabledKey, enabled)
                .apply()
        }

        private fun isCaptureEnabled(context: Context): Boolean =
            context.getSharedPreferences(preferencesName, MODE_PRIVATE)
                .getBoolean(enabledKey, false)

        fun getPending(context: Context): List<Map<String, Any>> = synchronized(queueLock) {
            val queue = readQueue(context)
            buildList {
                for (index in 0 until queue.length()) {
                    val item = queue.optJSONObject(index) ?: continue
                    add(
                        mapOf(
                            "id" to item.optString("id"),
                            "packageName" to item.optString("packageName"),
                            "title" to item.optString("title"),
                            "body" to item.optString("body"),
                            "postedAt" to item.optLong("postedAt"),
                        ),
                    )
                }
            }
        }

        fun acknowledge(context: Context, ids: List<String>) = synchronized(queueLock) {
            if (ids.isEmpty()) return@synchronized
            val acknowledged = ids.toSet()
            val current = readQueue(context)
            val remaining = JSONArray()
            for (index in 0 until current.length()) {
                val item = current.optJSONObject(index) ?: continue
                if (item.optString("id") !in acknowledged) remaining.put(item)
            }
            writeQueue(context, remaining)
        }

        private fun enqueue(context: Context, event: JSONObject) = synchronized(queueLock) {
            val current = readQueue(context)
            val id = event.optString("id")
            val body = event.optString("body")
            for (index in 0 until current.length()) {
                val existing = current.optJSONObject(index) ?: continue
                if (existing.optString("id") == id || existing.optString("body") == body) return
            }
            val next = JSONArray()
            val start = (current.length() - maxQueueSize + 1).coerceAtLeast(0)
            for (index in start until current.length()) next.put(current.get(index))
            next.put(event)
            writeQueue(context, next)
        }

        private fun readQueue(context: Context): JSONArray {
            val raw = context.getSharedPreferences(preferencesName, MODE_PRIVATE)
                .getString(queueKey, "[]")
                .orEmpty()
            return try {
                JSONArray(raw)
            } catch (_: Exception) {
                JSONArray()
            }
        }

        private fun writeQueue(context: Context, queue: JSONArray) {
            context.getSharedPreferences(preferencesName, MODE_PRIVATE)
                .edit()
                .putString(queueKey, queue.toString())
                .apply()
        }
    }
}
