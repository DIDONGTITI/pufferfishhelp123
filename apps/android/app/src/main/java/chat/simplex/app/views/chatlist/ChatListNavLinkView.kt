package chat.simplex.app.views.chatlist

import android.content.res.Configuration
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.layout.*
import androidx.compose.material.*
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.dp
import chat.simplex.app.R
import chat.simplex.app.model.*
import chat.simplex.app.ui.theme.SimpleXTheme
import chat.simplex.app.ui.theme.WarningOrange
import chat.simplex.app.views.chat.*
import chat.simplex.app.views.chat.group.deleteGroupDialog
import chat.simplex.app.views.chat.group.leaveGroupDialog
import chat.simplex.app.views.chat.item.ItemAction
import chat.simplex.app.views.helpers.*
import kotlinx.coroutines.delay
import kotlinx.datetime.Clock

@Composable
fun ChatListNavLinkView(chat: Chat, chatModel: ChatModel) {
  val showMenu = remember { mutableStateOf(false) }
  var showMarkRead by remember { mutableStateOf(false) }
  val stopped = chatModel.chatRunning.value == false
  LaunchedEffect(chat.id, chat.chatStats.unreadCount > 0) {
    showMenu.value = false
    delay(500L)
    showMarkRead = chat.chatStats.unreadCount > 0
  }
  when (chat.chatInfo) {
    is ChatInfo.Direct ->
      ChatListNavLinkLayout(
        chatLinkPreview = { ChatPreviewView(chat, stopped) },
        click = { directChatAction(chat.chatInfo, chatModel) },
        dropdownMenuItems = { ContactMenuItems(chat, chatModel, showMenu, showMarkRead) },
        showMenu,
        stopped
      )
    is ChatInfo.Group ->
      ChatListNavLinkLayout(
        chatLinkPreview = { ChatPreviewView(chat, stopped) },
        click = { groupChatAction(chat.chatInfo.groupInfo, chatModel) },
        dropdownMenuItems = { GroupMenuItems(chat, chat.chatInfo.groupInfo, chatModel, showMenu, showMarkRead) },
        showMenu,
        stopped
      )
    is ChatInfo.ContactRequest ->
      ChatListNavLinkLayout(
        chatLinkPreview = { ContactRequestView(chat.chatInfo) },
        click = { contactRequestAlertDialog(chat.chatInfo, chatModel) },
        dropdownMenuItems = { ContactRequestMenuItems(chat.chatInfo, chatModel, showMenu) },
        showMenu,
        stopped
      )
    is ChatInfo.ContactConnection ->
      ChatListNavLinkLayout(
        chatLinkPreview = { ContactConnectionView(chat.chatInfo.contactConnection) },
        click = { contactConnectionAlertDialog(chat.chatInfo.contactConnection, chatModel) },
        dropdownMenuItems = { ContactConnectionMenuItems(chat.chatInfo, chatModel, showMenu) },
        showMenu,
        stopped
      )
  }
}

fun directChatAction(chatInfo: ChatInfo, chatModel: ChatModel) {
  if (chatInfo.ready) {
    withApi { openChat(chatInfo, chatModel) }
  } else {
    pendingContactAlertDialog(chatInfo, chatModel)
  }
}

fun groupChatAction(groupInfo: GroupInfo, chatModel: ChatModel) {
  when (groupInfo.membership.memberStatus) {
    GroupMemberStatus.MemInvited -> acceptGroupInvitationAlertDialog(groupInfo, chatModel)
    GroupMemberStatus.MemAccepted -> groupInvitationAcceptedAlert()
    else -> withApi { openChat(ChatInfo.Group(groupInfo), chatModel) }
  }
}

suspend fun openChat(chatInfo: ChatInfo, chatModel: ChatModel) {
  val chat = chatModel.controller.apiGetChat(chatInfo.chatType, chatInfo.apiId)
  if (chat != null) {
    chatModel.chatItems.clear()
    chatModel.chatItems.addAll(chat.chatItems)
    chatModel.chatId.value = chatInfo.id
  }
}

@Composable
fun ContactMenuItems(chat: Chat, chatModel: ChatModel, showMenu: MutableState<Boolean>, showMarkRead: Boolean) {
  if (showMarkRead) {
    MarkReadChatAction(chat, chatModel, showMenu)
  }
  ClearChatAction(chat, chatModel, showMenu)
  DeleteContactAction(chat, chatModel, showMenu)
}

