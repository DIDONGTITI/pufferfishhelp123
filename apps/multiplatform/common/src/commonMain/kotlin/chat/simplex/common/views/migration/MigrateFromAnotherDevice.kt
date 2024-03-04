package chat.simplex.common.views.migration

import SectionItemView
import SectionSpacer
import SectionTextFooter
import SectionView
import androidx.compose.foundation.*
import androidx.compose.foundation.layout.*
import androidx.compose.material.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalClipboardManager
import androidx.compose.ui.unit.dp
import chat.simplex.common.model.*
import chat.simplex.common.model.AppPreferences.Companion.SHARED_PREFS_MIGRATION_STAGE
import chat.simplex.common.model.ChatController.getNetCfg
import chat.simplex.common.model.ChatController.startChat
import chat.simplex.common.model.ChatController.startChatWithTemporaryDatabase
import chat.simplex.common.model.ChatCtrl
import chat.simplex.common.model.ChatModel.controller
import chat.simplex.common.platform.*
import chat.simplex.common.ui.theme.*
import chat.simplex.common.views.database.*
import chat.simplex.common.views.helpers.*
import chat.simplex.common.views.helpers.DatabaseUtils.ksDatabasePassword
import chat.simplex.common.views.newchat.QRCodeScanner
import chat.simplex.common.views.onboarding.OnboardingStage
import chat.simplex.common.views.usersettings.*
import chat.simplex.res.MR
import dev.icerock.moko.resources.compose.painterResource
import dev.icerock.moko.resources.compose.stringResource
import kotlinx.coroutines.*
import kotlinx.datetime.Clock
import kotlinx.datetime.toJavaInstant
import kotlinx.serialization.*
import java.io.File
import java.text.SimpleDateFormat
import java.util.*
import kotlin.math.max

@Serializable
sealed class MigrationFromAnotherDeviceState {
  @Serializable data class Onion(val link: String): MigrationFromAnotherDeviceState()
  @Serializable data class DownloadProgress(val link: String, val archiveName: String, val netCfg: NetCfg): MigrationFromAnotherDeviceState()
  @Serializable data class ArchiveImport(val archiveName: String, val netCfg: NetCfg): MigrationFromAnotherDeviceState()
  @Serializable data class Passphrase(val netCfg: NetCfg): MigrationFromAnotherDeviceState()

  companion object  {
    // Here we check whether it's needed to show migration process after app restart or not
    // It's important to NOT show the process when archive was corrupted/not fully downloaded
    fun transform(): MigrationFromAnotherDeviceState? {
      val stage = settings.getStringOrNull(SHARED_PREFS_MIGRATION_STAGE)
      val state: MigrationFromAnotherDeviceState? = if (stage != null) json.decodeFromString(stage) else null
      if (state is DownloadProgress) {
        // iOS changes absolute directory every launch, check this way
        val archivePath = File(getMigrationTempFilesDirectory(), state.archiveName)
        archivePath.delete()
        settings.remove(SHARED_PREFS_MIGRATION_STAGE)
        // No migration happens at the moment actually since archive were not downloaded fully
        Log.e(TAG, "MigrateFromDevice: archive wasn't fully downloaded, removed broken file")
        return null
      } else if (state is Onion) {
        settings.remove(SHARED_PREFS_MIGRATION_STAGE)
        return null
      }
      return state
    }

    fun save(state: MigrationFromAnotherDeviceState?) {
      if (state != null) {
        appPreferences.migrationStage.set(json.encodeToString(state))
      } else {
        appPreferences.migrationStage.set(null)
      }
      chatModel.migrationState.value = state
    }
  }
}

@Serializable
private sealed class MigrationState {
  object PasteOrScanLink: MigrationState()
  data class Onion(val link: String): MigrationState()
  data class LinkDownloading(val link: String, val netCfg: NetCfg): MigrationState()
  data class DownloadProgress(val downloadedBytes: Long, val totalBytes: Long, val fileId: Long, val link: String, val archivePath: String, val netCfg: NetCfg, val ctrl: ChatCtrl?): MigrationState()
  data class DownloadFailed(val totalBytes: Long, val link: String, val archivePath: String, val netCfg: NetCfg): MigrationState()
  data class ArchiveImport(val archivePath: String, val netCfg: NetCfg): MigrationState()
  data class ArchiveImportFailed(val archivePath: String, val netCfg: NetCfg): MigrationState()
  data class Passphrase(val passphrase: String, val netCfg: NetCfg): MigrationState()
  data class Migration(val passphrase: String, val netCfg: NetCfg): MigrationState()
}

