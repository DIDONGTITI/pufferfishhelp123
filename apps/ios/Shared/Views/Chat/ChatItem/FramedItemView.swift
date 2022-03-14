//
//  FramedItemView.swift
//  SimpleX
//
//  Created by Evgeny Poberezkin on 04/02/2022.
//  Copyright © 2022 SimpleX Chat. All rights reserved.
//

import SwiftUI

private let sentColorLight = Color(.sRGB, red: 0.27, green: 0.72, blue: 1, opacity: 0.12)
private let sentColorDark = Color(.sRGB, red: 0.27, green: 0.72, blue: 1, opacity: 0.09)
private let sentQuoteColorLight = Color(.sRGB, red: 0.27, green: 0.72, blue: 1, opacity: 0.09)
private let sentQuoteColorDark = Color(.sRGB, red: 0.27, green: 0.72, blue: 1, opacity: 0.17)

struct FramedItemView: View {
    @Environment(\.colorScheme) var colorScheme
    var chatItem: ChatItem
    @State var maxMsgWidth: CGFloat = 0
    private let codeFont = Font.custom("Courier", size: UIFont.preferredFont(forTextStyle: .body).pointSize)

    var body: some View {
        let v = ZStack(alignment: .bottomTrailing) {
            VStack(alignment: .leading, spacing: 0) {
                if let qi = chatItem.quotedItem {
                    MsgContentView(
                        content: qi,
                        sender: qi.sender
                    )
                    .lineLimit(3)
                    .font(.subheadline)
                    .padding(.vertical, 6)
                    .padding(.horizontal, 12)
                    .frame(minWidth: maxMsgWidth, alignment: .leading)
                    .background(
                        chatItem.chatDir.sent
                        ? (colorScheme == .light ? sentQuoteColorLight : sentQuoteColorDark)
                        : Color(uiColor: .quaternarySystemFill)
                    )
                    .overlay(DetermineWidth())
                }

                if chatItem.formattedText == nil && isShortEmoji(chatItem.content.text) {
                    VStack {
                        emojiText(chatItem.content.text)
                        Text("")
                    }
                    .padding(.top, 6)
                    .padding(.bottom, 8)
                    .padding(.horizontal, 12)
                    .frame(minWidth: maxMsgWidth, alignment: .center)
                    .overlay(DetermineWidth())
                } else {
                    MsgContentView(
                        content: chatItem.content,
                        formattedText: chatItem.formattedText,
                        sender: chatItem.memberDisplayName,
                        metaText: chatItem.timestampText
                    )
                    .padding(.vertical, 6)
                    .padding(.horizontal, 12)
                    .frame(minWidth: maxMsgWidth, alignment: .leading)
                    .textSelection(.enabled)
                    .overlay(DetermineWidth())
                }
            }
            .onPreferenceChange(DetermineWidth.Key.self) { maxMsgWidth = $0 }
            
            CIMetaView(chatItem: chatItem)
                .padding(.trailing, 12)
                .padding(.bottom, 6)
        }
        .background(chatItemFrameColor(chatItem, colorScheme))
        .cornerRadius(18)

        switch chatItem.meta.itemStatus {
        case .sndErrorAuth:
            v.onTapGesture { msgDeliveryError("Most likely this contact has deleted the connection with you.") }
        case let .sndError(agentError):
            v.onTapGesture { msgDeliveryError("Unexpected error: \(String(describing: agentError))") }
        default: v
        }
    }

    private func msgDeliveryError(_ err: String) {
        AlertManager.shared.showAlertMsg(
            title: "Message delivery error",
            message: err
        )
    }
}

func chatItemFrameColor(_ ci: ChatItem, _ colorScheme: ColorScheme) -> Color {
    ci.chatDir.sent
    ? (colorScheme == .light ? sentColorLight : sentColorDark)
    : Color(uiColor: .tertiarySystemGroupedBackground)
}

struct FramedItemView_Previews: PreviewProvider {
    static var previews: some View {
        Group{
            FramedItemView(chatItem: ChatItem.getSample(1, .directSnd, .now, "hello"))
            FramedItemView(chatItem: ChatItem.getSample(1, .groupRcv(groupMember: GroupMember.sampleData), .now, "hello", quotedItem: CIQuote.getSampleDirect(1, .now, "hi", sent: true)))
            FramedItemView(chatItem: ChatItem.getSample(2, .directSnd, .now, "https://simplex.chat", .sndSent, quotedItem: CIQuote.getSampleDirect(1, .now, "hi")))
            FramedItemView(chatItem: ChatItem.getSample(2, .directSnd, .now, "👍", .sndSent, quotedItem: CIQuote.getSampleDirect(1, .now, "Hello too")))
            FramedItemView(chatItem: ChatItem.getSample(2, .directRcv, .now, "hello there too!!! this covers -"))
            FramedItemView(chatItem: ChatItem.getSample(2, .directRcv, .now, "hello there too!!! this text has the time on the same line "))
            FramedItemView(chatItem: ChatItem.getSample(2, .directRcv, .now, "https://simplex.chat"))
            FramedItemView(chatItem: ChatItem.getSample(2, .directRcv, .now, "chaT@simplex.chat"))
        }
        .previewLayout(.fixed(width: 360, height: 200))
    }
}