@Composable
fun GroupMenuItems(chat: Chat, groupInfo: GroupInfo, chatModel: ChatModel, showMenu: MutableState<Boolean>, showMarkRead: Boolean) {
  when (groupInfo.membership.memberStatus) {
    GroupMemberStatus.MemInvited -> {
      JoinGroupAction(groupInfo, chatModel, showMenu)
      if (groupInfo.canDelete) {
        DeleteGroupAction(chat, chatModel, showMenu)
      }
    }
    else -> {
      if (showMarkRead) {
        MarkReadChatAction(chat, chatModel, showMenu)
      }
      ClearChatAction(chat, chatModel, showMenu)
      if (groupInfo.membership.memberStatus != GroupMemberStatus.MemLeft) {
        LeaveGroupAction(groupInfo, chatModel, showMenu)
      }
      if (groupInfo.canDelete) {
        DeleteGroupAction(chat, chatModel, showMenu)
      }
    }
  }
}

@Composable
fun MarkReadChatAction(chat: Chat, chatModel: ChatModel, showMenu: MutableState<Boolean>) {
  ItemAction(
    stringResource(R.string.mark_read),
    Icons.Outlined.Check,
    onClick = {
      markChatRead(chat, chatModel)
      chatModel.controller.ntfManager.cancelNotificationsForChat(chat.id)
      showMenu.value = false
    }
  )
}

@Composable
fun ClearChatAction(chat: Chat, chatModel: ChatModel, showMenu: MutableState<Boolean>) {
  ItemAction(
    stringResource(R.string.clear_verb),
    Icons.Outlined.Restore,
    onClick = {
      clearChatDialog(chat.chatInfo, chatModel)
      showMenu.value = false
    },
    color = WarningOrange
  )
}

@Composable
fun DeleteContactAction(chat: Chat, chatModel: ChatModel, showMenu: MutableState<Boolean>) {
  ItemAction(
    stringResource(R.string.delete_verb),
    Icons.Outlined.Delete,
    onClick = {
      deleteContactDialog(chat.chatInfo, chatModel)
      showMenu.value = false
    },
    color = Color.Red
  )
}

@Composable
fun DeleteGroupAction(chat: Chat, chatModel: ChatModel, showMenu: MutableState<Boolean>) {
  ItemAction(
    stringResource(R.string.delete_verb),
    Icons.Outlined.Delete,
    onClick = {
      deleteGroupDialog(chat.chatInfo, chatModel)
      showMenu.value = false
    },
    color = Color.Red
  )
}

@Composable
fun JoinGroupAction(groupInfo: GroupInfo, chatModel: ChatModel, showMenu: MutableState<Boolean>) {
  ItemAction(
    stringResource(R.string.join_group_button),
    Icons.Outlined.Login,
    onClick = {
      withApi { chatModel.controller.joinGroup(groupInfo.groupId) }
      showMenu.value = false
    }
  )
}

@Composable
fun LeaveGroupAction(groupInfo: GroupInfo, chatModel: ChatModel, showMenu: MutableState<Boolean>) {
  ItemAction(
    stringResource(R.string.leave_group_button),
    Icons.Outlined.Logout,
    onClick = {
      leaveGroupDialog(groupInfo, chatModel)
      showMenu.value = false
    },
    color = Color.Red
  )
}

@Composable
fun ContactRequestMenuItems(chatInfo: ChatInfo.ContactRequest, chatModel: ChatModel, showMenu: MutableState<Boolean>) {
  ItemAction(
    stringResource(R.string.accept_contact_button),
    Icons.Outlined.Check,
    onClick = {
      acceptContactRequest(chatInfo, chatModel)
      showMenu.value = false
    }
  )
  ItemAction(
    stringResource(R.string.reject_contact_button),
    Icons.Outlined.Close,
    onClick = {
      rejectContactRequest(chatInfo, chatModel)
      showMenu.value = false
    },
    color = Color.Red
  )
}

@Composable
fun ContactConnectionMenuItems(chatInfo: ChatInfo.ContactConnection, chatModel: ChatModel, showMenu: MutableState<Boolean>) {
  ItemAction(
    stringResource(R.string.delete_verb),
    Icons.Outlined.Delete,
    onClick = {
      deleteContactConnectionAlert(chatInfo.contactConnection, chatModel)
      showMenu.value = false
    },
    color = Color.Red
  )
}

fun markChatRead(chat: Chat, chatModel: ChatModel) {
  chatModel.markChatItemsRead(chat.chatInfo)
  withApi {
    chatModel.controller.apiChatRead(
      chat.chatInfo.chatType,
      chat.chatInfo.apiId,
      CC.ItemRange(chat.chatStats.minUnreadItemId, chat.chatItems.last().id)
    )
  }
}

