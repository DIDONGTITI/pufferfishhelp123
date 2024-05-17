package chat.simplex.common.ui.theme

import androidx.compose.material.Colors
import androidx.compose.runtime.MutableState
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.toArgb
import androidx.compose.ui.text.font.FontFamily
import chat.simplex.common.model.*
import chat.simplex.common.platform.*
import chat.simplex.res.MR
import chat.simplex.common.views.helpers.*
import java.io.File

// https://github.com/rsms/inter
// I place it here because IDEA shows an error (but still works anyway) when this declaration inside Type.kt
expect val Inter: FontFamily
expect val EmojiFont: FontFamily

object ThemeManager {
  private val appPrefs: AppPreferences = ChatController.appPrefs

  data class ActiveTheme(val name: String, val base: DefaultTheme, val colors: Colors, val appColors: AppColors, val wallpaper: AppWallpaper = AppWallpaper())

  private fun systemDarkThemeColors(): Pair<Colors, DefaultTheme> = when (appPrefs.systemDarkTheme.get()) {
    DefaultTheme.DARK.themeName -> DarkColorPalette to DefaultTheme.DARK
    DefaultTheme.SIMPLEX.themeName -> SimplexColorPalette to DefaultTheme.SIMPLEX
    else -> SimplexColorPalette to DefaultTheme.SIMPLEX
  }

  private fun nonSystemThemeName(darkForSystemTheme: Boolean): String {
    val themeName = appPrefs.currentTheme.get()!!
    return if (themeName != DefaultTheme.SYSTEM.themeName) {
      themeName
    } else {
      if (darkForSystemTheme) appPrefs.systemDarkTheme.get()!! else DefaultTheme.LIGHT.themeName
    }
  }

  private fun defaultActiveTheme(darkForSystemTheme: Boolean, appSettingsTheme: List<ThemeOverrides>): ThemeOverrides? {
    val nonSystemThemeName = nonSystemThemeName(darkForSystemTheme)
    val defaultThemeId = appPrefs.currentThemeIds.get()[nonSystemThemeName]
    return appSettingsTheme.getTheme(defaultThemeId)
  }

  fun defaultActiveTheme(darkForSystemTheme: Boolean, perUserTheme: ThemeModeOverrides?, appSettingsTheme: List<ThemeOverrides>): ThemeModeOverride {
    val perUserTheme = if (darkForSystemTheme) perUserTheme?.dark else perUserTheme?.light
    if (perUserTheme != null) {
      return perUserTheme
    }
    val defaultTheme = defaultActiveTheme(darkForSystemTheme, appSettingsTheme)
    return ThemeModeOverride(colors = defaultTheme?.colors ?: ThemeColors(), wallpaper = defaultTheme?.wallpaper)
  }

