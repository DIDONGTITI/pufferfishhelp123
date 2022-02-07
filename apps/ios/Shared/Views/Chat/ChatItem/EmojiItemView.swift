//
//  EmojiItemView.swift
//  SimpleX
//
//  Created by Evgeny Poberezkin on 04/02/2022.
//  Copyright © 2022 SimpleX Chat. All rights reserved.
//

import SwiftUI

struct EmojiItemView: View {
    var chatItem: ChatItem

    var body: some View {
        let sent = chatItem.chatDir.sent

        VStack {
            Text(chatItem.content.text.trimmingCharacters(in: .whitespaces))
                .font(emojiFont)
                .padding(.top, 8)
                .padding(.horizontal, 6)
                .frame(maxWidth: .infinity, alignment: sent ? .trailing : .leading)
            Text(getDateFormatter().string(from: chatItem.meta.itemTs))
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.bottom, 8)
                .padding(.horizontal, 12)
                .frame(maxWidth: .infinity, alignment: sent ? .trailing : .leading)
        }
        .padding(.horizontal)
        .frame(maxWidth: .infinity, alignment: sent ? .trailing : .leading)
    }
}

struct EmojiItemView_Previews: PreviewProvider {
    static var previews: some View {
        Group{
            EmojiItemView(chatItem: chatItemSample(1, .directSnd, .now, "🙂"))
            EmojiItemView(chatItem: chatItemSample(2, .directRcv, .now, "👍"))
        }
        .previewLayout(.fixed(width: 360, height: 70))
    }
}
