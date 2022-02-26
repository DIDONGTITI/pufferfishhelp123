package chat.simplex.app.model

import android.app.*
import android.content.Context
import android.content.Intent
import android.util.Log
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import chat.simplex.app.MainActivity
import chat.simplex.app.R
import kotlinx.datetime.Clock

class NtfManager(val context: Context) {
  companion object {
    const val MainChannelName: String = "SimpleXNotifications"
    const val SilentChannelName: String = "SilentSimpleXNotifications"
    const val OpenChatAction: String = "OpenChatAction"
  }

  private val manager: NotificationManager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
  private var prevNtfTime = mutableMapOf<String, Long>()
  private val msgNtfTimeoutMs = 10000L

  fun createNotificationChannel(channelId: String, quiet: Boolean = false) {
    val name = "SimpleX Chat"
    val desc = "Channel for message notifications"
    val importance = NotificationManager.IMPORTANCE_HIGH
    val channel = NotificationChannel(channelId, name, importance)
      .apply {
      description = desc
    }
    if (quiet) {
      channel.enableVibration(false)
      channel.enableLights(false)
      channel.setSound(null, null)
    }
    manager.createNotificationChannel(channel)
  }

  fun notifyMessageReceived(cInfo: ChatInfo, cItem: ChatItem) {
    Log.d("SIMPLEX", "notifyMessageReceived ${cInfo.id}")
    val now = Clock.System.now().toEpochMilliseconds()
    val recentNotification = (now - prevNtfTime.getOrDefault(cInfo.id, 0) < msgNtfTimeoutMs)
    prevNtfTime[cInfo.id] = now
    val channelId = if (recentNotification) SilentChannelName else MainChannelName

    val pendingIntent = getMsgPendingIntent(cInfo)

    val notificationId = Clock.System.now().hashCode()
//    val group = cInfo.id
//    val notificationGroupId = group.hashCode()

//    val notifications = manager.activeNotifications
//    val jointNotifications = notifications.filter { n -> (n.notification.group != null && n.notification.group == group) }
//    val rawCount = jointNotifications.count()

    val builder = NotificationCompat.Builder(context, channelId)
      .setSmallIcon(R.mipmap.icon)
      .setContentTitle(cInfo.displayName)
      .setContentText(cItem.content.text)
      .setPriority(NotificationCompat.PRIORITY_HIGH)
//      .setGroup(group)
//      .setStyle(NotificationCompat.InboxStyle().addLine(cItem.content.text))
      .setAutoCancel(true)
      .setContentIntent(pendingIntent)
      .setOnlyAlertOnce(true)

//    val notificationGroupBuilder = getGroupNotificationBuilder(rawCount, pendingIntent, channelId, cInfo.displayName, group)

    with(NotificationManagerCompat.from(context)) {
//      if (rawCount != 0) {
//        notify(notificationGroupId, notificationBuilder.build())
//      }
//      if (rawCount == 1) {
//        val originalId = jointNotifications[0].id
//        manager.cancel(originalId)
//        notify(originalId, jointNotifications[0].notification.clone())
//      }
      notify(notificationId, builder.build())
    }
  }

  private fun getMsgPendingIntent(cInfo: ChatInfo) : PendingIntent{
    Log.d("SIMPLEX", "getMsgPendingIntent ${cInfo.id}")
    val uniqueInt = (System.currentTimeMillis() and 0xfffffff).toInt()
    val intent = Intent(context, MainActivity::class.java)
      .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP)
      .putExtra("chatId", cInfo.id)
      .setAction(OpenChatAction)
    return TaskStackBuilder.create(context).run {
      addNextIntentWithParentStack(intent)
      getPendingIntent(uniqueInt, PendingIntent.FLAG_IMMUTABLE)
    }
  }

//  private fun getGroupNotificationBuilder(
//    rawNotificationCount: Int,
//    pendingIntent: PendingIntent,
//    channelId: String,
//    title: String,
//    group: String? = null
//  ): NotificationCompat.Builder {
//    // Avoid counting existing group notification
//    val msgCount = if (rawNotificationCount <= 1) rawNotificationCount + 1 else rawNotificationCount
//    val groupNotificationText = if (msgCount > 1) "$msgCount new messages" else "$msgCount new message"
//    return NotificationCompat.Builder(context, channelId)
//      .setSmallIcon(R.mipmap.icon)
//      .setContentTitle(title)
//      .setContentText(groupNotificationText)
//      .setStyle(NotificationCompat.InboxStyle()
//        .setSummaryText(groupNotificationText)
//      )
//      .setGroup(group)
//      .setGroupSummary(true)
//      .setGroupAlertBehavior(NotificationCompat.GROUP_ALERT_CHILDREN)
//      .setContentIntent(pendingIntent)
//      .setAutoCancel(true)
//      .setOnlyAlertOnce(true)
//      .setSound(null)
//      .setVibrate(null)
//  }
}
