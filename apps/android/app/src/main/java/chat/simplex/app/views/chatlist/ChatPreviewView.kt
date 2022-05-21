package chat.simplex.app.views.chatlist

import android.content.res.Configuration
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.*
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Circle
import androidx.compose.material.icons.outlined.Error
import androidx.compose.material.icons.outlined.ErrorOutline
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import chat.simplex.app.R
import chat.simplex.app.model.*
import chat.simplex.app.ui.theme.*
import chat.simplex.app.views.chat.item.MarkdownText
import chat.simplex.app.views.helpers.ChatInfoImage
import chat.simplex.app.views.helpers.badgeLayout

@Composable
fun ChatPreviewView(chat: Chat) {
  Row {
    val cInfo = chat.chatInfo
    ChatInfoImage(cInfo, size = 72.dp)
    Column(
      modifier = Modifier
        .padding(horizontal = 8.dp)
        .weight(1F)
    ) {
      Text(
        cInfo.chatViewName,
        maxLines = 1,
        overflow = TextOverflow.Ellipsis,
        style = MaterialTheme.typography.h3,
        fontWeight = FontWeight.Bold,
        color = if (cInfo.ready) Color.Unspecified else HighOrLowlight
      )
      if (cInfo.ready) {
        val ci = chat.chatItems.lastOrNull()
        if (ci != null) {
          MarkdownText(
            ci.text, ci.formattedText, ci.memberDisplayName,
            metaText = ci.timestampText,
            maxLines = 2,
            overflow = TextOverflow.Ellipsis
          )
        }
      } else {
        Text(stringResource(R.string.contact_connection_pending), color = HighOrLowlight)
      }
    }
    val ts = chat.chatItems.lastOrNull()?.timestampText ?: getTimestampText(chat.chatInfo.updatedAt)
    Column(
      Modifier.fillMaxHeight(),
      verticalArrangement = Arrangement.Top
    ) {
      Box(
        contentAlignment = Alignment.TopEnd
      ) {
        Text(
          ts,
          color = HighOrLowlight,
          style = MaterialTheme.typography.body2,
          modifier = Modifier.padding(bottom = 5.dp)
        )
        val n = chat.chatStats.unreadCount
        if (n > 0) {
          Box(
            Modifier.padding(top = 24.dp),
            contentAlignment = Alignment.Center
          ) {
            Text(
              if (n < 1000) "$n" else "${n / 1000}" + stringResource(R.string.thousand_abbreviation),
              color = MaterialTheme.colors.onPrimary,
              fontSize = 11.sp,
              modifier = Modifier
                .background(MaterialTheme.colors.primary, shape = CircleShape)
                .badgeLayout()
                .padding(horizontal = 3.dp)
                .padding(vertical = 1.dp)
            )
          }
        }
        if (cInfo is ChatInfo.Direct) {
          Box(
            Modifier.padding(top = 52.dp),
            contentAlignment = Alignment.Center
          ) {
            ChatStatusImage(chat)
          }
        }
      }
    }
  }
}

@Composable
fun ChatStatusImage(chat: Chat) {
  val s = chat.serverInfo.networkStatus
  val descr = s.statusString
  if (s is Chat.NetworkStatus.Error) {
    Icon(
      Icons.Outlined.ErrorOutline,
      contentDescription = descr,
      tint = HighOrLowlight,
      modifier = Modifier
        .size(19.dp)
    )
  } else if (s !is Chat.NetworkStatus.Connected) {
    CircularProgressIndicator(
      Modifier.padding(horizontal = 2.dp).size(15.dp),
      color = HighOrLowlight,
      strokeWidth = 1.5.dp
    )
  }
}

@Preview(showBackground = true)
@Preview(
  uiMode = Configuration.UI_MODE_NIGHT_YES,
  showBackground = true,
  name = "Dark Mode"
)
@Composable
fun PreviewChatPreviewView() {
  SimpleXTheme {
    ChatPreviewView(Chat.sampleData)
  }
}
