//
//  ConnectViaLink.swift
//  SimpleX (iOS)
//
//  Created by Evgeny on 07/05/2022.
//  Copyright © 2022 SimpleX Chat. All rights reserved.
//

import SwiftUI

struct ConnectViaLink: View {
    @EnvironmentObject var chatModel: ChatModel

    var body: some View {
        VStack {
            Text("Connect via link")

            Spacer()

            Button {
                chatModel.onboardingStep = .step3c_ConnectToDevelopers
            } label: {
                HStack {
                    Text("Connect")
                    Image(systemName: "greaterthan")
                }
            }
            .frame(maxWidth: .infinity)

            Spacer()
        }
    }
}

struct ConnectViaLink_Previews: PreviewProvider {
    static var previews: some View {
        ConnectViaLink()
    }
}
