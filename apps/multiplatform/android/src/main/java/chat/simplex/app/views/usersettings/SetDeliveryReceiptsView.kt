package chat.simplex.app.views.usersettings

import SectionBottomSpacer
import android.util.Log
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import dev.icerock.moko.resources.compose.painterResource
import dev.icerock.moko.resources.compose.stringResource
import androidx.compose.ui.text.style.TextAlign
import chat.simplex.app.TAG
import chat.simplex.app.model.ChatModel
import chat.simplex.app.ui.theme.*
import chat.simplex.app.views.helpers.*
import chat.simplex.res.MR

@Composable
fun SetDeliveryReceiptsView(m: ChatModel) {
  SetDeliveryReceiptsLayout(
    enableReceipts = {
      val currentUser = m.currentUser.value
      if (currentUser != null) {
        withApi {
          try {
            m.controller.apiSetAllContactReceipts(enable = true)
            m.setDeliveryReceipts.value = false
            m.controller.appPrefs.privacyDeliveryReceiptsSet.set(true)
          } catch (e: Exception) {
            AlertManager.shared.showAlertDialog(
              title = generalGetString(MR.strings.error_enabling_delivery_receipts),
              text = e.stackTraceToString()
            )
            Log.e(TAG, "${generalGetString(MR.strings.error_enabling_delivery_receipts)}: ${e.stackTraceToString()}")
            m.setDeliveryReceipts.value = false
          }
        }
      }
    },
    skip = {
      AlertManager.shared.showAlertDialog(
        title = generalGetString(MR.strings.delivery_receipts_are_disabled),
        text = generalGetString(MR.strings.you_can_enable_delivery_receipts_later_alert),
        confirmText = generalGetString(MR.strings.ok),
        dismissText = generalGetString(MR.strings.dont_show_again),
        onConfirm = {
          m.setDeliveryReceipts.value = false
        },
        onDismiss = {
          m.setDeliveryReceipts.value = false
          m.controller.appPrefs.privacyDeliveryReceiptsSet.set(true)
        }
      )
    },
    userCount = m.users.size
  )
}

@Composable
private fun SetDeliveryReceiptsLayout(
  enableReceipts: () -> Unit,
  skip: () -> Unit,
  userCount: Int,
) {
  Column(
    Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(top = DEFAULT_PADDING),
    horizontalAlignment = Alignment.CenterHorizontally,
  ) {
    AppBarTitle(stringResource(MR.strings.delivery_receipts_title))

    Spacer(Modifier.weight(1f))

    EnableReceiptsButton(enableReceipts)
    if (userCount > 1) {
      TextBelowButton(stringResource(MR.strings.sending_delivery_receipts_will_be_enabled_all_profiles))
    } else {
      TextBelowButton(stringResource(MR.strings.sending_delivery_receipts_will_be_enabled))
    }

    Spacer(Modifier.weight(1f))

    SkipButton(skip)

    SectionBottomSpacer()
  }
}

@Composable
private fun EnableReceiptsButton(onClick: () -> Unit) {
  TextButton(onClick) {
    Text(stringResource(MR.strings.enable_receipts_all), style = MaterialTheme.typography.h2, color = MaterialTheme.colors.primary)
  }
}

@Composable
private fun SkipButton(onClick: () -> Unit) {
  SimpleButtonIconEnded(stringResource(MR.strings.dont_enable_receipts), painterResource(MR.images.ic_chevron_right), click = onClick)
  TextBelowButton(stringResource(MR.strings.you_can_enable_delivery_receipts_later))
}

@Composable
private fun TextBelowButton(text: String) {
  Text(
    text,
    Modifier
      .fillMaxWidth()
      .padding(horizontal = DEFAULT_PADDING * 3),
    style = MaterialTheme.typography.subtitle1,
    textAlign = TextAlign.Center,
  )
}

