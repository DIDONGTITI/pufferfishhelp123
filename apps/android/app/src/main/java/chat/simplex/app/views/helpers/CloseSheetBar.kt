package chat.simplex.app.views.helpers

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.material.Icon
import androidx.compose.material.MaterialTheme
import androidx.compose.material.Surface
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Close
import androidx.compose.material.icons.outlined.Settings
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.dp
import chat.simplex.app.ui.theme.SimpleXTheme
import chat.simplex.app.views.newchat.AddContactLayout

@Composable
fun CloseSheetBar(close: () -> Unit) {
  Row (Modifier
      .fillMaxWidth(),
    horizontalArrangement = Arrangement.End
  ) {
    Icon(
      Icons.Outlined.Close,
      "Close button",
      tint = MaterialTheme.colors.primary,
      modifier = Modifier
        .padding(horizontal = 10.dp)
        .clickable { close() }
    )
  }
}

@Preview
@Composable
fun PreviewCloseSheetBar() {
  SimpleXTheme {
    CloseSheetBar(close = {})
  }
}
