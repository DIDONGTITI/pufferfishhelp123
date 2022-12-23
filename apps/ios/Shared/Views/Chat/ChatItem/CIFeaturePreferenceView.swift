//
//  CIFeaturePreferenceView.swift
//  SimpleX (iOS)
//
//  Created by Evgeny on 21/12/2022.
//  Copyright © 2022 SimpleX Chat. All rights reserved.
//

import SwiftUI
import SimpleXChat

struct CIFeaturePreferenceView: View {
    @EnvironmentObject var chat: Chat
    var chatItem: ChatItem
    var feature: ChatFeature
    var allowed: FeatureAllowed
    var param: Int?

    var body: some View {
        HStack(alignment: .center, spacing: 4) {
            Image(systemName: feature.icon)
                .foregroundColor(.secondary)
                .scaleEffect(feature.iconScale)
            if let ct = chat.chatInfo.contact,
               allowed != .no && ct.allowsFeature(feature) && !ct.userAllowsFeature(feature) {
                featurePreferenceView(accept: true)
                    .onTapGesture {
                        allowFeatureToContact(ct, feature)
                    }
            } else {
                featurePreferenceView()
            }
        }
        .padding(.leading, 6)
        .padding(.bottom, 6)
        .textSelection(.disabled)
    }

    private func featurePreferenceView(accept: Bool = false) -> some View {
        var r = Text(CIContent.preferenceText(feature, allowed, param) + "  ")
                .fontWeight(.light)
                .foregroundColor(.secondary)
        if accept {
            r = r + Text("Accept" + "  ")
                .fontWeight(.medium)
                .foregroundColor(.accentColor)
        }
        r = r + chatItem.timestampText
                .fontWeight(.light)
                .foregroundColor(.secondary)
        return r.font(.caption)
    }
}

func allowFeatureToContact(_ contact: Contact, _ feature: ChatFeature) {
    Task {
        do {
            let prefs = contactUserPreferencesToPreferences(contact.mergedPreferences).setAllowed(feature)
            if let toContact = try await apiSetContactPrefs(contactId: contact.contactId, preferences: prefs) {
                await MainActor.run {
                    ChatModel.shared.updateContact(toContact)
                }
            }
        } catch {
            logger.error("allowFeatureToContact apiSetContactPrefs error: \(responseError(error))")
        }
    }
}

struct CIFeaturePreferenceView_Previews: PreviewProvider {
    static var previews: some View {
        let content = CIContent.rcvChatPreference(feature: .timedMessages, allowed: .yes, param: 30)
        let chatItem = ChatItem(
            chatDir: .directRcv,
            meta: CIMeta.getSample(1, .now, content.text, .rcvRead, false, false, false),
            content: content,
            quotedItem: nil,
            file: nil
        )
        CIFeaturePreferenceView(chatItem: chatItem, feature: ChatFeature.timedMessages, allowed: .yes, param: 30)
            .environmentObject(Chat.sampleData)
    }
}
