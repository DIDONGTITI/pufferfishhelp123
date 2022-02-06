//
//  WelcomeView.swift
//  SimpleX
//
//  Created by Evgeny Poberezkin on 18/01/2022.
//

import SwiftUI

struct WelcomeView: View {
    @EnvironmentObject var chatModel: ChatModel
    @State var displayName: String = ""
    @State var fullName: String = ""

    var body: some View {
        VStack(alignment: .leading) {
            Text("Create profile")
                .font(.largeTitle)
                .padding(.bottom)
            Text("Your profile is stored on your device and shared only with your contacts.\nSimpleX servers cannot see your profile.")
                .padding(.bottom)
            TextField("Display name", text: $displayName)
                .textInputAutocapitalization(.never)
                .disableAutocorrection(true)
                .padding(.bottom)
            TextField("Full name (optional)", text: $fullName)
                .textInputAutocapitalization(.never)
                .disableAutocorrection(true)
                .padding(.bottom)
            Button("Create") {
                let profile = Profile(
                    displayName: displayName,
                    fullName: fullName
                )
                do {
                    let user = try apiCreateActiveUser(profile)
                    chatModel.currentUser = user
                } catch {
                    fatalError("Failed to create user: \(error)")
                }
            }
        }
        .padding()
    }
}

struct WelcomeView_Previews: PreviewProvider {
    static var previews: some View {
        WelcomeView()
    }
}
