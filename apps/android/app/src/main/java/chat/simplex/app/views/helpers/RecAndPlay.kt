package chat.simplex.app.views.helpers

import android.media.*
import android.media.MediaRecorder.MEDIA_RECORDER_INFO_MAX_FILESIZE_REACHED
import android.os.Build
import android.util.Log
import androidx.compose.runtime.*
import chat.simplex.app.*
import chat.simplex.app.R
import chat.simplex.app.model.ChatItem
import kotlinx.coroutines.*
import java.io.*
import java.text.SimpleDateFormat
import java.util.*

interface Recorder {
  val recordingInProgress: MutableState<Boolean>
  fun start(onStop: () -> Unit): String
  fun stop()
  fun cancel(filePath: String, recordingInProgress: MutableState<Boolean>)
}

class RecorderNative(private val recordedBytesLimit: Long): Recorder {
  companion object {
    // Allows to stop the recorder from outside without having the recorder in a variable
    var stopRecording: (() -> Unit)? = null
  }
  override val recordingInProgress = mutableStateOf(false)
  private var recorder: MediaRecorder? = null
  private fun initRecorder() =
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
      MediaRecorder(SimplexApp.context)
    } else {
      MediaRecorder()
    }

  override fun start(onStop: () -> Unit): String {
    AudioPlayer.stop()
    recordingInProgress.value = true
    val rec: MediaRecorder
    recorder = initRecorder().also { rec = it }
    rec.setAudioSource(MediaRecorder.AudioSource.MIC)
    rec.setOutputFormat(MediaRecorder.OutputFormat.MPEG_4)
    rec.setAudioEncoder(MediaRecorder.AudioEncoder.AAC)
    rec.setAudioChannels(1)
    rec.setAudioSamplingRate(16000)
    rec.setAudioEncodingBitRate(16000)
    rec.setMaxDuration(-1)
    rec.setMaxFileSize(recordedBytesLimit)
    val timestamp = SimpleDateFormat("yyyyMMdd_HHmmss", Locale.US).format(Date())
    val filePath = getAppFilePath(SimplexApp.context, uniqueCombine(SimplexApp.context, getAppFilePath(SimplexApp.context, "voice_${timestamp}.m4a")))
    rec.setOutputFile(filePath)
    rec.prepare()
    rec.start()
    rec.setOnInfoListener { mr, what, extra ->
      if (what == MEDIA_RECORDER_INFO_MAX_FILESIZE_REACHED) {
        stop()
        onStop()
      }
    }
    stopRecording = { stop(); onStop() }
    return filePath
  }

  override fun stop() {
    if (!recordingInProgress.value) return
    stopRecording = null
    recordingInProgress.value = false
    recorder?.metrics?.
    runCatching {
      recorder?.stop()
    }
    runCatching {
      recorder?.reset()
    }
    runCatching {
      // release all resources
      recorder?.release()
    }
    recorder = null
  }

  override fun cancel(filePath: String, recordingInProgress: MutableState<Boolean>) {
    stop()
    runCatching { File(filePath).delete() }.getOrElse { Log.d(TAG, "Unable to delete a file: ${it.stackTraceToString()}") }
  }
}

object AudioPlayer {
  private val player = MediaPlayer().apply {
    setAudioAttributes(
      AudioAttributes.Builder()
        .setContentType(AudioAttributes.CONTENT_TYPE_MUSIC)
        .setUsage(AudioAttributes.USAGE_MEDIA)
        .build()
    )
  }
  private val helperPlayer: MediaPlayer =  MediaPlayer().apply {
        setAudioAttributes(
          AudioAttributes.Builder()
            .setContentType(AudioAttributes.CONTENT_TYPE_MUSIC)
            .setUsage(AudioAttributes.USAGE_MEDIA)
            .build()
        )
  }
  // Filepath: String, onProgressUpdate
  // onProgressUpdate(null) means stop
  private val currentlyPlaying: MutableState<Pair<String, (position: Int?) -> Unit>?> = mutableStateOf(null)
  private var progressJob: Job? = null

