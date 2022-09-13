package chat.simplex.app.views.database

import SectionItemView
import SectionItemViewSpaceBetween
import SectionView
import androidx.compose.foundation.background
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.ZeroCornerSize
import androidx.compose.foundation.text.*
import androidx.compose.material.*
import androidx.compose.material.TextFieldDefaults.indicatorLine
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material.icons.outlined.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.*
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.platform.LocalSoftwareKeyboardController
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.*
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.*
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import chat.simplex.app.R
import chat.simplex.app.SimplexApp
import chat.simplex.app.model.*
import chat.simplex.app.ui.theme.*
import chat.simplex.app.views.helpers.*
import kotlin.math.log2

@Composable
fun DatabaseEncryptionView(m: ChatModel) {
  val progressIndicator = remember { mutableStateOf(false) }
  val prefs = m.controller.appPrefs
  val useKeychain = remember { mutableStateOf(prefs.storeDBPassphrase.get()) }
  val initialRandomDBPassphrase = remember { mutableStateOf(prefs.initialRandomDBPassphrase.get()) }
  val storedKey = remember { mutableStateOf(DatabaseUtils.getDatabaseKey() != null) }
  // Do not do rememberSaveable on current key to prevent saving it on disk in clear text
  val currentKey = remember { mutableStateOf(if (initialRandomDBPassphrase.value) DatabaseUtils.getDatabaseKey() ?: "" else "") }
  val newKey = rememberSaveable { mutableStateOf("") }
  val confirmNewKey = rememberSaveable { mutableStateOf("") }

  Box(
    Modifier.fillMaxSize(),
  ) {
    DatabaseEncryptionLayout(
      useKeychain,
      prefs,
      m.chatDbEncrypted.value,
      currentKey,
      newKey,
      confirmNewKey,
      storedKey,
      initialRandomDBPassphrase,
      onConfirmEncrypt = {
        progressIndicator.value = true
        withApi {
          try {
            val error = m.controller.apiStorageEncryption(currentKey.value, newKey.value)
            val sqliteError = ((error?.chatError as? ChatError.ChatErrorDatabase)?.databaseError as? DatabaseError.ErrorExport)?.sqliteError
            when {
              sqliteError is SQLiteError.ErrorNotADatabase -> {
                operationEnded(m, progressIndicator) {
                  AlertManager.shared.showAlertMsg(
                    generalGetString(R.string.wrong_passphrase_title),
                    generalGetString(R.string.enter_correct_current_passphrase)
                  )
                }
              }
              error != null -> {
                operationEnded(m, progressIndicator) {
                  AlertManager.shared.showAlertMsg(generalGetString(R.string.error_encrypting_database),
                    "failed to set storage encryption: ${error.responseType} ${error.details}"
                  )
                }
              }
              else -> {
                prefs.initialRandomDBPassphrase.set(false)
                initialRandomDBPassphrase.value = false
                if (useKeychain.value) {
                  DatabaseUtils.setDatabaseKey(newKey.value)
                }
                resetFormAfterEncryption(m, initialRandomDBPassphrase, currentKey, newKey, confirmNewKey, storedKey, useKeychain.value)
                operationEnded(m, progressIndicator) {
                  AlertManager.shared.showAlertMsg(generalGetString(R.string.database_encrypted))
                }
              }
            }
          } catch (e: Exception) {
            operationEnded(m, progressIndicator) {
              AlertManager.shared.showAlertMsg(generalGetString(R.string.error_encrypting_database), e.stackTraceToString())
            }
          }
        }
      }
    )
    if (progressIndicator.value) {
      Box(
        Modifier.fillMaxSize(),
        contentAlignment = Alignment.Center
      ) {
        CircularProgressIndicator(
          Modifier
            .padding(horizontal = 2.dp)
            .size(30.dp),
          color = HighOrLowlight,
          strokeWidth = 2.5.dp
        )
      }
    }
  }
}

