//
//  SimpleXApp.swift
//  Shared
//
//  Created by Evgeny Poberezkin on 17/01/2022.
//

import SwiftUI
import OSLog
import SimpleXChat

let logger = Logger()

@main
struct SimpleXApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var chatModel = ChatModel.shared
    @ObservedObject var alertManager = AlertManager.shared
    @Environment(\.scenePhase) var scenePhase
    @AppStorage(DEFAULT_PERFORM_LA) private var prefPerformLA = false
    @State private var userAuthorized: Bool?
    @State private var doAuthenticate = false
    @State private var enteredBackground: TimeInterval? = nil

    init() {
        hs_init(0, nil)
        UserDefaults.standard.register(defaults: appDefaults)
        setGroupDefaults()
        registerGroupDefaults()
        setDbContainer()
        BGManager.shared.register()
        NtfManager.shared.registerCategories()
    }

    var body: some Scene {
        return WindowGroup {
            ContentView(doAuthenticate: $doAuthenticate, userAuthorized: $userAuthorized)
                .environmentObject(chatModel)
                .onOpenURL { url in
                    logger.debug("ContentView.onOpenURL: \(url)")
                    chatModel.appOpenUrl = url
                }
                .onAppear() {
                    initChatAndMigrate()
                }
                .onChange(of: scenePhase) { phase in
                    logger.debug("scenePhase was \(String(describing: scenePhase)), now \(String(describing: phase))")
                    switch (phase) {
                    case .background:
                        if CallController.useCallKit() && chatModel.activeCall != nil {
                            CallController.shared.onEndCall = {
                                suspendChat()
                                BGManager.shared.schedule()
                            }
                        } else {
                            suspendChat()
                            BGManager.shared.schedule()
                        }
                        if userAuthorized == true {
                            enteredBackground = ProcessInfo.processInfo.systemUptime
                        }
                        doAuthenticate = false
                        NtfManager.shared.setNtfBadgeCount(chatModel.totalUnreadCountForAllUsers())
                    case .active:
                        CallController.shared.onEndCall = nil
                        let appState = appStateGroupDefault.get()
                        startChatAndActivate()
                        if appState.inactive && chatModel.chatRunning == true {
                            updateChats()
                            updateCallInvitations()
                        }
                        doAuthenticate = authenticationExpired()
                    default:
                        break
                    }
                }
        }
    }

    private func setDbContainer() {
// Uncomment and run once to open DB in app documents folder:
//         dbContainerGroupDefault.set(.documents)
//         v3DBMigrationDefault.set(.offer)
// to create database in app documents folder also uncomment:
//         let legacyDatabase = true
        let legacyDatabase = hasLegacyDatabase()
        if legacyDatabase, case .documents = dbContainerGroupDefault.get() {
            dbContainerGroupDefault.set(.documents)
            setMigrationState(.offer)
            logger.debug("SimpleXApp init: using legacy DB in documents folder: \(getAppDatabasePath(), privacy: .public)*.db")
        } else {
            dbContainerGroupDefault.set(.group)
            setMigrationState(.ready)
            logger.debug("SimpleXApp init: using DB in app group container: \(getAppDatabasePath(), privacy: .public)*.db")
            logger.debug("SimpleXApp init: legacy DB\(legacyDatabase ? "" : " not", privacy: .public) present")
        }
    }

    private func setMigrationState(_ state: V3DBMigrationState) {
        if case .migrated = v3DBMigrationDefault.get() { return }
        v3DBMigrationDefault.set(state)
    }

    private func authenticationExpired() -> Bool {
        if let enteredBackground = enteredBackground {
            return ProcessInfo.processInfo.systemUptime - enteredBackground >= 30
        } else {
            return true
        }
    }

    private func updateChats() {
        do {
            let chats = try apiGetChats()
            chatModel.updateChats(with: chats)
            if let id = chatModel.chatId,
               let chat = chatModel.getChat(id) {
                loadChat(chat: chat)
            }
            if let chatId = chatModel.ntfContactRequest {
                chatModel.ntfContactRequest = nil
                if case let .contactRequest(contactRequest) = chatModel.getChat(chatId)?.chatInfo {
                    Task { await acceptContactRequest(contactRequest) }
                }
            }
        } catch let error {
            logger.error("apiGetChats: cannot update chats \(responseError(error))")
        }
    }

    private func updateCallInvitations() {
        do {
            try refreshCallInvitations()
        } catch let error {
            logger.error("apiGetCallInvitations: cannot update call invitations \(responseError(error))")
        }
    }
}
