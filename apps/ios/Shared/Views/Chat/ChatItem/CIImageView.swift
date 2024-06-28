//
//  CIImageView.swift
//  SimpleX
//
//  Created by JRoberts on 12/04/2022.
//  Copyright © 2022 SimpleX Chat. All rights reserved.
//

import SwiftUI
import SimpleXChat

struct CIImageView: View {
    @EnvironmentObject var m: ChatModel
    @Environment(\.colorScheme) var colorScheme
    let chatItem: ChatItem
    let preview: UIImage?
    @State private var showFullScreenImage = false

    var body: some View {
        let file = chatItem.file
        ZStack {
            let preview = preview ?? UIImage()
            imageView(preview)
                .onTapGesture {
                    if let file = file {
                        switch file.fileStatus {
                        case .rcvInvitation, .rcvAborted:
                            Task {
                                if let user = m.currentUser {
                                    await receiveFile(user: user, fileId: file.fileId)
                                }
                            }
                        case .rcvAccepted:
                            switch file.fileProtocol {
                            case .xftp:
                                AlertManager.shared.showAlertMsg(
                                    title: "Waiting for image",
                                    message: "Image will be received when your contact completes uploading it."
                                )
                            case .smp:
                                AlertManager.shared.showAlertMsg(
                                    title: "Waiting for image",
                                    message: "Image will be received when your contact is online, please wait or check later!"
                                )
                            case .local: ()
                            }
                        case .rcvTransfer: () // ?
                        case .rcvComplete: () // ?
                        case .rcvCancelled: () // TODO
                        case let .rcvError(rcvFileError):
                            AlertManager.shared.showAlert(Alert(
                                title: Text("File error"),
                                message: Text(rcvFileError.errorInfo)
                            ))
                        case let .rcvWarning(rcvFileError):
                            AlertManager.shared.showAlert(Alert(
                                title: Text("Temporary file error"),
                                message: Text(rcvFileError.errorInfo)
                            ))
                        case let .sndError(sndFileError):
                            AlertManager.shared.showAlert(Alert(
                                title: Text("File error"),
                                message: Text(sndFileError.errorInfo)
                            ))
                        case let .sndWarning(sndFileError):
                            AlertManager.shared.showAlert(Alert(
                                title: Text("Temporary file error"),
                                message: Text(sndFileError.errorInfo)
                            ))
                        default: ()
                        }
                    }
                }
            if let uiImage = getLoadedImage(file) {
                imageView(uiImage)
                .fullScreenCover(isPresented: $showFullScreenImage) {
                    FullScreenMediaView(chatItem: chatItem, image: uiImage, showView: $showFullScreenImage)
                }
                .onTapGesture { showFullScreenImage = true }
                .onChange(of: m.activeCallViewIsCollapsed) { _ in
                    showFullScreenImage = false
                }
            }
        }.background(Color(.secondarySystemBackground))
    }

    private func imageView(_ img: UIImage) -> some View {
        return ZStack(alignment: .topTrailing) {
            if img.imageData == nil {
                Image(uiImage: img)
                        .resizable()
                        .scaledToFit()
            } else {
                GeometryReader { proxy in
                    SwiftyGif(image: img)
                        .frame(width: proxy.size.width, height: proxy.size.height)
                        .scaledToFit()
                }

            }
            loadingIndicator()
        }
    }

    @ViewBuilder private func loadingIndicator() -> some View {
        if let file = chatItem.file {
            switch file.fileStatus {
            case .sndStored:
                switch file.fileProtocol {
                case .xftp: progressView()
                case .smp: EmptyView()
                case .local: EmptyView()
                }
            case .sndTransfer: progressView()
            case .sndComplete: fileIcon("checkmark", 10, 13)
            case .sndCancelled: fileIcon("xmark", 10, 13)
            case .sndError: fileIcon("xmark", 10, 13)
            case .sndWarning: fileIcon("exclamationmark.triangle.fill", 10, 13)
            case .rcvInvitation: fileIcon("arrow.down", 10, 13)
            case .rcvAccepted: fileIcon("ellipsis", 14, 11)
            case .rcvTransfer: progressView()
            case .rcvAborted: fileIcon("exclamationmark.arrow.circlepath", 14, 11)
            case .rcvComplete: EmptyView()
            case .rcvCancelled: fileIcon("xmark", 10, 13)
            case .rcvError: fileIcon("xmark", 10, 13)
            case .rcvWarning: fileIcon("exclamationmark.triangle.fill", 10, 13)
            case .invalid: fileIcon("questionmark", 10, 13)
            }
        }
    }

    private func fileIcon(_ icon: String, _ size: CGFloat, _ padding: CGFloat) -> some View {
        Image(systemName: icon)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: size, height: size)
            .foregroundColor(.white)
            .padding(padding)
    }

    private func progressView() -> some View {
        ProgressView()
            .progressViewStyle(.circular)
            .frame(width: 20, height: 20)
            .tint(.white)
            .padding(8)
    }
}