@Composable
fun DatabaseEncryptionLayout(
  useKeychain: MutableState<Boolean>,
  prefs: AppPreferences,
  chatDbEncrypted: Boolean?,
  currentKey: MutableState<String>,
  newKey: MutableState<String>,
  confirmNewKey: MutableState<String>,
  storedKey: MutableState<Boolean>,
  initialRandomDBPassphrase: MutableState<Boolean>,
  onConfirmEncrypt: () -> Unit,
) {
  Column(
    Modifier.fillMaxWidth(),
    horizontalAlignment = Alignment.Start,
  ) {
    Text(
      stringResource(R.string.database_passphrase),
      Modifier.padding(start = 16.dp, bottom = 24.dp),
      style = MaterialTheme.typography.h1
    )

    SectionView(null) {
      SavePassphraseSetting(useKeychain.value, initialRandomDBPassphrase.value, storedKey.value) { checked ->
        if (checked) {
          setUseKeychain(true, useKeychain, prefs)
        } else if (storedKey.value) {
          AlertManager.shared.showAlertDialog(
            title = generalGetString(R.string.remove_passphrase_from_keychain),
            text = generalGetString(R.string.notifications_will_be_hidden) + "\n" + storeSecurelyDanger(),
            confirmText = generalGetString(R.string.remove_passphrase),
            onConfirm = {
              DatabaseUtils.removeDatabaseKey()
              setUseKeychain(false, useKeychain, prefs)
              storedKey.value = false
            },
            destructive = true,
          )
        } else {
          setUseKeychain(false, useKeychain, prefs)
        }
      }

      if (!initialRandomDBPassphrase.value && chatDbEncrypted == true) {
        DatabaseKeyField(
          currentKey,
          generalGetString(R.string.current_passphrase),
          modifier = Modifier.padding(start = 8.dp),
          isValid = ::validKey,
          keyboardActions = KeyboardActions(onNext = { defaultKeyboardAction(ImeAction.Next) }),
        )
      }

      DatabaseKeyField(
        newKey,
        generalGetString(R.string.new_passphrase),
        modifier = Modifier.padding(start = 8.dp),
        showStrength = true,
        isValid = ::validKey,
        keyboardActions = KeyboardActions(onNext = { defaultKeyboardAction(ImeAction.Next) }),
      )
      val onClickUpdate = {
        if (currentKey.value == "") {
          if (useKeychain.value)
            encryptDatabaseSavedAlert(onConfirmEncrypt)
          else
            encryptDatabaseAlert(onConfirmEncrypt)
        } else {
          if (useKeychain.value)
            changeDatabaseKeySavedAlert(onConfirmEncrypt)
          else
            changeDatabaseKeyAlert(onConfirmEncrypt)
        }
      }
      val disabled = currentKey.value == newKey.value ||
          newKey.value != confirmNewKey.value ||
          newKey.value.isEmpty() ||
          !validKey(currentKey.value) ||
          !validKey(newKey.value)

      DatabaseKeyField(
        confirmNewKey,
        generalGetString(R.string.confirm_new_passphrase),
        modifier = Modifier.padding(start = 8.dp),
        isValid = { confirmNewKey.value == "" || newKey.value == confirmNewKey.value },
        keyboardActions = KeyboardActions(onDone = {
          if (!disabled) onClickUpdate()
          defaultKeyboardAction(ImeAction.Done)
        }),
      )

      SectionItemViewSpaceBetween(onClickUpdate, padding = PaddingValues(start = 8.dp, end = 12.dp), disabled = disabled) {
        Text(generalGetString(R.string.update_database_passphrase), color = if (disabled) HighOrLowlight else MaterialTheme.colors.primary)
      }
    }

    Column(
      Modifier.padding(start = 16.dp, end = 16.dp, top = 5.dp)
    ) {
      if (chatDbEncrypted == false) {
        FooterText(generalGetString(R.string.database_is_not_encrypted))
      } else if (useKeychain.value) {
        if (storedKey.value) {
          FooterText(generalGetString(R.string.keychain_is_storing_securely))
          if (initialRandomDBPassphrase.value) {
            FooterText(generalGetString(R.string.encrypted_with_random_passphrase))
          } else {
            FooterText(generalGetString(R.string.impossible_to_recover_passphrase))
          }
        } else {
          FooterText(generalGetString(R.string.keychain_allows_to_receive_ntfs))
        }
      } else {
        FooterText(generalGetString(R.string.you_have_to_enter_passphrase_every_time))
        FooterText(generalGetString(R.string.impossible_to_recover_passphrase))
      }
    }
  }
}

@Composable
private fun FooterText(text: String) {
  Text(
    text,
    Modifier.padding(horizontal = 16.dp).padding(top = 5.dp).fillMaxWidth(0.9F),
    color = HighOrLowlight,
    fontSize = 12.sp
  )
}

fun encryptDatabaseSavedAlert(onConfirm: () -> Unit) {
  AlertManager.shared.showAlertDialog(
    title = generalGetString(R.string.encrypt_database_question),
    text = generalGetString(R.string.database_will_be_encrypted_and_passphrase_stored) + "\n" + storeSecurelySaved(),
    confirmText = generalGetString(R.string.encrypt_database),
    onConfirm = onConfirm,
    destructive = false,
  )
}

