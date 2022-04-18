//
//  ChatNavLabel.swift
//  SimpleX
//
//  Created by Evgeny Poberezkin on 28/01/2022.
//  Copyright © 2022 SimpleX Chat. All rights reserved.
//

import SwiftUI

struct ChatPreviewView: View {
    @ObservedObject var chat: Chat
    @Environment(\.colorScheme) var colorScheme
    var darkGreen = Color(red: 0, green: 0.5, blue: 0)

    var body: some View {
        let cItem = chat.chatItems.last
        let unread = chat.chatStats.unreadCount
        return HStack(spacing: 8) {
            ZStack(alignment: .bottomLeading) {
                ChatInfoImage(chat: chat)
                    .frame(width: 63, height: 63)
                if case .direct = chat.chatInfo,
                   chat.serverInfo.networkStatus == .connected {
                    Image(systemName: "circle.fill")
                        .resizable()
                        .foregroundColor(colorScheme == .dark ? darkGreen : .green)
                        .frame(width: 5, height: 5)
                        .padding([.bottom, .leading], 1)
                }
            }
            .padding(.leading, 4)

            VStack(spacing: 0) {
                HStack(alignment: .top) {
                    Text(chat.chatInfo.chatViewName)
                        .font(.title3)
                        .fontWeight(.bold)
                        .foregroundColor(chat.chatInfo.ready ? .primary : .secondary)
                        .frame(maxHeight: .infinity, alignment: .topLeading)
                    Spacer()
                    (cItem?.timestampText ?? timestampText(chat.chatInfo.createdAt))
                        .font(.subheadline)
                        .frame(minWidth: 60, alignment: .trailing)
                        .foregroundColor(.secondary)
                        .padding(.top, 4)

                }
                .padding(.top, 4)
                .padding(.horizontal, 8)

                if let cItem = cItem {
                    ZStack(alignment: .topTrailing) {
                        (itemStatusMark(cItem) + messageText(cItem.content, cItem.formattedText, cItem.memberDisplayName, preview: true))
                            .frame(minWidth: 0, maxWidth: .infinity, minHeight: 44, maxHeight: 44, alignment: .topLeading)
                            .padding(.leading, 8)
                            .padding(.trailing, 36)
                            .padding(.bottom, 4)
                        if unread > 0 {
                            Text(unread > 999 ? "\(unread / 1000)k" : "\(unread)")
                                .font(.caption)
                                .foregroundColor(.white)
                                .padding(.horizontal, 4)
                                .frame(minWidth: 18, minHeight: 18)
                                .background(Color.accentColor)
                                .cornerRadius(10)
                        }
                    }
                    .padding(.trailing, 8)
                }
                else if case let .direct(contact) = chat.chatInfo, !contact.ready {
                    Text("Connecting...")
                        .frame(minWidth: 0, maxWidth: .infinity, minHeight: 44, maxHeight: 44, alignment: .topLeading)
                        .padding([.leading, .trailing], 8)
                        .padding(.bottom, 4)
                }
            }
        }
    }

    private func itemStatusMark(_ cItem: ChatItem) -> Text {
        switch cItem.meta.itemStatus {
        case .sndErrorAuth:
            return Text(Image(systemName: "multiply"))
                .font(.caption)
                .foregroundColor(.red) + Text(" ")
        case .sndError:
            return Text(Image(systemName: "exclamationmark.triangle.fill"))
                .font(.caption)
                .foregroundColor(.yellow) + Text(" ")
        default: return Text("")
        }
    }
}

struct ChatPreviewView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            ChatPreviewView(chat: Chat(
                chatInfo: ChatInfo.sampleData.direct,
                chatItems: []
            ))
            ChatPreviewView(chat: Chat(
                chatInfo: ChatInfo.sampleData.direct,
                chatItems: [ChatItem.getSample(1, .directSnd, .now, "hello", .sndSent)]
            ))
            ChatPreviewView(chat: Chat(
                chatInfo: ChatInfo.sampleData.group,
                chatItems: [ChatItem.getSample(1, .directSnd, .now, "Lorem ipsum dolor sit amet, d. consectetur adipiscing elit, sed do eiusmod tempor incididunt ut labore et dolore magna aliqua. Ut enim ad minim veniam, quis nostrud exercitation ullamco laboris nisi ut aliquip ex ea commodo consequat. Duis aute irure dolor in reprehenderit in voluptate velit esse cillum dolore eu fugiat nulla pariatur. Excepteur sint occaecat cupidatat non proident, sunt in culpa qui officia deserunt mollit anim id est laborum.")],
                chatStats: ChatStats(unreadCount: 11, minUnreadItemId: 0)
            ))
        }
        .previewLayout(.fixed(width: 360, height: 78))
    }
}
