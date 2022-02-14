//
//  NtfManager.swift
//  SimpleX
//
//  Created by Evgeny Poberezkin on 08/02/2022.
//  Copyright © 2022 SimpleX Chat. All rights reserved.
//

import Foundation
import UserNotifications
import UIKit

let ntfActionAccept = "NTF_ACT_ACCEPT"

let ntfCategoryContactRequest = "NTF_CAT_CONTACT_REQUEST"
let ntfCategoryContactConnected = "NTF_CAT_CONTACT_CONNECTED"
let ntfCategoryMessageReceived = "NTF_CAT_MESSAGE_RECEIVED"

let appNotificationId = "chat.simplex.app.notification"

private let ntfTimeInterval: TimeInterval = 1

class NtfManager: NSObject, UNUserNotificationCenterDelegate, ObservableObject {
    static let shared = NtfManager()

    private var granted = false
    private var prevNtfTime: Dictionary<ChatId, Date> = [:]


    // Handle notification when app is in background
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler handler: () -> Void) {
        logger.debug("NtfManager.userNotificationCenter: didReceive")
        let content = response.notification.request.content
        let chatModel = ChatModel.shared
        if content.categoryIdentifier == ntfCategoryContactRequest && response.actionIdentifier == ntfActionAccept,
           let chatId = content.userInfo["chatId"] as? String,
           case let .contactRequest(contactRequest) = chatModel.getChat(chatId)?.chatInfo {
            acceptContactRequest(contactRequest)
        } else {
            chatModel.chatId = content.targetContentIdentifier
        }
        handler()
    }

    // Handle notification when the app is in foreground
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler handler: (UNNotificationPresentationOptions) -> Void) {
        logger.debug("NtfManager.userNotificationCenter: willPresent")
        handler(presentationOptions(notification.request.content))
    }

    private func presentationOptions(_ content: UNNotificationContent) -> UNNotificationPresentationOptions {
        let model = ChatModel.shared
        if UIApplication.shared.applicationState == .active {
            switch content.categoryIdentifier {
            case ntfCategoryMessageReceived:
                if model.chatId == nil {
                    // in the chat list
                    return recentInTheSameChat(content) ? [] : [.sound, .list]
                } else if model.chatId == content.targetContentIdentifier {
                    // in the current chat
                    return recentInTheSameChat(content) ? [] : [.sound, .list]
                } else {
                    // in another chat
                    return recentInTheSameChat(content) ? [.banner, .list] : [.sound, .banner, .list]
                }
            default: return [.sound, .banner, .list]
            }
        } else {
            return [.sound, .banner, .list]
        }
    }

    private func recentInTheSameChat(_ content: UNNotificationContent) -> Bool {
        let now = Date.now
        if let chatId = content.targetContentIdentifier {
            var res: Bool = false
            if let t = prevNtfTime[chatId] { res = t.distance(to: now) < 30 }
            prevNtfTime[chatId] = now
            return res
        }
        return false
    }

    func registerCategories() {
        logger.debug("NtfManager.registerCategories")
        UNUserNotificationCenter.current().setNotificationCategories([
            UNNotificationCategory(
                identifier: ntfCategoryContactRequest,
                actions: [UNNotificationAction(
                    identifier: ntfActionAccept,
                    title: "Accept"
                )],
                intentIdentifiers: [],
                hiddenPreviewsBodyPlaceholder: "New contact request"
            ),
            UNNotificationCategory(
                identifier: ntfCategoryContactConnected,
                actions: [],
                intentIdentifiers: [],
                hiddenPreviewsBodyPlaceholder: "Contact is connected"
            ),
            UNNotificationCategory(
                identifier: ntfCategoryMessageReceived,
                actions: [],
                intentIdentifiers: [],
                hiddenPreviewsBodyPlaceholder: "New message"
            )
        ])
    }

    func requestAuthorization(onDeny handler: (()-> Void)? = nil) {
        logger.debug("NtfManager.requestAuthorization")
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { settings in
            switch settings.authorizationStatus {
            case .denied:
                if let handler = handler { handler() }
                return
            case .authorized:
                self.granted = true
            default:
                center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
                    if let error = error {
                        logger.error("NtfManager.requestAuthorization error \(error.localizedDescription)")
                    } else {
                        self.granted = granted
                    }
                }
            }
        }
        center.delegate = self
    }

    func notifyContactRequest(_ contactRequest: UserContactRequest) {
        logger.debug("NtfManager.notifyContactRequest")
        addNotification(
            categoryIdentifier: ntfCategoryContactRequest,
            title: "\(contactRequest.displayName) wants to connect!",
            body: "Accept contact request from \(contactRequest.chatViewName)?",
            targetContentIdentifier: nil,
            userInfo: ["chatId": contactRequest.id, "contactRequestId": contactRequest.apiId]
        )
    }

    func notifyContactConnected(_ contact: Contact) {
        logger.debug("NtfManager.notifyContactConnected")
        addNotification(
            categoryIdentifier: ntfCategoryContactConnected,
            title: "\(contact.displayName) is connected!",
            body: "You can now send messages to \(contact.chatViewName)",
            targetContentIdentifier: contact.id
//            userInfo: ["chatId": contact.id, "contactId": contact.apiId]
        )
    }

    func notifyMessageReceived(_ cInfo: ChatInfo, _ cItem: ChatItem) {
        logger.debug("NtfManager.notifyMessageReceived")
        addNotification(
            categoryIdentifier: ntfCategoryMessageReceived,
            title: "\(cInfo.chatViewName):",
            body: cItem.content.text,
            targetContentIdentifier: cInfo.id
//            userInfo: ["chatId": cInfo.id, "chatItemId": cItem.id]
        )
    }

    private func addNotification(categoryIdentifier: String, title: String, subtitle: String? = nil, body: String? = nil,
                                 targetContentIdentifier: String? = nil, userInfo: [AnyHashable : Any] = [:]) {
        if !granted { return }
        let content = UNMutableNotificationContent()
        content.categoryIdentifier = categoryIdentifier
        content.title = title
        if let s = subtitle { content.subtitle = s }
        if let s = body { content.body = s }
        content.targetContentIdentifier = targetContentIdentifier
        content.userInfo = userInfo
        content.sound = .default
//        content.interruptionLevel = .active
//        content.relevanceScore = 0.5 // 0-1
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: ntfTimeInterval, repeats: false)
        let request = UNNotificationRequest(identifier: appNotificationId, content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error { logger.error("addNotification error: \(error.localizedDescription)") }
        }
    }

    func removeNotifications(_ ids : [String]){
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: ids)
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ids)
    }
}
