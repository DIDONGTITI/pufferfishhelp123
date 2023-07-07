package chat.simplex.app.views.chat.item

import android.Manifest
import android.os.Build
import androidx.compose.runtime.Composable
import androidx.compose.runtime.MutableState
import chat.simplex.app.model.ChatItem
import chat.simplex.app.model.MsgContent
import chat.simplex.app.platform.saveImage
import chat.simplex.res.MR
import com.google.accompanist.permissions.rememberPermissionState
import dev.icerock.moko.resources.compose.painterResource
import dev.icerock.moko.resources.compose.stringResource

@Composable
fun SaveContentItemAction(cItem: ChatItem, showMenu: MutableState<Boolean>) {
  val saveFileLauncher = rememberSaveFileLauncher(ciFile = cItem.file)
  val writePermissionState = rememberPermissionState(permission = Manifest.permission.WRITE_EXTERNAL_STORAGE)
  ItemAction(stringResource(MR.strings.save_verb), painterResource(MR.images.ic_download), onClick = {
    when (cItem.content.msgContent) {
      is MsgContent.MCImage -> {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R || writePermissionState.hasPermission) {
          saveImage(cItem.file)
        } else {
          writePermissionState.launchPermissionRequest()
        }
      }
      is MsgContent.MCFile, is MsgContent.MCVoice, is MsgContent.MCVideo -> saveFileLauncher.launch(cItem.file?.fileName)
      else -> {}
    }
    showMenu.value = false
  })
}
