//
//  ChatListNavLink.swift
//  SimpleX
//
//  Created by Evgeny Poberezkin on 01/02/2022.
//  Copyright © 2022 SimpleX Chat. All rights reserved.
//

import SwiftUI
import SimpleXChat

typealias DynamicSizes = (
    rowHeight: CGFloat,
    profileImageSize: CGFloat,
    mediaSize: CGFloat,
    incognitoSize: CGFloat,
    chatInfoSize: CGFloat,
    unreadCorner: CGFloat,
    unreadPadding: CGFloat
)

private let dynamicSizes: [DynamicTypeSize: DynamicSizes] = [
    .xSmall: (68, 55, 33, 22, 18, 9, 3),
    .small: (72, 57, 34, 22, 18, 9, 3),
    .medium: (76, 60, 36, 22, 18, 10, 4),
    .large: (80, 63, 38, 24, 20, 10, 4),
    .xLarge: (88, 67, 41, 24, 20, 10, 4),
    .xxLarge: (100, 71, 44, 27, 22, 11, 4),
    .xxxLarge: (110, 75, 48, 30, 24, 12, 5),
    .accessibility1: (110, 75, 48, 30, 24, 12, 5),
    .accessibility2: (114, 75, 48, 30, 24, 12, 5),
    .accessibility3: (124, 75, 48, 30, 24, 12, 5),
    .accessibility4: (134, 75, 48, 30, 24, 12, 5),
    .accessibility5: (144, 75, 48, 30, 24, 12, 5)
]

private let defaultDynamicSizes: DynamicSizes = dynamicSizes[.large]!

func dynamicSize(_ font: DynamicTypeSize) -> DynamicSizes {
    dynamicSizes[font] ?? defaultDynamicSizes
}

struct ChatListNavLink: View {
    @EnvironmentObject var chatModel: ChatModel
    @EnvironmentObject var theme: AppTheme
    @Environment(\.dynamicTypeSize) private var userFont: DynamicTypeSize
    @ObservedObject var chat: Chat
    @State private var showContactRequestDialog = false
    @State private var showJoinGroupDialog = false
    @State private var showContactConnectionInfo = false
    @State private var showInvalidJSON = false
    @State private var showDeleteContactActionSheet = false
    @State private var showConnectContactViaAddressDialog = false
    @State private var inProgress = false
    @State private var progressByTimeout = false

    var dynamicRowHeight: CGFloat { dynamicSizes[userFont]?.rowHeight ?? 80 }

