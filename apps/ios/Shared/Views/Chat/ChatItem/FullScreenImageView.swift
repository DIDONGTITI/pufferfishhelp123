//
//  FullScreenImageView.swift
//  SimpleX (iOS)
//
//  Created by Evgeny on 08/10/2022.
//  Copyright © 2022 SimpleX Chat. All rights reserved.
//

import SwiftUI
import SimpleXChat

struct FullScreenImageView: View {
    @EnvironmentObject var m: ChatModel
    @State var chatItem: ChatItem
    @State var image: UIImage
    @Binding var showView: Bool
    @State var scrollProxy: ScrollViewProxy?
    @State private var showNext = false
    @State private var nextImage: UIImage?
    @State private var nextEdge = Edge.leading

    var body: some View {
        ZStack {
            Color.black.edgesIgnoringSafeArea(.all)
            ZoomableScrollView {
                imageView(image)
            }
            if showNext, let nextImage = nextImage {
                imageView(nextImage)
                    .transition(.move(edge: nextEdge))
            }
        }
        .onTapGesture { showView = false }
        .gesture(
            DragGesture(minimumDistance: 80)
            .onChanged { gesture in
                let t = gesture.translation
                if t.height > 60 && t.height > abs(t.width) * 2  {
                    showView = false
                    if let proxy = scrollProxy {
                        proxy.scrollTo(chatItem.viewId)
                    }
                }
            }
            .onEnded { gesture in
                let t = gesture.translation
                let w = abs(t.width)
                if w > 80 && w > abs(t.height) * 2 {
                    let previous = t.width > 0
                    if let item = m.nextChatItemData(chatItem.id, previous: previous, map: chatItemImage) {
                        var img: UIImage
                        (chatItem, img) = item
                        nextImage = img
                        nextEdge = previous ? .leading : .trailing
                        withAnimation(.easeIn(duration: 0.2)) {
                            showNext = true
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                            image = img
                            showNext = false
                        }
                    }
                }
            }
        )
    }

    private func imageView(_ img: UIImage) -> some View {
        ZStack {
            Color.black
            Image(uiImage: img)
                .resizable()
                .scaledToFit()
        }
    }

    private func chatItemImage(_ ci: ChatItem) -> (ChatItem, UIImage)? {
        if case .image = ci.content.msgContent,
           let img = getLoadedImage(ci.file) {
            return (ci, img)
        }
        return nil
    }
}
