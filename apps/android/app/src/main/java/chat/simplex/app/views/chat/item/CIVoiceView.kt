package chat.simplex.app.views.chat.item

import androidx.compose.foundation.clickable
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.CornerSize
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.*
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawWithCache
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.*
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.*
import chat.simplex.app.model.*
import chat.simplex.app.ui.theme.*
import chat.simplex.app.views.helpers.*

@Composable
fun CIVoiceView(
  providedDurationSec: Int,
  file: CIFile?,
  edited: Boolean,
  sent: Boolean,
  hasText: Boolean,
  ci: ChatItem,
  metaColor: Color,
  longClick: () -> Unit,
) {
  Row(
    Modifier.padding(top = 4.dp, bottom = 6.dp, start = 6.dp, end = 6.dp),
    verticalAlignment = Alignment.CenterVertically
  ) {
    if (file != null) {
      val context = LocalContext.current
      val filePath = remember(file.filePath, file.fileStatus) { getLoadedFilePath(context, file) }
      var brokenAudio by rememberSaveable(file.filePath) { mutableStateOf(false) }
      val audioPlaying = rememberSaveable(file.filePath) { mutableStateOf(false) }
      val progress = rememberSaveable(file.filePath) { mutableStateOf(0) }
      val duration = rememberSaveable(file.filePath) { mutableStateOf(providedDurationSec * 1000) }
      val play = {
        AudioPlayer.play(filePath, audioPlaying, progress, duration, true)
        brokenAudio = !audioPlaying.value
      }
      val pause = {
        AudioPlayer.pause(audioPlaying, progress)
      }

      val time = if (audioPlaying.value) progress.value else duration.value
      val minWidth = with(LocalDensity.current) { 45.sp.toDp() }
      val text = durationToString(time / 1000)
      if (hasText) {
        VoiceMsgIndicator(file, audioPlaying.value, sent, hasText, progress, duration, brokenAudio, play, pause, longClick)
        Text(
          text,
          Modifier
            .padding(start = 12.dp, end = 5.dp)
            .widthIn(min = minWidth),
          color = HighOrLowlight,
          fontSize = 16.sp,
          textAlign = TextAlign.Start,
          maxLines = 1
        )
      } else {
        if (sent) {
          Row {
            Row(verticalAlignment = Alignment.CenterVertically) {
              Spacer(Modifier.height(56.dp))
              Text(
                text,
                Modifier
                  .padding(end = 12.dp)
                  .widthIn(min = minWidth),
                color = HighOrLowlight,
                fontSize = 16.sp,
                maxLines = 1
              )
            }
            Column {
              VoiceMsgIndicator(file, audioPlaying.value, sent, hasText, progress, duration, brokenAudio, play, pause, longClick)
              Box(Modifier.align(Alignment.CenterHorizontally).padding(top = 6.dp)) {
                CIMetaView(ci, metaColor)
              }
            }
          }
        } else {
          Row {
            Column {
              VoiceMsgIndicator(file, audioPlaying.value, sent, hasText, progress, duration, brokenAudio, play, pause, longClick)
              Box(Modifier.align(Alignment.CenterHorizontally).padding(top = 6.dp)) {
                CIMetaView(ci, metaColor)
              }
            }
            Row(verticalAlignment = Alignment.CenterVertically) {
              Text(
                text,
                Modifier
                  .padding(start = 12.dp)
                  .widthIn(min = minWidth),
                color = HighOrLowlight,
                fontSize = 16.sp,
                maxLines = 1
              )
              Spacer(Modifier.height(56.dp))
            }
          }
        }
      }
    } else {
      VoiceMsgIndicator(null, false, sent, hasText, null, null, false, {}, {}, longClick)
      val metaReserve = if (edited)
        "                     "
      else
        "                 "
      Text(metaReserve)
    }
  }
}

