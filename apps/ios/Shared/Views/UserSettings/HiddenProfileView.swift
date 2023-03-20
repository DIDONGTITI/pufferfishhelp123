//
//  ProfilePrivacyView.swift
//  SimpleX (iOS)
//
//  Created by Evgeny on 17/03/2023.
//  Copyright © 2023 SimpleX Chat. All rights reserved.
//

import SwiftUI
import SimpleXChat

struct HiddenProfileView: View {
    @State var user: User
    @EnvironmentObject private var m: ChatModel
    @State private var hidePassword = ""
    @State private var confirmHidePassword = ""

    var body: some View {
        List {
            Text("Hide profile")
                .font(.title)
                .bold()
                .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                .listRowBackground(Color.clear)

            Section() {
                ProfilePreview(profileOf: user)
                    .padding(.leading, -8)
            }

            Section {
                PassphraseField(key: $hidePassword, placeholder: "Password to show", valid: true, showStrength: true)
                PassphraseField(key: $confirmHidePassword, placeholder: "Confirm password", valid: confirmValid)

                settingsRow("lock.rotation") {
                    Button("Save profile password") {

                    }
                }
                .disabled(saveDisabled)
            } header: {
                Text("Hidden profile password")
            } footer: {
                Text("To reveal your hidden profile, enter a full password into a search field in **Your chat profiles** page.")
                    .font(.body)
                    .padding(.top, 8)
            }
        }
    }

    var confirmValid: Bool { confirmHidePassword == "" || hidePassword == confirmHidePassword }

    var saveDisabled: Bool { hidePassword == "" || confirmHidePassword == "" || !confirmValid }
}

struct ProfilePrivacyView_Previews: PreviewProvider {
    static var previews: some View {
        HiddenProfileView(user: User.sampleData)
    }
}