  // Returns real duration of the track
  private fun start(filePath: String, seek: Int? = null, onProgressUpdate: (position: Int?) -> Unit): Int? {
    if (!File(filePath).exists()) {
      Log.e(TAG, "No such file: $filePath")
      return null
    }

    RecorderNative.stopRecording?.invoke()
    val current = currentlyPlaying.value
    if (current == null || current.first != filePath) {
      stopListener()
      player.reset()
      runCatching {
        player.setDataSource(filePath)
      }.onFailure {
        Log.e(TAG, it.stackTraceToString())
        AlertManager.shared.showAlertMsg(generalGetString(R.string.unknown_error), it.message)
        return null
      }
      runCatching { player.prepare() }.onFailure {
        // Can happen when audio file is broken
        Log.e(TAG, it.stackTraceToString())
        AlertManager.shared.showAlertMsg(generalGetString(R.string.unknown_error), it.message)
        return null
      }
    }
    if (seek != null) player.seekTo(seek)
    player.start()
    currentlyPlaying.value = filePath to onProgressUpdate
    progressJob = CoroutineScope(Dispatchers.Default).launch {
      onProgressUpdate(player.currentPosition)
      while(isActive && player.isPlaying) {
        // Even when current position is equal to duration, the player has isPlaying == true for some time,
        // so help to make the playback stopped in UI immediately
        if (player.currentPosition == player.duration) {
          onProgressUpdate(player.currentPosition)
          break
        }
        delay(50)
        onProgressUpdate(player.currentPosition)
      }
      /*
      * Since coroutine is still NOT canceled, means player ended (no stop/no pause). But in some cases
      * the player can show position != duration even if they actually equal.
      * Let's say to a listener that the position == duration in case of coroutine finished without cancel
      * */
      if (isActive) {
        onProgressUpdate(player.duration)
      }
      onProgressUpdate(null)
    }
    return player.duration
  }

  private fun pause(): Int {
    progressJob?.cancel()
    progressJob = null
    player.pause()
    return player.currentPosition
  }

  fun stop() {
    if (!player.isPlaying) return
    player.stop()
    stopListener()
  }

  fun stop(item: ChatItem) = stop(item.file?.fileName)

  // FileName or filePath are ok
  fun stop(fileName: String?) {
    if (fileName != null && currentlyPlaying.value?.first?.endsWith(fileName) == true) {
      stop()
    }
  }

  private fun stopListener() {
    progressJob?.cancel()
    progressJob = null
    // Notify prev audio listener about stop
    currentlyPlaying.value?.second?.invoke(null)
    currentlyPlaying.value = null
  }

  fun play(
    filePath: String?,
    audioPlaying: MutableState<Boolean>,
    progress: MutableState<Int>,
    duration: MutableState<Int>,
    resetOnStop: Boolean = false
  ) {
    if (progress.value == duration.value) {
      progress.value = 0
    }
    val realDuration = start(filePath ?: return, progress.value) { pro ->
      if (pro != null) {
        progress.value = pro
      }
      if (pro == null || pro == duration.value) {
        audioPlaying.value = false
        if (resetOnStop) {
          progress.value = 0
        } else if (pro == duration.value) {
          progress.value = duration.value
        }
      }
    }
    audioPlaying.value = realDuration != null
    // Update to real duration instead of what was received in ChatInfo
    realDuration?.let { duration.value = it }
  }

  fun pause(audioPlaying: MutableState<Boolean>, pro: MutableState<Int>) {
    pro.value = pause()
    audioPlaying.value = false
  }

  fun duration(filePath: String): Int {
    var res = 0
    kotlin.runCatching {
      helperPlayer.setDataSource(filePath)
      helperPlayer.prepare()
      helperPlayer.start()
      helperPlayer.stop()
      res = helperPlayer.duration
      helperPlayer.reset()
    }
    return res
  }
}
