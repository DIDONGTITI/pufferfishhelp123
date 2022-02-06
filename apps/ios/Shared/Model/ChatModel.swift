//
//  ChatModel.swift
//  SimpleX
//
//  Created by Evgeny Poberezkin on 22/01/2022.
//  Copyright © 2022 SimpleX Chat. All rights reserved.
//

import Foundation
import Combine
import SwiftUI

final class ChatModel: ObservableObject {
    @Published var currentUser: User?
    // list of chat "previews"
    @Published var chats: [Chat] = []
    // current chat
    @Published var chatId: String?
    @Published var chatItems: [ChatItem] = []
    // items in the terminal view
    @Published var terminalItems: [TerminalItem] = []
    @Published var userAddress: String?
    @Published var appOpenUrl: URL?
    @Published var connectViaUrl = false

    func hasChat(_ id: String) -> Bool {
        chats.first(where: { $0.id == id }) != nil
    }

    func getChat(_ id: String) -> Chat? {
        chats.first(where: { $0.id == id })
    }

    private func getChatIndex(_ id: String) -> Int? {
        chats.firstIndex(where: { $0.id == id })
    }

    func addChat(_ chat: Chat) {
        withAnimation {
            chats.insert(chat, at: 0)
        }
    }

    func updateChatInfo(_ cInfo: ChatInfo) {
        if let ix = getChatIndex(cInfo.id) {
            chats[ix].chatInfo = cInfo
        }
    }

    func updateContact(_ contact: Contact) {
        let cInfo = ChatInfo.direct(contact: contact)
        if hasChat(contact.id) {
            updateChatInfo(cInfo)
        } else {
            addChat(Chat(chatInfo: cInfo, chatItems: []))
        }
    }

    func updateNetworkStatus(_ contact: Contact, _ status: Chat.NetworkStatus) {
        if let ix = getChatIndex(contact.id) {
            chats[ix].serverInfo.networkStatus = status
        }
    }

    func replaceChat(_ id: String, _ chat: Chat) {
        if let ix = chats.firstIndex(where: { $0.id == id }) {
            chats[ix] = chat
        } else {
            // invalid state, correcting
            chats.insert(chat, at: 0)
        }
    }

    func addChatItem(_ cInfo: ChatInfo, _ cItem: ChatItem) {
        if let ix = chats.firstIndex(where: { $0.id == cInfo.id }) {
            chats[ix].chatItems = [cItem]
            if ix > 0 {
                if chatId == nil {
                    withAnimation { popChat(ix) }
                } else {
                    DispatchQueue.main.async { self.popChat(ix) }
                }
            }
        }
        if chatId == cInfo.id {
            withAnimation { chatItems.append(cItem) }
        } else if chatId != nil {
            // meesage arrived to some other chat, show notification
        }
    }

    private func popChat(_ ix: Int) {
        let chat = chats.remove(at: ix)
        chats.insert(chat, at: 0)
    }

    func removeChat(_ id: String) {
        withAnimation {
            chats.removeAll(where: { $0.id == id })
        }
    }
}

struct User: Decodable {
    var userId: Int64
    var userContactId: Int64
    var localDisplayName: ContactName
    var profile: Profile
    var activeUser: Bool

//    internal init(userId: Int64, userContactId: Int64, localDisplayName: ContactName, profile: Profile, activeUser: Bool) {
//        self.userId = userId
//        self.userContactId = userContactId
//        self.localDisplayName = localDisplayName
//        self.profile = profile
//        self.activeUser = activeUser
//    }
}

let sampleUser = User(
    userId: 1,
    userContactId: 1,
    localDisplayName: "alice",
    profile: sampleProfile,
    activeUser: true
)

typealias ContactName = String

typealias GroupName = String

struct Profile: Codable {
    var displayName: String
    var fullName: String
}

let sampleProfile = Profile(
    displayName: "alice",
    fullName: "Alice"
)

enum ChatType: String {
    case direct = "@"
    case group = "#"
    case contactRequest = "<@"
}