    var body: some View {
        Group {
            switch chat.chatInfo {
            case let .direct(contact):
                contactNavLink(contact)
            case let .group(groupInfo):
                groupNavLink(groupInfo)
            case let .local(noteFolder):
                noteFolderNavLink(noteFolder)
            case let .contactRequest(cReq):
                contactRequestNavLink(cReq)
            case let .contactConnection(cConn):
                contactConnectionNavLink(cConn)
            case let .invalidJSON(json):
                invalidJSONPreview(json)
            }
        }
        .onChange(of: inProgress) { inProgress in
            if inProgress {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                    progressByTimeout = inProgress
                }
            } else {
                progressByTimeout = false
            }
        }
    }

    @ViewBuilder private func contactNavLink(_ contact: Contact) -> some View {
        Group {
            if contact.activeConn == nil && contact.profile.contactLink != nil {
                ChatPreviewView(chat: chat, progressByTimeout: Binding.constant(false))
                    .frame(height: dynamicRowHeight)
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button {
                            showDeleteContactActionSheet = true
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                        .tint(.red)
                    }
                    .onTapGesture { showConnectContactViaAddressDialog = true }
                    .confirmationDialog("Connect with \(contact.chatViewName)", isPresented: $showConnectContactViaAddressDialog, titleVisibility: .visible) {
                        Button("Use current profile") { connectContactViaAddress_(contact, false) }
                        Button("Use new incognito profile") { connectContactViaAddress_(contact, true) }
                    }
            } else {
                NavLinkPlain(
                    tag: chat.chatInfo.id,
                    selection: $chatModel.chatId,
                    label: { ChatPreviewView(chat: chat, progressByTimeout: Binding.constant(false)) }
                )
                .swipeActions(edge: .leading, allowsFullSwipe: true) {
                    markReadButton()
                    toggleFavoriteButton()
                    ToggleNtfsButton(chat: chat)
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    if !chat.chatItems.isEmpty {
                        clearChatButton()
                    }
                    Button {
                        if contact.sndReady || !contact.active {
                            showDeleteContactActionSheet = true
                        } else {
                            AlertManager.shared.showAlert(deletePendingContactAlert(chat, contact))
                        }
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                    .tint(.red)
                }
                .frame(height: dynamicRowHeight)
            }
        }
        .actionSheet(isPresented: $showDeleteContactActionSheet) {
            if contact.sndReady && contact.active {
                return ActionSheet(
                    title: Text("Delete contact?\nThis cannot be undone!"),
                    buttons: [
                        .destructive(Text("Delete and notify contact")) { Task { await deleteChat(chat, notify: true) } },
                        .destructive(Text("Delete")) { Task { await deleteChat(chat, notify: false) } },
                        .cancel()
                    ]
                )
            } else {
                return ActionSheet(
                    title: Text("Delete contact?\nThis cannot be undone!"),
                    buttons: [
                        .destructive(Text("Delete")) { Task { await deleteChat(chat) } },
                        .cancel()
                    ]
                )
            }
        }
    }

    @ViewBuilder private func groupNavLink(_ groupInfo: GroupInfo) -> some View {
        switch (groupInfo.membership.memberStatus) {
        case .memInvited:
            ChatPreviewView(chat: chat, progressByTimeout: $progressByTimeout)
                .frame(height: dynamicRowHeight)
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    joinGroupButton()
                    if groupInfo.canDelete {
                        deleteGroupChatButton(groupInfo)
                    }
                }
                .onTapGesture { showJoinGroupDialog = true }
                .confirmationDialog("Group invitation", isPresented: $showJoinGroupDialog, titleVisibility: .visible) {
                    Button(chat.chatInfo.incognito ? "Join incognito" : "Join group") {
                        inProgress = true
                        joinGroup(groupInfo.groupId) {
                            await MainActor.run { inProgress = false }
                        }
                    }
                    Button("Delete invitation", role: .destructive) { Task { await deleteChat(chat) } }
                }
                .disabled(inProgress)
        case .memAccepted:
            ChatPreviewView(chat: chat, progressByTimeout: Binding.constant(false))
                .frame(height: dynamicRowHeight)
                .onTapGesture {
                    AlertManager.shared.showAlert(groupInvitationAcceptedAlert())
                }
                .swipeActions(edge: .trailing) {
                    if (groupInfo.membership.memberCurrent) {
                        leaveGroupChatButton(groupInfo)
                    }
                    if groupInfo.canDelete {
                        deleteGroupChatButton(groupInfo)
                    }
                }
        default:
            NavLinkPlain(
                tag: chat.chatInfo.id,
                selection: $chatModel.chatId,
                label: { ChatPreviewView(chat: chat, progressByTimeout: Binding.constant(false)) },
                disabled: !groupInfo.ready
            )
            .frame(height: dynamicRowHeight)
            .swipeActions(edge: .leading, allowsFullSwipe: true) {
                markReadButton()
                toggleFavoriteButton()
                ToggleNtfsButton(chat: chat)
            }
            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                if !chat.chatItems.isEmpty {
                    clearChatButton()
                }
                if (groupInfo.membership.memberCurrent) {
                    leaveGroupChatButton(groupInfo)
                }
                if groupInfo.canDelete {
                    deleteGroupChatButton(groupInfo)
                }
            }
        }
    }

    @ViewBuilder private func noteFolderNavLink(_ noteFolder: NoteFolder) -> some View {
        NavLinkPlain(
            tag: chat.chatInfo.id,
            selection: $chatModel.chatId,
            label: { ChatPreviewView(chat: chat, progressByTimeout: Binding.constant(false)) },
            disabled: !noteFolder.ready
        )
        .frame(height: dynamicRowHeight)
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            markReadButton()
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            if !chat.chatItems.isEmpty {
                clearNoteFolderButton()
            }
        }
    }

    private func joinGroupButton() -> some View {
        Button {
            inProgress = true
            joinGroup(chat.chatInfo.apiId) {
                await MainActor.run { inProgress = false }
            }
        } label: {
            Label("Join", systemImage: chat.chatInfo.incognito ? "theatermasks" : "ipad.and.arrow.forward")
        }
        .tint(chat.chatInfo.incognito ? .indigo : theme.colors.primary)
    }

    @ViewBuilder private func markReadButton() -> some View {
        if chat.chatStats.unreadCount > 0 || chat.chatStats.unreadChat {
            Button {
                Task { await markChatReadAll(chat) }
            } label: {
                Label("Read", systemImage: "checkmark")
            }
            .tint(theme.colors.primary)
        } else {
            Button {
                Task { await markChatUnread(chat) }
            } label: {
                Label("Unread", systemImage: "circlebadge.fill")
            }
            .tint(theme.colors.primary)
        }

    }

    @ViewBuilder private func toggleFavoriteButton() -> some View {
        if chat.chatInfo.chatSettings?.favorite == true {
            Button {
                toggleChatFavorite(chat, favorite: false)
            } label: {
                Label("Unfav.", systemImage: "star.slash")
            }
            .tint(.green)
        } else {
            Button {
                toggleChatFavorite(chat, favorite: true)
            } label: {
                Label("Favorite", systemImage: "star.fill")
            }
            .tint(.green)
        }
    }

    private func clearChatButton() -> some View {
        Button {
            AlertManager.shared.showAlert(clearChatAlert())
        } label: {
            Label("Clear", systemImage: "gobackward")
        }
        .tint(Color.orange)
    }

    private func clearNoteFolderButton() -> some View {
        Button {
            AlertManager.shared.showAlert(clearNoteFolderAlert())
        } label: {
            Label("Clear", systemImage: "gobackward")
        }
        .tint(Color.orange)
    }

    private func leaveGroupChatButton(_ groupInfo: GroupInfo) -> some View {
        Button {
            AlertManager.shared.showAlert(leaveGroupAlert(groupInfo))
        } label: {
            Label("Leave", systemImage: "rectangle.portrait.and.arrow.right")
        }
        .tint(Color.yellow)
    }

    private func deleteGroupChatButton(_ groupInfo: GroupInfo) -> some View {
        Button {
            AlertManager.shared.showAlert(deleteGroupAlert(groupInfo))
        } label: {
            Label("Delete", systemImage: "trash")
        }
        .tint(.red)
    }

    private func contactRequestNavLink(_ contactRequest: UserContactRequest) -> some View {
        ContactRequestView(contactRequest: contactRequest, chat: chat)
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button {
                Task { await acceptContactRequest(incognito: false, contactRequest: contactRequest) }
            } label: { Label("Accept", systemImage: "checkmark") }
                .tint(theme.colors.primary)
            Button {
                Task { await acceptContactRequest(incognito: true, contactRequest: contactRequest) }
            } label: {
                Label("Accept incognito", systemImage: "theatermasks")
            }
            .tint(.indigo)
            Button {
                AlertManager.shared.showAlert(rejectContactRequestAlert(contactRequest))
            } label: {
                Label("Reject", systemImage: "multiply")
            }
            .tint(.red)
        }
        .frame(height: dynamicRowHeight)
        .onTapGesture { showContactRequestDialog = true }
        .confirmationDialog("Accept connection request?", isPresented: $showContactRequestDialog, titleVisibility: .visible) {
            Button("Accept") { Task { await acceptContactRequest(incognito: false, contactRequest: contactRequest) } }
            Button("Accept incognito") { Task { await acceptContactRequest(incognito: true, contactRequest: contactRequest) } }
            Button("Reject (sender NOT notified)", role: .destructive) { Task { await rejectContactRequest(contactRequest) } }
        }
    }

    private func contactConnectionNavLink(_ contactConnection: PendingContactConnection) -> some View {
        ContactConnectionView(chat: chat)
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button {
                AlertManager.shared.showAlert(deleteContactConnectionAlert(contactConnection) { a in
                    AlertManager.shared.showAlertMsg(title: a.title, message: a.message)
                })
            } label: {
                Label("Delete", systemImage: "trash")
            }
            .tint(.red)

            Button {
                showContactConnectionInfo = true
            } label: {
                Label("Name", systemImage: "pencil")
            }
            .tint(theme.colors.primary)
        }
        .frame(height: dynamicRowHeight)
        .appSheet(isPresented: $showContactConnectionInfo) {
            Group {
                if case let .contactConnection(contactConnection) = chat.chatInfo {
                    ContactConnectionInfo(contactConnection: contactConnection)
                        .environment(\EnvironmentValues.refresh as! WritableKeyPath<EnvironmentValues, RefreshAction?>, nil)
                        .modifier(ThemedBackground(grouped: true))
                }
            }
        }
        .onTapGesture {
            showContactConnectionInfo = true
        }
    }

    private func deleteGroupAlert(_ groupInfo: GroupInfo) -> Alert {
        Alert(
            title: Text("Delete group?"),
            message: deleteGroupAlertMessage(groupInfo),
            primaryButton: .destructive(Text("Delete")) {
                Task { await deleteChat(chat) }
            },
            secondaryButton: .cancel()
        )
    }

    private func deleteGroupAlertMessage(_ groupInfo: GroupInfo) -> Text {
        groupInfo.membership.memberCurrent ? Text("Group will be deleted for all members - this cannot be undone!") : Text("Group will be deleted for you - this cannot be undone!")
    }

    private func clearChatAlert() -> Alert {
        Alert(
            title: Text("Clear conversation?"),
            message: Text("All messages will be deleted - this cannot be undone! The messages will be deleted ONLY for you."),
            primaryButton: .destructive(Text("Clear")) {
                Task { await clearChat(chat) }
            },
            secondaryButton: .cancel()
        )
    }

    private func clearNoteFolderAlert() -> Alert {
        Alert(
            title: Text("Clear private notes?"),
            message: Text("All messages will be deleted - this cannot be undone!"),
            primaryButton: .destructive(Text("Clear")) {
                Task { await clearChat(chat) }
            },
            secondaryButton: .cancel()
        )
    }

    private func leaveGroupAlert(_ groupInfo: GroupInfo) -> Alert {
        Alert(
            title: Text("Leave group?"),
            message: Text("You will stop receiving messages from this group. Chat history will be preserved."),
            primaryButton: .destructive(Text("Leave")) {
                Task { await leaveGroup(groupInfo.groupId) }
            },
            secondaryButton: .cancel()
        )
    }

    private func rejectContactRequestAlert(_ contactRequest: UserContactRequest) -> Alert {
        Alert(
            title: Text("Reject contact request"),
            message: Text("The sender will NOT be notified"),
            primaryButton: .destructive(Text("Reject")) {
                Task { await rejectContactRequest(contactRequest) }
            },
            secondaryButton: .cancel()
        )
    }

    private func pendingContactAlert(_ chat: Chat, _ contact: Contact) -> Alert {
        Alert(
            title: Text("Contact is not connected yet!"),
            message: Text("Your contact needs to be online for the connection to complete.\nYou can cancel this connection and remove the contact (and try later with a new link)."),
            primaryButton: .cancel(),
            secondaryButton: .destructive(Text("Delete Contact")) {
                removePendingContact(chat, contact)
            }
        )
    }

    private func groupInvitationAcceptedAlert() -> Alert {
        Alert(
            title: Text("Joining group"),
            message: Text("You joined this group. Connecting to inviting group member.")
        )
    }

    private func deletePendingContactAlert(_ chat: Chat, _ contact: Contact) -> Alert {
        Alert(
            title: Text("Delete pending connection"),
            message: Text("Your contact needs to be online for the connection to complete.\nYou can cancel this connection and remove the contact (and try later with a new link)."),
            primaryButton: .destructive(Text("Delete")) {
                removePendingContact(chat, contact)
            },
            secondaryButton: .cancel()
        )
    }

    private func removePendingContact(_ chat: Chat, _ contact: Contact) {
        Task {
            do {
                try await apiDeleteChat(type: chat.chatInfo.chatType, id: chat.chatInfo.apiId)
                DispatchQueue.main.async {
                    chatModel.removeChat(contact.id)
                }
            } catch let error {
                logger.error("ChatListNavLink.removePendingContact apiDeleteChat error: \(responseError(error))")
            }
        }
    }

    private func invalidJSONPreview(_ json: String) -> some View {
        Text("invalid chat data")
            .foregroundColor(.red)
            .padding(4)
            .frame(height: dynamicRowHeight)
            .onTapGesture { showInvalidJSON = true }
            .appSheet(isPresented: $showInvalidJSON) {
                invalidJSONView(json)
                    .environment(\EnvironmentValues.refresh as! WritableKeyPath<EnvironmentValues, RefreshAction?>, nil)
            }
    }

    private func connectContactViaAddress_(_ contact: Contact, _ incognito: Bool) {
        Task {
            let ok = await connectContactViaAddress(contact.contactId, incognito)
            if ok {
                await MainActor.run {
                    chatModel.chatId = contact.id
                }
            }
        }
    }
}

