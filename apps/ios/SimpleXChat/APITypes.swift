//
//  SimpleXAPI.swift
//  SimpleX NSE
//
//  Created by Evgeny on 26/04/2022.
//  Copyright © 2022 SimpleX Chat. All rights reserved.
//

import Foundation
import SwiftUI

let jsonDecoder = getJSONDecoder()
let jsonEncoder = getJSONEncoder()

public enum ChatCommand {
    case showActiveUser
    case createActiveUser(profile: Profile)
    case startChat(subscribe: Bool)
    case apiStopChat
    case apiActivateChat
    case apiSuspendChat(timeoutMicroseconds: Int)
    case setFilesFolder(filesFolder: String)
    case apiExportArchive(config: ArchiveConfig)
    case apiImportArchive(config: ArchiveConfig) 
    case apiDeleteStorage
    case apiGetChats
    case apiGetChat(type: ChatType, id: Int64)
    case apiSendMessage(type: ChatType, id: Int64, file: String?, quotedItemId: Int64?, msg: MsgContent)
    case apiUpdateChatItem(type: ChatType, id: Int64, itemId: Int64, msg: MsgContent)
    case apiDeleteChatItem(type: ChatType, id: Int64, itemId: Int64, mode: CIDeleteMode)
    case apiGetNtfToken
    case apiRegisterToken(token: DeviceToken, notificationMode: NotificationsMode)
    case apiVerifyToken(token: DeviceToken, nonce: String, code: String)
    case apiDeleteToken(token: DeviceToken)
    case apiGetNtfMessage(nonce: String, encNtfInfo: String)
    case getUserSMPServers
    case setUserSMPServers(smpServers: [String])
    case addContact
    case connect(connReq: String)
    case apiDeleteChat(type: ChatType, id: Int64)
    case apiClearChat(type: ChatType, id: Int64)
    case apiUpdateProfile(profile: Profile)
    case createMyAddress
    case deleteMyAddress
    case showMyAddress
    case apiAcceptContact(contactReqId: Int64)
    case apiRejectContact(contactReqId: Int64)
    // WebRTC calls
    case apiSendCallInvitation(contact: Contact, callType: CallType)
    case apiRejectCall(contact: Contact)
    case apiSendCallOffer(contact: Contact, callOffer: WebRTCCallOffer)
    case apiSendCallAnswer(contact: Contact, answer: WebRTCSession)
    case apiSendCallExtraInfo(contact: Contact, extraInfo: WebRTCExtraInfo)
    case apiEndCall(contact: Contact)
    case apiGetCallInvitations
    case apiCallStatus(contact: Contact, callStatus: WebRTCCallStatus)
    case apiChatRead(type: ChatType, id: Int64, itemRange: (Int64, Int64))
    case receiveFile(fileId: Int64)
    case string(String)

