//
//  CreateSimpleXAddress.swift
//  SimpleX (iOS)
//
//  Created by spaced4ndy on 28.04.2023.
//  Copyright © 2023 SimpleX Chat. All rights reserved.
//

import SwiftUI
import Contacts
import ContactsUI
import MessageUI
import SimpleXChat

struct CreateSimpleXAddress: View {
    @EnvironmentObject var m: ChatModel
    @State private var progressIndicator = false
    @State private var showContactPicker = false
    @State private var selectedRecipients: [String]?
    @State private var showMailView = false
    @State private var mailViewResult: Result<MFMailComposeResult, Error>? = nil

    var body: some View {
        GeometryReader { g in
            ScrollView {
                ZStack {
                    ContactPicker(
                        showPicker: $showContactPicker,
                        predicateForEnablingContact: NSPredicate(format: "emailAddresses.@count > 0"),
                        onSelectContacts: { cs in
                            selectedRecipients = Array(cs
                                .compactMap { $0.emailAddresses.first }
                                .prefix(3)
                                .map { String($0.value) }
                            )
                        }
                    )

                    VStack(alignment: .leading) {
                        Text("SimpleX Address").font(.largeTitle)

                        Spacer()

                        if let userAddress = m.userAddress {
                            QRCode(uri: userAddress.connReqContact)
                                .frame(maxHeight: g.size.width)
                            shareQRCodeButton(userAddress)
                                .frame(maxWidth: .infinity)
                            Divider()
                                .padding(.vertical, 12)
                            shareViaEmailButton(userAddress)
                                .frame(maxWidth: .infinity)

                            Spacer()

                            continueButton()
                                .padding(.bottom, 8)
                                .frame(maxWidth: .infinity)
                        } else {
                            createAddressButton()
                                .frame(maxWidth: .infinity)

                            Spacer()

                            skipButton()
                                .padding(.bottom, 56)
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .frame(minHeight: g.size.height)

                    if progressIndicator {
                        ProgressView().scaleEffect(2)
                    }
                }
            }
        }
        .frame(maxHeight: .infinity)
        .padding()
    }

    private func createAddressButton() -> some View {
        VStack(spacing: 8) {
            Button {
                progressIndicator = true
                Task {
                    do {
                        let connReqContact = try await apiCreateUserAddress()
                        DispatchQueue.main.async {
                            m.userAddress = UserContactLink(connReqContact: connReqContact)
                        }
                        if let u = try await apiSetProfileAddress(on: true) {
                            DispatchQueue.main.async {
                                m.updateUser(u)
                            }
                        }
                        await MainActor.run { progressIndicator = false }
                    } catch let error {
                        logger.error("CreateSimpleXAddress create address: \(responseError(error))")
                        await MainActor.run { progressIndicator = false }
                        let a = getErrorAlert(error, "Error creating address")
                        AlertManager.shared.showAlertMsg(
                            title: a.title,
                            message: a.message
                        )
                    }
                }
            } label: {
                Text("Create SimpleX address")
                    .font(.title)
            }
            Group {
                Text("Address will be shared with your future contacts. You can change it in Settings.")
            }
            .multilineTextAlignment(.center)
            .font(.footnote)
            .padding(.horizontal, 32)
        }
    }

    private func skipButton() -> some View {
        VStack(spacing: 8) {
            Button {
                withAnimation {
                    m.onboardingStage = .step4_SetNotificationsMode
                }
            } label: {
                Text("Don't create address")
                    .font(.title2)
            }
            Text("You can create it later.")
                .font(.footnote)
        }
    }

    private func shareQRCodeButton(_ userAdress: UserContactLink) -> some View {
        Button {
            showShareSheet(items: [userAdress.connReqContact])
        } label: {
            Label("Share", systemImage: "square.and.arrow.up")
        }
    }

    private func shareViaEmailButton(_ userAdress: UserContactLink) -> some View {
        Button {
            showContactPicker = true
        } label: {
            VStack {
                Image(systemName: "envelope")
                    .resizable()
                    .scaledToFill()
                    .frame(width: 30, height: 30)
                Text("Send to 3 friends")
                    .font(.title2)
            }
        }
        .onChange(of: selectedRecipients) { _ in
            showMailView = true
        }
        .sheet(isPresented: $showMailView) {
            let messageBody = """
                <p>Hello! Let's talk in SimpleX Chat:</p>
                <a href="\(userAdress.connReqContact)">Connect via SimpleX address</a>
                """
            MailView(
                isShowing: self.$showMailView,
                result: $mailViewResult,
                recipients: selectedRecipients ?? [],
                subject: "Invitation to SimpleX Chat",
                messageBody: messageBody
            )
        }
        .onChange(of: mailViewResult == nil) { _ in
            if let r = mailViewResult {
                switch r {
                case .success:
                    m.onboardingStage = .step4_SetNotificationsMode
                case let .failure(error):
                    let a = getErrorAlert(error, "Error sending email")
                    AlertManager.shared.showAlertMsg(
                        title: a.title,
                        message: a.message
                    )
                }
            }
        }
    }

    private func continueButton() -> some View {
        Button {
            withAnimation {
                m.onboardingStage = .step4_SetNotificationsMode
            }
        } label: {
            HStack {
                Text("Continue")
                Image(systemName: "greaterthan")
            }
        }
    }
}

struct CreateSimpleXAddress_Previews: PreviewProvider {
    static var previews: some View {
        CreateSimpleXAddress()
    }
}