@Composable
private fun PlayPauseButton(
  audioPlaying: Boolean,
  sent: Boolean,
  angle: Float,
  strokeWidth: Float,
  strokeColor: Color,
  enabled: Boolean,
  error: Boolean,
  play: () -> Unit,
  pause: () -> Unit,
  longClick: () -> Unit
) {
  Surface(
    Modifier.drawRingModifier(angle, strokeColor, strokeWidth),
    color = if (sent) SentColorLight else ReceivedColorLight,
    shape = MaterialTheme.shapes.small.copy(CornerSize(percent = 50))
  ) {
    Box(
      Modifier
        .defaultMinSize(minWidth = 56.dp, minHeight = 56.dp)
        .combinedClickable(
          onClick = { if (!audioPlaying) play() else pause() },
          onLongClick = longClick
        ),
      contentAlignment = Alignment.Center
    ) {
      Icon(
        imageVector = if (audioPlaying) Icons.Filled.Pause else Icons.Filled.PlayArrow,
        contentDescription = null,
        Modifier.size(36.dp),
        tint = if (error) WarningOrange else if (!enabled) HighOrLowlight else MaterialTheme.colors.primary
      )
    }
  }
}

@Composable
private fun VoiceMsgIndicator(
  file: CIFile?,
  audioPlaying: Boolean,
  sent: Boolean,
  hasText: Boolean,
  progress: State<Int>?,
  duration: State<Int>?,
  error: Boolean,
  play: () -> Unit,
  pause: () -> Unit,
  longClick: () -> Unit
) {
  val strokeWidth = with(LocalDensity.current){ 3.dp.toPx() }
  val strokeColor = MaterialTheme.colors.primary
  if (file != null && file.loaded && progress != null && duration != null) {
    val angle = 360f * (progress.value.toDouble() / duration.value).toFloat()
    if (hasText) {
      IconButton({ if (!audioPlaying) play() else pause() }, Modifier.drawRingModifier(angle, strokeColor, strokeWidth)) {
        Icon(
          imageVector = if (audioPlaying) Icons.Filled.Pause else Icons.Filled.PlayArrow,
          contentDescription = null,
          Modifier.size(36.dp),
          tint = MaterialTheme.colors.primary
        )
      }
    } else {
      PlayPauseButton(audioPlaying, sent, angle, strokeWidth, strokeColor, true, error, play, pause, longClick = longClick)
    }
  } else {
    if (file?.fileStatus == CIFileStatus.RcvInvitation
      || file?.fileStatus == CIFileStatus.RcvTransfer
      || file?.fileStatus == CIFileStatus.RcvAccepted) {
      Box(
        Modifier
          .size(56.dp)
          .clip(RoundedCornerShape(4.dp)),
        contentAlignment = Alignment.Center
      ) {
        ProgressIndicator()
      }
    } else {
      PlayPauseButton(audioPlaying, sent, 0f, strokeWidth, strokeColor, false, false, {}, {}, longClick)
    }
  }
}

private fun Modifier.drawRingModifier(angle: Float, color: Color, strokeWidth: Float) = drawWithCache {
  val brush = Brush.linearGradient(
    0f to Color.Transparent,
    0f to color,
    start = Offset(0f, 0f),
    end = Offset(strokeWidth, strokeWidth),
    tileMode = TileMode.Clamp
  )
  onDrawWithContent {
    drawContent()
    drawArc(
      brush = brush,
      startAngle = -90f,
      sweepAngle = angle,
      useCenter = false,
      topLeft = Offset(strokeWidth / 2, strokeWidth / 2),
      size = Size(size.width - strokeWidth, size.height - strokeWidth),
      style = Stroke(width = strokeWidth, cap = StrokeCap.Square)
    )
  }
}

@Composable
private fun ProgressIndicator() {
  CircularProgressIndicator(
    Modifier.size(32.dp),
    color = if (isInDarkTheme()) FileDark else FileLight,
    strokeWidth = 4.dp
  )
}