fun encryptDatabaseAlert(onConfirm: () -> Unit) {
  AlertManager.shared.showAlertDialog(
    title = generalGetString(R.string.encrypt_database_question),
    text = generalGetString(R.string.database_will_be_encrypted) +"\n" + storeSecurelyDanger(),
    confirmText = generalGetString(R.string.encrypt_database),
    onConfirm = onConfirm,
    destructive = true,
  )
}

fun changeDatabaseKeySavedAlert(onConfirm: () -> Unit) {
  AlertManager.shared.showAlertDialog(
    title = generalGetString(R.string.change_database_passphrase_question),
    text = generalGetString(R.string.database_encryption_will_be_updated) + "\n" + storeSecurelySaved(),
    confirmText = generalGetString(R.string.update_database),
    onConfirm = onConfirm,
    destructive = false,
  )
}

fun changeDatabaseKeyAlert(onConfirm: () -> Unit) {
  AlertManager.shared.showAlertDialog(
    title = generalGetString(R.string.change_database_passphrase_question),
    text = generalGetString(R.string.database_passphrase_will_be_updated) + "\n" + storeSecurelyDanger(),
    confirmText = generalGetString(R.string.update_database),
    onConfirm = onConfirm,
    destructive = true,
  )
}

@Composable
fun SavePassphraseSetting(
  useKeychain: Boolean,
  initialRandomDBPassphrase: Boolean,
  storedKey: Boolean,
  onCheckedChange: (Boolean) -> Unit,
) {
  SectionItemView() {
    Row(verticalAlignment = Alignment.CenterVertically) {
      Icon(
        if (storedKey) Icons.Filled.VpnKey else Icons.Filled.VpnKeyOff,
        stringResource(R.string.save_passphrase_in_keychain),
        tint = if (storedKey) SimplexGreen else HighOrLowlight
      )
      Spacer(Modifier.padding(horizontal = 4.dp))
      Text(
        stringResource(R.string.save_passphrase_in_keychain),
        Modifier.padding(end = 24.dp),
        color = Color.Unspecified
      )
      Spacer(Modifier.fillMaxWidth().weight(1f))
      Switch(
        checked = useKeychain,
        onCheckedChange = onCheckedChange,
        colors = SwitchDefaults.colors(
          checkedThumbColor = MaterialTheme.colors.primary,
          uncheckedThumbColor = HighOrLowlight
        ),
        enabled = !initialRandomDBPassphrase
      )
    }
  }
}

fun resetFormAfterEncryption(
  m: ChatModel,
  initialRandomDBPassphrase: MutableState<Boolean>,
  currentKey: MutableState<String>,
  newKey: MutableState<String>,
  confirmNewKey: MutableState<String>,
  storedKey: MutableState<Boolean>,
  stored: Boolean = false,
) {
  m.chatDbEncrypted.value = true
  initialRandomDBPassphrase.value = false
  m.controller.appPrefs.initialRandomDBPassphrase.set(false)
  currentKey.value = ""
  newKey.value = ""
  confirmNewKey.value = ""
  storedKey.value = stored
}

fun setUseKeychain(value: Boolean, useKeychain: MutableState<Boolean>, prefs: AppPreferences) {
  useKeychain.value = value
  prefs.storeDBPassphrase.set(value)
}

fun storeSecurelySaved() = generalGetString(R.string.store_passphrase_securely)

fun storeSecurelyDanger() = generalGetString(R.string.store_passphrase_securely_without_recover)

private fun operationEnded(m: ChatModel, progressIndicator: MutableState<Boolean>, alert: () -> Unit) {
  m.chatDbChanged.value = true
  progressIndicator.value = false
  alert.invoke()
}

