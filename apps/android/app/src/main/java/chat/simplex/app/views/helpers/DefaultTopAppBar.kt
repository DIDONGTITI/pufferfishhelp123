package chat.simplex.app.views.helpers

import chat.simplex.app.R
import androidx.compose.foundation.*
import androidx.compose.foundation.layout.*
import androidx.compose.material.*
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.ArrowBackIos
import androidx.compose.material.icons.outlined.Menu
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.*
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import chat.simplex.app.ui.theme.ToolbarDark
import chat.simplex.app.ui.theme.ToolbarLight

@Composable
fun DefaultTopAppBar(
  navigationButton: @Composable RowScope.() -> Unit,
  title: @Composable () -> Unit,
  onTitleClick: (() -> Unit)? = null,
  showSearch: Boolean,
  onSearchValueChanged: (String) -> Unit,
  buttons: List<@Composable RowScope.() -> Unit> = emptyList(),
) {
  // If I just disable clickable modifier when don't need it, it will stop passing clicks to search. Replacing the whole modifier
  val modifier = if (!showSearch) {
    Modifier.clickable(enabled = onTitleClick != null, onClick = onTitleClick ?: { })
  } else Modifier

  TopAppBar(
    modifier = modifier,
    title = {
      if (!showSearch) {
        title()
      } else {
        SearchTextField(Modifier.fillMaxWidth(), stringResource(android.R.string.search_go), onSearchValueChanged)
      }
    },
    backgroundColor = if (isSystemInDarkTheme()) ToolbarDark else ToolbarLight,
    navigationIcon = navigationButton,
    buttons = if (!showSearch) buttons else emptyList(),
    centered = !showSearch
  )
}

@Composable
fun NavigationButtonBack(onButtonClicked: () -> Unit) {
  IconButton(onButtonClicked) {
    Icon(
      Icons.Outlined.ArrowBackIos, stringResource(R.string.back), tint = MaterialTheme.colors.primary
    )
  }
}

@Composable
fun NavigationButtonMenu(onButtonClicked: () -> Unit) {
  IconButton(onClick = onButtonClicked) {
    Icon(
      Icons.Outlined.Menu,
      stringResource(R.string.icon_descr_settings),
      tint = MaterialTheme.colors.primary,
    )
  }
}

@Composable
private fun TopAppBar(
  title: @Composable () -> Unit,
  modifier: Modifier = Modifier,
  navigationIcon: @Composable (RowScope.() -> Unit)? = null,
  buttons: List<@Composable RowScope.() -> Unit> = emptyList(),
  backgroundColor: Color = MaterialTheme.colors.primarySurface,
  centered: Boolean,
) {
  Box(
    modifier
      .fillMaxWidth()
      .height(AppBarHeight)
      .background(backgroundColor)
      .padding(horizontal = 4.dp),
    contentAlignment = Alignment.CenterStart,
  ) {
    if (navigationIcon != null) {
      Row(
        Modifier
          .fillMaxHeight()
          .width(TitleInsetWithIcon - AppBarHorizontalPadding),
        verticalAlignment = Alignment.CenterVertically,
        content = navigationIcon
      )
    }

    Row(
      Modifier
        .fillMaxHeight()
        .fillMaxWidth(),
      horizontalArrangement = Arrangement.End,
      verticalAlignment = Alignment.CenterVertically,
    ) {
      buttons.forEach { it() }
    }
    val startPadding = if (navigationIcon != null) TitleInsetWithIcon else TitleInsetWithoutIcon
    val endPadding = (buttons.size * 50f).dp
    Box(
      Modifier
        .fillMaxWidth()
        .padding(
          start = if (centered) kotlin.math.max(startPadding.value, endPadding.value).dp else startPadding,
          end = if (centered) kotlin.math.max(startPadding.value, endPadding.value).dp else endPadding
        ),
      contentAlignment = Alignment.Center
    ) {
      title()
    }
  }
}

val AppBarHeight = 56.dp
private val AppBarHorizontalPadding = 4.dp
private val TitleInsetWithoutIcon = 16.dp - AppBarHorizontalPadding
private val TitleInsetWithIcon = 72.dp