fun contactRequestAlertDialog(contactRequest: ChatInfo.ContactRequest, chatModel: ChatModel) {
  AlertManager.shared.showAlertDialog(
    title = generalGetString(R.string.accept_connection_request__question),
    text = generalGetString(R.string.if_you_choose_to_reject_the_sender_will_not_be_notified),
    confirmText = generalGetString(R.string.accept_contact_button),
    onConfirm = { acceptContactRequest(contactRequest, chatModel) },
    dismissText = generalGetString(R.string.reject_contact_button),
    onDismiss = { rejectContactRequest(contactRequest, chatModel) }
  )
}

fun acceptContactRequest(contactRequest: ChatInfo.ContactRequest, chatModel: ChatModel) {
  withApi {
    val contact = chatModel.controller.apiAcceptContactRequest(contactRequest.apiId)
    if (contact != null) {
      val chat = Chat(ChatInfo.Direct(contact), listOf())
      chatModel.replaceChat(contactRequest.id, chat)
    }
  }
}

fun rejectContactRequest(contactRequest: ChatInfo.ContactRequest, chatModel: ChatModel) {
  withApi {
    chatModel.controller.apiRejectContactRequest(contactRequest.apiId)
    chatModel.removeChat(contactRequest.id)
  }
}

fun contactConnectionAlertDialog(connection: PendingContactConnection, chatModel: ChatModel) {
  AlertManager.shared.showAlertDialogButtons(
    title = generalGetString(
      if (connection.initiated) R.string.you_invited_your_contact
      else R.string.you_accepted_connection
    ),
    text = generalGetString(
      if (connection.viaContactUri) R.string.you_will_be_connected_when_your_connection_request_is_accepted
      else R.string.you_will_be_connected_when_your_contacts_device_is_online
    ),
    buttons = {
      Row(
        Modifier
          .fillMaxWidth()
          .padding(horizontal = 8.dp, vertical = 2.dp),
        horizontalArrangement = Arrangement.End,
      ) {
        Button(onClick = {
          AlertManager.shared.hideAlert()
          deleteContactConnectionAlert(connection, chatModel)
        }) {
          Text(stringResource(R.string.delete_verb))
        }
        Spacer(Modifier.padding(horizontal = 4.dp))
        Button(onClick = { AlertManager.shared.hideAlert() }) {
          Text(stringResource(R.string.ok))
        }
      }
    }
  )
}

fun deleteContactConnectionAlert(connection: PendingContactConnection, chatModel: ChatModel) {
  AlertManager.shared.showAlertDialog(
    title = generalGetString(R.string.delete_pending_connection__question),
    text = generalGetString(
      if (connection.initiated) R.string.contact_you_shared_link_with_wont_be_able_to_connect
      else R.string.connection_you_accepted_will_be_cancelled
    ),
    confirmText = generalGetString(R.string.delete_verb),
    onConfirm = {
      withApi {
        AlertManager.shared.hideAlert()
        if (chatModel.controller.apiDeleteChat(ChatType.ContactConnection, connection.apiId)) {
          chatModel.removeChat(connection.id)
        }
      }
    }
  )
}

fun pendingContactAlertDialog(chatInfo: ChatInfo, chatModel: ChatModel) {
  AlertManager.shared.showAlertDialog(
    title = generalGetString(R.string.alert_title_contact_connection_pending),
    text = generalGetString(R.string.alert_text_connection_pending_they_need_to_be_online_can_delete_and_retry),
    confirmText = generalGetString(R.string.button_delete_contact),
    onConfirm = {
      withApi {
        val r = chatModel.controller.apiDeleteChat(chatInfo.chatType, chatInfo.apiId)
        if (r) {
          chatModel.removeChat(chatInfo.id)
          chatModel.chatId.value = null
        }
      }
    },
    dismissText = generalGetString(R.string.cancel_verb),
  )
}

fun acceptGroupInvitationAlertDialog(groupInfo: GroupInfo, chatModel: ChatModel) {
  AlertManager.shared.showAlertDialog(
    title = generalGetString(R.string.join_group_question),
    text = generalGetString(R.string.you_are_invited_to_group_join_to_connect_with_group_members),
    confirmText = generalGetString(R.string.join_group_button),
    onConfirm = { withApi { chatModel.controller.joinGroup(groupInfo.groupId) } },
    dismissText = generalGetString(R.string.delete_verb),
    onDismiss = { deleteGroup(groupInfo, chatModel) }
  )
}

