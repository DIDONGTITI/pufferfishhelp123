//
//  ChatInfoView.swift
//  SimpleX
//
//  Created by Evgeny Poberezkin on 05/02/2022.
//  Copyright © 2022 SimpleX Chat. All rights reserved.
//

import SwiftUI
import SimpleXChat

func infoRow(_ title: LocalizedStringKey, _ value: String) -> some View {
    HStack {
        Text(title)
        Spacer()
        Text(value)
            .foregroundStyle(.secondary)
    }
}

func infoRow(_ title: Text, _ value: String) -> some View {
    HStack {
        title
        Spacer()
        Text(value)
            .foregroundStyle(.secondary)
    }
}

func localizedInfoRow(_ title: LocalizedStringKey, _ value: LocalizedStringKey) -> some View {
    HStack {
        Text(title)
        Spacer()
        Text(value)
            .foregroundStyle(.secondary)
    }
}

@ViewBuilder func smpServers(_ title: LocalizedStringKey, _ servers: [String], _ secondaryColor: Color) -> some View {
    if servers.count > 0 {
        HStack {
            Text(title).frame(width: 120, alignment: .leading)
            Button(serverHost(servers[0])) {
                UIPasteboard.general.string = servers.joined(separator: ";")
            }
            .foregroundColor(secondaryColor)
            .lineLimit(1)
        }
    }
}

func serverHost(_ s: String) -> String {
    if let i = s.range(of: "@")?.lowerBound {
        return String(s[i...].dropFirst())
    } else {
        return s
    }
}

enum SendReceipts: Identifiable, Hashable {
    case yes
    case no
    case userDefault(Bool)

    var id: Self { self }

    var text: LocalizedStringKey {
        switch self {
        case .yes: return "yes"
        case .no: return "no"
        case let .userDefault(on): return on ? "default (yes)" : "default (no)"
        }
    }

    func bool() -> Bool? {
        switch self {
        case .yes: return true
        case .no: return false
        case .userDefault: return nil
        }
    }

    static func fromBool(_ enable: Bool?, userDefault def: Bool) -> SendReceipts {
        if let enable = enable {
            return enable ? .yes : .no
        }
        return .userDefault(def)
    }
}

struct ChatInfoView: View {
    @EnvironmentObject var chatModel: ChatModel
    @EnvironmentObject var theme: AppTheme
    @Environment(\.dismiss) var dismiss: DismissAction
    @ObservedObject var chat: Chat
    @State var contact: Contact
    @Binding var connectionStats: ConnectionStats?
    @Binding var customUserProfile: Profile?
    @State var localAlias: String
    @Binding var connectionCode: String?
    @FocusState private var aliasTextFieldFocused: Bool
    @State private var alert: ChatInfoViewAlert? = nil
    @State private var showDeleteContactActionSheet = false
    @State private var sendReceipts = SendReceipts.userDefault(true)
    @State private var sendReceiptsUserDefault = true
    @AppStorage(DEFAULT_DEVELOPER_TOOLS) private var developerTools = false

    enum ChatInfoViewAlert: Identifiable {
        case clearChatAlert
        case networkStatusAlert
        case switchAddressAlert
        case abortSwitchAddressAlert
        case syncConnectionForceAlert
        case queueInfo(info: String)
        case error(title: LocalizedStringKey, error: LocalizedStringKey?)

        var id: String {
            switch self {
            case .clearChatAlert: return "clearChatAlert"
            case .networkStatusAlert: return "networkStatusAlert"
            case .switchAddressAlert: return "switchAddressAlert"
            case .abortSwitchAddressAlert: return "abortSwitchAddressAlert"
            case .syncConnectionForceAlert: return "syncConnectionForceAlert"
            case let .queueInfo(info): return "queueInfo \(info)"
            case let .error(title, _): return "error \(title)"
            }
        }
    }

