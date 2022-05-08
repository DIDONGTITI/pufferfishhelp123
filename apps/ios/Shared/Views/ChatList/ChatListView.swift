//
//  ChatListView.swift
//  SimpleX
//
//  Created by Evgeny Poberezkin on 27/01/2022.
//  Copyright © 2022 SimpleX Chat. All rights reserved.
//

import SwiftUI

struct ChatListView: View {
    @EnvironmentObject var chatModel: ChatModel
    // not really used in this view
    @State private var showSettings = false
    @State private var searchText = ""

    var user: User

    var body: some View {
        let v = NavigationView {
            List {
                if chatModel.chats.isEmpty {
                    ChatHelp(showSettings: $showSettings)
                } else {
                    ForEach(filteredChats()) { chat in
                        ChatListNavLink(chat: chat)
                            .padding(.trailing, -16)
                    }
                }
            }
            .onChange(of: chatModel.chatId) { _ in
                if chatModel.chatId == nil, let chatId = chatModel.chatToTop {
                    chatModel.chatToTop = nil
                    chatModel.popChat(chatId)
                }
            }
            .onChange(of: chatModel.appOpenUrl) { _ in
                if let url = chatModel.appOpenUrl {
                    chatModel.appOpenUrl = nil
                    AlertManager.shared.showAlert(connectViaUrlAlert(url))
                }
            }
            .offset(x: -8)
            .listStyle(.plain)
            .navigationTitle(chatModel.chats.isEmpty ? "Welcome \(user.displayName)!" : "Your chats")
            .navigationBarTitleDisplayMode(chatModel.chats.count > 8 ? .inline : .large)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    SettingsButton()
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    NewChatButton()
                }
            }
        }
        .navigationViewStyle(.stack)

        if chatModel.chats.count > 8 {
            v.searchable(text: $searchText)
        } else {
            v
        }
    }

    private func filteredChats() -> [Chat] {
        let s = searchText.trimmingCharacters(in: .whitespaces).localizedLowercase
        return s == ""
            ? chatModel.chats
            : chatModel.chats.filter { $0.chatInfo.chatViewName.localizedLowercase.contains(s) }
    }

    private func connectViaUrlAlert(_ url: URL) -> Alert {
        var path = url.path
        logger.debug("ChatListView.connectViaUrlAlert path: \(path)")
        if (path == "/contact" || path == "/invitation") {
            path.removeFirst()
            let action: ConnReqType = path == "contact" ? .contact : .invitation
            let link = url.absoluteString.replacingOccurrences(of: "///\(path)", with: "/\(path)")
            let title: LocalizedStringKey
            if case .contact = action { title = "Connect via contact link?" }
            else { title = "Connect via one-time link?" }
            return Alert(
                title: Text(title),
                message: Text("Your profile will be sent to the contact that you received this link from"),
                primaryButton: .default(Text("Connect")) {
                    connectViaLink(link)
                },
                secondaryButton: .cancel()
            )
        } else {
            return Alert(title: Text("Error: URL is invalid"))
        }
    }
}

struct ChatListView_Previews: PreviewProvider {
    static var previews: some View {
        let chatModel = ChatModel()
        chatModel.chats = [
            Chat(
                chatInfo: ChatInfo.sampleData.direct,
                chatItems: [ChatItem.getSample(1, .directSnd, .now, "hello")]
            ),
            Chat(
                chatInfo: ChatInfo.sampleData.group,
                chatItems: [ChatItem.getSample(1, .directSnd, .now, "Lorem ipsum dolor sit amet, consectetur adipiscing elit, sed do eiusmod tempor incididunt ut labore et dolore magna aliqua. Ut enim ad minim veniam, quis nostrud exercitation ullamco laboris nisi ut aliquip ex ea commodo consequat. Duis aute irure dolor in reprehenderit in voluptate velit esse cillum dolore eu fugiat nulla pariatur. Excepteur sint occaecat cupidatat non proident, sunt in culpa qui officia deserunt mollit anim id est laborum.")]
            ),
            Chat(
                chatInfo: ChatInfo.sampleData.contactRequest,
                chatItems: []
            )

        ]
        return Group {
            ChatListView(user: User.sampleData)
                .environmentObject(chatModel)
            ChatListView(user: User.sampleData)
                .environmentObject(ChatModel())
        }
    }
}
