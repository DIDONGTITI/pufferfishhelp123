//
//  NotificationService.swift
//  SimpleX NSE
//
//  Created by Evgeny on 26/04/2022.
//  Copyright © 2022 SimpleX Chat. All rights reserved.
//

import UserNotifications
import OSLog
import SimpleXChat

let logger = Logger()

class NotificationService: UNNotificationServiceExtension {
    var contentHandler: ((UNNotificationContent) -> Void)?
    var bestAttemptContent: UNMutableNotificationContent?

    override func didReceive(_ request: UNNotificationRequest, withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void) {
        logger.debug("NotificationService.didReceive")
        let appState = appStateGroupDefault.get()
        if appState.running  {
            print("userInfo", request.content.userInfo)
            contentHandler(request.content)
            return
        }
        logger.debug("NotificationService: app is in the background")
        self.contentHandler = contentHandler
        bestAttemptContent = (request.content.mutableCopy() as? UNMutableNotificationContent)
        let userInfo = request.content.userInfo
        if let ntfData = userInfo["notificationData"] as? [AnyHashable : Any],
           let nonce = ntfData["nonce"] as? String,
           let encNtfInfo = ntfData["message"] as? String,
           let _ = startChat() {
            apiGetNtfMessage(nonce: nonce, encNtfInfo: encNtfInfo)
            if let content = receiveMessages() {
                contentHandler(content)
                return
            }
        }

        if let bestAttemptContent = bestAttemptContent {
            // Modify the notification content here...
            bestAttemptContent.title = "\(bestAttemptContent.title) [modified]"
            
            contentHandler(bestAttemptContent)
        }
    }
    
    override func serviceExtensionTimeWillExpire() {
        logger.debug("NotificationService.serviceExtensionTimeWillExpire")
        // Called just before the extension will be terminated by the system.
        // Use this as an opportunity to deliver your "best attempt" at modified content, otherwise the original push payload will be used.
        if let contentHandler = contentHandler, let bestAttemptContent =  bestAttemptContent {
            contentHandler(bestAttemptContent)
        }
    }
}

func receivedAppMachMessage(msgId: Int32, msg: String) -> String? {
    logger.debug("MachMessenger: receivedAppMachMessage \"\(msg)\" from App, replying")
    return "reply from NSE to: \(msg)"
}

func startChat() -> User? {
    hs_init(0, nil)
    if let user = apiGetActiveUser() {
        logger.debug("active user \(String(describing: user))")
        do {
            try apiStartChat()
            try apiSetFilesFolder(filesFolder: getAppFilesDirectory().path)
            chatLastStartGroupDefault.set(Date.now)
            return user
        } catch {
            logger.error("NotificationService startChat error: \(responseError(error), privacy: .public)")
        }
    } else {
        logger.debug("no active user")
    }
    return nil
}

func receiveMessages() -> UNNotificationContent? {
    logger.debug("NotificationService receiveMessages started")
    while true {
        if let res = recvSimpleXMsg() {
            logger.debug("NotificationService receiveMessages: \(res.responseType)")
            switch res {
    //        case let .newContactConnection(connection):
    //        case let .contactConnectionDeleted(connection):
            case let .contactConnected(contact):
                return createContactConnectedNtf(contact)
    //        case let .contactConnecting(contact):
    //            TODO profile update
            case let .receivedContactRequest(contactRequest):
                return createContactRequestNtf(contactRequest)
    //        case let .contactUpdated(toContact):
    //            TODO profile updated
            case let .newChatItem(aChatItem):
                let cInfo = aChatItem.chatInfo
                let cItem = aChatItem.chatItem
                return createMessageReceivedNtf(cInfo, cItem)
    //        case let .chatItemUpdated(aChatItem):
    //            TODO message updated
    //            let cInfo = aChatItem.chatInfo
    //            let cItem = aChatItem.chatItem
    //            NtfManager.shared.notifyMessageReceived(cInfo, cItem)
    //        case let .chatItemDeleted(_, toChatItem):
    //            TODO message updated
    //        case let .rcvFileComplete(aChatItem):
    //            TODO file received?
    //            let cInfo = aChatItem.chatInfo
    //            let cItem = aChatItem.chatItem
    //            NtfManager.shared.notifyMessageReceived(cInfo, cItem)
            default:
                logger.debug("NotificationService ignored event: \(res.responseType)")
            }
        } else {
            return nil
        }
    }
}

func apiGetActiveUser() -> User? {
    let _ = getChatCtrl()
    let r = sendSimpleXCmd(.showActiveUser)
    logger.debug("apiGetActiveUser sendSimpleXCmd responce: \(String(describing: r))")
    switch r {
    case let .activeUser(user): return user
    case .chatCmdError(.error(.noActiveUser)): return nil
    default:
        logger.error("NotificationService apiGetActiveUser unexpected response: \(String(describing: r))")
        return nil
    }
}

func apiStartChat() throws {
    let r = sendSimpleXCmd(.startChat(subscribe: false))
    switch r {
    case .chatStarted: return
    case .chatRunning: return
    default: throw r
    }
}

func apiSetFilesFolder(filesFolder: String) throws {
    let r = sendSimpleXCmd(.setFilesFolder(filesFolder: filesFolder))
    if case .cmdOk = r { return }
    throw r
}

func apiGetNtfMessage(nonce: String, encNtfInfo: String) {
    let r = sendSimpleXCmd(.apiGetNtfMessage(nonce: nonce, encNtfInfo: encNtfInfo))
    if case let .ntfMessages(connEntity, msgTs, ntfMessages) = r {
        if let connEntity = connEntity { print("connEntity", connEntity) }
        if let msgTs = msgTs { print("msgTs", msgTs) }
        print("ntfMessages", ntfMessages)
        return
    }
}