fun deleteGroup(groupInfo: GroupInfo, chatModel: ChatModel) {
  withApi {
    val r = chatModel.controller.apiDeleteChat(ChatType.Group, groupInfo.apiId)
    if (r) {
      chatModel.removeChat(groupInfo.id)
      chatModel.chatId.value = null
      chatModel.controller.ntfManager.cancelNotificationsForChat(groupInfo.id)
    }
  }
}

fun groupInvitationAcceptedAlert() {
  AlertManager.shared.showAlertMsg(
    generalGetString(R.string.joining_group),
    generalGetString(R.string.youve_accepted_group_invitation_connecting_to_inviting_group_member)
  )
}

@Composable
fun ChatListNavLinkLayout(
  chatLinkPreview: @Composable () -> Unit,
  click: () -> Unit,
  dropdownMenuItems: (@Composable () -> Unit)?,
  showMenu: MutableState<Boolean>,
  stopped: Boolean
) {
  var modifier = Modifier.fillMaxWidth().height(88.dp)
  if (!stopped) modifier = modifier.combinedClickable(onClick = click, onLongClick = { showMenu.value = true })
  Surface(modifier) {
    Row(
      modifier = Modifier
        .fillMaxWidth()
        .padding(vertical = 8.dp)
        .padding(start = 8.dp)
        .padding(end = 12.dp),
      verticalAlignment = Alignment.Top
    ) {
      chatLinkPreview()
    }
    if (dropdownMenuItems != null) {
      Box(Modifier.padding(horizontal = 16.dp)) {
        DropdownMenu(
          expanded = showMenu.value,
          onDismissRequest = { showMenu.value = false },
          Modifier.width(220.dp)
        ) {
          dropdownMenuItems()
        }
      }
    }
  }
  Divider(Modifier.padding(horizontal = 8.dp))
}

@Preview
@Preview(
  uiMode = Configuration.UI_MODE_NIGHT_YES,
  showBackground = true,
  name = "Dark Mode"
)
@Composable
fun PreviewChatListNavLinkDirect() {
  SimpleXTheme {
    ChatListNavLinkLayout(
      chatLinkPreview = {
        ChatPreviewView(
          chat = Chat(
            chatInfo = ChatInfo.Direct.sampleData,
            chatItems = listOf(
              ChatItem.getSampleData(
                1,
                CIDirection.DirectSnd(),
                Clock.System.now(),
                "Lorem ipsum dolor sit amet, consectetur adipiscing elit, sed do eiusmod tempor incididunt ut labore et dolore magna aliqua. Ut enim ad minim veniam, quis nostrud exercitation ullamco laboris nisi ut aliquip ex ea commodo consequat."
              )
            ),
            chatStats = Chat.ChatStats()
          ),
          stopped = false
        )
      },
      click = {},
      dropdownMenuItems = null,
      showMenu = remember { mutableStateOf(false) },
      stopped = false
    )
  }
}

@Preview
@Preview(
  uiMode = Configuration.UI_MODE_NIGHT_YES,
  showBackground = true,
  name = "Dark Mode"
)
@Composable
fun PreviewChatListNavLinkGroup() {
  SimpleXTheme {
    ChatListNavLinkLayout(
      chatLinkPreview = {
        ChatPreviewView(
          Chat(
            chatInfo = ChatInfo.Group.sampleData,
            chatItems = listOf(
              ChatItem.getSampleData(
                1,
                CIDirection.DirectSnd(),
                Clock.System.now(),
                "Lorem ipsum dolor sit amet, consectetur adipiscing elit, sed do eiusmod tempor incididunt ut labore et dolore magna aliqua. Ut enim ad minim veniam, quis nostrud exercitation ullamco laboris nisi ut aliquip ex ea commodo consequat."
              )
            ),
            chatStats = Chat.ChatStats()
          ),
          stopped = false
        )
      },
      click = {},
      dropdownMenuItems = null,
      showMenu = remember { mutableStateOf(false) },
      stopped = false
    )
  }
}

@Preview
@Preview(
  uiMode = Configuration.UI_MODE_NIGHT_YES,
  showBackground = true,
  name = "Dark Mode"
)
@Composable
fun PreviewChatListNavLinkContactRequest() {
  SimpleXTheme {
    ChatListNavLinkLayout(
      chatLinkPreview = {
        ContactRequestView(ChatInfo.ContactRequest.sampleData)
      },
      click = {},
      dropdownMenuItems = null,
      showMenu = remember { mutableStateOf(false) },
      stopped = false
    )
  }
}
