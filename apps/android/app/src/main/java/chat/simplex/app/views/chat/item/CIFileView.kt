import android.widget.Toast
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.material.*
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.InsertDriveFile
import androidx.compose.material.icons.outlined.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.tooling.preview.*
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import chat.simplex.app.R
import chat.simplex.app.model.*
import chat.simplex.app.ui.theme.*
import chat.simplex.app.views.chat.item.FramedItemView
import chat.simplex.app.views.helpers.*
import kotlinx.datetime.Clock
import kotlin.math.log2
import kotlin.math.pow

@Composable
fun CIFileView(
  file: CIFile?,
  edited: Boolean,
  receiveFile: (Long) -> Unit
) {
  val context = LocalContext.current
  val saveFileLauncher = rememberLauncherForActivityResult(
    contract = ActivityResultContracts.CreateDocument(),
    onResult = { destination ->
      saveFile(context, file, destination)
    }
  )

  @Composable
  fun fileIcon(innerIcon: ImageVector? = null, color: Color = HighOrLowlight) {
    Box(
      contentAlignment = Alignment.Center
    ) {
      Icon(
        Icons.Filled.InsertDriveFile,
        stringResource(R.string.icon_descr_file),
        Modifier.fillMaxSize(),
        tint = color
      )
      if (innerIcon != null) {
        Icon(
          innerIcon,
          stringResource(R.string.icon_descr_file),
          Modifier
            .size(32.dp)
            .padding(top = 12.dp),
          tint = Color.White
        )
      }
    }
  }

  fun fileSizeValid(): Boolean {
    if (file != null) {
      return file.fileSize <= MAX_FILE_SIZE
    }
    return false
  }

  fun fileAction() {
    if (file != null) {
      when (file.fileStatus) {
        CIFileStatus.RcvInvitation -> {
          if (fileSizeValid()) {
            receiveFile(file.fileId)
          } else {
            AlertManager.shared.showAlertMsg(
              generalGetString(R.string.large_file),
              String.format(generalGetString(R.string.contact_sent_large_file), MAX_FILE_SIZE)
            )
          }
        }
        CIFileStatus.RcvAccepted ->
          AlertManager.shared.showAlertMsg(
            generalGetString(R.string.waiting_for_file),
            String.format(generalGetString(R.string.file_will_be_received_when_contact_is_online), MAX_FILE_SIZE)
          )
        CIFileStatus.RcvComplete -> {
          val filePath = getStoredFilePath(context, file)
          if (filePath != null) {
            saveFileLauncher.launch(file.fileName)
          } else {
            Toast.makeText(context, generalGetString(R.string.file_not_found), Toast.LENGTH_SHORT).show()
          }
        }
        else -> {}
      }
    }
  }

  @Composable
  fun fileIndicator() {
    Box(
      Modifier.size(44.dp),
      contentAlignment = Alignment.Center
    ) {
      if (file != null) {
        when (file.fileStatus) {
          CIFileStatus.SndCancelled -> fileIcon(innerIcon = Icons.Outlined.Close)
          CIFileStatus.RcvInvitation ->
            if (fileSizeValid())
              fileIcon(innerIcon = Icons.Outlined.ArrowDownward, color = MaterialTheme.colors.primary)
            else
              fileIcon(innerIcon = Icons.Outlined.PriorityHigh, color = WarningOrange)
          CIFileStatus.RcvAccepted -> fileIcon(innerIcon = Icons.Outlined.MoreHoriz)
          CIFileStatus.RcvTransfer ->
            CircularProgressIndicator(
              Modifier.size(36.dp),
              color = HighOrLowlight,
              strokeWidth = 4.dp
            )
          CIFileStatus.RcvCancelled -> fileIcon(innerIcon = Icons.Outlined.Close)
          else -> fileIcon()
        }
      } else {
        fileIcon()
      }
    }
  }

  fun formatBytes(bytes: Long): String {
    if (bytes == 0.toLong()) {
      return "0 bytes"
    }
    val bytesDouble = bytes.toDouble()
    val k = 1000.toDouble()
    val units = arrayOf("bytes", "KB", "MB", "GB", "TB", "PB", "EB", "ZB", "YB")
    val i = kotlin.math.floor(log2(bytesDouble) / log2(k))
    val size = bytesDouble / k.pow(i)
    val unit = units[i.toInt()]

    return if (i <= 1) {
      String.format("%.0f %s", size, unit)
    } else {
      String.format("%.2f %s", size, unit)
    }
  }

  Row(
    Modifier
      .padding(top = 4.dp, bottom = 6.dp, start = 10.dp, end = 12.dp)
      .clickable(onClick = { fileAction() }),
    verticalAlignment = Alignment.Bottom,
    horizontalArrangement = Arrangement.spacedBy(4.dp)
  ) {
    fileIndicator()
    val metaReserve = if (edited)
      "                     "
    else
      "                 "
    if (file != null) {
      Column(
        horizontalAlignment = Alignment.Start
      ) {
        Text(
          file.fileName,
          maxLines = 1
        )
        Text(
          formatBytes(file.fileSize) + metaReserve,
          color = HighOrLowlight,
          fontSize = 14.sp,
          maxLines = 1
        )
      }
    } else {
      Text(metaReserve)
    }
  }
}

