//
//  CallSettings.swift
//  SimpleX (iOS)
//
//  Created by Evgeny on 27/05/2022.
//  Copyright © 2022 SimpleX Chat. All rights reserved.
//

import SwiftUI
import SimpleXChat

struct CallSettings: View {
    @AppStorage(DEFAULT_WEBRTC_POLICY_RELAY) private var webrtcPolicyRelay = true
    @AppStorage(GROUP_DEFAULT_CALL_KIT_ENABLED, store: UserDefaults(suiteName: APP_GROUP_NAME)!) private var callKitEnabled = true
    @AppStorage(DEFAULT_CALL_KIT_CALLS_IN_RECENTS) private var callKitCallsInRecents = false
    @AppStorage(DEFAULT_DEVELOPER_TOOLS) private var developerTools = false
    private let allowChangingCallsHistory = false

    var body: some View {
        VStack {
            List {
                Section {
                    NavigationLink {
                        RTCServers()
                            .navigationTitle("Your ICE servers")
                    } label: {
                        Text("WebRTC ICE servers")
                    }
                    Toggle("Always use relay", isOn: $webrtcPolicyRelay)
                } header: {
                    Text("Settings")
                } footer: {
                    if webrtcPolicyRelay {
                        Text("Relay server protects your IP address, but it can observe the duration of the call.")
                    } else {
                        Text("Relay server is only used if necessary. Another party can observe your IP address.")
                    }
                }

                if !CallController.isInChina {
                    Section {
                        Toggle("Use iOS call interface", isOn: $callKitEnabled)
                        Toggle("Show calls in phone history", isOn: $callKitCallsInRecents)
                        .disabled(!callKitEnabled)
                        .onChange(of: callKitCallsInRecents) { value in
                            CallController.shared.showInRecents(value)
                        }
                    } header: {
                        Text("Interface")
                    } footer: {
                        if callKitEnabled {
                            Text("You can accept calls from lock screen, without device and app authentication.")
                        } else {
                            Text("Authentication is required before the call is connected, but you may miss calls.")
                        }
                    }
                }

                Section("Limitations") {
                    VStack(alignment: .leading, spacing: 8) {
                        textListItem("1.", "Do NOT use SimpleX for emergency calls.")
                        textListItem("2.", "Unless you use iOS call interface, enable Do Not Disturb mode to avoid interruptions.")
                    }
                    .font(.callout)
                    .padding(.vertical, 8)
                }
            }
        }
    }
}

func textListItem(_ n: String, _ text: LocalizedStringKey) -> some View {
    ZStack(alignment: .topLeading) {
        Text(n)
        Text(text).frame(maxWidth: .infinity, alignment: .leading).padding(.leading, 20)
    }
}

struct CallSettings_Previews: PreviewProvider {
    static var previews: some View {
        CallSettings()
    }
}
