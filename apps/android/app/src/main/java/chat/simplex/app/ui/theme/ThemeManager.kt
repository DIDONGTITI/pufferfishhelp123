package chat.simplex.app.ui.theme

import androidx.compose.material.Colors
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.toArgb
import chat.simplex.app.R
import chat.simplex.app.SimplexApp
import chat.simplex.app.model.AppPreferences
import chat.simplex.app.views.helpers.generalGetString
import okhttp3.internal.toHexString

object ThemeManager {
  private val appPrefs: AppPreferences by lazy {
    SimplexApp.context.chatModel.controller.appPrefs
  }

  data class ActiveTheme(val name: String, val base: DefaultTheme, val colors: Colors, val appColors: AppColors)

  private fun systemDarkThemeColors(): Pair<Colors, DefaultTheme> = when (appPrefs.systemDarkTheme.get()) {
    DefaultTheme.DARK.name -> DarkColorPalette to DefaultTheme.DARK
    DefaultTheme.SIMPLEX.name -> SimplexColorPalette to DefaultTheme.SIMPLEX
    else -> SimplexColorPalette to DefaultTheme.SIMPLEX
  }

  fun currentColors(darkForSystemTheme: Boolean): ActiveTheme {
    val themeName = appPrefs.currentTheme.get()!!
    val themeOverrides = appPrefs.themeOverrides.get()

    val nonSystemThemeName = if (themeName != DefaultTheme.SYSTEM.name) {
      themeName
    } else {
      if (darkForSystemTheme) appPrefs.systemDarkTheme.get()!! else DefaultTheme.LIGHT.name
    }
    val theme = themeOverrides[nonSystemThemeName]
    val baseTheme = when (nonSystemThemeName) {
      DefaultTheme.LIGHT.name -> Triple(DefaultTheme.LIGHT, LightColorPalette, LightColorPaletteApp)
      DefaultTheme.DARK.name -> Triple(DefaultTheme.DARK, DarkColorPalette, DarkColorPaletteApp)
      DefaultTheme.SIMPLEX.name -> Triple(DefaultTheme.SIMPLEX, SimplexColorPalette, SimplexColorPaletteApp)
      else -> Triple(DefaultTheme.LIGHT, LightColorPalette, LightColorPaletteApp)
    }
    if (theme == null) {
      return ActiveTheme(themeName, baseTheme.first, baseTheme.second, baseTheme.third)
    }
    return ActiveTheme(themeName, baseTheme.first, theme.colors.toColors(theme.base), theme.colors.toAppColors(theme.base))
  }

  fun currentThemeData(darkForSystemTheme: Boolean): ThemeData {
    val t = currentColors(darkForSystemTheme)
    return ThemeData(colors = ThemeColors(
      primary = t.colors.primary.toReadableHex(),
      primaryVariant = t.colors.primaryVariant.toReadableHex(),
      secondary = t.colors.secondary.toReadableHex(),
      secondaryVariant = t.colors.secondaryVariant.toReadableHex(),
      background = t.colors.background.toReadableHex(),
      surface = t.colors.surface.toReadableHex(),
      title = t.appColors.title.toReadableHex(),
      sentMessage = t.appColors.sentMessage.toReadableHex(),
      receivedMessage = t.appColors.receivedMessage.toReadableHex()
    ))
  }

  // colors, default theme enum, localized name of theme
  fun allThemes(darkForSystemTheme: Boolean): List<Triple<Colors, DefaultTheme, String>> {
    val allThemes = ArrayList<Triple<Colors, DefaultTheme, String>>()
    allThemes.add(
      Triple(
        if (darkForSystemTheme) systemDarkThemeColors().first else LightColorPalette,
        DefaultTheme.SYSTEM,
        generalGetString(R.string.theme_system)
      )
    )
    allThemes.add(
      Triple(
        LightColorPalette,
        DefaultTheme.LIGHT,
        generalGetString(R.string.theme_light)
      )
    )
    allThemes.add(
      Triple(
        DarkColorPalette,
        DefaultTheme.DARK,
        generalGetString(R.string.theme_dark)
      )
    )
    allThemes.add(
      Triple(
        SimplexColorPalette,
        DefaultTheme.SIMPLEX,
        generalGetString(R.string.theme_simplex)
      )
    )
    return allThemes
  }

  fun applyTheme(theme: String, darkForSystemTheme: Boolean) {
    appPrefs.currentTheme.set(theme)
    CurrentColors.value = currentColors(darkForSystemTheme)
  }

  fun changeDarkTheme(theme: String, darkForSystemTheme: Boolean) {
    appPrefs.systemDarkTheme.set(theme)
    CurrentColors.value = currentColors(darkForSystemTheme)
  }

  fun saveAndApplyThemeColor(name: ThemeColor, color: Color? = null, darkForSystemTheme: Boolean) {
    val themeName = appPrefs.currentTheme.get()!!
    val nonSystemThemeName = if (themeName != DefaultTheme.SYSTEM.name) {
      themeName
    } else {
      if (darkForSystemTheme) appPrefs.systemDarkTheme.get()!! else DefaultTheme.LIGHT.name
    }
    var colorToSet = color
    if (colorToSet == null) {
      // Setting default color from a base theme
      colorToSet = when(nonSystemThemeName) {
        DefaultTheme.LIGHT.name -> name.fromColors(LightColorPalette, LightColorPaletteApp)
        DefaultTheme.DARK.name -> name.fromColors(DarkColorPalette, DarkColorPaletteApp)
        DefaultTheme.SIMPLEX.name -> name.fromColors(SimplexColorPalette, SimplexColorPaletteApp)
        // Will not be here
        else -> return
      }
    }
    val overrides = appPrefs.themeOverrides.get().toMutableMap()
    val prevValue = overrides[nonSystemThemeName] ?: ThemeOverrides(base = CurrentColors.value.base, colors = ThemeColors())
    overrides[nonSystemThemeName] = prevValue.withUpdatedColor(name, colorToSet.toReadableHex())
    appPrefs.themeOverrides.set(overrides)
    CurrentColors.value = currentColors(!CurrentColors.value.colors.isLight)
  }

  fun saveAndApplyThemeData(name: String, theme: ThemeData, darkForSystemTheme: Boolean) {
    val overrides = appPrefs.themeOverrides.get().toMutableMap()
    val prevValue = overrides[name] ?: ThemeOverrides(base = CurrentColors.value.base, colors = ThemeColors())
    overrides[name] = prevValue.copy(colors = theme.colors)
    appPrefs.themeOverrides.set(overrides)
    CurrentColors.value = currentColors(!CurrentColors.value.colors.isLight)
  }

  fun resetAllThemeColors(darkForSystemTheme: Boolean) {
    val themeName = appPrefs.currentTheme.get()!!
    val nonSystemThemeName = if (themeName != DefaultTheme.SYSTEM.name) {
      themeName
    } else {
      if (darkForSystemTheme) appPrefs.systemDarkTheme.get()!! else DefaultTheme.LIGHT.name
    }
    val overrides = appPrefs.themeOverrides.get().toMutableMap()
    val prevValue = overrides[nonSystemThemeName] ?: return
    overrides[nonSystemThemeName] = prevValue.copy(colors = ThemeColors())
    appPrefs.themeOverrides.set(overrides)
    CurrentColors.value = currentColors(!CurrentColors.value.colors.isLight)
  }
}

private fun Color.toReadableHex(): String = "#" + toArgb().toHexString()