func deleteContactConnectionAlert(_ contactConnection: PendingContactConnection, showError: @escaping (ErrorAlert) -> Void, success: @escaping () -> Void = {}) -> Alert {
    Alert(
        title: Text("Delete pending connection?"),
        message:
            contactConnection.initiated
            ? Text("The contact you shared this link with will NOT be able to connect!")
            : Text("The connection you accepted will be cancelled!"),
        primaryButton: .destructive(Text("Delete")) {
            Task {
                do {
                    try await apiDeleteChat(type: .contactConnection, id: contactConnection.apiId)
                    await MainActor.run {
                        ChatModel.shared.removeChat(contactConnection.id)
                        success()
                    }
                } catch let error {
                    await MainActor.run {
                        showError(getErrorAlert(error, "Error deleting connection"))
                    }
                }
            }
        },
        secondaryButton: .cancel()
    )
}

func connectContactViaAddress(_ contactId: Int64, _ incognito: Bool) async -> Bool {
    let (contact, alert) = await apiConnectContactViaAddress(incognito: incognito, contactId: contactId)
    if let alert = alert {
        AlertManager.shared.showAlert(alert)
        return false
    } else if let contact = contact {
        await MainActor.run {
            ChatModel.shared.updateContact(contact)
            AlertManager.shared.showAlert(connReqSentAlert(.contact))
        }
        return true
    }
    return false
}