    public var cmdString: String {
        get {
            switch self {
            case .showActiveUser: return "/u"
            case let .createActiveUser(profile): return "/u \(profile.displayName) \(profile.fullName)"
            case let .startChat(subscribe): return "/_start subscribe=\(subscribe ? "on" : "off")"
            case .apiStopChat: return "/_stop"
            case .apiActivateChat: return "/_app activate"
            case let .apiSuspendChat(timeoutMicroseconds): return "/_app suspend \(timeoutMicroseconds)"
            case let .setFilesFolder(filesFolder): return "/_files_folder \(filesFolder)"
            case let .apiExportArchive(cfg): return "/_db export \(encodeJSON(cfg))"
            case let .apiImportArchive(cfg): return "/_db import \(encodeJSON(cfg))"
            case .apiDeleteStorage: return "/_db delete"
            case .apiGetChats: return "/_get chats pcc=on"
            case let .apiGetChat(type, id): return "/_get chat \(ref(type, id)) count=100"
            case let .apiSendMessage(type, id, file, quotedItemId, mc):
                let msg = encodeJSON(ComposedMessage(filePath: file, quotedItemId: quotedItemId, msgContent: mc))
                return "/_send \(ref(type, id)) json \(msg)"
            case let .apiUpdateChatItem(type, id, itemId, mc): return "/_update item \(ref(type, id)) \(itemId) \(mc.cmdString)"
            case let .apiDeleteChatItem(type, id, itemId, mode): return "/_delete item \(ref(type, id)) \(itemId) \(mode.rawValue)"
            case .apiGetNtfToken: return "/_ntf get "
            case let .apiRegisterToken(token, notificationMode): return "/_ntf register \(token.cmdString) \(notificationMode.rawValue)"
            case let .apiVerifyToken(token, nonce, code): return "/_ntf verify \(token.cmdString) \(nonce) \(code)"
            case let .apiDeleteToken(token): return "/_ntf delete \(token.cmdString)"
            case let .apiGetNtfMessage(nonce, encNtfInfo): return "/_ntf message \(nonce) \(encNtfInfo)"
            case .getUserSMPServers: return "/smp_servers"
            case let .setUserSMPServers(smpServers): return "/smp_servers \(smpServersStr(smpServers: smpServers))"
            case .addContact: return "/connect"
            case let .connect(connReq): return "/connect \(connReq)"
            case let .apiDeleteChat(type, id): return "/_delete \(ref(type, id))"
            case let .apiClearChat(type, id): return "/_clear chat \(ref(type, id))"
            case let .apiUpdateProfile(profile): return "/_profile \(encodeJSON(profile))"
            case .createMyAddress: return "/address"
            case .deleteMyAddress: return "/delete_address"
            case .showMyAddress: return "/show_address"
            case let .apiAcceptContact(contactReqId): return "/_accept \(contactReqId)"
            case let .apiRejectContact(contactReqId): return "/_reject \(contactReqId)"
            case let .apiSendCallInvitation(contact, callType): return "/_call invite @\(contact.apiId) \(encodeJSON(callType))"
            case let .apiRejectCall(contact): return "/_call reject @\(contact.apiId)"
            case let .apiSendCallOffer(contact, callOffer): return "/_call offer @\(contact.apiId) \(encodeJSON(callOffer))"
            case let .apiSendCallAnswer(contact, answer): return "/_call answer @\(contact.apiId) \(encodeJSON(answer))"
            case let .apiSendCallExtraInfo(contact, extraInfo): return "/_call extra @\(contact.apiId) \(encodeJSON(extraInfo))"
            case let .apiEndCall(contact): return "/_call end @\(contact.apiId)"
            case .apiGetCallInvitations: return "/_call get"
            case let .apiCallStatus(contact, callStatus): return "/_call status @\(contact.apiId) \(callStatus.rawValue)"
            case let .apiChatRead(type, id, itemRange: (from, to)): return "/_read chat \(ref(type, id)) from=\(from) to=\(to)"
            case let .receiveFile(fileId): return "/freceive \(fileId)"
            case let .string(str): return str
            }
        }
    }

    public var cmdType: String {
        get {
            switch self {
            case .showActiveUser: return "showActiveUser"
            case .createActiveUser: return "createActiveUser"
            case .startChat: return "startChat"
            case .apiStopChat: return "apiStopChat"
            case .apiActivateChat: return "apiActivateChat"
            case .apiSuspendChat: return "apiSuspendChat"
            case .setFilesFolder: return "setFilesFolder"
            case .apiExportArchive: return "apiExportArchive"
            case .apiImportArchive: return "apiImportArchive"
            case .apiDeleteStorage: return "apiDeleteStorage"
            case .apiGetChats: return "apiGetChats"
            case .apiGetChat: return "apiGetChat"
            case .apiSendMessage: return "apiSendMessage"
            case .apiUpdateChatItem: return "apiUpdateChatItem"
            case .apiDeleteChatItem: return "apiDeleteChatItem"
            case .apiGetNtfToken: return "apiGetNtfToken"
            case .apiRegisterToken: return "apiRegisterToken"
            case .apiVerifyToken: return "apiVerifyToken"
            case .apiDeleteToken: return "apiDeleteToken"
            case .apiGetNtfMessage: return "apiGetNtfMessage"
            case .getUserSMPServers: return "getUserSMPServers"
            case .setUserSMPServers: return "setUserSMPServers"
            case .addContact: return "addContact"
            case .connect: return "connect"
            case .apiDeleteChat: return "apiDeleteChat"
            case .apiClearChat: return "apiClearChat"
            case .apiUpdateProfile: return "apiUpdateProfile"
            case .createMyAddress: return "createMyAddress"
            case .deleteMyAddress: return "deleteMyAddress"
            case .showMyAddress: return "showMyAddress"
            case .apiAcceptContact: return "apiAcceptContact"
            case .apiRejectContact: return "apiRejectContact"
            case .apiSendCallInvitation: return "apiSendCallInvitation"
            case .apiRejectCall: return "apiRejectCall"
            case .apiSendCallOffer: return "apiSendCallOffer"
            case .apiSendCallAnswer: return "apiSendCallAnswer"
            case .apiSendCallExtraInfo: return "apiSendCallExtraInfo"
            case .apiEndCall: return "apiEndCall"
            case .apiGetCallInvitations: return "apiGetCallInvitations"
            case .apiCallStatus: return "apiCallStatus"
            case .apiChatRead: return "apiChatRead"
            case .receiveFile: return "receiveFile"
            case .string: return "console command"
            }
        }
    }

