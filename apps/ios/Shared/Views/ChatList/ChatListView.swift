//
//  ChatListView.swift
//  SimpleX
//
//  Created by Evgeny Poberezkin on 27/01/2022.
//  Copyright © 2022 SimpleX Chat. All rights reserved.
//

import SwiftUI
import SimpleXChat

struct ChatListView: View {
    @EnvironmentObject var chatModel: ChatModel
    // not really used in this view
    @State private var showSettings = false
    @State private var searchText = ""
    @State private var selectedChat: ChatId?

    var body: some View {
        let v = NavigationView {
            List {
                ForEach(filteredChats(), id: \.viewId) { chat in
                    ChatListNavLink(chat: chat)
                        .padding(.trailing, -16)
                        .disabled(chatModel.chatRunning != true)
                }
            }
            .onChange(of: chatModel.chatId) { _ in
                selectedChat = chatModel.chatId
                if chatModel.chatId == nil, let chatId = chatModel.chatToTop {
                    chatModel.chatToTop = nil
                    chatModel.popChat(chatId)
                }
            }
            .onChange(of: chatModel.chats.isEmpty) { empty in
                if !empty { return }
                withAnimation { chatModel.onboardingStage = .step4_MakeConnection }
            }
            .onChange(of: chatModel.appOpenUrl) { _ in connectViaUrl() }
            .onAppear() { connectViaUrl() }
            .offset(x: -8)
            .listStyle(.plain)
            .navigationTitle("Your chats")
            .navigationBarTitleDisplayMode(chatModel.chats.count > 8 ? .inline : .large)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    SettingsButton()
                }
                ToolbarItem(placement: .principal) {
                    if (chatModel.incognito) {
                        HStack {
                            if (chatModel.chats.count > 8) {
                                Text("Your chats").font(.headline)
                                Spacer().frame(width: 16)
                            }
                            Image(systemName: "theatermasks").frame(maxWidth: 24, maxHeight: 24, alignment: .center).foregroundColor(.indigo)
                        }
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    switch chatModel.chatRunning {
                    case .some(true): NewChatButton()
                    case .some(false): chatStoppedIcon()
                    case .none: EmptyView()
                    }
                }
            }
            .background(
                NavigationLink(
                    destination: chatView(selectedChat),
                    isActive: Binding(
                        get: { selectedChat != nil },
                        set: { _, _ in selectedChat = nil }
                    )
                ) { EmptyView() }
            )
        }
        .navigationViewStyle(.stack)

        if chatModel.chats.count > 8 {
            v.searchable(text: $searchText)
        } else {
            v
        }
    }

    @ViewBuilder private func chatView(_ chatId: ChatId?) -> some View {
        if let chatId = chatId, let chat = chatModel.getChat(chatId) {
            ChatView(chat: chat).onAppear {
                loadChat(chat: chat)
            }
        }
    }

    private func filteredChats() -> [Chat] {
        let s = searchText.trimmingCharacters(in: .whitespaces).localizedLowercase
        return s == ""
            ? chatModel.chats
            : chatModel.chats.filter { chat in
                let contains = chat.chatInfo.chatViewName.localizedLowercase.contains(s)
                switch chat.chatInfo {
                case let .direct(contact):
                    return contains
                    || contact.profile.displayName.localizedLowercase.contains(s)
                    || contact.fullName.localizedLowercase.contains(s)
                case .contactConnection: return false
                default: return contains
                }
            }
    }
}

func chatStoppedIcon() -> some View {
    Button {
        AlertManager.shared.showAlertMsg(
            title: "Chat is stopped",
            message: "You can start chat via app Settings / Database or by restarting the app"
        )
    } label: {
        Image(systemName: "exclamationmark.octagon.fill").foregroundColor(.red)
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
            ChatListView()
                .environmentObject(chatModel)
            ChatListView()
                .environmentObject(ChatModel())
        }
    }
}