private var MutableState<MigrationState>.state: MigrationState
  get() = value
  set(v) { value = v }

@Composable
fun ModalData.MigrateFromAnotherDeviceView(state: MigrationFromAnotherDeviceState? = null, close: () -> Unit) {
  // Prevent from hiding the view until migration is finished or app deleted
  val backDisabled = remember {
    mutableStateOf(
      state != null && state !is MigrationFromAnotherDeviceState.ArchiveImport && state !is MigrationFromAnotherDeviceState.Onion
    )
  }
  val migrationState = rememberSaveable(stateSaver = serializableSaver()) {
    mutableStateOf(
      when (state) {
        null -> MigrationState.PasteOrScanLink
        is MigrationFromAnotherDeviceState.Onion -> {
          MigrationState.Onion(state.link)
        }
        is MigrationFromAnotherDeviceState.DownloadProgress -> {
          val archivePath = File(getMigrationTempFilesDirectory(), state.archiveName)
          archivePath.delete()
          // SHOULDN'T BE HERE because the app checks this before opening migration screen and will not open it in this case.
          // See analyzeMigrationState()
          MigrationState.DownloadFailed(totalBytes = 0, link = state.link, archivePath = archivePath.absolutePath, state.netCfg)
        }
        is MigrationFromAnotherDeviceState.ArchiveImport -> {
          val archivePath = File(getMigrationTempFilesDirectory(), state.archiveName)
          MigrationState.ArchiveImportFailed(archivePath.absolutePath, state.netCfg)
        }
        is MigrationFromAnotherDeviceState.Passphrase -> {
          MigrationState.Passphrase("", state.netCfg)
        }
      }
    )
  }
  val chatReceiver = remember { mutableStateOf(null as MigrationChatReceiver?) }
  ModalView(
    enableClose = !backDisabled.value,
    close = {
      migrationState.cleanUpOnBack(backDisabled, chatReceiver.value)
      close()
    },
  ) {
    MigrateFromAnotherDeviceLayout(
      migrationState = migrationState,
      backDisabled = backDisabled,
      chatReceiver = chatReceiver,
      close = close,
    )
  }
}

@Composable
private fun ModalData.MigrateFromAnotherDeviceLayout(
  migrationState: MutableState<MigrationState>,
  backDisabled: MutableState<Boolean>,
  chatReceiver: MutableState<MigrationChatReceiver?>,
  close: () -> Unit,
) {
  val tempDatabaseFile = rememberSaveable { mutableStateOf(fileForTemporaryDatabase()) }

  Column(
    Modifier.fillMaxSize().verticalScroll(rememberScrollState()).height(IntrinsicSize.Max),
  ) {
    AppBarTitle(stringResource(MR.strings.migrate_here))
    SectionByState(migrationState, tempDatabaseFile.value, backDisabled, chatReceiver, close)
  }
}

@Composable
private fun ModalData.SectionByState(
  migrationState: MutableState<MigrationState>,
  tempDatabaseFile: File,
  backDisabled: MutableState<Boolean>,
  chatReceiver: MutableState<MigrationChatReceiver?>,
  close: () -> Unit
) {
  when (val s = migrationState.value) {
    is MigrationState.PasteOrScanLink -> migrationState.PasteOrScanLinkView()
    is MigrationState.Onion -> OnionView(s.link, migrationState, close)
    is MigrationState.LinkDownloading -> migrationState.LinkDownloadingView(s.link, tempDatabaseFile, chatReceiver, s.netCfg)
    is MigrationState.DownloadProgress -> migrationState.DownloadProgressView(s.downloadedBytes, totalBytes = s.totalBytes, chatReceiver.value, s.netCfg)
    is MigrationState.DownloadFailed -> migrationState.DownloadFailedView(totalBytes = s.totalBytes, s.link, s.archivePath, s.netCfg)
    is MigrationState.ArchiveImport -> migrationState.ArchiveImportView(s.archivePath, s.netCfg)
    is MigrationState.ArchiveImportFailed -> migrationState.ArchiveImportFailedView(s.archivePath, s.netCfg)
    is MigrationState.Passphrase -> migrationState.PassphraseEnteringView(currentKey = s.passphrase, s.netCfg)
    is MigrationState.Migration -> migrationState.MigrationView(s.passphrase, s.netCfg, close)
  }
  KeyChangeEffect(migrationState.value) {
    backDisabled.value = migrationState.value !is MigrationState.ArchiveImportFailed && chatModel.migrationState.value != null
  }
}

