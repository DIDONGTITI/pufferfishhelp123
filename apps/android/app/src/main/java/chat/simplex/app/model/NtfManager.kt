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

  fun createNotificationChannel(channelId: String) {
    val name = "SimpleX Chat"
    val desc = "Channel for message notifications"
    val importance = NotificationManager.IMPORTANCE_DEFAULT
    val channel = NotificationChannel(channelId, name, importance).apply {
      description = desc
    }
    val manager: NotificationManager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
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
      intent = intent
    )
  }

  private fun notify(
    channelId: String,
    title: String,
    content: String,
    notificationId: Int,
    intent: Intent,
    priority: Int = NotificationCompat.PRIORITY_DEFAULT
  ) {
    val pendingIntent = TaskStackBuilder.create(context).run {
      addNextIntentWithParentStack(intent)
      getPendingIntent(0, PendingIntent.FLAG_IMMUTABLE)
    }
    val builder = NotificationCompat.Builder(context, channelId)
      .setSmallIcon(R.mipmap.icon)
      .setContentTitle(title)
      .setContentText(content)
      .setPriority(priority)
      .setContentIntent(pendingIntent)
      .setAutoCancel(true)
    with(NotificationManagerCompat.from(context)) {
      notify(notificationId, builder.build())
    }
  }
}