func joinGroup(_ groupId: Int64, _ onComplete: @escaping () async -> Void) {
    Task {
        logger.debug("joinGroup")
        do {
            let r = try await apiJoinGroup(groupId)
            switch r {
            case let .joined(groupInfo):
                await MainActor.run { ChatModel.shared.updateGroup(groupInfo) }
            case .invitationRemoved:
                AlertManager.shared.showAlertMsg(title: "Invitation expired!", message: "Group invitation is no longer valid, it was removed by sender.")
                await deleteGroup()
            case .groupNotFound:
                AlertManager.shared.showAlertMsg(title: "No group!", message: "This group no longer exists.")
                await deleteGroup()
            }
            await onComplete()
        } catch let error {
            await onComplete()
            let a = getErrorAlert(error, "Error joining group")
            AlertManager.shared.showAlertMsg(title: a.title, message: a.message)
        }

        func deleteGroup() async {
            do {
                // TODO this API should update chat item with the invitation as well
                try await apiDeleteChat(type: .group, id: groupId)
                await MainActor.run { ChatModel.shared.removeChat("#\(groupId)") }
            } catch {
                logger.error("apiDeleteChat error: \(responseError(error))")
            }
        }
    }
}

func getErrorAlert(_ error: Error, _ title: LocalizedStringKey) -> ErrorAlert {
    if let r = error as? ChatResponse,
       let alert = getNetworkErrorAlert(r) {
        return alert
    } else {
        return ErrorAlert(title: title, message: "Error: \(responseError(error))")
    }
}

struct ChatListNavLink_Previews: PreviewProvider {
    static var previews: some View {
        @State var chatId: String? = "@1"
        return Group {
            ChatListNavLink(chat: Chat(
                chatInfo: ChatInfo.sampleData.direct,
                chatItems: [ChatItem.getSample(1, .directSnd, .now, "hello")]
            ))
            ChatListNavLink(chat: Chat(
                chatInfo: ChatInfo.sampleData.direct,
                chatItems: [ChatItem.getSample(1, .directSnd, .now, "hello")]
            ))
            ChatListNavLink(chat: Chat(
                chatInfo: ChatInfo.sampleData.contactRequest,
                chatItems: []
            ))
        }
        .previewLayout(.fixed(width: 360, height: 82))
    }
}