enum ChatInfo: Identifiable, Decodable {
    case direct(contact: Contact)
    case group(groupInfo: GroupInfo)
    case contactRequest(contactRequest: UserContactRequest)
    
    var localDisplayName: String {
        get {
            switch self {
            case let .direct(contact): return contact.localDisplayName
            case let .group(groupInfo): return groupInfo.localDisplayName
            case let .contactRequest(contactRequest): return contactRequest.localDisplayName
            }
        }
    }

    var fullName: String {
        get {
            switch self {
            case let .direct(contact): return contact.profile.fullName
            case let .group(groupInfo): return groupInfo.groupProfile.fullName
            case let .contactRequest(contactRequest): return contactRequest.profile.fullName
            }
        }
    }

    var chatViewName: String {
        get { localDisplayName + (fullName == "" || fullName == localDisplayName ? "" : " / \(fullName)") }
    }
    
    var id: String {
        get {
            switch self {
            case let .direct(contact): return contact.id
            case let .group(groupInfo): return groupInfo.id
            case let .contactRequest(contactRequest): return contactRequest.id
            }
        }
    }

    var chatType: ChatType {
        get {
            switch self {
            case .direct: return .direct
            case .group: return .group
            case .contactRequest: return .contactRequest
            }
        }
    }
    
    var apiId: Int64 {
        get {
            switch self {
            case let .direct(contact): return contact.apiId
            case let .group(groupInfo): return groupInfo.apiId
            case let .contactRequest(contactRequest): return contactRequest.apiId
            }
        }
    }

    var createdAt: Date {
        switch self {
        case let .direct(contact): return contact.createdAt
        case let .group(groupInfo): return groupInfo.createdAt
        case let .contactRequest(contactRequest): return contactRequest.createdAt
        }
    }
}

let sampleDirectChatInfo = ChatInfo.direct(contact: sampleContact)

let sampleGroupChatInfo = ChatInfo.group(groupInfo: sampleGroupInfo)

let sampleContactRequestChatInfo = ChatInfo.contactRequest(contactRequest: sampleContactRequest)

final class Chat: ObservableObject, Identifiable {
    @Published var chatInfo: ChatInfo
    @Published var chatItems: [ChatItem]
    @Published var serverInfo = ServerInfo(networkStatus: .unknown)

    struct ServerInfo: Decodable {
        var networkStatus: NetworkStatus
    }

    enum NetworkStatus: Decodable, Equatable {
        case unknown
        case connected
        case disconnected
        case error(String)

        var statusString: String {
            get {
                switch self {
                case .connected: return "Server connected"
                case let .error(err): return "Connecting server… (error: \(err))"
                default: return "Connecting server…"
                }
            }
        }

        var statusExplanation: String {
            get {
                switch self {
                case .connected: return "You are connected to the server you use to receve messages from this contact."
                case let .error(err): return "Trying to connect to the server you use to receve messages from this contact (error: \(err))."
                default: return "Trying to connect to the server you use to receve messages from this contact."
                }
            }
        }

        var imageName: String {
            get {
                switch self {
                case .unknown: return "circle.dotted"
                case .connected: return "circle.fill"
                case .disconnected: return "ellipsis.circle.fill"
                case .error: return "exclamationmark.circle.fill"
                }
            }
        }
    }

    init(_ cData: ChatData) {
        self.chatInfo = cData.chatInfo
        self.chatItems = cData.chatItems
    }

    init(chatInfo: ChatInfo, chatItems: [ChatItem] = []) {
        self.chatInfo = chatInfo
        self.chatItems = chatItems
    }

    var id: String { get { chatInfo.id } }
}

struct ChatData: Decodable, Identifiable {
    var chatInfo: ChatInfo
    var chatItems: [ChatItem]

    var id: String { get { chatInfo.id } }
}

struct Contact: Identifiable, Decodable {
    var contactId: Int64
    var localDisplayName: ContactName
    var profile: Profile
    var activeConn: Connection
    var viaGroup: Int64?
    var createdAt: Date

    var id: String { get { "@\(contactId)" } }
    var apiId: Int64 { get { contactId } }
    var ready: Bool { get { activeConn.connStatus == "ready" || activeConn.connStatus == "snd-ready" } }
}

