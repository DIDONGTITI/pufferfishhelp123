//
//  ComposeView.swift
//  SimpleX
//
//  Created by Evgeny on 13/03/2022.
//  Copyright © 2022 SimpleX Chat. All rights reserved.
//

import SwiftUI

struct ComposeView: View {
    @Binding var quotedItem: ChatItem?
    @Binding var editingItem: ChatItem?
    var sendMessage: (String) -> Void
    var inProgress: Bool = false
    @FocusState.Binding var keyboardVisible: Bool

    var body: some View {
        VStack(spacing: 0) {
            QuotedItemView(quotedItem: $quotedItem)
                .transition(.move(edge: .bottom))
            EditingItemView(editingItem: $editingItem)
                .transition(.move(edge: .bottom))
            SendMessageView(
                sendMessage: sendMessage,
                inProgress: inProgress,
                keyboardVisible: $keyboardVisible,
                editing: editingItem != nil
            )
            .background(.background)
        }
    }
}

struct ComposeView_Previews: PreviewProvider {
    static var previews: some View {
        @FocusState var keyboardVisible: Bool
        @State var item: ChatItem? = ChatItem.getSample(1, .directSnd, .now, "hello")
        @State var nilItem: ChatItem? = nil

        return Group {
            ComposeView(
                quotedItem: $item,
                editingItem: $nilItem,
                sendMessage: { print ($0) },
                keyboardVisible: $keyboardVisible
            )
            ComposeView(
                quotedItem: $nilItem,
                editingItem: $item,
                sendMessage: { print ($0) },
                keyboardVisible: $keyboardVisible
            )
        }
    }
}
