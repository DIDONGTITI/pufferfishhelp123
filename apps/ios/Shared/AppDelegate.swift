//
//  AppDelegate.swift
//  SimpleX
//
//  Created by Evgeny on 30/03/2022.
//  Copyright © 2022 SimpleX Chat. All rights reserved.
//

import Foundation
import UIKit
import SimpleXChat

class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
        logger.debug("AppDelegate: didFinishLaunchingWithOptions")
        application.registerForRemoteNotifications()
        return true
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        let token = deviceToken.map { String(format: "%02hhx", $0) }.joined()
        logger.debug("AppDelegate: didRegisterForRemoteNotificationsWithDeviceToken \(token)")
        let m = ChatModel.shared
        m.deviceToken = token
        let useNotifications = UserDefaults.standard.bool(forKey: "useNotifications")
        if useNotifications {
            Task {
                do {
                    m.tokenStatus = try await apiRegisterToken(token: token, notificationMode: .instant)
                } catch {
                    logger.error("apiRegisterToken error: \(responseError(error))")
                }
            }
        }
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        logger.error("AppDelegate: didFailToRegisterForRemoteNotificationsWithError \(error.localizedDescription)")
    }

    func application(_ application: UIApplication,
                     didReceiveRemoteNotification userInfo: [AnyHashable : Any],
                     fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
        logger.debug("AppDelegate: didReceiveRemoteNotification")
        print("*** userInfo", userInfo)
        if let ntfData = userInfo["notificationData"] as? [AnyHashable : Any],
           UserDefaults.standard.bool(forKey: "useNotifications") {
            if let verification = ntfData["verification"] as? String,
               let nonce = ntfData["nonce"] as? String {
                if let token = ChatModel.shared.deviceToken {
                    logger.debug("AppDelegate: didReceiveRemoteNotification: verification, confirming \(verification)")
                    Task {
                        let m = ChatModel.shared
                        do {
                            if case .active = m.tokenStatus {} else { m.tokenStatus = .confirmed }
                            try await apiVerifyToken(token: token, code: verification, nonce: nonce)
                            m.tokenStatus = .active
                            try await apiIntervalNofication(token: token, interval: 20)
                        } catch {
                            if let cr = error as? ChatResponse, case .chatCmdError(.errorAgent(.NTF(.AUTH))) = cr {
                                m.tokenStatus = .expired
                            }
                            logger.error("AppDelegate: didReceiveRemoteNotification: apiVerifyToken or apiIntervalNofication error: \(responseError(error))")
                        }
                        completionHandler(.newData)
                    }
                } else {
                    completionHandler(.noData)
                }
            } else if let checkMessages = ntfData["checkMessages"] as? Bool, checkMessages {
                // TODO check if app in background
                logger.debug("AppDelegate: didReceiveRemoteNotification: checkMessages")
                // TODO remove
                // NtfManager.shared.notifyCheckingMessages()
                receiveMessages(completionHandler)
            } else if let smpQueue = ntfData["checkMessage"] as? String {
                // TODO check if app in background
                logger.debug("AppDelegate: didReceiveRemoteNotification: checkMessage \(smpQueue)")
                receiveMessages(completionHandler)
            } else {
                completionHandler(.noData)
            }
        } else {
            completionHandler(.noData)
        }
    }

    private func receiveMessages(_ completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
        let complete = BGManager.shared.completionHandler {
            logger.debug("AppDelegate: completed BGManager.receiveMessages")
            completionHandler(.newData)
        }

        BGManager.shared.receiveMessages(complete)
    }
}