    var body: some View {
        NavigationView {
            List {
                contactInfoHeader()
                    .listRowBackground(Color.clear)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        aliasTextFieldFocused = false
                    }

                Group {
                    localAliasTextEdit()
                }
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)

                if let customUserProfile = customUserProfile {
                    Section(header: Text("Incognito").foregroundColor(theme.colors.secondary)) {
                        HStack {
                            Text("Your random profile")
                            Spacer()
                            Text(customUserProfile.chatViewName)
                                .foregroundStyle(.indigo)
                        }
                    }
                }

                Section {
                    Group {
                        if let code = connectionCode { verifyCodeButton(code) }
                        contactPreferencesButton()
                        sendReceiptsOption()
                        if let connStats = connectionStats,
                           connStats.ratchetSyncAllowed {
                            synchronizeConnectionButton()
                        }
                        // } else if developerTools {
                        //     synchronizeConnectionButtonForce()
                        // }
                    }
                    .disabled(!contact.ready || !contact.active)
                    NavigationLink {
                        ChatWallpaperEditorSheet(chat: chat)
                    } label: {
                        Label("Chat theme", systemImage: "photo")
                    }
                }

                if let conn = contact.activeConn {
                    Section {
                        infoRow(Text(String("E2E encryption")), conn.connPQEnabled ? "Quantum resistant" : "Standard")
                    }
                }

                if let contactLink = contact.contactLink {
                    Section {
                        SimpleXLinkQRCode(uri: contactLink)
                        Button {
                            showShareSheet(items: [simplexChatLink(contactLink)])
                        } label: {
                            Label("Share address", systemImage: "square.and.arrow.up")
                        }
                    } header: {
                        Text("Address")
                            .foregroundColor(theme.colors.secondary)
                    } footer: {
                        Text("You can share this address with your contacts to let them connect with **\(contact.displayName)**.")
                            .foregroundColor(theme.colors.secondary)
                    }
                }

                if contact.ready && contact.active {
                    Section(header: Text("Servers").foregroundColor(theme.colors.secondary)) {
                        networkStatusRow()
                            .onTapGesture {
                                alert = .networkStatusAlert
                            }
                        if let connStats = connectionStats {
                            Button("Change receiving address") {
                                alert = .switchAddressAlert
                            }
                            .disabled(
                                connStats.rcvQueuesInfo.contains { $0.rcvSwitchStatus != nil }
                                || connStats.ratchetSyncSendProhibited
                            )
                            if connStats.rcvQueuesInfo.contains(where: { $0.rcvSwitchStatus != nil }) {
                                Button("Abort changing address") {
                                    alert = .abortSwitchAddressAlert
                                }
                                .disabled(
                                    connStats.rcvQueuesInfo.contains { $0.rcvSwitchStatus != nil && !$0.canAbortSwitch }
                                    || connStats.ratchetSyncSendProhibited
                                )
                            }
                            smpServers("Receiving via", connStats.rcvQueuesInfo.map { $0.rcvServer }, theme.colors.secondary)
                            smpServers("Sending via", connStats.sndQueuesInfo.map { $0.sndServer }, theme.colors.secondary)
                        }
                    }
                }

                Section {
                    clearChatButton()
                    deleteContactButton()
                }

                if developerTools {
                    Section(header: Text("For console").foregroundColor(theme.colors.secondary)) {
                        infoRow("Local name", chat.chatInfo.localDisplayName)
                        infoRow("Database ID", "\(chat.chatInfo.apiId)")
                        Button ("Debug delivery") {
                            Task {
                                do {
                                    let info = queueInfoText(try await apiContactQueueInfo(chat.chatInfo.apiId))
                                    await MainActor.run { alert = .queueInfo(info: info) }
                                } catch let e {
                                    logger.error("apiContactQueueInfo error: \(responseError(e))")
                                    let a = getErrorAlert(e, "Error")
                                    await MainActor.run { alert = .error(title: a.title, error: a.message) }
                                }
                            }
                        }
                    }
                }
            }
            .modifier(ThemedBackground(grouped: true))
            .navigationBarHidden(true)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onAppear {
            if let currentUser = chatModel.currentUser {
                sendReceiptsUserDefault = currentUser.sendRcptsContacts
            }
            sendReceipts = SendReceipts.fromBool(contact.chatSettings.sendRcpts, userDefault: sendReceiptsUserDefault)
        }
        .alert(item: $alert) { alertItem in
            switch(alertItem) {
            case .clearChatAlert: return clearChatAlert()
            case .networkStatusAlert: return networkStatusAlert()
            case .switchAddressAlert: return switchAddressAlert(switchContactAddress)
            case .abortSwitchAddressAlert: return abortSwitchAddressAlert(abortSwitchContactAddress)
            case .syncConnectionForceAlert: return syncConnectionForceAlert({ syncContactConnection(force: true) })
            case let .queueInfo(info): return queueInfoAlert(info)
            case let .error(title, error): return mkAlert(title: title, message: error)
            }
        }
        .actionSheet(isPresented: $showDeleteContactActionSheet) {
            if contact.sndReady && contact.active {
                return ActionSheet(
                    title: Text("Delete contact?\nThis cannot be undone!"),
                    buttons: [
                        .destructive(Text("Delete and notify contact")) { deleteContact(notify: true) },
                        .destructive(Text("Delete")) { deleteContact(notify: false) },
                        .cancel()
                    ]
                )
            } else {
                return ActionSheet(
                    title: Text("Delete contact?\nThis cannot be undone!"),
                    buttons: [
                        .destructive(Text("Delete")) { deleteContact() },
                        .cancel()
                    ]
                )
            }
        }
    }

    private func contactInfoHeader() -> some View {
        VStack {
            let cInfo = chat.chatInfo
            ChatInfoImage(chat: chat, size: 192, color: Color(uiColor: .tertiarySystemFill))
                .padding(.top, 12)
                .padding()
            if contact.verified {
                (
                    Text(Image(systemName: "checkmark.shield"))
                        .foregroundColor(theme.colors.secondary)
                        .font(.title2)
                    + Text(" ")
                    + Text(contact.profile.displayName)
                        .font(.largeTitle)
                )
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .padding(.bottom, 2)
            } else {
                Text(contact.profile.displayName)
                    .font(.largeTitle)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .padding(.bottom, 2)
            }
            if cInfo.fullName != "" && cInfo.fullName != cInfo.displayName && cInfo.fullName != contact.profile.displayName {
                Text(cInfo.fullName)
                    .font(.title2)
                    .multilineTextAlignment(.center)
                    .lineLimit(4)
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private func localAliasTextEdit() -> some View {
        TextField("Set contact name…", text: $localAlias)
            .disableAutocorrection(true)
            .focused($aliasTextFieldFocused)
            .submitLabel(.done)
            .onChange(of: aliasTextFieldFocused) { focused in
                if !focused {
                    setContactAlias()
                }
            }
            .onSubmit {
                setContactAlias()
            }
            .multilineTextAlignment(.center)
            .foregroundColor(theme.colors.secondary)
    }

    private func setContactAlias() {
        Task {
            do {
                if let contact = try await apiSetContactAlias(contactId: chat.chatInfo.apiId, localAlias: localAlias) {
                    await MainActor.run {
                        chatModel.updateContact(contact)
                    }
                }
            } catch {
                logger.error("setContactAlias error: \(responseError(error))")
            }
        }
    }

    private func verifyCodeButton(_ code: String) -> some View {
        NavigationLink {
            VerifyCodeView(
                displayName: contact.displayName,
                connectionCode: code,
                connectionVerified: contact.verified,
                verify: { code in
                    if let r = apiVerifyContact(chat.chatInfo.apiId, connectionCode: code) {
                        let (verified, existingCode) = r
                        contact.activeConn?.connectionCode = verified ? SecurityCode(securityCode: existingCode, verifiedAt: .now) : nil
                        connectionCode = existingCode
                        DispatchQueue.main.async {
                            chat.chatInfo = .direct(contact: contact)
                        }
                        return r
                    }
                    return nil
                }
            )
            .navigationBarTitleDisplayMode(.inline)
            .navigationTitle("Security code")
            .modifier(ThemedBackground(grouped: true))
        } label: {
            Label(
                contact.verified ? "View security code" : "Verify security code",
                systemImage: contact.verified ? "checkmark.shield" : "shield"
            )
        }
    }

    private func contactPreferencesButton() -> some View {
        NavigationLink {
            ContactPreferencesView(
                contact: $contact,
                featuresAllowed: contactUserPrefsToFeaturesAllowed(contact.mergedPreferences),
                currentFeaturesAllowed: contactUserPrefsToFeaturesAllowed(contact.mergedPreferences)
            )
            .navigationBarTitle("Contact preferences")
            .modifier(ThemedBackground(grouped: true))
            .navigationBarTitleDisplayMode(.large)
        } label: {
            Label("Contact preferences", systemImage: "switch.2")
        }
    }

    private func sendReceiptsOption() -> some View {
        Picker(selection: $sendReceipts) {
            ForEach([.yes, .no, .userDefault(sendReceiptsUserDefault)]) { (opt: SendReceipts) in
                Text(opt.text)
            }
        } label: {
            Label("Send receipts", systemImage: "checkmark.message")
        }
        .frame(height: 36)
        .onChange(of: sendReceipts) { _ in
            setSendReceipts()
        }
    }

    private func setSendReceipts() {
        var chatSettings = chat.chatInfo.chatSettings ?? ChatSettings.defaults
        chatSettings.sendRcpts = sendReceipts.bool()
        updateChatSettings(chat, chatSettings: chatSettings)
    }

    private func synchronizeConnectionButton() -> some View {
        Button {
            syncContactConnection(force: false)
        } label: {
            Label("Fix connection", systemImage: "exclamationmark.arrow.triangle.2.circlepath")
                .foregroundColor(.orange)
        }
    }

    private func synchronizeConnectionButtonForce() -> some View {
        Button {
            alert = .syncConnectionForceAlert
        } label: {
            Label("Renegotiate encryption", systemImage: "exclamationmark.triangle")
                .foregroundColor(.red)
        }
    }

    private func networkStatusRow() -> some View {
        HStack {
            Text("Network status")
            Image(systemName: "info.circle")
                .foregroundColor(theme.colors.primary)
                .font(.system(size: 14))
            Spacer()
            Text(chatModel.contactNetworkStatus(contact).statusString)
                .foregroundColor(theme.colors.secondary)
            serverImage()
        }
    }

    private func serverImage() -> some View {
        let status = chatModel.contactNetworkStatus(contact)
        return Image(systemName: status.imageName)
            .foregroundColor(status == .connected ? .green : theme.colors.secondary)
            .font(.system(size: 12))
    }

    private func deleteContactButton() -> some View {
        Button(role: .destructive) {
            showDeleteContactActionSheet = true
        } label: {
            Label("Delete contact", systemImage: "trash")
                .foregroundColor(Color.red)
        }
    }

    private func clearChatButton() -> some View {
        Button() {
            alert = .clearChatAlert
        } label: {
            Label("Clear conversation", systemImage: "gobackward")
                .foregroundColor(Color.orange)
        }
    }

    private func deleteContact(notify: Bool? = nil) {
        Task {
            do {
                try await apiDeleteChat(type: chat.chatInfo.chatType, id: chat.chatInfo.apiId, notify: notify)
                await MainActor.run {
                    dismiss()
                    chatModel.chatId = nil
                    chatModel.removeChat(chat.chatInfo.id)
                }
            } catch let error {
                logger.error("deleteContactAlert apiDeleteChat error: \(responseError(error))")
                let a = getErrorAlert(error, "Error deleting contact")
                await MainActor.run {
                    alert = .error(title: a.title, error: a.message)
                }
            }
        }
    }

    private func clearChatAlert() -> Alert {
        Alert(
            title: Text("Clear conversation?"),
            message: Text("All messages will be deleted - this cannot be undone! The messages will be deleted ONLY for you."),
            primaryButton: .destructive(Text("Clear")) {
                Task {
                    await clearChat(chat)
                    await MainActor.run { dismiss() }
                }
            },
            secondaryButton: .cancel()
        )
    }

    private func networkStatusAlert() -> Alert {
        Alert(
            title: Text("Network status"),
            message: Text(chatModel.contactNetworkStatus(contact).statusExplanation)
        )
    }

    private func switchContactAddress() {
        Task {
            do {
                let stats = try apiSwitchContact(contactId: contact.apiId)
                connectionStats = stats
                await MainActor.run {
                    chatModel.updateContactConnectionStats(contact, stats)
                    dismiss()
                }
            } catch let error {
                logger.error("switchContactAddress apiSwitchContact error: \(responseError(error))")
                let a = getErrorAlert(error, "Error changing address")
                await MainActor.run {
                    alert = .error(title: a.title, error: a.message)
                }
            }
        }
    }

    private func abortSwitchContactAddress() {
        Task {
            do {
                let stats = try apiAbortSwitchContact(contact.apiId)
                connectionStats = stats
                await MainActor.run {
                    chatModel.updateContactConnectionStats(contact, stats)
                }
            } catch let error {
                logger.error("abortSwitchContactAddress apiAbortSwitchContact error: \(responseError(error))")
                let a = getErrorAlert(error, "Error aborting address change")
                await MainActor.run {
                    alert = .error(title: a.title, error: a.message)
                }
            }
        }
    }

    private func syncContactConnection(force: Bool) {
        Task {
            do {
                let stats = try apiSyncContactRatchet(contact.apiId, force)
                connectionStats = stats
                await MainActor.run {
                    chatModel.updateContactConnectionStats(contact, stats)
                    dismiss()
                }
            } catch let error {
                logger.error("syncContactConnection apiSyncContactRatchet error: \(responseError(error))")
                let a = getErrorAlert(error, "Error synchronizing connection")
                await MainActor.run {
                    alert = .error(title: a.title, error: a.message)
                }
            }
        }
    }
}

struct ChatWallpaperEditorSheet: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var theme: AppTheme
    @State private var globalThemeUsed: Bool = false
    @State var chat: Chat
    @State private var themes: ThemeModeOverrides

    init(chat: Chat) {
        self.chat = chat
        self.themes = if case let ChatInfo.direct(contact) = chat.chatInfo, let uiThemes = contact.uiThemes {
            uiThemes
        } else if case let ChatInfo.group(groupInfo) = chat.chatInfo, let uiThemes = groupInfo.uiThemes {
            uiThemes
        } else {
            ThemeModeOverrides()
        }
    }

    var body: some View {
        let preferred = themes.preferredMode(!theme.colors.isLight)
        let initialTheme = preferred ?? ThemeManager.defaultActiveTheme(ChatModel.shared.currentUser?.uiThemes, themeOverridesDefault.get())
        ChatWallpaperEditor(
            initialTheme: initialTheme,
            themeModeOverride: initialTheme,
            applyToMode: themes.light == themes.dark ? nil : initialTheme.mode,
            globalThemeUsed: $globalThemeUsed,
            save: { applyToMode, newTheme in
                await save(applyToMode, newTheme, $chat)
            }
        )
        .navigationTitle("Chat theme")
        .modifier(ThemedBackground(grouped: true))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            globalThemeUsed = preferred == nil
        }
        .onChange(of: theme.base.mode) { _ in
            globalThemeUsed = themesFromChat(chat).preferredMode(!theme.colors.isLight) == nil
        }
        .onChange(of: ChatModel.shared.chatId) { _ in
            dismiss()
        }
    }

    private func themesFromChat(_ chat: Chat) -> ThemeModeOverrides {
        if case let ChatInfo.direct(contact) = chat.chatInfo, let uiThemes = contact.uiThemes {
            uiThemes
        } else if case let ChatInfo.group(groupInfo) = chat.chatInfo, let uiThemes = groupInfo.uiThemes {
            uiThemes
        } else {
            ThemeModeOverrides()
        }
    }

    private static var updateBackendTask: Task = Task {}
    private func save(
        _ applyToMode: DefaultThemeMode?,
        _ newTheme: ThemeModeOverride?,
        _ chat: Binding<Chat>
    ) async {
        let unchangedThemes: ThemeModeOverrides = themesFromChat(chat.wrappedValue)
        var wallpaperFiles = Set([unchangedThemes.light?.wallpaper?.imageFile, unchangedThemes.dark?.wallpaper?.imageFile])
        var changedThemes: ThemeModeOverrides? = unchangedThemes
        let light: ThemeModeOverride? = if let newTheme {
            ThemeModeOverride(mode: DefaultThemeMode.light, colors: newTheme.colors, wallpaper: newTheme.wallpaper?.withFilledWallpaperPath())
        } else {
            nil
        }
        let dark: ThemeModeOverride? = if let newTheme {
            ThemeModeOverride(mode: DefaultThemeMode.dark, colors: newTheme.colors, wallpaper: newTheme.wallpaper?.withFilledWallpaperPath())
        } else {
            nil
        }

        if let applyToMode {
            switch applyToMode {
            case DefaultThemeMode.light:
                changedThemes?.light = light
            case DefaultThemeMode.dark:
                changedThemes?.dark = dark
            }
        } else {
            changedThemes?.light = light
            changedThemes?.dark = dark
        }
        if changedThemes?.light != nil || changedThemes?.dark != nil {
            let light = changedThemes?.light
            let dark = changedThemes?.dark
            let currentMode = CurrentColors.base.mode
            // same image file for both modes, copy image to make them as different files
            if var light, var dark, let lightWallpaper = light.wallpaper, let darkWallpaper = dark.wallpaper, let lightImageFile = lightWallpaper.imageFile, let darkImageFile = darkWallpaper.imageFile, lightWallpaper.imageFile == darkWallpaper.imageFile {
                let imageFile = if currentMode == DefaultThemeMode.light {
                    darkImageFile
                } else {
                    lightImageFile
                }
                let filePath = saveWallpaperFile(url: getWallpaperFilePath(imageFile))
                if currentMode == DefaultThemeMode.light {
                    dark.wallpaper?.imageFile = filePath
                    changedThemes = ThemeModeOverrides(light: changedThemes?.light, dark: dark)
                } else {
                    light.wallpaper?.imageFile = filePath
                    changedThemes = ThemeModeOverrides(light: light, dark: changedThemes?.dark)
                }
            }
        } else {
            changedThemes = nil
        }
        wallpaperFiles.remove(changedThemes?.light?.wallpaper?.imageFile)
        wallpaperFiles.remove(changedThemes?.dark?.wallpaper?.imageFile)
        wallpaperFiles.forEach(removeWallpaperFile)

        let changedThemesConstant = changedThemes
        ChatWallpaperEditorSheet.updateBackendTask.cancel()
        ChatWallpaperEditorSheet.updateBackendTask = Task {
            do {
                try await Task.sleep(nanoseconds: 300_000000)
                if await apiSetChatUIThemes(chatId: chat.id, themes: changedThemesConstant) {
                    if case var ChatInfo.direct(contact) = chat.wrappedValue.chatInfo {
                        contact.uiThemes = changedThemesConstant
                        await MainActor.run {
                            ChatModel.shared.updateChatInfo(ChatInfo.direct(contact: contact))
                            chat.wrappedValue = Chat.init(chatInfo: ChatInfo.direct(contact: contact))
                            themes = themesFromChat(chat.wrappedValue)
                        }
                    } else if case var ChatInfo.group(groupInfo) = chat.wrappedValue.chatInfo {
                        groupInfo.uiThemes = changedThemesConstant

                        await MainActor.run {
                            ChatModel.shared.updateChatInfo(ChatInfo.group(groupInfo: groupInfo))
                            chat.wrappedValue = Chat.init(chatInfo: ChatInfo.group(groupInfo: groupInfo))
                            themes = themesFromChat(chat.wrappedValue)
                        }
                    }
                }
            } catch {
                // canceled task
            }
        }
    }
}