@Composable
private fun MutableState<MigrationState>.PasteOrScanLinkView() {
  if (appPlatform.isAndroid) {
    SectionView(stringResource(MR.strings.scan_QR_code).uppercase()) {
      QRCodeScanner(showQRCodeScanner = remember { mutableStateOf(true) }) { text ->
        checkUserLink(text)
      }
    }
  }

  SectionView(stringResource(if (appPlatform.isAndroid) MR.strings.or_paste_archive_link else MR.strings.paste_archive_link).uppercase()) {
    PasteLinkView()
  }
}

@Composable
private fun MutableState<MigrationState>.PasteLinkView() {
  val clipboard = LocalClipboardManager.current
  SectionItemView({
    val str = clipboard.getText()?.text ?: return@SectionItemView
    checkUserLink(str)
  }) {
    Text(stringResource(MR.strings.tap_to_paste_link))
  }
}

@Composable
private fun ModalData.OnionView(link: String, state: MutableState<MigrationState>, close: () -> Unit) {
  val onionHosts = remember { stateGetOrPut("onionHosts") { OnionHosts.NEVER } }
  val networkUseSocksProxy = remember { stateGetOrPut("networkUseSocksProxy") { false } }
  val sessionMode = remember { stateGetOrPut("sessionMode") { TransportSessionMode.User} }
  val networkProxyHostPort = remember { stateGetOrPut("networkHostProxyPort") { chatModel.controller.appPrefs.networkProxyHostPort.get() } }
  val proxyPort = remember { derivedStateOf { networkProxyHostPort.value?.split(":")?.lastOrNull()?.toIntOrNull() ?: 9050 } }

  val netCfg = rememberSaveable(stateSaver = serializableSaver()) {
    mutableStateOf(getNetCfg().withOnionHosts(onionHosts.value).copy(sessionMode = sessionMode.value))
  }

  SectionView(stringResource(MR.strings.migration_from_device_review_onion_settings).uppercase()) {
    SettingsActionItemWithContent(
      icon = painterResource(MR.images.ic_check),
      text = stringResource(MR.strings.migration_from_device_apply_onion),
      textColor = MaterialTheme.colors.primary,
      click = {
        val updated = netCfg.value.withOnionHosts(onionHosts.value).copy(
          socksProxy = if (networkUseSocksProxy.value) networkProxyHostPort.value else null,
          sessionMode = sessionMode.value,
        )
        withBGApi {
          state.value = MigrationState.LinkDownloading(link, updated)
        }
      }
    ){}
    SectionTextFooter(stringResource(MR.strings.migration_from_device_review_onion_settings_footer))
  }

  SectionSpacer()

  val networkProxyHostPortPref = SharedPreference(get = { networkProxyHostPort.value }, set = {
    networkProxyHostPort.value = it
  })
  SectionView(stringResource(MR.strings.network_use_onion_hosts).uppercase()) {
    OnionRelatedLayout(
      appPreferences.developerTools.get(),
      networkUseSocksProxy,
      onionHosts,
      sessionMode,
      networkProxyHostPortPref,
      proxyPort,
      toggleSocksProxy = { enable ->
        networkUseSocksProxy.value = enable
      },
      useOnion = {
        onionHosts.value = it
      },
      updateSessionMode = {
        sessionMode.value = it
      }
    )
    SectionTextFooter(
      stringResource(
        when (onionHosts.value) {
          OnionHosts.NEVER -> MR.strings.migration_from_device_onion_hosts_never
          OnionHosts.PREFER -> MR.strings.migration_from_device_onion_hosts_prefer
          OnionHosts.REQUIRED -> MR.strings.migration_from_device_onion_hosts_require
        }
      )
    )
  }
}