  fun currentColors(darkForSystemTheme: Boolean, themeOverridesForType: Pair<BackgroundImageType?, Boolean>?, perChatTheme: ThemeModeOverride?, perUserTheme: ThemeModeOverrides?, appSettingsTheme: List<ThemeOverrides>): ActiveTheme {
    val themeName = appPrefs.currentTheme.get()!!
    val nonSystemThemeName = nonSystemThemeName(darkForSystemTheme)
    val defaultTheme = defaultActiveTheme(darkForSystemTheme, appSettingsTheme)
    val perUserTheme = if (darkForSystemTheme) perUserTheme?.dark else perUserTheme?.light

    val theme = (appSettingsTheme.sameTheme(themeOverridesForType?.first ?: perChatTheme?.type ?: perUserTheme?.type ?: defaultTheme?.wallpaper?.toAppWallpaper()?.type, nonSystemThemeName) ?: defaultTheme)

    val baseTheme = when (nonSystemThemeName) {
      DefaultTheme.LIGHT.themeName -> ActiveTheme(DefaultTheme.LIGHT.themeName, DefaultTheme.LIGHT, LightColorPalette, LightColorPaletteApp)
      DefaultTheme.DARK.themeName -> ActiveTheme(DefaultTheme.DARK.themeName, DefaultTheme.DARK, DarkColorPalette, DarkColorPaletteApp)
      DefaultTheme.SIMPLEX.themeName -> ActiveTheme(DefaultTheme.SIMPLEX.themeName, DefaultTheme.SIMPLEX, SimplexColorPalette, SimplexColorPaletteApp)
      else -> ActiveTheme(DefaultTheme.LIGHT.themeName, DefaultTheme.LIGHT, LightColorPalette, LightColorPaletteApp)
    }

    if (theme == null && perUserTheme == null && perChatTheme == null && themeOverridesForType == null) {
      return ActiveTheme(themeName, baseTheme.base, baseTheme.colors, baseTheme.appColors, baseTheme.wallpaper)
    }
    val presetWallpaperTheme = when {
      perChatTheme?.wallpaper != null -> if (perChatTheme.wallpaper.preset != null) PredefinedBackgroundImage.from(perChatTheme.wallpaper.preset)?.colors?.get(baseTheme.base) else null
      perUserTheme?.wallpaper != null -> if (perUserTheme.wallpaper.preset != null) PredefinedBackgroundImage.from(perUserTheme.wallpaper.preset)?.colors?.get(baseTheme.base) else null
      else -> if (theme?.wallpaper?.preset != null) PredefinedBackgroundImage.from(theme.wallpaper.preset)?.colors?.get(baseTheme.base) else null
    }
    val themeOrEmpty = theme ?: ThemeOverrides(base = baseTheme.base)
    val colors = themeOrEmpty.toColors(themeOrEmpty.base, perChatTheme?.colors, perUserTheme?.colors, presetWallpaperTheme)
    return ActiveTheme(
      themeName,
      baseTheme.base,
      colors,
      themeOrEmpty.toAppColors(themeOrEmpty.base, perChatTheme?.colors, perChatTheme?.type, perUserTheme?.colors, perUserTheme?.type, presetWallpaperTheme),
      themeOrEmpty.toAppWallpaper(themeOverridesForType?.first, perChatTheme, perUserTheme, colors.background)
    )
  }

  fun currentThemeOverridesForExport(darkForSystemTheme: Boolean, perChatTheme: ThemeModeOverride?, perUserTheme: ThemeModeOverrides?): ThemeOverrides {
    val current = currentColors(darkForSystemTheme, null, perChatTheme, perUserTheme, appPrefs.themeOverrides.get())
    val wType = current.wallpaper.type
    val wBackground = current.wallpaper.background
    val wTint = current.wallpaper.tint
    return ThemeOverrides(
      themeId = "",
      base = current.base,
      colors = ThemeColors.from(current.colors, current.appColors),
      wallpaper = if (wType !is BackgroundImageType.Empty) ThemeWallpaper.from(wType, wBackground?.toReadableHex(), wTint?.toReadableHex()).withFilledWallpaperBase64() else null
    )
  }

  // colors, default theme enum, localized name of theme
  fun allThemes(darkForSystemTheme: Boolean): List<Triple<Colors, DefaultTheme, String>> {
    val allThemes = ArrayList<Triple<Colors, DefaultTheme, String>>()
    allThemes.add(
      Triple(
        if (darkForSystemTheme) systemDarkThemeColors().first else LightColorPalette,
        DefaultTheme.SYSTEM,
        generalGetString(MR.strings.theme_system)
      )
    )
    allThemes.add(
      Triple(
        LightColorPalette,
        DefaultTheme.LIGHT,
        generalGetString(MR.strings.theme_light)
      )
    )
    allThemes.add(
      Triple(
        DarkColorPalette,
        DefaultTheme.DARK,
        generalGetString(MR.strings.theme_dark)
      )
    )
    allThemes.add(
      Triple(
        SimplexColorPalette,
        DefaultTheme.SIMPLEX,
        generalGetString(MR.strings.theme_simplex)
      )
    )
    return allThemes
  }

  fun applyTheme(theme: String, darkForSystemTheme: Boolean) {
    appPrefs.currentTheme.set(theme)
    CurrentColors.value = currentColors(darkForSystemTheme, null, null, chatModel.currentUser.value?.uiThemes, appPrefs.themeOverrides.get())
    platform.androidSetNightModeIfSupported()
  }

