package chat.simplex.app.views.newchat

import SectionItemView
import android.content.res.Configuration
import androidx.compose.foundation.layout.*
import androidx.compose.material.*
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Circle
import androidx.compose.material.icons.filled.TheaterComedy
import androidx.compose.material.icons.outlined.Info
import androidx.compose.material.icons.outlined.Share
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import chat.simplex.app.R
import chat.simplex.app.model.ChatModel
import chat.simplex.app.ui.theme.*
import chat.simplex.app.views.helpers.generalGetString
import chat.simplex.app.views.helpers.shareText

@Composable
fun AddContactView(chatModel: ChatModel) {
  val connReq = chatModel.connReqInvitation
  if (connReq != null) {
    val cxt = LocalContext.current
    AddContactLayout(
      chatModelIncognito = chatModel.incognito.value,
      connReq = connReq,
      share = { shareText(cxt, connReq) }
    )
  }
}

@Composable
fun AddContactLayout(chatModelIncognito: Boolean, connReq: String, share: () -> Unit) {
  BoxWithConstraints {
    val screenHeight = maxHeight
    Column(
      horizontalAlignment = Alignment.CenterHorizontally,
      verticalArrangement = Arrangement.SpaceBetween,
    ) {
      Text(
        stringResource(R.string.add_contact),
        style = MaterialTheme.typography.h1.copy(fontWeight = FontWeight.Normal),
      )
      Text(
        stringResource(R.string.show_QR_code_for_your_contact_to_scan_from_the_app__multiline),
        style = MaterialTheme.typography.h3,
        textAlign = TextAlign.Center,
      )
      InfoAboutIncognito(
        chatModelIncognito,
        true,
        generalGetString(R.string.incognito_random_profile_description),
        generalGetString(R.string.your_profile_will_be_sent)
      )
      QRCode(
        connReq, Modifier
          .weight(1f, fill = false)
          .aspectRatio(1f)
          .padding(vertical = 3.dp)
      )
      Text(
        stringResource(R.string.if_you_cannot_meet_in_person_show_QR_in_video_call_or_via_another_channel),
        textAlign = TextAlign.Center,
        lineHeight = 22.sp,
        modifier = Modifier
          .padding(horizontal = 16.dp)
          .padding(bottom = if (screenHeight > 600.dp) 16.dp else 8.dp)
      )
      SimpleButton(stringResource(R.string.share_invitation_link), icon = Icons.Outlined.Share, click = share)
      Spacer(Modifier.height(10.dp))
    }
  }
}

@Composable
fun ColumnScope.InfoAboutIncognito(chatModelIncognito: Boolean, supportedIncognito: Boolean = true, onText: String, offText: String) {
  Spacer(Modifier.padding(top = 10.dp))
  if (chatModelIncognito) {
    SectionItemView {
      Icon(
        if (supportedIncognito) Icons.Filled.TheaterComedy else Icons.Filled.Circle,
        stringResource(R.string.incognito),
        tint = if (supportedIncognito) Indigo else Orange,
        modifier = Modifier.padding(10.dp).size(26.dp)
      )
      Text(onText, textAlign = TextAlign.Center)
    }
  } else {
    SectionItemView {
      Icon(
        Icons.Outlined.Info,
        stringResource(R.string.incognito),
        tint = MaterialTheme.colors.primary,
        modifier = Modifier.padding(10.dp).size(26.dp)
      )
      Text(offText, textAlign = TextAlign.Center)
    }
  }
  Spacer(Modifier.padding(top = 10.dp))
}

@Preview
@Preview(
  uiMode = Configuration.UI_MODE_NIGHT_YES,
  showBackground = true,
  name = "Dark Mode"
)
@Composable
fun PreviewAddContactView() {
  SimpleXTheme {
    AddContactLayout(
      chatModelIncognito = false,
      connReq = "https://simplex.chat/contact#/?v=1&smp=smp%3A%2F%2FPQUV2eL0t7OStZOoAsPEV2QYWt4-xilbakvGUGOItUo%3D%40smp6.simplex.im%2FK1rslx-m5bpXVIdMZg9NLUZ_8JBm8xTt%23MCowBQYDK2VuAyEALDeVe-sG8mRY22LsXlPgiwTNs9dbiLrNuA7f3ZMAJ2w%3D",
      share = {}
    )
  }
}
