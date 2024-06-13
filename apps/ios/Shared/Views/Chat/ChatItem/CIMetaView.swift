//
//  CIMetaView.swift
//  SimpleX
//
//  Created by Evgeny Poberezkin on 11/02/2022.
//  Copyright © 2022 SimpleX Chat. All rights reserved.
//

import SwiftUI
import SimpleXChat

struct CIMetaView: View {
    @ObservedObject var chat: Chat
    @EnvironmentObject var theme: AppTheme
    var chatItem: ChatItem
    var metaColor: Color
    var paleMetaColor = Color(UIColor.tertiaryLabel)
    var showStatus = true
    var showEdited = true

    @AppStorage(DEFAULT_SHOW_SENT_VIA_RPOXY) private var showSentViaProxy = false

    var body: some View {
        if chatItem.isDeletedContent {
            chatItem.timestampText.font(.caption).foregroundColor(metaColor)
        } else {
            let meta = chatItem.meta
            let ttl = chat.chatInfo.timedMessagesTTL
            let encrypted = chatItem.encryptedFile
            switch meta.itemStatus {
            case let .sndSent(sndProgress):
                switch sndProgress {
                case .complete: ciMetaText(meta, chatTTL: ttl, encrypted: encrypted,  color: metaColor, sent: .sent, showStatus: showStatus, showEdited: showEdited, showViaProxy: showSentViaProxy)
                case .partial: ciMetaText(meta, chatTTL: ttl, encrypted: encrypted, color: paleMetaColor, sent: .sent, showStatus: showStatus, showEdited: showEdited, showViaProxy: showSentViaProxy)
                }
            case let .sndRcvd(_, sndProgress):
                switch sndProgress {
                case .complete:
                    ZStack {
                        ciMetaText(meta, chatTTL: ttl, encrypted: encrypted, color: metaColor, sent: .rcvd1, showStatus: showStatus, showEdited: showEdited, showViaProxy: showSentViaProxy)
                        ciMetaText(meta, chatTTL: ttl, encrypted: encrypted, color: metaColor, sent: .rcvd2, showStatus: showStatus, showEdited: showEdited, showViaProxy: showSentViaProxy)
                    }
                case .partial:
                    ZStack {
                        ciMetaText(meta, chatTTL: ttl, encrypted: encrypted, color: paleMetaColor, sent: .rcvd1, showStatus: showStatus, showEdited: showEdited, showViaProxy: showSentViaProxy)
                        ciMetaText(meta, chatTTL: ttl, encrypted: encrypted, color: paleMetaColor, sent: .rcvd2, showStatus: showStatus, showEdited: showEdited, showViaProxy: showSentViaProxy)
                    }
                }
            default:
                ciMetaText(meta, chatTTL: ttl, encrypted: encrypted, color: metaColor, showStatus: showStatus, showEdited: showEdited, showViaProxy: showSentViaProxy)
            }
        }
    }
}

enum SentCheckmark {
    case sent
    case rcvd1
    case rcvd2
}

func ciMetaText(
    _ meta: CIMeta,
    chatTTL: Int?,
    encrypted: Bool?,
    color: Color = .clear,
    primaryColor: Color = .accentColor,
    transparent: Bool = false,
    sent: SentCheckmark? = nil,
    showStatus: Bool = true,
    showEdited: Bool = true,
    showViaProxy: Bool
) -> Text {
    var r = Text("")
    if showEdited, meta.itemEdited {
        r = r + statusIconText("pencil", color)
    }
    if meta.disappearing {
        r = r + statusIconText("timer", color).font(.caption2)
        let ttl = meta.itemTimed?.ttl
        if ttl != chatTTL {
            r = r + Text(shortTimeText(ttl)).foregroundColor(color)
        }
        r = r + Text(" ")
    }
    if showViaProxy, meta.sentViaProxy == true {
        r = r + statusIconText("arrow.forward", color.opacity(0.67)).font(.caption2)
    }
    if showStatus {
        if let (icon, statusColor) = meta.statusIcon(color, primaryColor) {
            let t = Text(Image(systemName: icon)).font(.caption2)
            let gap = Text("  ").kerning(-1.25)
            let t1 = t.foregroundColor(transparent ? .clear : statusColor.opacity(0.67))
            switch sent {
            case nil: r = r + t1
            case .sent: r = r + t1 + gap
            case .rcvd1: r = r + t.foregroundColor(transparent ? .clear : statusColor.opacity(0.67)) + gap
            case .rcvd2: r = r + gap + t1
            }
            r = r + Text(" ")
        } else if !meta.disappearing {
            r = r + statusIconText("circlebadge.fill", .clear) + Text(" ")
        }
    }
    if let enc = encrypted {
        r = r + statusIconText(enc ? "lock" : "lock.open", color) + Text(" ")
    }
    r = r + meta.timestampText.foregroundColor(color)
    return r.font(.caption)
}

private func statusIconText(_ icon: String, _ color: Color) -> Text {
    Text(Image(systemName: icon)).foregroundColor(color)
}

struct CIMetaView_Previews: PreviewProvider {
    static let metaColor = Color.secondary
    static var previews: some View {
        Group {
            CIMetaView(chat: Chat.sampleData, chatItem: ChatItem.getSample(2, .directSnd, .now, "https://simplex.chat", .sndSent(sndProgress: .complete)), metaColor: metaColor)
            CIMetaView(chat: Chat.sampleData, chatItem: ChatItem.getSample(2, .directSnd, .now, "https://simplex.chat", .sndSent(sndProgress: .partial)), metaColor: metaColor)
            CIMetaView(chat: Chat.sampleData, chatItem: ChatItem.getSample(2, .directSnd, .now, "https://simplex.chat", .sndRcvd(msgRcptStatus: .ok, sndProgress: .complete)), metaColor: metaColor)
            CIMetaView(chat: Chat.sampleData, chatItem: ChatItem.getSample(2, .directSnd, .now, "https://simplex.chat", .sndRcvd(msgRcptStatus: .ok, sndProgress: .partial)), metaColor: metaColor)
            CIMetaView(chat: Chat.sampleData, chatItem: ChatItem.getSample(2, .directSnd, .now, "https://simplex.chat", .sndRcvd(msgRcptStatus: .badMsgHash, sndProgress: .complete)), metaColor: metaColor)
            CIMetaView(chat: Chat.sampleData, chatItem: ChatItem.getSample(2, .directSnd, .now, "https://simplex.chat", .sndSent(sndProgress: .complete), itemEdited: true), metaColor: metaColor)
            CIMetaView(chat: Chat.sampleData, chatItem: ChatItem.getDeletedContentSample(), metaColor: metaColor)
        }
        .previewLayout(.fixed(width: 360, height: 100))
    }
}