let sampleContact = Contact(
    contactId: 1,
    localDisplayName: "alice",
    profile: sampleProfile,
    activeConn: sampleConnection,
    createdAt: .now
)

struct Connection: Decodable {
    var connStatus: String
}

let sampleConnection = Connection(connStatus: "ready")

struct UserContactRequest: Decodable {
    var contactRequestId: Int64
    var localDisplayName: ContactName
    var profile: Profile
    var createdAt: Date

    var id: String { get { "<@\(contactRequestId)" } }

    var apiId: Int64 { get { contactRequestId } }
}

let sampleContactRequest = UserContactRequest(
    contactRequestId: 1,
    localDisplayName: "alice",
    profile: sampleProfile,
    createdAt: .now
)

struct GroupInfo: Identifiable, Decodable {
    var groupId: Int64
    var localDisplayName: GroupName
    var groupProfile: GroupProfile
    var createdAt: Date
    
    var id: String { get { "#\(groupId)" } }

    var apiId: Int64 { get { groupId } }
}

let sampleGroupInfo = GroupInfo(
    groupId: 1,
    localDisplayName: "team",
    groupProfile: sampleGroupProfile,
    createdAt: .now
)

struct GroupProfile: Codable {
    var displayName: String
    var fullName: String
}

let sampleGroupProfile = GroupProfile(
    displayName: "team",
    fullName: "My Team"
)

struct GroupMember: Decodable {

}

struct AChatItem: Decodable {
    var chatInfo: ChatInfo
    var chatItem: ChatItem
}

struct ChatItem: Identifiable, Decodable {
    var chatDir: CIDirection
    var meta: CIMeta
    var content: CIContent
    
    var id: Int64 { get { meta.itemId } }
}

func chatItemSample(_ id: Int64, _ dir: CIDirection, _ ts: Date, _ text: String) -> ChatItem {
    ChatItem(
       chatDir: dir,
       meta: ciMetaSample(id, ts, text),
       content: .sndMsgContent(msgContent: .text(text))
   )
}

enum CIDirection: Decodable {
    case directSnd
    case directRcv
    case groupSnd
    case groupRcv(GroupMember)

    var sent: Bool {
        get {
            switch self {
            case .directSnd: return true
            case .directRcv: return false
            case .groupSnd: return true
            case .groupRcv: return false
            }
        }
    }
}

struct CIMeta: Decodable {
    var itemId: Int64
    var itemTs: Date
    var itemText: String
    var createdAt: Date
}

func ciMetaSample(_ id: Int64, _ ts: Date, _ text: String) -> CIMeta {
    CIMeta(
        itemId: id,
        itemTs: ts,
        itemText: text,
        createdAt: ts
    )
}

enum CIContent: Decodable {
    case sndMsgContent(msgContent: MsgContent)
    case rcvMsgContent(msgContent: MsgContent)
    // files etc.

    var text: String {
        get {
            switch self {
            case let .sndMsgContent(mc): return mc.text
            case let .rcvMsgContent(mc): return mc.text
            }
        }
    }
}

enum MsgContent {
    case text(String)
    case unknown(type: String, text: String)
    case invalid(error: String)

    var text: String {
        get {
            switch self {
            case let .text(text): return text
            case let .unknown(_, text): return text
            case .invalid:  return "invalid"
            }
        }
    }

    var cmdString: String {
        get {
            switch self {
            case let .text(text): return "text \(text)"
            default: return ""
            }
        }
    }

    enum CodingKeys: String, CodingKey {
        case type
        case text
    }
}

extension MsgContent: Decodable {
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        do {
            let type = try container.decode(String.self, forKey: CodingKeys.type)
            switch type {
            case "text":
                let text = try container.decode(String.self, forKey: CodingKeys.text)
                self = .text(text)
            default:
                let text = try? container.decode(String.self, forKey: CodingKeys.text)
                self = .unknown(type: type, text: text ?? "unknown message format")
            }
        } catch {
            self = .invalid(error: String(describing: error))
        }
    }
}
