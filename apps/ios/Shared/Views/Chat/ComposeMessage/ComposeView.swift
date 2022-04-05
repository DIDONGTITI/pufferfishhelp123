//
//  ComposeView.swift
//  SimpleX
//
//  Created by Evgeny on 13/03/2022.
//  Copyright © 2022 SimpleX Chat. All rights reserved.
//

import SwiftUI
import LinkPresentation

// TODO
//enum ComposeState {
//    case plain
//    case quoted(quotedItem: ChatItem)
//    case editing(editingItem: ChatItem)
//}

struct ComposeView: View {
    @Binding var message: String
    @Binding var quotedItem: ChatItem?
    @Binding var editingItem: ChatItem?
    var sendMessage: (String) -> Void
    var resetMessage: () -> Void
    var inProgress: Bool = false
    @FocusState.Binding var keyboardVisible: Bool
    @State var editing: Bool = false
    @State var linkMetadata: LPLinkMetadata? = nil
    @State var linkUrl: URL? = nil
    
    
    private func isValidLink(link: String) -> Bool {
        return !(link.starts(with: "https://simplex.chat") || link.starts(with: "http://simplex.chat") || link.starts(with: "simplex.chat"))
    }
    
    private func getMetadata(_ url: URL) {
        LPMetadataProvider().startFetchingMetadata(for: url){ metadata, error in
            if let e = error {
                logger.error("Error retrieving link metadata: \(e.localizedDescription)")
            }
            linkMetadata = metadata
        }
    }
    
    func parseMessage(_ msg: String) {
        Task {
            do {
                if let parsedMsg = try await apiParseMarkdown(text: msg),
                   let link = parsedMsg.first(where: { $0.format == .uri }),
                   isValidLink(link: link.text) {
                        linkUrl = URL(string: link.text)
                    }
            } catch {
                logger.error("MessageParsing error: \(error.localizedDescription)")
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            if let metadata = linkMetadata {
                LinkPreview(metadata: metadata)
            }
            if (quotedItem != nil) {
                ContextItemView(contextItem: $quotedItem, editing: $editing)
            } else if (editingItem != nil) {
                ContextItemView(contextItem: $editingItem, editing: $editing, resetMessage: resetMessage)
            }
            SendMessageView(
                sendMessage: sendMessage,
                inProgress: inProgress,
                message: $message,
                keyboardVisible: $keyboardVisible,
                editing: $editing
            )
            .background(.background)
        }
        .onChange(of: message) {
            _ in
            if  message.count > 0 {
                parseMessage(message)
                if let url = linkUrl {
                    getMetadata(url)
                }
            }
        }
        .onChange(of: editingItem == nil) { _ in
            editing = (editingItem != nil)
        }
    }
}

struct ComposeView_Previews: PreviewProvider {
    static var previews: some View {
        @State var message: String = ""
        @FocusState var keyboardVisible: Bool
        @State var item: ChatItem? = ChatItem.getSample(1, .directSnd, .now, "hello")
        @State var nilItem: ChatItem? = nil

        return Group {
            ComposeView(
                message: $message,
                quotedItem: $item,
                editingItem: $nilItem,
                sendMessage: { print ($0) },
                resetMessage: {},
                keyboardVisible: $keyboardVisible
            )
            ComposeView(
                message: $message,
                quotedItem: $nilItem,
                editingItem: $item,
                sendMessage: { print ($0) },
                resetMessage: {},
                keyboardVisible: $keyboardVisible
            )
        }
    }
}
