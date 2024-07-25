package chat.simplex.common.platform

import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.BlurredEdgeTreatment
import androidx.compose.ui.draw.blur
import androidx.compose.ui.graphics.painter.Painter
import androidx.compose.ui.unit.dp
import chat.simplex.common.model.ChatController.appPrefs
import chat.simplex.common.views.helpers.KeyChangeEffect
import kotlinx.coroutines.flow.filter
import java.io.File

expect fun Modifier.navigationBarsWithImePadding(): Modifier

@Composable
expect fun ProvideWindowInsets(
  consumeWindowInsets: Boolean = true,
  windowInsetsAnimationsEnabled: Boolean = true,
  content: @Composable () -> Unit
)

@Composable
expect fun Modifier.desktopOnExternalDrag(
  enabled: Boolean = true,
  onFiles: (List<File>) -> Unit = {},
  onImage: (Painter) -> Unit = {},
  onText: (String) -> Unit = {}
): Modifier

expect fun Modifier.onRightClick(action: () -> Unit): Modifier

expect fun Modifier.desktopPointerHoverIconHand(): Modifier

expect fun Modifier.desktopOnHovered(action: (Boolean) -> Unit): Modifier

@Composable
fun Modifier.desktopModifyBlurredState(enabled: Boolean, blurred: MutableState<Boolean>): Modifier {
  return this
  val blurRadius = remember { appPrefs.privacyMediaBlurRadius.state }
  if (appPlatform.isDesktop) {
    KeyChangeEffect(blurRadius.value) {
      blurred.value = enabled && blurRadius.value > 0
    }
  }
  return if (appPlatform.isDesktop && enabled && blurRadius.value > 0) {
    this then Modifier.desktopOnHovered { blurred.value = !it }
  } else {
    this
  }
}

@Composable
fun Modifier.privacyBlur(
  enabled: Boolean,
  blurred: MutableState<Boolean> = remember { mutableStateOf(appPrefs.privacyMediaBlurRadius.get() > 0) },
  scrollState: State<Boolean>,
  onLongClick: () -> Unit = {}
): Modifier {
  return this
  val blurRadius = remember { appPrefs.privacyMediaBlurRadius.state }
  return if (enabled && blurred.value) {
    this then Modifier.blur(
      radiusX = remember { appPrefs.privacyMediaBlurRadius.state }.value.dp,
      radiusY = remember { appPrefs.privacyMediaBlurRadius.state }.value.dp,
      edgeTreatment = BlurredEdgeTreatment(RoundedCornerShape(0.dp))
    )
      .combinedClickable(
        onLongClick = onLongClick,
        onClick = {
          blurred.value = false
        }
      )
  } else if (enabled && blurRadius.value > 0 && appPlatform.isAndroid) {
      LaunchedEffect(Unit) {
        snapshotFlow { scrollState.value }
          .filter { it }
          .filter { !blurred.value }
          .collect { blurred.value = true }
      }
      this
    } else {
      this
    }
}
