package chat.simplex.app.model

import android.app.*
import android.content.Context
import android.content.Intent
import androidx.compose.ui.text.ExperimentalTextApi
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import chat.simplex.app.MainActivity
import chat.simplex.app.R

class NtfManager(val context: Context) {
  private val manager: NotificationManager = (
      context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
    )

  fun createNotificationChannel(channelId: String) {
    val name = "SimpleX Chat"
    val desc = "Channel for message notifications"
    val importance = NotificationManager.IMPORTANCE_DEFAULT
    val channel = NotificationChannel(channelId, name, importance).apply {
      description = desc
    }
    manager.createNotificationChannel(channel)
  }

  @OptIn(
    ExperimentalTextApi::class,
    com.google.accompanist.insets.ExperimentalAnimatedInsets::class,
    com.google.accompanist.permissions.ExperimentalPermissionsApi::class,
    androidx.compose.material.ExperimentalMaterialApi::class
  )
  fun notifyMessageReceived(cInfo: ChatInfo, cItem: ChatItem, channelId: String = "SimpleXNotifications") {
    val intent = Intent(
      context,
      MainActivity::class.java
    ).apply {
      flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TASK
    }
      .putExtra("chatId", cInfo.id)
      .putExtra("chatType", cInfo.chatType.chatTypeName)
      .setAction("openChatWithId")
    notify(
      channelId,
      title = cInfo.displayName,
      content = cItem.content.text,
      notificationId = cItem.hashCode(),
      intent = intent,
      group = cInfo.id
    )
  }

  private fun getMsgNotificationBuilder(
    channelId: String,
    title: String,
    content: String,
    group: String?,
    priority: Int,
    pendingIntent: PendingIntent,
    groupNotificationText: String? = null,
  ): NotificationCompat.Builder {
    val builder = NotificationCompat.Builder(context, channelId)
      .setSmallIcon(R.mipmap.icon)
      .setContentTitle(title)
      .setContentText(content)
      .setPriority(priority)
      .setGroup(group)
      .setGroupAlertBehavior(NotificationCompat.GROUP_ALERT_SUMMARY)
      .setAutoCancel(true)
      .setContentIntent(pendingIntent)
    if (groupNotificationText != null) {
      builder.setStyle(NotificationCompat.InboxStyle().addLine(content))
    }
    else {
      builder.setStyle(NotificationCompat.InboxStyle()
        .setSummaryText(groupNotificationText)
      )
    }
    return builder
  }

  private fun notify(
    channelId: String,
    title: String,
    content: String,
    notificationId: Int,
    intent: Intent,
    group: String? = null,
    priority: Int = NotificationCompat.PRIORITY_DEFAULT
  ) {
    val pendingIntent = TaskStackBuilder.create(context).run {
      addNextIntentWithParentStack(intent)
      getPendingIntent(0, PendingIntent.FLAG_IMMUTABLE)
    }
    val builder = getMsgNotificationBuilder(channelId, title, content, group, priority, pendingIntent)

    // Deal with notifications for the same chat
    val notifications = manager.activeNotifications
    val jointNotifications = notifications.filter { n -> (n.notification.group != null && n.notification.group == group) }
    val rawCount = jointNotifications.count()
    val msgCount = if (rawCount <= 1) rawCount + 1 else rawCount  // Avoid counting existing collective notification
    val groupNotificationText = if (msgCount > 1) "$msgCount new messages" else "$msgCount new message"
    val groupNotificationBuilder = getMsgNotificationBuilder(channelId, title, content, group, priority, pendingIntent, groupNotificationText)

    // Send notifications
    with(NotificationManagerCompat.from(context)) {
      // Cancel solo notification as it doesn't join group. Resend it to be in the group.
      if (rawCount != 0) {
        notify(group.hashCode(), groupNotificationBuilder.build())
      }
      if (rawCount == 1) {
        val originalId = jointNotifications[0].id
        manager.cancel(originalId)
        notify(originalId, jointNotifications[0].notification.clone())
      }
      notify(notificationId, builder.build())
    }
  }
}