package chat.simplex.app.views.call

import android.app.*
import android.content.Context
import android.content.Intent
import android.content.res.Configuration
import android.graphics.Rect
import android.os.Build
import android.os.Bundle
import android.util.Rational
import android.view.View
import android.view.WindowManager
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.trackPipAnimationHintView
import androidx.compose.foundation.Image
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.scale
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.painter.Painter
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import chat.simplex.app.MainActivity
import chat.simplex.app.TAG
import chat.simplex.app.model.NtfManager
import chat.simplex.app.model.NtfManager.AcceptCallAction
import chat.simplex.common.model.CallOnLockScreen
import chat.simplex.common.model.ChatModel
import chat.simplex.common.platform.*
import chat.simplex.common.ui.theme.*
import chat.simplex.common.views.call.*
import chat.simplex.common.views.helpers.*
import chat.simplex.res.MR
import dev.icerock.moko.resources.compose.stringResource
import kotlinx.coroutines.launch
import java.lang.ref.WeakReference

class CallActivity: ComponentActivity() {
  var relaunchingActivity = false

  override fun onCreate(savedInstanceState: Bundle?) {
    super.onCreate(savedInstanceState)
    callActivity = WeakReference(this)
    when (intent?.action) {
      AcceptCallAction -> {
        val remoteHostId = intent.getLongExtra("remoteHostId", -1).takeIf { it != -1L }
        val chatId = intent.getStringExtra("chatId")
        val invitation = (chatModel.callInvitations.values + chatModel.activeCallInvitation.value).lastOrNull {
          it?.remoteHostId == remoteHostId && it?.contact?.id == chatId
        }
        if (invitation != null) {
          chatModel.callManager.acceptIncomingCall(invitation = invitation)
        }
      }
    }

    setContent { CallActivityView() }

    if (isOnLockScreenNow()) {
      unlockForIncomingCall()
    }
  }

  override fun onDestroy() {
    super.onDestroy()
    if (isOnLockScreenNow()) {
      lockAfterIncomingCall()
    }
  }

  private fun isOnLockScreenNow() = getKeyguardManager(this).isKeyguardLocked

  fun setPipParams(video: Boolean, sourceRectHint: Rect? = null) {
    // By manually specifying source rect we exclude empty background while toggling PiP
    val builder = PictureInPictureParams.Builder()
        .setAspectRatio(Rational(100, 133))
        .setSourceRectHint(sourceRectHint)
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
      builder.setAutoEnterEnabled(video)
    }
    setPictureInPictureParams(builder.build())
  }

  override fun onPictureInPictureModeChanged(isInPictureInPictureMode: Boolean, newConfig: Configuration) {
    super.onPictureInPictureModeChanged(isInPictureInPictureMode, newConfig)
    chatModel.activeCallViewIsCollapsed.value = isInPictureInPictureMode
    val layoutType = if (!isInPictureInPictureMode) {
      LayoutType.Default
    } else {
      LayoutType.RemoteVideo
    }
    chatModel.callCommand.add(WCallCommand.Layout(layoutType))
  }

  override fun onBackPressed() {
    if (isOnLockScreenNow()) {
      super.onBackPressed()
    } else {
      chatModel.activeCallViewIsCollapsed.value = true
    }
  }

  override fun onUserLeaveHint() {
    // On Android 12+ PiP is enabled automatically when a user hides the app
    if (Build.VERSION.SDK_INT <= Build.VERSION_CODES.R && callSupportsVideo()) {
      enterPictureInPictureMode()
    }
  }

  override fun onStop() {
    super.onStop()
    val call = chatModel.activeCall.value
    if (call != null && chatModel.activeCallViewIsCollapsed.value && !relaunchingActivity) {
      withBGApi {
        chatModel.callManager.endCall(call)
      }
    }
    relaunchingActivity = false
  }

  private fun unlockForIncomingCall() {
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
      setShowWhenLocked(true)
      setTurnScreenOn(true)
    } else {
      window.addFlags(activityFlags)
    }
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
      getKeyguardManager(this).requestDismissKeyguard(this, null)
    }
  }

  private fun lockAfterIncomingCall() {
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
      setShowWhenLocked(false)
      setTurnScreenOn(false)
    } else {
      window.clearFlags(activityFlags)
    }
  }

  companion object {
    const val activityFlags = WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON or WindowManager.LayoutParams.FLAG_ALLOW_LOCK_WHILE_SCREEN_ON
  }
}