func switchAddressAlert(_ switchAddress: @escaping () -> Void) -> Alert {
    Alert(
        title: Text("Change receiving address?"),
        message: Text("Receiving address will be changed to a different server. Address change will complete after sender comes online."),
        primaryButton: .default(Text("Change"), action: switchAddress),
        secondaryButton: .cancel()
    )
}

func abortSwitchAddressAlert(_ abortSwitchAddress: @escaping () -> Void) -> Alert {
    Alert(
        title: Text("Abort changing address?"),
        message: Text("Address change will be aborted. Old receiving address will be used."),
        primaryButton: .destructive(Text("Abort"), action: abortSwitchAddress),
        secondaryButton: .cancel()
    )
}

func syncConnectionForceAlert(_ syncConnectionForce: @escaping () -> Void) -> Alert {
    Alert(
        title: Text("Renegotiate encryption?"),
        message: Text("The encryption is working and the new encryption agreement is not required. It may result in connection errors!"),
        primaryButton: .destructive(Text("Renegotiate"), action: syncConnectionForce),
        secondaryButton: .cancel()
    )
}

func queueInfoText(_ info: (RcvMsgInfo?, QueueInfo)) -> String {
    let (rcvMsgInfo, qInfo) = info
    var msgInfo: String
    if let rcvMsgInfo { msgInfo = encodeJSON(rcvMsgInfo) } else { msgInfo = "none" }
    return String.localizedStringWithFormat(NSLocalizedString("server queue info: %@\n\nlast received msg: %@", comment: "queue info"), encodeJSON(qInfo), msgInfo)
}

func queueInfoAlert(_ info: String) -> Alert {
    Alert(
        title: Text("Message queue info"),
        message: Text(info),
        primaryButton: .default(Text("Ok")),
        secondaryButton: .default(Text("Copy")) { UIPasteboard.general.string = info }
    )
}

struct ChatInfoView_Previews: PreviewProvider {
    static var previews: some View {
        ChatInfoView(
            chat: Chat(chatInfo: ChatInfo.sampleData.direct, chatItems: []),
            contact: Contact.sampleData,
            connectionStats: Binding.constant(nil),
            customUserProfile: Binding.constant(nil),
            localAlias: "",
            connectionCode: Binding.constant(nil)
        )
    }
}
