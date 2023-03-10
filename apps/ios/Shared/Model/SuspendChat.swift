//
//  SuspendChat.swift
//  SimpleX (iOS)
//
//  Created by Evgeny on 26/06/2022.
//  Copyright © 2022 SimpleX Chat. All rights reserved.
//

import Foundation
import UIKit
import SimpleXChat

private let suspendLockQueue = DispatchQueue(label: "chat.simplex.app.suspend.lock")

let appSuspendTimeout: Int = 15 // seconds

let bgSuspendTimeout: Int = 5 // seconds

let terminationTimeout: Int = 3 // seconds

private func _suspendChat(timeout: Int) {
    if ChatModel.ok {
        appStateGroupDefault.set(.suspending)
        apiSuspendChat(timeoutMicroseconds: timeout * 1000000)
        let endTask = beginBGTask(chatSuspended)
        DispatchQueue.global().asyncAfter(deadline: .now() + Double(timeout) + 1, execute: endTask)
    } else {
        appStateGroupDefault.set(.suspended)
    }
}

func suspendChat() {
    suspendLockQueue.sync {
        if appStateGroupDefault.get() != .stopped {
            _suspendChat(timeout: appSuspendTimeout)
        }
    }
}

func suspendBgRefresh() {
    suspendLockQueue.sync {
        if case .bgRefresh = appStateGroupDefault.get()  {
            _suspendChat(timeout: bgSuspendTimeout)
        }
    }
}

func terminateChat() {
    suspendLockQueue.sync {
        switch appStateGroupDefault.get() {
        case .suspending:
            // suspend instantly if already suspending
            _chatSuspended()
            if ChatModel.ok { apiSuspendChat(timeoutMicroseconds: 0) }
        case .stopped: ()
        default:
            _suspendChat(timeout: terminationTimeout)
        }
    }
}

func chatSuspended() {
    suspendLockQueue.sync {
        if case .suspending = appStateGroupDefault.get() {
            _chatSuspended()
        }
    }
}

private func _chatSuspended() {
    logger.debug("_chatSuspended")
    appStateGroupDefault.set(.suspended)
    if ChatModel.shared.chatRunning == true {
        ChatReceiver.shared.stop()
    }
}

func activateChat(appState: AppState = .active) {
    suspendLockQueue.sync {
        appStateGroupDefault.set(appState)
        if ChatModel.ok { apiActivateChat() }
    }
}

func initChatAndMigrate() {
    let m = ChatModel.shared
    if (!m.chatInitialized) {
        do {
            m.v3DBMigration = v3DBMigrationDefault.get()
            try initializeChat(start: m.v3DBMigration.startChat)
        } catch let error {
            fatalError("Failed to start or load chats: \(responseError(error))")
        }
    }
}

func startChatAndActivate() {
    if ChatModel.shared.chatRunning == true {
        ChatReceiver.shared.start()
    }
    if .active != appStateGroupDefault.get()  {
        activateChat()
    }
}