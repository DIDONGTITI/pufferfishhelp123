package chat.simplex.common.views.helpers

import SectionItemView
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.material.MaterialTheme
import androidx.compose.material.Text
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.style.TextAlign
import chat.simplex.common.BuildConfigCommon
import chat.simplex.common.model.ChatController.appPrefs
import chat.simplex.common.model.ChatController.getNetCfg
import chat.simplex.common.model.json
import chat.simplex.common.platform.*
import chat.simplex.common.ui.theme.WarningOrange
import chat.simplex.common.views.onboarding.ReadMoreButton
import chat.simplex.res.MR
import kotlinx.coroutines.*
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import okhttp3.OkHttpClient
import okhttp3.Request
import java.io.Closeable
import java.io.File
import java.net.InetSocketAddress
import java.net.Proxy

@Serializable
data class GitHubRelease(
  val id: Long,
  @SerialName("html_url")
  val htmlUrl: String,
  val name: String,
  val draft: Boolean,
  val prerelease: Boolean,
  val body: String,
  @SerialName("published_at")
  val publishedAt: String,
  val assets: List<GitHubAsset>
)

@Serializable
data class GitHubAsset(
  @SerialName("browser_download_url")
  val browserDownloadUrl: String,
  val name: String,
  val size: Long,

  val isAppImage: Boolean = name.lowercase().contains(".appimage")
)

private var updateCheckerJob: Job = Job()
fun setupUpdateChecker() = withLongRunningApi {
  updateCheckerJob.cancel()
  if (appPrefs.appUpdateChannel.get() == AppUpdatesChannel.DISABLED) {
    return@withLongRunningApi
  }
  checkForUpdate()
  createUpdateJob()
}

private fun createUpdateJob() {
  updateCheckerJob = withLongRunningApi {
    delay(24 * 60 * 60 * 1000)
    checkForUpdate()
    createUpdateJob()
  }
}


fun checkForUpdate() {
  val client = setupHttpClient()
  try {
    // LALAL
    val request = Request.Builder().url("https://api.github.com/repos/avently/simplex-chat/releases").addHeader("User-agent", "curl").build()
    client.newCall(request).execute().use { response ->
      response.body?.use {
        val body = it.string()
        val releases = json.decodeFromString<List<GitHubRelease>>(body).filterNot { it.draft }
        val release = when (appPrefs.appUpdateChannel.get()) {
          AppUpdatesChannel.STABLE -> releases.firstOrNull { !it.prerelease }
          AppUpdatesChannel.BETA -> releases.firstOrNull()
          AppUpdatesChannel.DISABLED -> return
        } ?: return
        val currentVersionName = "v" + (if (appPlatform.isAndroid) BuildConfigCommon.ANDROID_VERSION_NAME else BuildConfigCommon.DESKTOP_VERSION_NAME)
        val redactedCurrentVersionName = when {
          currentVersionName.contains('-') && currentVersionName.substringBefore('-').count { it == '.' } == 1 -> "${currentVersionName.substringBefore('-')}.0-${currentVersionName.substringAfter('-')}"
          currentVersionName.substringBefore('-').count { it == '.' } == 1 -> "${currentVersionName}.0"
          else -> currentVersionName
        }
        // LALAL
//        if (release.id == appPrefs.appSkippedUpdate.get() || release.name == currentVersionName || release.name == redactedCurrentVersionName) {
//          return
//        }
        val assets = chooseGitHubReleaseAssets(release).ifEmpty { return }
        val lines = ArrayList<String>()
        for (line in release.body.lines()) {
          if (line == "Commits:") break
          lines.add(line)
        }
        val text = lines.joinToString("\n")
        AlertManager.shared.showAlertDialogButtonsColumn(
          generalGetString(MR.strings.app_check_for_updates_update_available).format(release.name),
          text = text,
          textAlign = TextAlign.Start,
          dismissible = false,
          belowTextContent = {
            ReadMoreButton(release.htmlUrl)
          },
          buttons = {
            Column {
              for (asset in assets) {
                SectionItemView({
                  AlertManager.shared.hideAlert()
                  chatModel.updatingProgress.value = 0f
                  withLongRunningApi {
                    try {
                      downloadAsset(asset)
                    } finally {
                      chatModel.updatingProgress.value = null
                    }
                  }
                }) {
                  Text(
                    generalGetString(MR.strings.app_check_for_updates_button_download).format(
                      if (asset.name.length > 34) "…" + asset.name.substringAfter("simplex-desktop-") else asset.name,
                      formatBytes(asset.size)), Modifier.fillMaxWidth(), textAlign = TextAlign.Center, color = MaterialTheme.colors.primary
                  )
                }
              }

              SectionItemView({
                AlertManager.shared.hideAlert()
                skipRelease(release)
              }) {
                Text(generalGetString(MR.strings.app_check_for_updates_button_skip), Modifier.fillMaxWidth(), textAlign = TextAlign.Center, color = WarningOrange)
              }

              SectionItemView({
                AlertManager.shared.hideAlert()
              }) {
                Text(generalGetString(MR.strings.app_check_for_updates_button_remind_later), Modifier.fillMaxWidth(), textAlign = TextAlign.Center, color = MaterialTheme.colors.primary)
              }
            }
          }
        )
      }
    }
  } catch (e: Exception) {
    Log.e(TAG, "Failed to get the latest release: ${e.stackTraceToString()}")
  }
}

