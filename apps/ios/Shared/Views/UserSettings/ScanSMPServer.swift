//
//  ScanSMPServer.swift
//  SimpleX (iOS)
//
//  Created by Evgeny on 19/11/2022.
//  Copyright © 2022 SimpleX Chat. All rights reserved.
//

import SwiftUI
import SimpleXChat
import CodeScanner

struct ScanSMPServer: View {
    @Environment(\.dismiss) var dismiss: DismissAction
    @Binding var servers: [ServerCfg]
    @State private var showAddressError = false

    var body: some View {
        VStack(alignment: .leading) {
            Text("Scan Server QR code")
                .font(.largeTitle)
                .bold()
                .padding(.vertical)
            ZStack {
                CodeScannerView(codeTypes: [.qr], completion: processQRCode)
                    .aspectRatio(1, contentMode: .fit)
                    .border(.gray)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .alert(isPresented: $showAddressError) {
            Alert(
                title: Text("Invalid server address!"),
                message: Text("Check server address and try again.")
            )
        }
    }

    func processQRCode(_ resp: Result<ScanResult, ScanError>) {
        switch resp {
        case let .success(r):
            let srv = ServerCfg(server: r.string, preset: false, tested: nil, enabled: true)
            if serverHostname(srv) != nil {
                servers.append(srv)
                dismiss()
            } else {
                showAddressError = true
            }
        case let .failure(e):
            logger.error("ConnectContactView.processQRCode QR code error: \(e.localizedDescription)")
            dismiss()
        }
    }
}

struct ScanSMPServer_Previews: PreviewProvider {
    static var previews: some View {
        ScanSMPServer(servers: Binding.constant([]))
    }
}
