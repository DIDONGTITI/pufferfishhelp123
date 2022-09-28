package chat.simplex.app.views.usersettings

import SectionViewSelectable
import androidx.compose.foundation.*
import androidx.compose.foundation.layout.*
import androidx.compose.material.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.capitalize
import androidx.compose.ui.text.intl.Locale
import androidx.compose.ui.unit.dp
import chat.simplex.app.R
import chat.simplex.app.ui.theme.*
import chat.simplex.app.views.helpers.ValueTitleDesc

@Composable
fun ThemeSelectorView() {
  val darkTheme = isSystemInDarkTheme()
  val allThemes by remember { mutableStateOf(ThemeManager.allThemes(darkTheme).map { ValueTitleDesc(it.second, it.third, "") }) }

  ThemeSelectorLayout(
    allThemes,
    onSelectTheme = {
      ThemeManager.applyTheme(it.name, darkTheme)
    },
  )
}

@Composable
private fun ThemeSelectorLayout(
  allThemes: List<ValueTitleDesc<DefaultTheme>>,
  onSelectTheme: (DefaultTheme) -> Unit,
) {
  Column(
    Modifier.fillMaxWidth(),
    horizontalAlignment = Alignment.Start,
  ) {
    Text(
      stringResource(R.string.settings_section_title_themes).lowercase().capitalize(Locale.current),
      Modifier.padding(start = 16.dp, bottom = 24.dp),
      style = MaterialTheme.typography.h1
    )
    val currentTheme by CurrentColors.collectAsState()
    val state = remember { derivedStateOf { currentTheme.second } }
    SectionViewSelectable(null, state, allThemes, onSelectTheme)
  }
}

