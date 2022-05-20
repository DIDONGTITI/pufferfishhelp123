//
//  CICallItemView.swift
//  SimpleX (iOS)
//
//  Created by Evgeny on 20/05/2022.
//  Copyright © 2022 SimpleX Chat. All rights reserved.
//

import SwiftUI

struct CICallItemView: View {
    @EnvironmentObject var m: ChatModel
    var chatInfo: ChatInfo
    var chatItem: ChatItem
    var status: CICallStatus
    var duration: Int

    var body: some View {
        let sent = chatItem.chatDir.sent
        VStack(spacing: 4) {
            switch status {
            case .pending:
                if sent {
                    Image(systemName: "phone.arrow.up.right").foregroundColor(.secondary)
                } else {
                    acceptCallButton()
                }
            case .missed: missedCallIcon(sent).foregroundColor(.red)
            case .rejected: Image(systemName: "phone.down").foregroundColor(.secondary)
            case .accepted: connectingCallIcon()
            case .negotiated: connectingCallIcon()
            case .progress: Image(systemName: "phone.and.waveform.fill").foregroundColor(.green)
            case .ended: endedCallIcon(sent)
            case .error: missedCallIcon(sent).foregroundColor(.orange)
            }

            chatItem.timestampText
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.bottom, 8)
                .padding(.horizontal, 12)
        }
    }

    private func missedCallIcon(_ sent: Bool) -> some View {
        Image(systemName: sent ? "phone.arrow.up.right" : "phone.arrow.down.left")
    }

    private func connectingCallIcon() -> some View {
        Image(systemName: "phone.connection").foregroundColor(.green)
    }

    @ViewBuilder private func endedCallIcon(_ sent: Bool) -> some View {
        HStack {
            Image(systemName: "phone.down")
            Text(CICallStatus.durationText(duration)).foregroundColor(.secondary)
        }
    }


    @ViewBuilder private func acceptCallButton() -> some View {
        if case let .direct(contact) = chatInfo {
            Button {
                if let invitation = m.callInvitations.removeValue(forKey: contact.id) {
                    m.activeCallInvitation = nil
                    m.activeCall = Call(
                        contact: contact,
                        callState: .invitationReceived,
                        localMedia: invitation.peerMedia,
                        sharedKey: invitation.sharedKey
                    )
                    m.showCallView = true
                    m.callCommand = .start(media: invitation.peerMedia, aesKey: invitation.sharedKey, useWorker: true)
                } else {
                    AlertManager.shared.showAlertMsg(title: "Call already ended!")
                }
            } label: {
                Label("Answer call", systemImage: "phone.arrow.down.left")
            }
        } else {
            Image(systemName: "phone.arrow.down.left").foregroundColor(.secondary)
        }
    }
}

//struct CICallItemView_Previews: PreviewProvider {
//    static var previews: some View {
//        CICallItemView()
//    }
//}