    func ref(_ type: ChatType, _ id: Int64) -> String {
        "\(type.rawValue)\(id)"
    }

    func smpServersStr(smpServers: [String]) -> String {
        smpServers.isEmpty ? "default" : smpServers.joined(separator: ",")
    }
}

struct APIResponse: Decodable {
    var resp: ChatResponse
}

public enum ChatResponse: Decodable, Error {
    case response(type: String, json: String)
    case activeUser(user: User)
    case chatStarted
    case chatRunning
    case chatStopped
    case chatSuspended
    case apiChats(chats: [ChatData])
    case apiChat(chat: ChatData)
    case userSMPServers(smpServers: [String])
    case invitation(connReqInvitation: String)
    case sentConfirmation
    case sentInvitation
    case contactAlreadyExists(contact: Contact)
    case contactDeleted(contact: Contact)
    case chatCleared(chatInfo: ChatInfo)
    case userProfileNoChange
    case userProfileUpdated(fromProfile: Profile, toProfile: Profile)
    case userContactLink(connReqContact: String)
    case userContactLinkCreated(connReqContact: String)
    case userContactLinkDeleted
    case contactConnected(contact: Contact)
    case contactConnecting(contact: Contact)
    case receivedContactRequest(contactRequest: UserContactRequest)
    case acceptingContactRequest(contact: Contact)
    case contactRequestRejected
    case contactUpdated(toContact: Contact)
    case contactsSubscribed(server: String, contactRefs: [ContactRef])
    case contactsDisconnected(server: String, contactRefs: [ContactRef])
    case contactSubError(contact: Contact, chatError: ChatError)
    case contactSubSummary(contactSubscriptions: [ContactSubStatus])
    case groupSubscribed(groupInfo: GroupInfo)
    case memberSubErrors(memberSubErrors: [MemberSubError])
    case groupEmpty(groupInfo: GroupInfo)
    case userContactLinkSubscribed
    case newChatItem(chatItem: AChatItem)
    case chatItemStatusUpdated(chatItem: AChatItem)
    case chatItemUpdated(chatItem: AChatItem)
    case chatItemDeleted(deletedChatItem: AChatItem, toChatItem: AChatItem)
    // receiving file events
    case rcvFileAccepted(chatItem: AChatItem)
    case rcvFileStart(chatItem: AChatItem)
    case rcvFileComplete(chatItem: AChatItem)
    // sending file events
    case sndFileStart(chatItem: AChatItem, sndFileTransfer: SndFileTransfer)
    case sndFileComplete(chatItem: AChatItem, sndFileTransfer: SndFileTransfer)
    case sndFileCancelled(chatItem: AChatItem, sndFileTransfer: SndFileTransfer)
    case sndFileRcvCancelled(chatItem: AChatItem, sndFileTransfer: SndFileTransfer)
    case sndGroupFileCancelled(chatItem: AChatItem, fileTransferMeta: FileTransferMeta, sndFileTransfers: [SndFileTransfer])
    case callInvitation(callInvitation: RcvCallInvitation)
    case callOffer(contact: Contact, callType: CallType, offer: WebRTCSession, sharedKey: String?, askConfirmation: Bool)
    case callAnswer(contact: Contact, answer: WebRTCSession)
    case callExtraInfo(contact: Contact, extraInfo: WebRTCExtraInfo)
    case callEnded(contact: Contact)
    case callInvitations(callInvitations: [RcvCallInvitation])
    case ntfTokenStatus(status: NtfTknStatus)
    case ntfToken(token: DeviceToken, status: NtfTknStatus, ntfMode: NotificationsMode)
    case ntfMessages(connEntity: ConnectionEntity?, msgTs: Date?, ntfMessages: [NtfMsgInfo])
    case newContactConnection(connection: PendingContactConnection)
    case contactConnectionDeleted(connection: PendingContactConnection)
    case cmdOk
    case chatCmdError(chatError: ChatError)
    case chatError(chatError: ChatError)