private fun setupHttpClient(): OkHttpClient {
  val netCfg = getNetCfg()
  var proxy: Proxy? = null
  if (netCfg.useSocksProxy && netCfg.socksProxy != null) {
    val hostname = netCfg.socksProxy.substringBefore(":").ifEmpty { "localhost" }
    val port = netCfg.socksProxy.substringAfter(":").toIntOrNull()
    if (port != null) {
      proxy = Proxy(Proxy.Type.SOCKS, InetSocketAddress(hostname, port))
    }
  }
  return OkHttpClient.Builder().proxy(proxy).followRedirects(true).build()
}

private fun skipRelease(release: GitHubRelease) {
  appPrefs.appSkippedUpdate.set(release.id)
}

private suspend fun downloadAsset(asset: GitHubAsset) {
  withContext(Dispatchers.Main) {
    showToast(generalGetString(MR.strings.app_check_for_updates_download_started))
  }
  val progressListener = object: ProgressListener {
    override fun update(bytesRead: Long, contentLength: Long, done: Boolean) {
      if (contentLength != -1L) {
        chatModel.updatingProgress.value = if (done) 1f else bytesRead / contentLength.toFloat()
      }
    }
  }
  val client = setupHttpClient().newBuilder()
    .addNetworkInterceptor { chain ->
      val originalResponse = chain.proceed(chain.request())
      val body = originalResponse.body
      if (body != null) {
        originalResponse.newBuilder().body(ProgressResponseBody(body, progressListener)).build()
      } else {
        originalResponse
      }
    }
    .build()

  try {
    val request = Request.Builder().url(asset.browserDownloadUrl).addHeader("User-agent", "curl").build()
    val call = client.newCall(request)
    chatModel.updatingRequest = Closeable { call.cancel(); println("LALAL CANCELLED") }
    call.execute().use { response ->
      response.body?.use { body ->
        body.byteStream().use { stream ->
          createTmpFileAndDelete { file ->
            // It's important to close output stream (with use{}), otherwise, Windows cannot rename the file
            file.outputStream().use { output ->
              stream.copyTo(output)
            }
            val newFile = File(file.parentFile, asset.name)
            file.renameTo(newFile)

            AlertManager.shared.showAlertDialogButtonsColumn(
              generalGetString(MR.strings.app_check_for_updates_download_completed_title),
              text = generalGetString(MR.strings.app_check_for_updates_download_completed_desc),
              dismissible = false,
              buttons = {
                Column {
                  SectionItemView({
                    AlertManager.shared.hideAlert()
                    chatModel.updatingProgress.value = -1f
                    withLongRunningApi {
                      try {
                        installAppUpdate(newFile)
                      } finally {
                        chatModel.updatingProgress.value = null
                      }
                    }
                  }) {
                    Text(generalGetString(MR.strings.app_check_for_updates_button_install), Modifier.fillMaxWidth(), textAlign = TextAlign.Center, color = MaterialTheme.colors.primary)
                  }
                  SectionItemView({
                    desktopOpenDir(newFile.parentFile)
                  }) {
                    Text(generalGetString(MR.strings.app_check_for_updates_button_open), Modifier.fillMaxWidth(), textAlign = TextAlign.Center, color = MaterialTheme.colors.primary)
                  }

                  SectionItemView({
                    AlertManager.shared.hideAlert()
                    newFile.delete()
                  }) {
                    Text(generalGetString(MR.strings.app_check_for_updates_button_remind_later), Modifier.fillMaxWidth(), textAlign = TextAlign.Center, color = MaterialTheme.colors.primary)
                  }
                }
              }
            )
          }
        }
      }
    }
  } catch (e: Exception) {
    Log.e(TAG, "Failed to download the asset from release: ${e.stackTraceToString()}")
  }
}