@Composable
private fun MutableState<MigrationState>.LinkDownloadingView(link: String, tempDatabaseFile: File, chatReceiver: MutableState<MigrationChatReceiver?>, netCfg: NetCfg) {
  Box {
    SectionView(stringResource(MR.strings.migration_from_device_downloading_details).uppercase()) {}
    ProgressView()
  }
  LaunchedEffect(Unit) {
    downloadLinkDetails(link, tempDatabaseFile, chatReceiver, netCfg)
  }
  DisposableEffectOnGone {
    if (state !is MigrationState.DownloadProgress) {
      chatReceiver.value?.stopAndCleanUp()
    }
  }
}

@Composable
private fun MutableState<MigrationState>.DownloadProgressView(downloadedBytes: Long, totalBytes: Long, chatReceiver: MigrationChatReceiver?, netCfg: NetCfg) {
  Box {
    SectionView(stringResource(MR.strings.migration_from_device_downloading_archive).uppercase()) {
      val ratio = downloadedBytes.toFloat() / max(totalBytes, 1)
      LargeProgressView(ratio, "${(ratio * 100).toInt()}%", stringResource(MR.strings.migration_from_device_bytes_downloaded).format(formatBytes(downloadedBytes)))
    }
  }
  DisposableEffectOnGone {
    chatReceiver?.stopAndCleanUp()
  }
}

@Composable
private fun MutableState<MigrationState>.DownloadFailedView(totalBytes: Long, link: String, archivePath: String, netCfg: NetCfg) {
  SectionView(stringResource(MR.strings.migration_from_device_download_failed).uppercase()) {
    SettingsActionItemWithContent(
      icon = painterResource(MR.images.ic_download),
      text = stringResource(MR.strings.migration_from_device_repeat_download),
      textColor = MaterialTheme.colors.primary,
      click = {
        state = MigrationState.LinkDownloading(link, netCfg)
      }
    ) {}
    SectionTextFooter(stringResource(MR.strings.migration_from_device_try_again))
  }
  LaunchedEffect(Unit) {
    File(archivePath).delete()
    MigrationFromAnotherDeviceState.save(null)
  }
}

@Composable
private fun MutableState<MigrationState>.ArchiveImportView(archivePath: String, netCfg: NetCfg) {
  Box {
    SectionView(stringResource(MR.strings.migration_from_device_importing_archive).uppercase()) {}
    ProgressView()
  }
  LaunchedEffect(Unit) {
    importArchive(archivePath, netCfg)
  }
}

@Composable
private fun MutableState<MigrationState>.ArchiveImportFailedView(archivePath: String, netCfg: NetCfg) {
  SectionView(stringResource(MR.strings.migration_from_device_import_failed).uppercase()) {
    SettingsActionItemWithContent(
      icon = painterResource(MR.images.ic_download),
      text = stringResource(MR.strings.migration_from_device_repeat_import),
      textColor = MaterialTheme.colors.primary,
      click = {
        state = MigrationState.ArchiveImport(archivePath, netCfg)
      }
    ) {}
    SectionTextFooter(stringResource(MR.strings.migration_from_device_try_again))
  }
}

@Composable
private fun MutableState<MigrationState>.PassphraseEnteringView(currentKey: String, netCfg: NetCfg) {
  val currentKey = rememberSaveable { mutableStateOf(currentKey) }
  val verifyingPassphrase = rememberSaveable { mutableStateOf(false) }
  Box {
    val view = LocalMultiplatformView()
    SectionView(stringResource(MR.strings.migration_from_device_enter_passphrase).uppercase()) {
      PassphraseField(currentKey, placeholder = stringResource(MR.strings.current_passphrase), Modifier.padding(horizontal = DEFAULT_PADDING), isValid = ::validKey)

      SettingsActionItemWithContent(
        icon = painterResource(MR.images.ic_vpn_key_filled),
        text = stringResource(MR.strings.open_chat),
        textColor = MaterialTheme.colors.primary,
        click = {
          verifyingPassphrase.value = true
          hideKeyboard(view)
          withBGApi {
            val (status, ctrl) = chatInitTemporaryDatabase(dbAbsolutePrefixPath, key = currentKey.value)
            val success = status == DBMigrationResult.OK || status == DBMigrationResult.InvalidConfirmation || status is DBMigrationResult.ErrorMigration
            if (success) {
              ChatController.ctrl = ctrl
              state = MigrationState.Migration(currentKey.value, netCfg)
            } else {
              showErrorOnMigrationIfNeeded(status)
            }
            verifyingPassphrase.value = false
          }
        }
      ) {}
      SectionTextFooter(stringResource(MR.strings.migration_from_device_passphrase_will_be_stored))
    }
    if (verifyingPassphrase.value) {
      ProgressView()
    }
  }
}