fun getKeyguardManager(context: Context): KeyguardManager =
  context.getSystemService(Context.KEYGUARD_SERVICE) as KeyguardManager

private fun callSupportsVideo() = chatModel.activeCall.value?.supportsVideo() == true || chatModel.activeCallInvitation.value?.callType?.media == CallMediaType.Video

@Composable
fun CallActivityView() {
  val m = chatModel
  val switchingCall = m.switchingCall.value
  val invitation = m.activeCallInvitation.value
  val call = m.activeCall.value
  val showCallView = m.showCallView.value
  val activity = LocalContext.current as CallActivity
  LaunchedEffect(invitation, call, switchingCall, showCallView) {
    if (!switchingCall && invitation == null && (!showCallView || call == null)) {
      Log.d(TAG, "CallActivityView: finishing activity")
      activity.finish()
    }
  }
  LaunchedEffect(Unit) {
    snapshotFlow { chatModel.activeCallViewIsCollapsed.value }
      .collect { collapsed ->
        when {
          collapsed -> {
            if (chatModel.activeCall.value?.supportsVideo() == true) {
              activity.enterPictureInPictureMode()
            } else {
              activity.relaunchingActivity = true
              activity.moveTaskToBack(true)
//              activity.startActivity(Intent(activity, MainActivity::class.java))
            }
          }
          activity.isInPictureInPictureMode -> {
//            activity.moveTaskToBack(false)
            platform.androidStartCallActivity(false)
          }
        }
      }
  }
  SimpleXTheme {
    if (chatModel.activeCall.value != null) {
      val view = LocalView.current
      ActiveCallView()
      if (callSupportsVideo()) {
        val scope = rememberCoroutineScope()
        LaunchedEffect(Unit) {
          scope.launch {
            activity.setPipParams(callSupportsVideo())
            activity.trackPipAnimationHintView(view)
          }
        }
        //TrackViewSizeManually()
      }
    } else if (invitation != null) {
      Surface(
        Modifier
          .fillMaxSize(),
        color = MaterialTheme.colors.background,
        contentColor = LocalContentColor.current
      ) {
        IncomingCallLockScreenAlert(invitation, m)
      }
    }
  }
}

@Composable
private fun TrackViewSizeManually() {
  val activity = LocalContext.current as CallActivity
  val view = LocalView.current
  DisposableEffect(Unit) {
    val listener = View.OnLayoutChangeListener { _: View?, _: Int, _: Int, _: Int, _: Int, _: Int, _: Int, _: Int, _: Int ->
      val sourceRectHint = Rect()
      view.getGlobalVisibleRect(sourceRectHint)
      activity.setPipParams(callSupportsVideo(), sourceRectHint)
    }
    view.addOnLayoutChangeListener(listener)
    onDispose {
      view.removeOnLayoutChangeListener(listener)
    }
  }
}


/**
* Related to lockscreen
* */

@Composable
fun IncomingCallLockScreenAlert(invitation: RcvCallInvitation, chatModel: ChatModel) {
  val cm = chatModel.callManager
  val callOnLockScreen by remember { mutableStateOf(chatModel.controller.appPrefs.callOnLockScreen.get()) }
  val context = LocalContext.current
  DisposableEffect(Unit) {
    onDispose {
      // Cancel notification whatever happens next since otherwise sound from notification and from inside the app can co-exist
      ntfManager.cancelCallNotification()
    }
  }
  IncomingCallLockScreenAlertLayout(
    invitation,
    callOnLockScreen,
    chatModel,
    rejectCall = { cm.endCall(invitation = invitation) },
    ignoreCall = {
      chatModel.activeCallInvitation.value = null
      ntfManager.cancelCallNotification()
    },
    acceptCall = { cm.acceptIncomingCall(invitation = invitation) },
    openApp = {
      val intent = Intent(context, MainActivity::class.java)
        .setAction(NtfManager.OpenChatAction)
        .putExtra("userId", invitation.user.userId)
        .putExtra("chatId", invitation.contact.id)
      context.startActivity(intent)
      if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
        getKeyguardManager(context).requestDismissKeyguard((context as Activity), null)
      }
      (context as Activity).finish()
    }
  )
}

