package chat.simplex.app.views.usersettings

import androidx.compose.foundation.*
import androidx.compose.foundation.layout.*
import androidx.compose.material.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import chat.simplex.app.R
import chat.simplex.app.views.helpers.generalGetString

@Composable
fun IncognitoView() {
  IncognitoLayout()
}

@Composable
fun IncognitoLayout() {
  Column(
    Modifier.fillMaxWidth(),
    horizontalAlignment = Alignment.Start,
  ) {
    Text(
      stringResource(R.string.settings_section_title_incognito),
      Modifier.padding(start = 16.dp, bottom = 24.dp),
      style = MaterialTheme.typography.h1
    )

    Column(
      Modifier
        .verticalScroll(rememberScrollState())
        .padding(horizontal = 8.dp)
    ) {
      Column(verticalArrangement = Arrangement.spacedBy(20.dp)) {
        Text(generalGetString(R.string.incognito_info_protects))
        Text(generalGetString(R.string.incognito_info_allows))
        Text(generalGetString(R.string.incognito_info_find))
      }

      Spacer(Modifier.padding(top = 20.dp))

      Text(generalGetString(R.string.incognito_info_groups), style = MaterialTheme.typography.h2)

      Spacer(Modifier.padding(top = 15.dp))

      Text(generalGetString(R.string.incognito_info_member))

      Spacer(Modifier.padding(top = 15.dp))
      Text(generalGetString(R.string.incognito_info_when))
      Spacer(Modifier.padding(top = 10.dp))

      TextListItem("•", generalGetString(R.string.incognito_info_created))
      TextListItem("•", generalGetString(R.string.incognito_info_invited))
      TextListItem("•", generalGetString(R.string.incognito_info_connection))

      Spacer(Modifier.padding(top = 15.dp))

      Text(generalGetString(R.string.incognito_info_risks))
      Spacer(Modifier.padding(top = 10.dp))

      TextListItem("•", generalGetString(R.string.incognito_info_not_allowed))
      TextListItem("•", generalGetString(R.string.incognito_info_shared))
    }
  }
}

@Composable
fun TextListItem(n: String, text: String) {
  Row(horizontalArrangement = Arrangement.spacedBy(20.dp)) {
    Text(n)
    Text(text)
  }
}
