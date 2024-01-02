package chat.simplex.common.views.localauth

import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import chat.simplex.common.model.*
import chat.simplex.common.model.ChatModel.controller
import dev.icerock.moko.resources.compose.stringResource
import chat.simplex.common.views.helpers.*
import chat.simplex.common.views.helpers.DatabaseUtils.ksSelfDestructPassword
import chat.simplex.common.views.helpers.DatabaseUtils.ksAppPassword
import chat.simplex.common.views.onboarding.OnboardingStage
import chat.simplex.common.platform.*
import chat.simplex.common.views.database.*
import chat.simplex.res.MR
import kotlinx.coroutines.delay

@Composable
fun LocalAuthView(m: ChatModel, authRequest: LocalAuthRequest) {
  val passcode = rememberSaveable { mutableStateOf("") }
  val allowToReact = rememberSaveable { mutableStateOf(true) }
  if (!allowToReact.value) {
    BackHandler {
      // do nothing until submit action finishes to prevent concurrent removing of storage
    }
  }
  PasscodeView(passcode, authRequest.title ?: stringResource(MR.strings.la_enter_app_passcode), authRequest.reason, stringResource(MR.strings.submit_passcode), buttonsEnabled = allowToReact,
    submit = {
      val sdPassword = ksSelfDestructPassword.get()
      if (sdPassword == passcode.value && authRequest.selfDestruct) {
        allowToReact.value = false
        deleteStorageAndRestart(m, sdPassword) { r ->
          authRequest.completed(r)
        }
      } else {
        val r: LAResult = if (passcode.value == authRequest.password) {
          if (authRequest.selfDestruct && sdPassword != null && controller.ctrl == -1L) {
            initChatControllerAndRunMigrations(true)
          }
          LAResult.Success
        } else {
          LAResult.Error(generalGetString(MR.strings.incorrect_passcode))
        }
        authRequest.completed(r)
      }
    },
    cancel = {
      authRequest.completed(LAResult.Error(generalGetString(MR.strings.authentication_cancelled)))
    })
}

private fun deleteStorageAndRestart(m: ChatModel, password: String, completed: (LAResult) -> Unit) {
  withBGApi {
    try {
      /** Waiting until [initChatController] finishes */
      while (m.ctrlInitInProgress.value) {
        delay(50)
      }
      if (m.chatRunning.value == true) {
        stopChatAsync(m)
      }
      val ctrl = m.controller.ctrl
      if (ctrl != null && ctrl != -1L) {
        /**
         * The following sequence can bring a user here:
         * the user opened the app, entered app passcode, went to background, returned back, entered self-destruct code.
         * In this case database should be closed to prevent possible situation when OS can deny database removal command
         * */
        chatCloseStore(ctrl)
      }
      deleteChatDatabaseFiles()
      // Clear sensitive data on screen just in case ModalManager will fail to prevent hiding its modals while database encrypts itself
      m.chatId.value = null
      m.chatItems.clear()
      m.chats.clear()
      m.users.clear()
      ksAppPassword.set(password)
      ksSelfDestructPassword.remove()
      ntfManager.cancelAllNotifications()
      val selfDestructPref = m.controller.appPrefs.selfDestruct
      val displayNamePref = m.controller.appPrefs.selfDestructDisplayName
      val displayName = displayNamePref.get()
      selfDestructPref.set(false)
      displayNamePref.set(null)
      m.chatDbChanged.value = true
      m.chatDbStatus.value = null
      try {
        initChatController(startChat = true)
      } catch (e: Exception) {
        Log.d(TAG, "initializeChat ${e.stackTraceToString()}")
      }
      m.chatDbChanged.value = false
      if (m.currentUser.value != null) {
        return@withBGApi
      }
      var profile: Profile? = null
      if (!displayName.isNullOrEmpty()) {
        profile = Profile(displayName = displayName, fullName = "")
      }
      val createdUser = m.controller.apiCreateActiveUser(null, profile, pastTimestamp = true)
      m.currentUser.value = createdUser
      m.controller.appPrefs.onboardingStage.set(OnboardingStage.OnboardingComplete)
      if (createdUser != null) {
        controller.chatModel.chatRunning.value = false
        m.controller.startChat(createdUser)
      }
      ModalManager.closeAllModalsEverywhere()
      AlertManager.shared.hideAllAlerts()
      AlertManager.privacySensitive.hideAllAlerts()
      completed(LAResult.Success)
    } catch (e: Exception) {
      Log.e(TAG, "Unable to delete storage: ${e.stackTraceToString()}")
      completed(LAResult.Error(generalGetString(MR.strings.incorrect_passcode)))
    }
  }
}
