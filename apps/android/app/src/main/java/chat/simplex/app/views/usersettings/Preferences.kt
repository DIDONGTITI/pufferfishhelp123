package chat.simplex.app.views.usersettings

import SectionCustomFooter
import SectionItemView
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
import androidx.compose.ui.unit.dp
import chat.simplex.app.R
import chat.simplex.app.model.*
import chat.simplex.app.ui.theme.*
import chat.simplex.app.views.helpers.*

@Composable
fun PreferencesView(m: ChatModel, user: User) {
  var currentPrefs by remember { mutableStateOf(user.profile.preferences ?: ChatPreferences.default) }
  var savedPrefs by remember { mutableStateOf(currentPrefs) }
  PreferencesLayout(
    currentPrefs,
    savedPrefs,
    applyPrefs = { prefs ->
      currentPrefs = prefs
    },
    revert = {
      currentPrefs = savedPrefs
    },
    savePrefs = {
      showConfirmSavingAlert {
        withApi {
          val updatedProfile = user.profile.toProfile().copy(preferences = currentPrefs)
          val updatedUser = user.copy(profile = updatedProfile.toLocalProfile(user.profile.profileId))
          if (m.controller.apiUpdateProfile(updatedProfile) != null) {
            savedPrefs = currentPrefs
            m.currentUser.value = updatedUser
          }
        }
      }
    },
  )
}

@Composable fun PreferencesLayout(
  prefs: ChatPreferences,
  savedPrefs: ChatPreferences,
  applyPrefs: (ChatPreferences) -> Unit,
  revert: () -> Unit,
  savePrefs: () -> Unit,
) {
  Column(
    Modifier.fillMaxWidth().verticalScroll(rememberScrollState()),
    horizontalAlignment = Alignment.Start,
  ) {
    AppBarTitle(stringResource(R.string.chat_preferences))
    val voice = remember(prefs) {
      val pref = prefs.voice ?: ChatPreference.voiceDefault
      mutableStateOf(pref.toLocal())
    }
    VoiceSection(voice) {
      applyPrefs(prefs.copy(voice = it.toPref(ChatPreference.voiceDefault)))
    }

    SectionSpacer()
    val messageDelete = remember(prefs) {
      val pref = prefs.messageDelete ?: ChatPreference.messageDeleteDefault
      mutableStateOf(pref.toLocal())
    }
    MessageDeleteSection(messageDelete) {
      applyPrefs(prefs.copy(messageDelete = it.toPref(ChatPreference.messageDeleteDefault)))
    }

    Spacer(Modifier.height(15.dp))

    SectionCustomFooter(PaddingValues(horizontal = DEFAULT_PADDING)) {
      ButtonsFooter(
        cancel = revert,
        save = savePrefs,
        disabled = prefs == savedPrefs
      )
    }
  }
}

@Composable
private fun VoiceSection(current: State<ChatPreferenceLocal>, onSelected: (ChatPreferenceLocal) -> Unit) {
  val values = remember {
    listOf(
      ValueTitleDesc(ChatPreferenceLocal.ON, generalGetString(R.string.chat_preferences_on), generalGetString(R.string.chat_preferences_voice_on_desc)),
      ValueTitleDesc(ChatPreferenceLocal.OFF, generalGetString(R.string.chat_preferences_off), generalGetString(R.string.chat_preferences_voice_off_desc)),
      ValueTitleDesc(ChatPreferenceLocal.PREFER, generalGetString(R.string.chat_preferences_prefer), generalGetString(R.string.chat_preferences_voice_prefer_desc))
    )
  }
  SectionView(padding = PaddingValues(horizontal = DEFAULT_PADDING_HALF)) {
    SectionItemView {
      val mappedValues = remember { values.map { it.value to it.title } }
      ExposedDropDownSettingRow(
        generalGetString(R.string.chat_preferences_voice),
        mappedValues,
        current,
        icon = Icons.Outlined.Audiotrack,
        onSelected = onSelected
      )
    }
  }
  SectionTextFooter(values.firstOrNull { it.value == current.value }!!.description)
}

@Composable
private fun MessageDeleteSection(current: State<ChatPreferenceLocal>, onSelected: (ChatPreferenceLocal) -> Unit) {
  val values = remember {
    listOf(
      ValueTitleDesc(ChatPreferenceLocal.ON, generalGetString(R.string.chat_preferences_on), generalGetString(R.string.chat_preferences_deletion_on_desc)),
      ValueTitleDesc(ChatPreferenceLocal.OFF, generalGetString(R.string.chat_preferences_off), generalGetString(R.string.chat_preferences_deletion_off_desc)),
      ValueTitleDesc(ChatPreferenceLocal.PREFER, generalGetString(R.string.chat_preferences_prefer), generalGetString(R.string.chat_preferences_deletion_prefer_desc))
    )
  }
  SectionView(padding = PaddingValues(horizontal = DEFAULT_PADDING_HALF)) {
    SectionItemView {
      val mappedValues = remember { values.map { it.value to it.title } }
      ExposedDropDownSettingRow(
        generalGetString(R.string.chat_preferences_deletion),
        mappedValues,
        current,
        icon = Icons.Outlined.Delete,
        onSelected = onSelected
      )
    }
  }
  SectionTextFooter(values.firstOrNull { it.value == current.value }!!.description)
}

private fun showConfirmSavingAlert(onConfirm: () -> Unit) {
  AlertManager.shared.showAlertMsg(
    title = generalGetString(R.string.confirm_saving_prefs_question),
    text = generalGetString(R.string.confirm_saving_prefs_info),
    confirmText = generalGetString(R.string.save_verb),
    onConfirm = onConfirm
  )
}

@Composable
private fun ButtonsFooter(cancel: () -> Unit, save: () -> Unit, disabled: Boolean) {
  Row(
    Modifier.fillMaxWidth(),
    horizontalArrangement = Arrangement.SpaceBetween,
    verticalAlignment = Alignment.CenterVertically
  ) {
    FooterButton(Icons.Outlined.Replay, stringResource(R.string.cancel_verb), cancel, disabled)
    FooterButton(Icons.Outlined.Check, stringResource(R.string.save_verb), save, disabled)
  }
}
