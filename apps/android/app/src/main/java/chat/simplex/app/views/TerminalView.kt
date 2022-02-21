package chat.simplex.app.views

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.ClickableText
import androidx.compose.foundation.text.selection.SelectionContainer
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.Button
import androidx.compose.material.Text
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.AnnotatedString
import androidx.navigation.NavController
import chat.simplex.app.model.*
import chat.simplex.app.views.chat.SendMsgView
import chat.simplex.app.views.helpers.withApi
import kotlinx.coroutines.DelicateCoroutinesApi

@DelicateCoroutinesApi
@Composable
fun TerminalView(chatModel: ChatModel, navController: NavController) {
  Column {
    Button(onClick = { navController.popBackStack() }) {
      Text("Back")
    }
    TerminalLog(chatModel.terminalItems, navController)
    SendMsgView(sendMessage = { cmd ->
      withApi {
        // show "in progress"
        chatModel.controller.sendCmd(CC.Console(cmd))
        // hide "in progress"
      }
    })
  }
}

@Composable
fun TerminalLog(terminalItems: List<TerminalItem>, navController: NavController) {
  LazyColumn {
    items(terminalItems) { item ->
      ClickableText(
        AnnotatedString(item.label),
        onClick = { navController.navigate("details/${item.id}") }
      )
    }
  }
}

@Composable
fun DetailView(identifier: Long, terminalItems: List<TerminalItem>, navController: NavController){
  Column(
    modifier = Modifier.verticalScroll(rememberScrollState())
  ) {
    Button(onClick = { navController.popBackStack() }) {
      Text("Back")
    }
    SelectionContainer {
      Text((terminalItems.firstOrNull { it.id == identifier })?.details ?: "")
    }
  }
}