    public var responseType: String {
        get {
            switch self {
            case let .response(type, _): return "* \(type)"
            case .activeUser: return "activeUser"
            case .chatStarted: return "chatStarted"
            case .chatRunning: return "chatRunning"
            case .chatStopped: return "chatStopped"
            case .chatSuspended: return "chatSuspended"
            case .apiChats: return "apiChats"
            case .apiChat: return "apiChat"
            case .userSMPServers: return "userSMPServers"
            case .invitation: return "invitation"
            case .sentConfirmation: return "sentConfirmation"
            case .sentInvitation: return "sentInvitation"
            case .contactAlreadyExists: return "contactAlreadyExists"
            case .contactDeleted: return "contactDeleted"
            case .chatCleared: return "chatCleared"
            case .userProfileNoChange: return "userProfileNoChange"
            case .userProfileUpdated: return "userProfileUpdated"
            case .userContactLink: return "userContactLink"
            case .userContactLinkCreated: return "userContactLinkCreated"
            case .userContactLinkDeleted: return "userContactLinkDeleted"
            case .contactConnected: return "contactConnected"
            case .contactConnecting: return "contactConnecting"
            case .receivedContactRequest: return "receivedContactRequest"
            case .acceptingContactRequest: return "acceptingContactRequest"
            case .contactRequestRejected: return "contactRequestRejected"
            case .contactUpdated: return "contactUpdated"
            case .contactsSubscribed: return "contactsSubscribed"
            case .contactsDisconnected: return "contactsDisconnected"
            case .contactSubError: return "contactSubError"
            case .contactSubSummary: return "contactSubSummary"
            case .groupSubscribed: return "groupSubscribed"
            case .memberSubErrors: return "memberSubErrors"
            case .groupEmpty: return "groupEmpty"
            case .userContactLinkSubscribed: return "userContactLinkSubscribed"
            case .newChatItem: return "newChatItem"
            case .chatItemStatusUpdated: return "chatItemStatusUpdated"
            case .chatItemUpdated: return "chatItemUpdated"
            case .chatItemDeleted: return "chatItemDeleted"
            case .rcvFileAccepted: return "rcvFileAccepted"
            case .rcvFileStart: return "rcvFileStart"
            case .rcvFileComplete: return "rcvFileComplete"
            case .sndFileStart: return "sndFileStart"
            case .sndFileComplete: return "sndFileComplete"
            case .sndFileCancelled: return "sndFileCancelled"
            case .sndFileRcvCancelled: return "sndFileRcvCancelled"
            case .sndGroupFileCancelled: return "sndGroupFileCancelled"
            case .callInvitation: return "callInvitation"
            case .callOffer: return "callOffer"
            case .callAnswer: return "callAnswer"
            case .callExtraInfo: return "callExtraInfo"
            case .callEnded: return "callEnded"
            case .callInvitations: return "callInvitations"
            case .ntfTokenStatus: return "ntfTokenStatus"
            case .ntfToken: return "ntfToken"
            case .ntfMessages: return "ntfMessages"
            case .newContactConnection: return "newContactConnection"
            case .contactConnectionDeleted: return "contactConnectionDeleted"
            case .cmdOk: return "cmdOk"
            case .chatCmdError: return "chatCmdError"
            case .chatError: return "chatError"
            }
        }
    }

