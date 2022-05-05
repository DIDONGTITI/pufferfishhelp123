//
//  CIImageView.swift
//  SimpleX
//
//  Created by JRoberts on 12/04/2022.
//  Copyright © 2022 SimpleX Chat. All rights reserved.
//

import SwiftUI

struct CIImageView: View {
    @Environment(\.colorScheme) var colorScheme
    let image: String
    let file: CIFile?
    let maxWidth: CGFloat
    @Binding var imgWidth: CGFloat?
    @State var showFullScreenImage = false

    var body: some View {
        VStack(alignment: .center, spacing: 6) {
            if let uiImage = getStoredImage(file) {
                imageView(uiImage)
                .fullScreenCover(isPresented: $showFullScreenImage) {
                    ZStack {
                        Color.black.edgesIgnoringSafeArea(.all)
                        Image(uiImage: uiImage)
                            .resizable()
                            .scaledToFit()
                    }
                    .onTapGesture { showFullScreenImage = false }
                    .gesture(
                        DragGesture(minimumDistance: 80).onChanged { gesture in
                            let t = gesture.translation
                            if t.height > 60 && t.height > abs(t.width)  {
                                showFullScreenImage = false
                            }
                        }
                    )
                }
                .onTapGesture { showFullScreenImage = true }
            } else if let data = Data(base64Encoded: dropImagePrefix(image)),
              let uiImage = UIImage(data: data) {
                imageView(uiImage)
                    .onTapGesture {
                        if case .rcvAccepted = file?.fileStatus {
                            AlertManager.shared.showAlertMsg(
                                title: "Waiting for image",
                                message: "Image will be received when your contact is online, please wait or check later!"
                            )
                        }
                    }
            }
        }
    }

    private func imageView(_ img: UIImage) -> some View {
        let w = img.size.width > img.size.height ? .infinity : maxWidth * 0.75
        DispatchQueue.main.async { imgWidth = w }
        return ZStack(alignment: .topTrailing) {
            Image(uiImage: img)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: w)
            loadingIndicator()
        }
    }

    @ViewBuilder private func loadingIndicator() -> some View {
        if let file = file {
            switch file.fileStatus {
            case .sndTransfer:
                ProgressView()
                    .progressViewStyle(.circular)
                    .frame(width: 20, height: 20)
                    .tint(.white)
                    .padding(8)
            case .sndComplete:
                Image(systemName: "checkmark")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 10, height: 10)
                    .foregroundColor(.white)
                    .padding(13)
            case .rcvAccepted:
                Image(systemName: "ellipsis")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 14, height: 14)
                    .foregroundColor(.white)
                    .padding(11)
            case .rcvTransfer:
                ProgressView()
                    .progressViewStyle(.circular)
                    .frame(width: 20, height: 20)
                    .tint(.white)
                    .padding(8)
            default: EmptyView()
            }
        }
    }
}
