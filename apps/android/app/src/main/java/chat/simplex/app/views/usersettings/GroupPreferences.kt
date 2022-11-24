package chat.simplex.app.views.usersettings

import SectionCustomFooter
import SectionItemView
import SectionItemWithValue
import SectionSpacer
import SectionTextFooter
import SectionView
import androidx.compose.foundation.*
import androidx.compose.foundation.layout.*
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import chat.simplex.app.R
import chat.simplex.app.model.*
import chat.simplex.app.ui.theme.*
import chat.simplex.app.views.helpers.*

@Composable
fun GroupPreferencesView(m: ChatModel, groupInfo: GroupInfo) {
  var preferences by remember { mutableStateOf(groupInfo.fullGroupPreferences) }
  var currentPreferences by remember { mutableStateOf(preferences) }
  GroupPreferencesLayout(
    preferences,
    currentPreferences,
    groupInfo,
    applyPrefs = { prefs ->
      preferences = prefs
    },
    reset = {
      preferences = currentPreferences
    },
    savePrefs = {
      withApi {
        val gp = groupInfo.groupProfile.copy(groupPreferences = preferences.toGroupPreferences())
        val gInfo = m.controller.apiUpdateGroup(groupInfo.groupId, gp)
        if (gInfo != null) {
          m.updateGroup(gInfo)
          currentPreferences = preferences
        }
      }
    },
  )
}

@Composable
private fun GroupPreferencesLayout(
  preferences: FullGroupPreferences,
  currentPreferences: FullGroupPreferences,
  groupInfo: GroupInfo,
  applyPrefs: (FullGroupPreferences) -> Unit,
  reset: () -> Unit,
  savePrefs: () -> Unit,
) {
  Column {
    Column(
      Modifier.weight(1f).fillMaxWidth().verticalScroll(rememberScrollState()),
      horizontalAlignment = Alignment.Start,
    ) {
      AppBarTitle(stringResource(R.string.group_preferences))
      val allowFullDeletion = remember(preferences) { mutableStateOf(preferences.fullDelete.enable) }
      FeatureSection(Feature.FullDelete, allowFullDeletion, groupInfo) {
        applyPrefs(preferences.copy(fullDelete = GroupPreference(enable = it)))
      }

      SectionSpacer()
      val allowVoice = remember(preferences) { mutableStateOf(preferences.voice.enable) }
      FeatureSection(Feature.Voice, allowVoice, groupInfo) {
        applyPrefs(preferences.copy(voice = GroupPreference(enable = it)))
      }
    }
    SectionCustomFooter(PaddingValues(DEFAULT_PADDING)) {
      ButtonsFooter(
        reset = reset,
        save = savePrefs,
        disabled = preferences == currentPreferences
      )
    }
  }
}

@Composable
private fun FeatureSection(feature: Feature, enableFeature: State<GroupFeatureEnabled>, groupInfo: GroupInfo, onSelected: (GroupFeatureEnabled) -> Unit) {
  SectionView {
    if (groupInfo.canEdit) {
      SectionItemView {
        ExposedDropDownSettingRow(
          feature.text(),
          GroupFeatureEnabled.values().map { it to it.text },
          enableFeature,
          icon = feature.icon(),
          onSelected = onSelected
        )
      }
    } else {
      SectionItemWithValue(
        feature.text(),
        remember { mutableStateOf(enableFeature.value) },
        listOf(ValueTitleDesc(enableFeature.value, enableFeature.value.text, "")),
        icon = null,
        enabled = remember { mutableStateOf(true) },
        onSelected = {}
      )
    }
  }
  SectionTextFooter(feature.enableGroupPrefDescription(enableFeature.value, groupInfo.canEdit))
}

@Composable
private fun ButtonsFooter(reset: () -> Unit, save: () -> Unit, disabled: Boolean) {
  Row(
    Modifier.fillMaxWidth(),
    horizontalArrangement = Arrangement.SpaceBetween,
    verticalAlignment = Alignment.CenterVertically
  ) {
    FooterButton(Icons.Outlined.Replay, stringResource(R.string.reset_verb), reset, disabled)
    FooterButton(Icons.Outlined.Check, stringResource(R.string.save_and_notify_group_members), save, disabled)
  }
}