@Composable
private fun MutableState<MigrationState>.MigrationView(passphrase: String, netCfg: NetCfg, close: () -> Unit) {
  Box {
    SectionView(stringResource(MR.strings.migration_from_device_migrating).uppercase()) {}
    ProgressView()
  }
  LaunchedEffect(Unit) {
    startChat(passphrase, netCfg, close)
  }
}

@Composable
private fun ProgressView() {
  DefaultProgressView("")
}

@Composable
private fun LargeProgressView(value: Float, title: String, description: String) {
  Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
      CircularProgressIndicator(
        progress = value,
        Modifier
          .padding(bottom = DEFAULT_PADDING)
          .size(DEFAULT_START_MODAL_WIDTH)
          .align(Alignment.TopCenter),
        color = MaterialTheme.colors.primary,
        strokeWidth = 25.dp
      )
    Column(Modifier.size(DEFAULT_START_MODAL_WIDTH), horizontalAlignment = Alignment.CenterHorizontally) {
      Text(description, color = Color.Transparent)
      Text(title, style = MaterialTheme.typography.h1, color = MaterialTheme.colors.primary)
      Text(description, style = MaterialTheme.typography.subtitle1)
    }
  }
}

private fun MutableState<MigrationState>.checkUserLink(link: String) {
  if (strHasSimplexFileLink(link.trim())) {
    // LALAL need to show onion setup or not
    if (true) {
      state = MigrationState.Onion(link.trim())
      MigrationFromAnotherDeviceState.save(MigrationFromAnotherDeviceState.Onion(link.trim()))
    } else {
      state = MigrationState.LinkDownloading(link.trim(), getNetCfg())
    }
  } else {
    AlertManager.shared.showAlertMsg(
      title = generalGetString(MR.strings.invalid_file_link),
      text = generalGetString(MR.strings.the_text_you_pasted_is_not_a_link)
    )
  }
}


private fun MutableState<MigrationState>.downloadLinkDetails(
  link: String,
  tempDatabaseFile: File,
  chatReceiver: MutableState<MigrationChatReceiver?>,
  netCfg: NetCfg,
) {
  val archiveTime = Clock.System.now()
  val ts = SimpleDateFormat("yyyy-MM-dd'T'HHmmss", Locale.US).format(Date.from(archiveTime.toJavaInstant()))
  val archiveName = "simplex-chat.$ts.zip"
  val archivePath = File(getMigrationTempFilesDirectory(), archiveName)

  startDownloading(0, tempDatabaseFile, chatReceiver, link, archivePath.absolutePath, netCfg)
}

private suspend fun initTemporaryDatabase(tempDatabaseFile: File, netCfg: NetCfg): Pair<ChatCtrl, User>? {
  val (status, ctrl) = chatInitTemporaryDatabase(tempDatabaseFile.absolutePath)
  showErrorOnMigrationIfNeeded(status)
  try {
    if (ctrl != null) {
      val user = startChatWithTemporaryDatabase(ctrl, netCfg)
      return if (user != null) ctrl to user else null
    }
  } catch (e: Throwable) {
    Log.e(TAG, "Error while starting chat in temporary database: ${e.stackTraceToString()}")
  }
  return null
}

