package chat.simplex.app

import android.app.Application
import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.util.Log
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.viewModels
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material.MaterialTheme
import androidx.compose.material.Surface
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.lifecycle.AndroidViewModel
import chat.simplex.app.model.*
import chat.simplex.app.ui.theme.SimpleXTheme
import chat.simplex.app.views.*
import chat.simplex.app.views.chat.ChatView
import chat.simplex.app.views.chatlist.ChatListView
import chat.simplex.app.views.chatlist.openChat
import chat.simplex.app.views.helpers.withApi
import chat.simplex.app.views.newchat.*
//import kotlinx.serialization.decodeFromString

class MainActivity: ComponentActivity() {
  private val vm by viewModels<SimplexViewModel>()

  override fun onCreate(savedInstanceState: Bundle?) {
    super.onCreate(savedInstanceState)
//    testJson()
    processIntent(intent, vm.chatModel)
//    vm.app.initiateBackgroundWork()
    setContent {
      SimpleXTheme {
        Surface(
          Modifier
            .background(MaterialTheme.colors.background)
            .fillMaxSize()
        ) {
          MainPage(vm.chatModel)
        }
      }
    }
  }
}

class SimplexViewModel(application: Application): AndroidViewModel(application) {
  val app = getApplication<SimplexApp>()
  val chatModel = app.chatModel
}

@Composable
fun MainPage(chatModel: ChatModel) {
  Box {
    when (chatModel.userCreated.value) {
      null -> SplashView()
      false -> WelcomeView(chatModel) // { nav.navigate(Pages.ChatList.route) }
      true -> if (chatModel.chatId.value == null) {
        ChatListView(chatModel)
      } else {
        ChatView(chatModel)
      }
    }
    ModalManager.shared.showInView()
    val am = chatModel.alertManager
    if (am.presentAlert.value) am.alertView.value?.invoke()
  }
}

fun processIntent(intent: Intent?, chatModel: ChatModel) {
  when (intent?.action) {
    NtfManager.OpenChatAction -> {
      val chatId = intent.getStringExtra("chatId")
      Log.d("SIMPLEX", "processIntent: OpenChatAction $chatId")
      if (chatId != null) {
        val cInfo = chatModel.getChat(chatId)?.chatInfo
        if (cInfo != null) withApi { openChat(chatModel, cInfo) }
      }
    }
    "android.intent.action.VIEW" -> {
      val uri = intent.data
      if (uri != null) connectIfOpenedViaUri(uri, chatModel)
    }
  }
}

fun connectIfOpenedViaUri(uri: Uri, chatModel: ChatModel) {
  Log.d("SIMPLEX", "connectIfOpenedViaUri: opened via link")
  if (chatModel.currentUser.value == null) {
    // TODO open from chat list view
    chatModel.appOpenUrl.value = uri
  } else {
    withUriAction(chatModel, uri) { action ->
      chatModel.alertManager.showAlertMsg(
        title = "Connect via $action link?",
        text = "Your profile will be sent to the contact that you received this link from.",
        confirmText = "Connect",
        onConfirm = {
          withApi {
            Log.d("SIMPLEX", "connectIfOpenedViaUri: connecting")
            connectViaUri(chatModel, action, uri)
          }
        }
      )
    }
  }
}

//fun testJson() {
//  val str = """
//    {}
//  """.trimIndent()
//
//  println(json.decodeFromString<ChatItem>(str))
//}
