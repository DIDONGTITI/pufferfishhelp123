package chat.simplex.app.views.newchat

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.*
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.*
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.dp
import chat.simplex.app.R
import chat.simplex.app.model.ChatModel
import chat.simplex.app.ui.theme.*
import chat.simplex.app.views.helpers.ModalManager

@Composable
fun NewChatSheet(chatModel: ChatModel, newChatDialogOpen: Boolean, closeNewChatDialog: () -> Unit) {
  if (newChatDialogOpen) BackHandler { closeNewChatDialog() }
  NewChatSheetLayout(
    addContact = {
      closeNewChatDialog()
      ModalManager.shared.showModal { CreateLinkView(chatModel, CreateLinkTab.ONE_TIME) }
    },
    connectViaLink = {
      closeNewChatDialog()
      ModalManager.shared.showModalCloseable { close -> ConnectViaLinkView(chatModel, close) }
    },
    createGroup = {
      closeNewChatDialog()
      ModalManager.shared.showCustomModal { close -> AddGroupView(chatModel, close) }
    }
  )
}

@Composable
fun NewChatSheetLayout(
  addContact: () -> Unit,
  connectViaLink: () -> Unit,
  createGroup: () -> Unit
) {
  val actions = remember { listOf(addContact, connectViaLink, createGroup) }
  val titles = remember { listOf(R.string.share_one_time_link, R.string.connect_via_link_or_qr, R.string.create_group) }
  val icons = remember { listOf(Icons.Outlined.AddLink, Icons.Outlined.QrCode, Icons.Outlined.Group) }
  LazyColumn {
    items(3) { index ->
      Row {
        Spacer(Modifier.weight(1f))
        Box(contentAlignment = Alignment.CenterEnd) {
          Button(
            actions[index],
            shape = RoundedCornerShape(21.dp),
            colors = ButtonDefaults.textButtonColors(
              backgroundColor = if (isInDarkTheme()) DarkGray else MaterialTheme.colors.background
            ),
            elevation = null,
            contentPadding = PaddingValues(horizontal = DEFAULT_PADDING_HALF, vertical = DEFAULT_PADDING_HALF),
            modifier = Modifier.height(42.dp)
          ) {
            Text(
              stringResource(titles[index]),
              Modifier.padding(start = DEFAULT_PADDING_HALF),
              color = if (isInDarkTheme()) MaterialTheme.colors.primary else MaterialTheme.colors.primary,
              fontWeight = FontWeight.Medium,
            )
            Icon(
              icons[index],
              stringResource(titles[index]),
              Modifier.size(42.dp),
              tint = if (isInDarkTheme()) MaterialTheme.colors.primary else MaterialTheme.colors.primary
            )
          }
        }
        Spacer(Modifier.width(DEFAULT_PADDING))
      }
      Spacer(Modifier.height(DEFAULT_PADDING))
    }
  }
}

@Composable
fun ActionButton(
  text: String?,
  comment: String?,
  icon: ImageVector,
  disabled: Boolean = false,
  click: () -> Unit = {}
) {
  Surface(shape = RoundedCornerShape(18.dp)) {
    Column(
      Modifier
        .clickable(onClick = click)
        .padding(8.dp),
      horizontalAlignment = Alignment.CenterHorizontally
    ) {
      val tint = if (disabled) HighOrLowlight else MaterialTheme.colors.primary
      Icon(icon, text,
        tint = tint,
        modifier = Modifier
          .size(40.dp)
          .padding(bottom = 8.dp))
      if (text != null) {
        Text(
          text,
          textAlign = TextAlign.Center,
          fontWeight = FontWeight.Bold,
          color = tint,
          modifier = Modifier.padding(bottom = 4.dp)
        )
      }
      if (comment != null) {
        Text(
          comment,
          textAlign = TextAlign.Center,
          style = MaterialTheme.typography.body2
        )
      }
    }
  }
}

@Preview
@Composable
fun PreviewNewChatSheet() {
  SimpleXTheme {
    NewChatSheetLayout(
      addContact = {},
      connectViaLink = {},
      createGroup = {}
    )
  }
}