private fun MutableState<MigrationState>.startDownloading(
  totalBytes: Long,
  tempDatabaseFile: File,
  chatReceiver: MutableState<MigrationChatReceiver?>,
  link: String,
  archivePath: String,
  netCfg: NetCfg,
) {
  withBGApi {
    val ctrlAndUser = initTemporaryDatabase(tempDatabaseFile, netCfg)
    if (ctrlAndUser == null) {
      state = MigrationState.DownloadFailed(totalBytes, link, archivePath, netCfg)
      return@withBGApi
    }

    val (ctrl, user) = ctrlAndUser
    chatReceiver.value = MigrationChatReceiver(ctrl, tempDatabaseFile) { msg ->
        when (msg) {
          is CR.RcvFileProgressXFTP -> {
            state = MigrationState.DownloadProgress(msg.receivedSize, msg.totalSize, msg.rcvFileTransfer.fileId, link, archivePath, netCfg, ctrl)
            MigrationFromAnotherDeviceState.save(MigrationFromAnotherDeviceState.DownloadProgress(link, File(archivePath).name, netCfg))
          }
          is CR.RcvStandaloneFileComplete -> {
            delay(500)
            state = MigrationState.ArchiveImport(archivePath, netCfg)
            MigrationFromAnotherDeviceState.save(MigrationFromAnotherDeviceState.ArchiveImport(File(archivePath).name, netCfg))
          }
          is CR.RcvFileError -> {
            AlertManager.shared.showAlertMsg(
              generalGetString(MR.strings.migration_from_device_download_failed),
              generalGetString(MR.strings.migration_from_device_file_delete_or_link_invalid)
            )
            state = MigrationState.DownloadFailed(totalBytes, link, archivePath, netCfg)
          }
          else -> Log.d(TAG, "unsupported event: ${msg.responseType}")
        }
    }
    chatReceiver.value?.start()

    val (res, error) = controller.downloadStandaloneFile(user, link, CryptoFile.plain(File(archivePath).path), ctrl)
    if (res == null) {
      state = MigrationState.DownloadFailed(totalBytes, link, archivePath, netCfg)
      AlertManager.shared.showAlertMsg(
        generalGetString(MR.strings.migration_from_device_error_downloading_archive),
        error
      )
    }
  }
}

private fun MutableState<MigrationState>.importArchive(archivePath: String, netCfg: NetCfg) {
  withBGApi {
    try {
      if (ChatController.ctrl == null || ChatController.ctrl == -1L) {
        chatInitControllerRemovingDatabases()
      }
      controller.apiDeleteStorage()
      try {
        val config = ArchiveConfig(archivePath)
        val archiveErrors = controller.apiImportArchive(config)
        if (archiveErrors.isNotEmpty()) {
          AlertManager.shared.showAlertMsg(
            generalGetString(MR.strings.chat_database_imported),
            generalGetString(MR.strings.non_fatal_errors_occured_during_import)
          )
        }
        state = MigrationState.Passphrase("", netCfg)
        MigrationFromAnotherDeviceState.save(MigrationFromAnotherDeviceState.Passphrase(netCfg))
      } catch (e: Exception) {
        state = MigrationState.ArchiveImportFailed(archivePath, netCfg)
        AlertManager.shared.showAlertMsg (generalGetString(MR.strings.error_importing_database), e.stackTraceToString())
      }
    } catch (e: Exception) {
      state = MigrationState.ArchiveImportFailed(archivePath, netCfg)
      AlertManager.shared.showAlertMsg (generalGetString(MR.strings.error_deleting_database), e.stackTraceToString())
    }
  }
}


private suspend fun stopArchiveDownloading(fileId: Long, ctrl: ChatCtrl) {
  controller.apiCancelFile(null, fileId, ctrl)
}

private fun cancelMigration(fileId: Long, ctrl: ChatCtrl, close: () -> Unit) {
  withBGApi {
    stopArchiveDownloading(fileId, ctrl)
    close()
  }
}

private fun MutableState<MigrationState>.startChat(passphrase: String, netCfg: NetCfg, close: () -> Unit) {
  ksDatabasePassword.set(passphrase)
  appPreferences.storeDBPassphrase.set(true)
  appPreferences.initialRandomDBPassphrase.set(false)
  withBGApi {
    try {
      initChatController(useKey = passphrase) { CompletableDeferred(false) }
      val appSettings = controller.apiGetAppSettings(AppSettings.current).copy(
        networkConfig = netCfg
      )
      finishMigration(appSettings, close)
    } catch (e: Exception) {
      hideView(close)
      AlertManager.shared.showAlertMsg(generalGetString(MR.strings.error_starting_chat), e.stackTraceToString())
    }
  }
}