  fun changeDarkTheme(theme: String, darkForSystemTheme: Boolean) {
    appPrefs.systemDarkTheme.set(theme)
    CurrentColors.value = currentColors(darkForSystemTheme, null, null, chatModel.currentUser.value?.uiThemes, appPrefs.themeOverrides.get())
  }

  fun saveAndApplyThemeColor(baseTheme: DefaultTheme, name: ThemeColor, color: Color? = null, pref: SharedPreference<List<ThemeOverrides>> = appPrefs.themeOverrides) {
    val nonSystemThemeName = baseTheme.themeName
    var colorToSet = color
    if (colorToSet == null) {
      // Setting default color from a base theme
      colorToSet = when(nonSystemThemeName) {
        DefaultTheme.LIGHT.themeName -> name.fromColors(LightColorPalette, LightColorPaletteApp, AppWallpaper())
        DefaultTheme.DARK.themeName -> name.fromColors(DarkColorPalette, DarkColorPaletteApp, AppWallpaper())
        DefaultTheme.SIMPLEX.themeName -> name.fromColors(SimplexColorPalette, SimplexColorPaletteApp, AppWallpaper())
        // Will not be here
        else -> return
      }
    }
    val overrides = pref.get()
    val themeId = appPrefs.currentThemeIds.get()[nonSystemThemeName]
    val prevValue = overrides.getTheme(themeId) ?: ThemeOverrides(base = baseTheme)
    pref.set(overrides.replace(prevValue.withUpdatedColor(name, colorToSet?.toReadableHex())))
    val themeIds = appPrefs.currentThemeIds.get().toMutableMap()
    themeIds[nonSystemThemeName] = prevValue.themeId
    appPrefs.currentThemeIds.set(themeIds)
    CurrentColors.value = currentColors(!CurrentColors.value.colors.isLight, null, null, chatModel.currentUser.value?.uiThemes, appPrefs.themeOverrides.get())
  }

  fun applyThemeColor(name: ThemeColor, color: Color? = null, pref: MutableState<ThemeModeOverride>) {
    pref.value = pref.value.withUpdatedColor(name, color?.toReadableHex())
  }

  fun saveAndApplyBackgroundImage(baseTheme: DefaultTheme, type: BackgroundImageType?, pref: SharedPreference<List<ThemeOverrides>> = appPrefs.themeOverrides) {
    val nonSystemThemeName = baseTheme.themeName
    val overrides = pref.get()
    val theme = overrides.sameTheme(type, baseTheme.themeName)
    val prevValue = theme ?: ThemeOverrides(base = baseTheme)
    pref.set(overrides.replace(prevValue.copy(wallpaper = if (type != null && type !is BackgroundImageType.Empty) ThemeWallpaper.from(type, prevValue.wallpaper?.background, prevValue.wallpaper?.tint) else null)))
    val themeIds = appPrefs.currentThemeIds.get().toMutableMap()
    themeIds[nonSystemThemeName] = prevValue.themeId
    appPrefs.currentThemeIds.set(themeIds)
    CurrentColors.value = currentColors(!CurrentColors.value.colors.isLight, null, null, chatModel.currentUser.value?.uiThemes, appPrefs.themeOverrides.get())
  }