    public var details: String {
        get {
            switch self {
            case let .response(_, json): return json
            case let .activeUser(user): return String(describing: user)
            case .chatStarted: return noDetails
            case .chatRunning: return noDetails
            case .chatStopped: return noDetails
            case .chatSuspended: return noDetails
            case let .apiChats(chats): return String(describing: chats)
            case let .apiChat(chat): return String(describing: chat)
            case let .userSMPServers(smpServers): return String(describing: smpServers)
            case let .invitation(connReqInvitation): return connReqInvitation
            case .sentConfirmation: return noDetails
            case .sentInvitation: return noDetails
            case let .contactAlreadyExists(contact): return String(describing: contact)
            case let .contactDeleted(contact): return String(describing: contact)
            case let .chatCleared(chatInfo): return String(describing: chatInfo)
            case .userProfileNoChange: return noDetails
            case let .userProfileUpdated(_, toProfile): return String(describing: toProfile)
            case let .userContactLink(connReq): return connReq
            case let .userContactLinkCreated(connReq): return connReq
            case .userContactLinkDeleted: return noDetails
            case let .contactConnected(contact): return String(describing: contact)
            case let .contactConnecting(contact): return String(describing: contact)
            case let .receivedContactRequest(contactRequest): return String(describing: contactRequest)
            case let .acceptingContactRequest(contact): return String(describing: contact)
            case .contactRequestRejected: return noDetails
            case let .contactUpdated(toContact): return String(describing: toContact)
            case let .contactsSubscribed(server, contactRefs): return "server: \(server)\ncontacts:\n\(String(describing: contactRefs))"
            case let .contactsDisconnected(server, contactRefs): return "server: \(server)\ncontacts:\n\(String(describing: contactRefs))"
            case let .contactSubError(contact, chatError): return "contact:\n\(String(describing: contact))\nerror:\n\(String(describing: chatError))"
            case let .contactSubSummary(contactSubscriptions): return String(describing: contactSubscriptions)
            case let .groupSubscribed(groupInfo): return String(describing: groupInfo)
            case let .memberSubErrors(memberSubErrors): return String(describing: memberSubErrors)
            case let .groupEmpty(groupInfo): return String(describing: groupInfo)
            case .userContactLinkSubscribed: return noDetails
            case let .newChatItem(chatItem): return String(describing: chatItem)
            case let .chatItemStatusUpdated(chatItem): return String(describing: chatItem)
            case let .chatItemUpdated(chatItem): return String(describing: chatItem)
            case let .chatItemDeleted(deletedChatItem, toChatItem): return "deletedChatItem:\n\(String(describing: deletedChatItem))\ntoChatItem:\n\(String(describing: toChatItem))"
            case let .rcvFileAccepted(chatItem): return String(describing: chatItem)
            case let .rcvFileStart(chatItem): return String(describing: chatItem)
            case let .rcvFileComplete(chatItem): return String(describing: chatItem)
            case let .sndFileStart(chatItem, _): return String(describing: chatItem)
            case let .sndFileComplete(chatItem, _): return String(describing: chatItem)
            case let .sndFileCancelled(chatItem, _): return String(describing: chatItem)
            case let .sndFileRcvCancelled(chatItem, _): return String(describing: chatItem)
            case let .sndGroupFileCancelled(chatItem, _, _): return String(describing: chatItem)
            case let .callInvitation(inv): return String(describing: inv)
            case let .callOffer(contact, callType, offer, sharedKey, askConfirmation): return "contact: \(contact.id)\ncallType: \(String(describing: callType))\nsharedKey: \(sharedKey ?? "")\naskConfirmation: \(askConfirmation)\noffer: \(String(describing: offer))"
            case let .callAnswer(contact, answer): return "contact: \(contact.id)\nanswer: \(String(describing: answer))"
            case let .callExtraInfo(contact, extraInfo): return "contact: \(contact.id)\nextraInfo: \(String(describing: extraInfo))"
            case let .callEnded(contact): return "contact: \(contact.id)"
            case let .callInvitations(invs): return String(describing: invs)
            case let .ntfTokenStatus(status): return String(describing: status)
            case let .ntfToken(token, status, ntfMode): return "token: \(token)\nstatus: \(status.rawValue)\nntfMode: \(ntfMode.rawValue)"
            case let .ntfMessages(connEntity, msgTs, ntfMessages): return "connEntity: \(String(describing: connEntity))\nmsgTs: \(String(describing: msgTs))\nntfMessages: \(String(describing: ntfMessages))"
            case let .newContactConnection(connection): return String(describing: connection)
            case let .contactConnectionDeleted(connection): return String(describing: connection)
            case .cmdOk: return noDetails
            case let .chatCmdError(chatError): return String(describing: chatError)
            case let .chatError(chatError): return String(describing: chatError)
            }
        }
    }