private suspend fun finishMigration(appSettings: AppSettings, close: () -> Unit) {
  try {
    getMigrationTempFilesDirectory().deleteRecursively()
    MigrationFromAnotherDeviceState.save(null)
    appSettings.importIntoApp()
    val user = chatModel.currentUser.value
    if (user != null) {
      startChat(user)
    }
    AlertManager.shared.showAlertMsg(generalGetString(MR.strings.migration_from_device_chat_migrated), generalGetString(MR.strings.migration_from_device_finalize_migration))
  } catch (e: Exception) {
    AlertManager.shared.showAlertMsg(generalGetString(MR.strings.error_starting_chat), e.stackTraceToString())
  }
  hideView(close)
}

private fun hideView(close: () -> Unit) {
  appPreferences.onboardingStage.set(OnboardingStage.OnboardingComplete)
  close()
}

private fun MutableState<MigrationState>.cleanUpOnBack(backDisabled: MutableState<Boolean>, chatReceiver: MigrationChatReceiver?) {
  val state = state
  if (state is MigrationState.ArchiveImportFailed) {
    // Original database is not exist, nothing is set up correctly for showing to a user yet. Return to clean state
    deleteChatDatabaseFilesAndState()
    initChatControllerAndRunMigrations()
  } else if (state is MigrationState.DownloadProgress && state.ctrl != null) {
    withBGApi {
      stopArchiveDownloading(state.fileId, state.ctrl)
    }
  }
  if (!backDisabled.value) {
    chatReceiver?.stopAndCleanUp()
    getMigrationTempFilesDirectory().deleteRecursively()
    MigrationFromAnotherDeviceState.save(null)
  }
}

private fun strHasSimplexFileLink(text: String): Boolean =
  text.startsWith("simplex:/file") || text.startsWith("https://simplex.chat/file")

private fun fileForTemporaryDatabase(): File =
  File(getMigrationTempFilesDirectory(), generateNewFileName("migration", "db", getMigrationTempFilesDirectory()))

private class MigrationChatReceiver(
  val ctrl: ChatCtrl,
  val databaseUrl: File,
  val processReceivedMsg: suspend (CR) -> Unit,
) {
  fun start() {
    Log.d(TAG, "MigrationChatReceiver startReceiver")
    CoroutineScope(Dispatchers.IO).launch {
      while (true) {
        try {
          val msg = ChatController.recvMsg(ctrl)
          if (msg != null) {
            val r = msg.resp
            val rhId = msg.remoteHostId
            Log.d(TAG, "processReceivedMsg: ${r.responseType}")
            chatModel.addTerminalItem(TerminalItem.resp(rhId, r))
            val finishedWithoutTimeout = withTimeoutOrNull(60_000L) {
              processReceivedMsg(r)
            }
            if (finishedWithoutTimeout == null) {
              Log.e(TAG, "Timeout reached while processing received message: " + msg.resp.responseType)
              if (appPreferences.developerTools.get() && appPreferences.showSlowApiCalls.get()) {
                AlertManager.shared.showAlertMsg(
                  title = generalGetString(MR.strings.possible_slow_function_title),
                  text = generalGetString(MR.strings.possible_slow_function_desc).format(60, msg.resp.responseType + "\n" + Exception().stackTraceToString()),
                  shareText = true
                )
              }
            }
          }
        } catch (e: Exception) {
          Log.e(TAG, "MigrationChatReceiver recvMsg/processReceivedMsg exception: " + e.stackTraceToString());
        } catch (e: Exception) {
          Log.e(TAG, "MigrationChatReceiver recvMsg/processReceivedMsg throwable: " + e.stackTraceToString())
          AlertManager.shared.showAlertMsg(generalGetString(MR.strings.error), e.stackTraceToString())
        }
      }
    }
  }

  fun stopAndCleanUp() {
    Log.d(TAG, "MigrationChatReceiver.stop")
    chatCloseStore(ctrl)
    File(databaseUrl.absolutePath + "_chat.db").delete()
    File(databaseUrl.absolutePath + "_agent.db").delete()
  }
}
