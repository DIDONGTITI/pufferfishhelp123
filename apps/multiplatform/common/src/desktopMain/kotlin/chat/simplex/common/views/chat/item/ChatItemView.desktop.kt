package chat.simplex.common.views.chat.item

import androidx.compose.foundation.Image
import androidx.compose.foundation.layout.size
import androidx.compose.material.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.MutableState
import androidx.compose.ui.Modifier
import androidx.compose.foundation.layout.padding
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.unit.*
import chat.simplex.common.model.ChatItem
import chat.simplex.common.model.MsgContent
import chat.simplex.common.platform.FileChooserLauncher
import chat.simplex.common.platform.desktopPlatform
import chat.simplex.common.ui.theme.EmojiFont
import chat.simplex.common.views.helpers.*
import chat.simplex.res.MR
import dev.icerock.moko.resources.compose.painterResource
import dev.icerock.moko.resources.compose.stringResource

@Composable
actual fun ReactionIcon(text: String, fontSize: TextUnit) {
  if (desktopPlatform.isMac() && isHearEmoji(text)) {
    val sp = with(LocalDensity.current) { (fontSize.value + 8).sp.toDp() }
    Image(painterResource(MR.images.ic_heart), null, Modifier.size(sp).padding(top = 4.dp, bottom = 2.dp))
  } else {
    Text(text, fontSize = fontSize, fontFamily = EmojiFont)
  }
}

@Composable
actual fun SaveContentItemAction(cItem: ChatItem, saveFileLauncher: FileChooserLauncher, showMenu: MutableState<Boolean>) {
  ItemAction(stringResource(MR.strings.save_verb), painterResource(MR.images.ic_download), onClick = {
    when (cItem.content.msgContent) {
      is MsgContent.MCImage, is MsgContent.MCFile, is MsgContent.MCVoice, is MsgContent.MCVideo -> withApi { saveFileLauncher.launch(cItem.file?.fileName ?: "") }
      else -> {}
    }
    showMenu.value = false
  })
}
