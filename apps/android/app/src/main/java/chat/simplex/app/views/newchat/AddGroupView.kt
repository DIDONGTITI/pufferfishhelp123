package chat.simplex.app.views.newchat

import android.graphics.Bitmap
import androidx.compose.foundation.*
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.*
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.ArrowForwardIos
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import chat.simplex.app.R
import chat.simplex.app.model.*
import chat.simplex.app.ui.theme.HighOrLowlight
import chat.simplex.app.views.ProfileNameField
import chat.simplex.app.views.helpers.*
import chat.simplex.app.views.isValidDisplayName
import chat.simplex.app.views.onboarding.ReadableText
import chat.simplex.app.views.usersettings.DeleteImageButton
import chat.simplex.app.views.usersettings.EditImageButton
import com.google.accompanist.insets.ProvideWindowInsets
import com.google.accompanist.insets.navigationBarsWithImePadding
import kotlinx.coroutines.launch

@Composable
fun AddGroupView(chatModel: ChatModel, close: () -> Unit) {
  AddGroupLayout(
    createGroup = { groupProfile ->
      withApi {
        val groupInfo = chatModel.controller.apiNewGroup(groupProfile)
        if (groupInfo != null) {
          chatModel.addChat(Chat(chatInfo = ChatInfo.Group(groupInfo), chatItems = listOf()))
          close.invoke()
          chatModel.chatId.value = groupInfo.id
        }
      }
    },
    close
  )
}

@Composable
fun AddGroupLayout(createGroup: (GroupProfile) -> Unit, close: () -> Unit) {
  val bottomSheetModalState = rememberModalBottomSheetState(initialValue = ModalBottomSheetValue.Hidden)
  val scope = rememberCoroutineScope()
  val displayName = remember { mutableStateOf("") }
  val fullName = remember { mutableStateOf("") }
  val profileImage = remember { mutableStateOf<String?>(null) }
  val chosenImage = remember { mutableStateOf<Bitmap?>(null) }
  val focusRequester = remember { FocusRequester() }

  ProvideWindowInsets(windowInsetsAnimationsEnabled = true) {
    ModalBottomSheetLayout(
      scrimColor = Color.Black.copy(alpha = 0.12F),
      modifier = Modifier.navigationBarsWithImePadding(),
      sheetContent = {
        GetImageBottomSheet(
          chosenImage,
          onImageChange = { bitmap -> profileImage.value = resizeImageToStrSize(cropToSquare(bitmap), maxDataSize = 12500) },
          hideBottomSheet = {
            scope.launch { bottomSheetModalState.hide() }
          })
      },
      sheetState = bottomSheetModalState,
      sheetShape = RoundedCornerShape(topStart = 18.dp, topEnd = 18.dp)
    ) {
      ModalView(close) {
        Surface(Modifier.background(MaterialTheme.colors.onBackground)) {
          Column(
            Modifier
              .verticalScroll(rememberScrollState())
              .padding(bottom = 16.dp),
          ) {
            Text(
              stringResource(R.string.create_secret_group_title),
              style = MaterialTheme.typography.h4,
              modifier = Modifier.padding(vertical = 5.dp)
            )
            ReadableText(R.string.group_is_decentralized)
            Spacer(Modifier.height(10.dp))
            Box(
              Modifier
                .fillMaxWidth()
                .padding(bottom = 24.dp),
              contentAlignment = Alignment.Center
            ) {
              Box(contentAlignment = Alignment.TopEnd) {
                Box(contentAlignment = Alignment.Center) {
                  ProfileImage(192.dp, null)
                  EditImageButton { scope.launch { bottomSheetModalState.show() } }
                }
                if (profileImage.value != null) {
                  DeleteImageButton { profileImage.value = null }
                }
              }
            }
            Text(
              stringResource(R.string.group_display_name_field),
              style = MaterialTheme.typography.h6,
              modifier = Modifier.padding(bottom = 3.dp)
            )
            ProfileNameField(displayName, focusRequester)
            val errorText = if (!isValidDisplayName(displayName.value)) stringResource(R.string.display_name_cannot_contain_whitespace) else ""
            Text(
              errorText,
              fontSize = 15.sp,
              color = MaterialTheme.colors.error
            )
            Spacer(Modifier.height(3.dp))
            Text(
              stringResource(R.string.group_full_name_field),
              style = MaterialTheme.typography.h6,
              modifier = Modifier.padding(bottom = 5.dp)
            )
            ProfileNameField(fullName)

            Spacer(Modifier.fillMaxHeight())
            val enabled = displayName.value.isNotEmpty() && isValidDisplayName(displayName.value)
            val createModifier: Modifier
            val createColor: Color
            if (enabled) {
              val groupProfile = GroupProfile(displayName.value, fullName.value, profileImage.value)
              createModifier = Modifier.clickable { createGroup(groupProfile) }.padding(8.dp)
              createColor = MaterialTheme.colors.primary
            } else {
              createModifier = Modifier.padding(8.dp)
              createColor = HighOrLowlight
            }
            Row(
              Modifier.fillMaxWidth(),
              horizontalArrangement = Arrangement.End
            ) {
              Surface(shape = RoundedCornerShape(20.dp)) {
                Row(
                  createModifier,
                  verticalAlignment = Alignment.CenterVertically,
                ) {
                  Text(stringResource(R.string.create_profile_button), style = MaterialTheme.typography.caption, color = createColor)
                  Icon(Icons.Outlined.ArrowForwardIos, stringResource(R.string.create_profile_button), tint = createColor)
                }
              }
            }

            LaunchedEffect(Unit) {
              focusRequester.requestFocus()
            }
          }
        }
      }
    }
  }
}