    private var noDetails: String { get { "\(responseType): no details" } }
}

struct ComposedMessage: Encodable {
    var filePath: String?
    var quotedItemId: Int64?
    var msgContent: MsgContent
}

public struct ArchiveConfig: Encodable {
    var archivePath: String
    var disableCompression: Bool?

    public init(archivePath: String, disableCompression: Bool? = nil) {
        self.archivePath = archivePath
        self.disableCompression = disableCompression
    }
}

public protocol SelectableItem: Hashable, Identifiable {
    var label: LocalizedStringKey { get }
    static var values: [Self] { get }
}

public struct DeviceToken: Decodable {
    var pushProvider: PushProvider
    var token: String

    public init(pushProvider: PushProvider, token: String) {
        self.pushProvider = pushProvider
        self.token = token
    }

    public var cmdString: String {
        "\(pushProvider) \(token)"
    }
}

public enum PushEnvironment: String {
    case development
    case production
}

public enum PushProvider: String, Decodable {
    case apns_dev
    case apns_prod

    public init(env: PushEnvironment) {
        switch env {
        case .development: self = .apns_dev
        case .production: self = .apns_prod
        }
    }
}

public enum NotificationsMode: String, Decodable, SelectableItem {
    case off = "OFF"
    case periodic = "PERIODIC"
    case instant = "INSTANT"

    public var label: LocalizedStringKey {
        switch self {
        case .off: return "Off (Local)"
        case .periodic: return "Periodically"
        case .instant: return "Instantly"
        }
    }

    public var id: String { self.rawValue }

    public static var values: [NotificationsMode] = [.instant, .periodic, .off]
}

public enum NotificationPreviewMode: String, SelectableItem {
    case hidden
    case contact
    case message

    public var label: LocalizedStringKey {
        switch self {
        case .hidden: return "Hidden"
        case .contact: return "Contact"
        case .message: return "Message"
        }
    }

    public var id: String { self.rawValue }

    public static var values: [NotificationPreviewMode] = [.message, .contact, .hidden]
}

public func decodeJSON<T: Decodable>(_ json: String) -> T? {
    if let data = json.data(using: .utf8) {
        return try? jsonDecoder.decode(T.self, from: data)
    }
    return nil
}

func decodeCJSON<T: Decodable>(_ cjson: UnsafePointer<CChar>) -> T? {
    // TODO is there a way to do it without copying the data? e.g:
    //    let p = UnsafeMutableRawPointer.init(mutating: UnsafeRawPointer(cjson))
    //    let d = Data.init(bytesNoCopy: p, count: strlen(cjson), deallocator: .free)
    decodeJSON(String.init(cString: cjson))
}

private func getJSONObject(_ cjson: UnsafePointer<CChar>) -> NSDictionary? {
    let s = String.init(cString: cjson)
    let d = s.data(using: .utf8)!
    return try? JSONSerialization.jsonObject(with: d) as? NSDictionary
}

public func encodeJSON<T: Encodable>(_ value: T) -> String {
    let data = try! jsonEncoder.encode(value)
    return String(decoding: data, as: UTF8.self)
}

private func encodeCJSON<T: Encodable>(_ value: T) -> [CChar] {
    encodeJSON(value).cString(using: .utf8)!
}

public enum ChatError: Decodable {
    case error(errorType: ChatErrorType)
    case errorAgent(agentError: AgentErrorType)
    case errorStore(storeError: StoreError)
}