@Composable
fun IncomingCallLockScreenAlertLayout(
  invitation: RcvCallInvitation,
  callOnLockScreen: CallOnLockScreen?,
  chatModel: ChatModel,
  rejectCall: () -> Unit,
  ignoreCall: () -> Unit,
  acceptCall: () -> Unit,
  openApp: () -> Unit
) {
  Column(
    Modifier
      .padding(30.dp)
      .fillMaxSize(),
    horizontalAlignment = Alignment.CenterHorizontally
  ) {
    IncomingCallInfo(invitation, chatModel)
    Spacer(Modifier.fillMaxHeight().weight(1f))
    if (callOnLockScreen == CallOnLockScreen.ACCEPT) {
      ProfileImage(size = 192.dp, image = invitation.contact.profile.image)
      Text(invitation.contact.chatViewName, style = MaterialTheme.typography.h2)
      Spacer(Modifier.fillMaxHeight().weight(1f))
      Row {
        LockScreenCallButton(stringResource(MR.strings.reject), painterResource(chat.simplex.app.R.drawable.ic_call_end_filled), Color.Red, rejectCall)
        Spacer(Modifier.size(48.dp))
        LockScreenCallButton(stringResource(MR.strings.ignore), painterResource(chat.simplex.app.R.drawable.ic_close), MaterialTheme.colors.primary, ignoreCall)
        Spacer(Modifier.size(48.dp))
        LockScreenCallButton(stringResource(MR.strings.accept), painterResource(chat.simplex.app.R.drawable.ic_check_filled), SimplexGreen, acceptCall)
      }
    } else if (callOnLockScreen == CallOnLockScreen.SHOW) {
      SimpleXLogo()
      Text(stringResource(MR.strings.open_simplex_chat_to_accept_call), textAlign = TextAlign.Center, lineHeight = 22.sp)
      Text(stringResource(MR.strings.allow_accepting_calls_from_lock_screen), textAlign = TextAlign.Center, style = MaterialTheme.typography.body2, lineHeight = 22.sp)
      Spacer(Modifier.fillMaxHeight().weight(1f))
      SimpleButton(text = stringResource(MR.strings.open_verb), icon = painterResource(chat.simplex.app.R.drawable.ic_check_filled), click = openApp)
    }
  }
}

@Composable
private fun SimpleXLogo() {
  Image(
    painter = painterResource(if (isInDarkTheme()) chat.simplex.app.R.drawable.logo_light else chat.simplex.app.R.drawable.logo),
    contentDescription = stringResource(MR.strings.image_descr_simplex_logo),
    modifier = Modifier
      .padding(vertical = DEFAULT_PADDING)
      .fillMaxWidth(0.80f)
  )
}

@Composable
private fun LockScreenCallButton(text: String, icon: Painter, color: Color, action: () -> Unit) {
  Surface(
    shape = RoundedCornerShape(10.dp),
    color = Color.Transparent,
    contentColor = LocalContentColor.current
  ) {
    Column(
      Modifier
        .defaultMinSize(minWidth = 50.dp)
        .padding(4.dp),
      horizontalAlignment = Alignment.CenterHorizontally
    ) {
      IconButton(action) {
        Icon(icon, text, tint = color, modifier = Modifier.scale(1.75f))
      }
      Spacer(Modifier.height(DEFAULT_PADDING))
      Text(text, style = MaterialTheme.typography.body2, color = MaterialTheme.colors.secondary)
    }
  }
}