private fun chooseGitHubReleaseAssets(release: GitHubRelease): List<GitHubAsset> {
  val process = Runtime.getRuntime().exec("which dpkg").onExit().join()
  val isDebianBased = process.exitValue() == 0
  // Show all available .deb packages and user will choose the one that works on his system
  val res = if (isDebianBased) {
    release.assets.filter { it.name.lowercase().endsWith(".deb") }
  } else {
    release.assets.filter { it.name == desktopPlatform.githubAssetName }
  }
  return res
}

private suspend fun installAppUpdate(file: File) = withContext(Dispatchers.IO) {
  when {
    desktopPlatform.isLinux() -> {
      val process = Runtime.getRuntime().exec("xdg-open ${file.absolutePath}").onExit().join()
      val startedInstallation = process.exitValue() == 0 && process.children().count() > 0
      if (!startedInstallation) {
        Log.e(TAG, "Error starting installation: ${process.inputReader().use { it.readLines().joinToString("\n") }}${process.errorStream.use { String(it.readAllBytes()) }}")
        // Failed to start installation. show directory with the file for manual installation
        desktopOpenDir(file.parentFile)
      } else {
        withApi {
          ntfManager.showMessage(generalGetString(MR.strings.app_check_for_updates_installed_successfully_title), generalGetString(MR.strings.app_check_for_updates_installed_successfully_desc))
        }
        file.delete()
      }
    }
    desktopPlatform.isWindows() -> {
      val process = Runtime.getRuntime().exec("msiexec /i ${file.absolutePath}"/* /qb */).onExit().join()
      val startedInstallation = process.exitValue() == 0
      if (!startedInstallation) {
        Log.e(TAG, "Error starting installation: ${process.inputReader().use { it.readLines().joinToString("\n") }}${process.errorStream.use { String(it.readAllBytes()) }}")
        // Failed to start installation. show directory with the file for manual installation
        desktopOpenDir(file.parentFile)
      } else {
        withApi {
          ntfManager.showMessage(generalGetString(MR.strings.app_check_for_updates_installed_successfully_title), generalGetString(MR.strings.app_check_for_updates_installed_successfully_desc))
        }
        file.delete()
      }
    }
    desktopPlatform.isMac() -> {
      try {
        val process = Runtime.getRuntime().exec("hdiutil mount ${file.absolutePath}").onExit().join()
        val startedInstallation = process.exitValue() == 0
        if (!startedInstallation) {
          Log.e(TAG, "Error starting installation: ${process.inputReader().use { it.readLines().joinToString("\n") }}${process.errorStream.use { String(it.readAllBytes()) }}")
          // Failed to start installation. show directory with the file for manual installation
          desktopOpenDir(file.parentFile)
          return@withContext
        }
        val process2 = Runtime.getRuntime().exec("cp -R /Volumes/SimpleX/SimpleX.app /Applications").onExit().join()
        val copiedSuccessfully = process2.exitValue() == 0
        if (!copiedSuccessfully) {
          Log.e(TAG, "Error copying the app: ${process.inputReader().use { it.readLines().joinToString("\n") }}${process.errorStream.use { String(it.readAllBytes()) }}")
          // Failed to start installation. show directory with the file for manual installation
          desktopOpenDir(file.parentFile)
        } else {
          withApi {
            ntfManager.showMessage(generalGetString(MR.strings.app_check_for_updates_installed_successfully_title), generalGetString(MR.strings.app_check_for_updates_installed_successfully_desc))
          }
          file.delete()
        }
      } finally {
        Runtime.getRuntime().exec("hdiutil unmount /Volumes/SimpleX").onExit().join()
      }
    }
  }
  Unit
}