  fun copyFromSameThemeOverrides(type: BackgroundImageType?, pref: MutableState<ThemeModeOverride>): Boolean {
    val overrides = appPrefs.themeOverrides.get()
    val sameTheme = overrides.sameTheme(type, CurrentColors.value.base.themeName)
    if (sameTheme == null) {
      if (type != null) {
        pref.value = ThemeModeOverride(wallpaper = ThemeWallpaper.from(type, null, null).copy(scale = null, scaleType = null))
      } else {
        // Make an empty wallpaper to override any top level ones
        pref.value = ThemeModeOverride(wallpaper = ThemeWallpaper())
      }
      return true
    }
    var type = sameTheme.wallpaper?.toAppWallpaper()?.type
    if (type is BackgroundImageType.Static && sameTheme.wallpaper?.imageFile == type.filename) {
      // same image file. Needs to be copied first in order to be able to remove the file once it's not needed anymore without affecting main theme override
      val filename = saveBackgroundImage(File(getBackgroundImageFilePath(type.filename)).toURI())
      if (filename != null) {
        type = BackgroundImageType.Static(filename, type.scale, type.scaleType)
      } else {
        Log.e(TAG, "Error while copying wallpaper from global overrides to chat overrides")
        return false
      }
    }
    val prevValue = pref.value
    pref.value = prevValue.copy(
      colors = ThemeColors(),
      wallpaper = if (type != null)
        ThemeWallpaper.from(type, null, null).copy(scale = null, scaleType = null)
      // Make an empty wallpaper to override any top level ones
      else ThemeWallpaper()
    )
    return true
  }

  fun applyBackgroundImage(type: BackgroundImageType?, pref: MutableState<ThemeModeOverride>) {
    val prevValue = pref.value
    pref.value = prevValue.copy(
      wallpaper = if (type != null)
        ThemeWallpaper.from(type, prevValue.wallpaper?.background, prevValue.wallpaper?.tint)
      else null
    )
  }

  fun saveAndApplyThemeOverrides(theme: ThemeOverrides, pref: SharedPreference<List<ThemeOverrides>> = appPrefs.themeOverrides) {
    if (theme.base == DefaultTheme.SYSTEM) {
      AlertManager.shared.showAlertMsg(generalGetString(MR.strings.error), generalGetString(MR.strings.theme_has_unsupported_base))
      return
    }
    val wallpaper = theme.wallpaper?.importFromString()
    val nonSystemThemeName = theme.base.themeName
    val overrides = pref.get()
    val prevValue = overrides.getTheme(null, wallpaper?.toAppWallpaper()?.type, theme.base) ?: ThemeOverrides(base = theme.base)
    if (prevValue.wallpaper?.imageFile != null) {
      File(getBackgroundImageFilePath(prevValue.wallpaper.imageFile)).delete()
    }
    pref.set(overrides.replace(prevValue.copy(base = theme.base, colors = theme.colors, wallpaper = wallpaper)))
    appPrefs.currentTheme.set(nonSystemThemeName)
    val currentThemeIds = appPrefs.currentThemeIds.get().toMutableMap()
    currentThemeIds[nonSystemThemeName] = prevValue.themeId
    appPrefs.currentThemeIds.set(currentThemeIds)
    CurrentColors.value = currentColors(!CurrentColors.value.colors.isLight, null, null, chatModel.currentUser.value?.uiThemes, appPrefs.themeOverrides.get())
  }

  fun resetAllThemeColors(darkForSystemTheme: Boolean, pref: SharedPreference<List<ThemeOverrides>> = appPrefs.themeOverrides) {
    val nonSystemThemeName = nonSystemThemeName(darkForSystemTheme)
    val themeId = appPrefs.currentThemeIds.get()[nonSystemThemeName] ?: return
    val overrides = pref.get()
    val prevValue = overrides.getTheme(themeId) ?: return
    pref.set(overrides.replace(prevValue.copy(colors = ThemeColors(), wallpaper = prevValue.wallpaper?.copy(background = null, tint = null))))
    CurrentColors.value = currentColors(!CurrentColors.value.colors.isLight, null, null, chatModel.currentUser.value?.uiThemes, appPrefs.themeOverrides.get())
  }

  fun resetAllThemeColors(pref: MutableState<ThemeModeOverride>) {
    val prevValue = pref.value
    pref.value = prevValue.copy(colors = ThemeColors(), wallpaper = prevValue.wallpaper?.copy(background = null, tint = null))
  }

  fun String.colorFromReadableHex(): Color =
    Color(this.replace("#", "").toLongOrNull(16) ?: Color.White.toArgb().toLong())

  fun Color.toReadableHex(): String = "#" + if (this == Color.Transparent) "00ffffff" else Integer.toHexString(toArgb())
}