class ChatItemProvider: PreviewParameterProvider<ChatItem> {
  private val sentFile = ChatItem(
    chatDir = CIDirection.DirectSnd(),
    meta = CIMeta.getSample(1, Clock.System.now(), "", CIStatus.SndSent(), itemDeleted = false, itemEdited = true, editable = false),
    content = CIContent.SndMsgContent(msgContent = MsgContent.MCFile("")),
    quotedItem = null,
    file = CIFile.getSample(fileStatus = CIFileStatus.SndStored)
  )
  private val fileChatItemWtFile = ChatItem(
    chatDir = CIDirection.DirectRcv(),
    meta = CIMeta.getSample(1, Clock.System.now(), "", CIStatus.RcvRead(), itemDeleted = false, itemEdited = false, editable = false),
    content = CIContent.RcvMsgContent(msgContent = MsgContent.MCFile("")),
    quotedItem = null,
    file = null
  )
  override val values = listOf(
    sentFile,
    ChatItem.getFileMsgContentSample(),
    ChatItem.getFileMsgContentSample(fileName = "some_long_file_name_here", fileStatus = CIFileStatus.RcvInvitation),
    ChatItem.getFileMsgContentSample(fileStatus = CIFileStatus.RcvAccepted),
    ChatItem.getFileMsgContentSample(fileStatus = CIFileStatus.RcvTransfer),
    ChatItem.getFileMsgContentSample(fileStatus = CIFileStatus.RcvCancelled),
    ChatItem.getFileMsgContentSample(fileSize = 2000000, fileStatus = CIFileStatus.RcvInvitation),
    ChatItem.getFileMsgContentSample(text = "Hello there", fileStatus = CIFileStatus.RcvInvitation),
    ChatItem.getFileMsgContentSample(text = "Lorem ipsum dolor sit amet, consectetur adipiscing elit, sed do eiusmod tempor incididunt ut labore et dolore magna aliqua. Ut enim ad minim veniam, quis nostrud exercitation ullamco laboris nisi ut aliquip ex ea commodo consequat. Duis aute irure dolor in reprehenderit in voluptate velit esse cillum dolore eu fugiat nulla pariatur. Excepteur sint occaecat cupidatat non proident, sunt in culpa qui officia deserunt mollit anim id est laborum.", fileStatus = CIFileStatus.RcvInvitation),
    fileChatItemWtFile
  ).asSequence()
}

@Preview
@Composable
fun PreviewTextItemViewSnd(@PreviewParameter(ChatItemProvider::class) chatItem: ChatItem) {
  val showMenu = remember { mutableStateOf(false) }
  SimpleXTheme {
    FramedItemView(User.sampleData, chatItem, showMenu = showMenu, receiveFile = {})
  }
}