@OptIn(ExperimentalComposeUiApi::class)
@Composable
fun DatabaseKeyField(
  key: MutableState<String>,
  placeholder: String,
  modifier: Modifier = Modifier,
  showStrength: Boolean = false,
  isValid: (String) -> Boolean,
  keyboardActions: KeyboardActions = KeyboardActions(),
) {
  var valid by remember { mutableStateOf(validKey(key.value)) }
  var showKey by remember { mutableStateOf(false) }
  val icon = if (valid) {
    if (showKey) Icons.Filled.VisibilityOff else Icons.Filled.Visibility
  } else Icons.Outlined.Error
  val iconColor = if (valid) {
    if (showStrength && key.value.isNotEmpty()) PassphraseStrength.check(key.value).color else HighOrLowlight
  } else Color.Red
  val keyboard = LocalSoftwareKeyboardController.current
  val keyboardOptions = KeyboardOptions(
    imeAction = if (keyboardActions.onNext != null) ImeAction.Next else ImeAction.Done,
    autoCorrect = false,
    keyboardType = KeyboardType.Password
  )
  val state = remember {
    mutableStateOf(TextFieldValue(key.value))
  }
  val enabled = true
  val colors = TextFieldDefaults.textFieldColors(
    backgroundColor = Color.Unspecified,
    textColor = MaterialTheme.colors.onBackground,
    focusedIndicatorColor = Color.Unspecified,
    unfocusedIndicatorColor = Color.Unspecified,
  )
  val color = MaterialTheme.colors.onBackground
  val shape = MaterialTheme.shapes.small.copy(bottomEnd = ZeroCornerSize, bottomStart = ZeroCornerSize)
  val interactionSource = remember { MutableInteractionSource() }
  BasicTextField(
    value = state.value,
    modifier = modifier
      .fillMaxWidth()
      .background(colors.backgroundColor(enabled).value, shape)
      .indicatorLine(enabled, false, interactionSource, colors)
      .defaultMinSize(
        minWidth = TextFieldDefaults.MinWidth,
        minHeight = TextFieldDefaults.MinHeight
      ),
    onValueChange = {
      state.value = it
      key.value = it.text
      valid = isValid(it.text)
    },
    cursorBrush = SolidColor(colors.cursorColor(false).value),
    visualTransformation = if (showKey)
      VisualTransformation.None
    else
      VisualTransformation { TransformedText(AnnotatedString(it.text.map { "*" }.joinToString(separator = "")), OffsetMapping.Identity) },
    keyboardOptions = keyboardOptions,
    keyboardActions = KeyboardActions(onDone = {
      keyboard?.hide()
      keyboardActions.onDone?.invoke(this)
    }),
    singleLine = true,
    textStyle = TextStyle.Default.copy(
      color = color,
      fontWeight = FontWeight.Normal,
      fontSize = 16.sp
    ),
    interactionSource = interactionSource,
    decorationBox = @Composable { innerTextField ->
      TextFieldDefaults.TextFieldDecorationBox(
        value = state.value.text,
        innerTextField = innerTextField,
        placeholder = { Text(placeholder, color = HighOrLowlight) },
        singleLine = true,
        enabled = enabled,
        isError = !valid,
        trailingIcon = {
          IconButton({ showKey = !showKey }) {
            Icon(icon, null, tint = iconColor)
          }
        },
        interactionSource = interactionSource,
        contentPadding = TextFieldDefaults.textFieldWithLabelPadding(start = 0.dp, end = 0.dp),
        visualTransformation = VisualTransformation.None,
        colors = colors
      )
    }
  )
}

// based on https://generatepasswords.org/how-to-calculate-entropy/
private fun passphraseEntropy(s: String): Double {
  var hasDigits = false
  var hasUppercase = false
  var hasLowercase = false
  var hasSymbols = false
  for (c in s) {
    if (c.isDigit()) {
      hasDigits = true
    } else if (c.isLetter()) {
      if (c.isUpperCase()) {
        hasUppercase = true
      } else {
        hasLowercase = true
      }
    } else if (c.isASCII()) {
      hasSymbols = true
    }
  }
  val poolSize = (if (hasDigits) 10 else 0) + (if (hasUppercase) 26 else 0) + (if (hasLowercase) 26 else 0) + (if (hasSymbols) 32 else 0)
  return s.length * log2(poolSize.toDouble())
}

private enum class PassphraseStrength(val color: Color) {
  VERY_WEAK(Color.Red), WEAK(WarningOrange), REASONABLE(Color.Yellow), STRONG(Color.Green);

  companion object {
    fun check(s: String) = with(passphraseEntropy(s)) {
      when {
        this > 60 -> STRONG
        this > 45 -> REASONABLE
        this > 30 -> WEAK
        else -> VERY_WEAK
      }
    }
  }
}

fun validKey(s: String): Boolean {
  for (c in s) {
    if (c.isWhitespace() || !c.isASCII()) {
      return false
    }
  }
  return true
}

private fun Char.isASCII() = code in 32..126

@Preview
@Composable
fun PreviewDatabaseEncryptionLayout() {
  SimpleXTheme {
    DatabaseEncryptionLayout(
      useKeychain = remember { mutableStateOf(true) },
      prefs = AppPreferences(SimplexApp.context),
      chatDbEncrypted = true,
      currentKey = remember { mutableStateOf("") },
      newKey = remember { mutableStateOf("") },
      confirmNewKey = remember { mutableStateOf("") },
      storedKey = remember { mutableStateOf(true) },
      initialRandomDBPassphrase = remember { mutableStateOf(true) },
      onConfirmEncrypt = {},
    )
  }
}