public enum ChatErrorType: Decodable {
    case noActiveUser
    case activeUserExists
    case chatNotStarted
    case invalidConnReq
    case invalidChatMessage(message: String)
    case contactNotReady(contact: Contact)
    case contactGroups(contact: Contact, groupNames: [GroupName])
    case groupUserRole
    case groupContactRole(contactName: ContactName)
    case groupDuplicateMember(contactName: ContactName)
    case groupDuplicateMemberId
    case groupNotJoined(groupInfo: GroupInfo)
    case groupMemberNotActive
    case groupMemberUserRemoved
    case groupMemberNotFound(contactName: ContactName)
    case groupMemberIntroNotFound(contactName: ContactName)
    case groupCantResendInvitation(groupInfo: GroupInfo, contactName: ContactName)
    case groupInternal(message: String)
    case fileNotFound(message: String)
    case fileAlreadyReceiving(message: String)
    case fileAlreadyExists(filePath: String)
    case fileRead(filePath: String, message: String)
    case fileWrite(filePath: String, message: String)
    case fileSend(fileId: Int64, agentError: String)
    case fileRcvChunk(message: String)
    case fileInternal(message: String)
    case invalidQuote
    case invalidChatItemUpdate
    case invalidChatItemDelete
    case agentVersion
    case commandError(message: String)
}

public enum StoreError: Decodable {
    case duplicateName
    case contactNotFound(contactId: Int64)
    case contactNotFoundByName(contactName: ContactName)
    case contactNotReady(contactName: ContactName)
    case duplicateContactLink
    case userContactLinkNotFound
    case contactRequestNotFound(contactRequestId: Int64)
    case contactRequestNotFoundByName(contactName: ContactName)
    case groupNotFound(groupId: Int64)
    case groupNotFoundByName(groupName: GroupName)
    case groupWithoutUser
    case duplicateGroupMember
    case groupAlreadyJoined
    case groupInvitationNotFound
    case sndFileNotFound(fileId: Int64)
    case sndFileInvalid(fileId: Int64)
    case rcvFileNotFound(fileId: Int64)
    case fileNotFound(fileId: Int64)
    case rcvFileInvalid(fileId: Int64)
    case connectionNotFound(agentConnId: String)
    case pendingConnectionNotFound(connId: Int64)
    case introNotFound
    case uniqueID
    case internalError(message: String)
    case noMsgDelivery(connId: Int64, agentMsgId: String)
    case badChatItem(itemId: Int64)
    case chatItemNotFound(itemId: Int64)
    case quotedChatItemNotFound
    case chatItemSharedMsgIdNotFound(sharedMsgId: String)
    case chatItemNotFoundByFileId(fileId: Int64)
}

public enum AgentErrorType: Decodable {
    case CMD(cmdErr: CommandErrorType)
    case CONN(connErr: ConnectionErrorType)
    case SMP(smpErr: ProtocolErrorType)
    case NTF(ntfErr: ProtocolErrorType)
    case BROKER(brokerErr: BrokerErrorType)
    case AGENT(agentErr: SMPAgentError)
    case INTERNAL(internalErr: String)
}

public enum CommandErrorType: Decodable {
    case PROHIBITED
    case SYNTAX
    case NO_CONN
    case SIZE
    case LARGE
}

public enum ConnectionErrorType: Decodable {
    case NOT_FOUND
    case DUPLICATE
    case SIMPLEX
    case NOT_ACCEPTED
    case NOT_AVAILABLE
}

public enum BrokerErrorType: Decodable {
    case RESPONSE(smpErr: ProtocolErrorType)
    case UNEXPECTED
    case NETWORK
    case TRANSPORT(transportErr: ProtocolTransportError)
    case TIMEOUT
}

public enum ProtocolErrorType: Decodable {
    case BLOCK
    case SESSION
    case CMD(cmdErr: ProtocolCommandError)
    case AUTH
    case QUOTA
    case NO_MSG
    case LARGE_MSG
    case INTERNAL
}

public enum ProtocolCommandError: Decodable {
    case UNKNOWN
    case SYNTAX
    case NO_AUTH
    case HAS_AUTH
    case NO_ENTITY
}

public enum ProtocolTransportError: Decodable {
    case badBlock
    case largeMsg
    case badSession
    case handshake(handshakeErr: SMPHandshakeError)
}

public enum SMPHandshakeError: Decodable {
    case PARSE
    case VERSION
    case IDENTITY
}

public enum SMPAgentError: Decodable {
    case A_MESSAGE
    case A_PROHIBITED
    case A_VERSION
    case A_ENCRYPTION
}
