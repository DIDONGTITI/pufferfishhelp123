//
//  CIFileView.swift
//  SimpleX
//
//  Created by JRoberts on 28/04/2022.
//  Copyright © 2022 SimpleX Chat. All rights reserved.
//

import SwiftUI
import SimpleXChat

struct CIFileView: View {
    @Environment(\.colorScheme) var colorScheme
    let file: CIFile?
    let edited: Bool

    var body: some View {
        let metaReserve = edited
          ? "                         "
          : "                     "
        Button(action: fileAction) {
            HStack(alignment: .bottom, spacing: 6) {
                fileIndicator()
                    .padding(.top, 5)
                    .padding(.bottom, 3)
                if let file = file {
                    let prettyFileSize = ByteCountFormatter().string(fromByteCount: file.fileSize)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(file.fileName)
                            .lineLimit(1)
                            .multilineTextAlignment(.leading)
                            .foregroundColor(.primary)
                        Text(prettyFileSize + metaReserve)
                            .font(.caption)
                            .lineLimit(1)
                            .multilineTextAlignment(.leading)
                            .foregroundColor(.secondary)
                    }
                } else {
                    Text(metaReserve)
                }
            }
            .padding(.top, 4)
            .padding(.bottom, 6)
            .padding(.leading, 10)
            .padding(.trailing, 12)
        }
        .disabled(file == nil || (file?.fileStatus != .rcvInvitation && file?.fileStatus != .rcvAccepted && file?.fileStatus != .rcvComplete))
    }

    func fileSizeValid() -> Bool {
        if let file = file {
            return file.fileSize <= maxFileSize
        }
        return false
    }

    func fileAction() {
        logger.debug("CIFileView fileAction")
        if let file = file {
            switch (file.fileStatus) {
            case .rcvInvitation:
                if fileSizeValid() {
                    Task {
                        logger.debug("CIFileView fileAction - in .rcvInvitation, in Task")
                        await receiveFile(fileId: file.fileId)
                    }
                } else {
                    let prettyMaxFileSize = ByteCountFormatter().string(fromByteCount: maxFileSize)
                    AlertManager.shared.showAlertMsg(
                        title: "Large file!",
                        message: "Your contact sent a file that is larger than currently supported maximum size (\(prettyMaxFileSize))."
                    )
                }
            case .rcvAccepted:
                AlertManager.shared.showAlertMsg(
                    title: "Waiting for file",
                    message: "File will be received when your contact is online, please wait or check later!"
                )
            case .rcvComplete:
                logger.debug("CIFileView fileAction - in .rcvComplete")
                if let filePath = getLoadedFilePath(file){
                    let url = URL(fileURLWithPath: filePath)
                    showShareSheet(items: [url])
                }
            default: break
            }
        }
    }

    @ViewBuilder func fileIndicator() -> some View {
        if let file = file {
            switch file.fileStatus {
            case .sndStored: fileIcon("doc.fill")
            case .sndTransfer: ProgressView().frame(width: 30, height: 30)
            case .sndComplete: fileIcon("doc.fill", innerIcon: "checkmark", innerIconSize: 10)
            case .sndCancelled: fileIcon("doc.fill", innerIcon: "xmark", innerIconSize: 10)
            case .rcvInvitation:
                if fileSizeValid() {
                    fileIcon("arrow.down.doc.fill", color: .accentColor)
                } else {
                    fileIcon("doc.fill", color: .orange, innerIcon: "exclamationmark", innerIconSize: 12)
                }
            case .rcvAccepted: fileIcon("doc.fill", innerIcon: "ellipsis", innerIconSize: 12)
            case .rcvTransfer: ProgressView().frame(width: 30, height: 30)
            case .rcvComplete: fileIcon("doc.fill")
            case .rcvCancelled: fileIcon("doc.fill", innerIcon: "xmark", innerIconSize: 10)
            }
        } else {
            fileIcon("doc.fill")
        }
    }

    func fileIcon(_ icon: String, color: Color = Color(uiColor: .tertiaryLabel), innerIcon: String? = nil, innerIconSize: CGFloat? = nil) -> some View {
        ZStack(alignment: .center) {
            Image(systemName: icon)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 30, height: 30)
                .foregroundColor(color)
            if let innerIcon = innerIcon,
               let innerIconSize = innerIconSize {
                Image(systemName: innerIcon)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxHeight: 16)
                    .frame(width: innerIconSize, height: innerIconSize)
                    .foregroundColor(.white)
                    .padding(.top, 12)
            }
        }
    }
}

struct CIFileView_Previews: PreviewProvider {
    static var previews: some View {
        let sentFile: ChatItem = ChatItem(
            chatDir: .directSnd,
            meta: CIMeta.getSample(1, .now, "", .sndSent, false, true, false),
            content: .sndMsgContent(msgContent: .file("")),
            quotedItem: nil,
            file: CIFile.getSample(fileStatus: .sndComplete)
        )
        let fileChatItemWtFile = ChatItem(
            chatDir: .directRcv,
            meta: CIMeta.getSample(1, .now, "", .rcvRead, false, false, false),
            content: .rcvMsgContent(msgContent: .file("")),
            quotedItem: nil,
            file: nil
        )
        Group {
            ChatItemView(chatInfo: ChatInfo.sampleData.direct, chatItem: sentFile)
            ChatItemView(chatInfo: ChatInfo.sampleData.direct, chatItem: ChatItem.getFileMsgContentSample())
            ChatItemView(chatInfo: ChatInfo.sampleData.direct, chatItem: ChatItem.getFileMsgContentSample(fileName: "some_long_file_name_here", fileStatus: .rcvInvitation))
            ChatItemView(chatInfo: ChatInfo.sampleData.direct, chatItem: ChatItem.getFileMsgContentSample(fileStatus: .rcvAccepted))
            ChatItemView(chatInfo: ChatInfo.sampleData.direct, chatItem: ChatItem.getFileMsgContentSample(fileStatus: .rcvTransfer))
            ChatItemView(chatInfo: ChatInfo.sampleData.direct, chatItem: ChatItem.getFileMsgContentSample(fileStatus: .rcvCancelled))
            ChatItemView(chatInfo: ChatInfo.sampleData.direct, chatItem: ChatItem.getFileMsgContentSample(fileSize: 1_000_000_000, fileStatus: .rcvInvitation))
            ChatItemView(chatInfo: ChatInfo.sampleData.direct, chatItem: ChatItem.getFileMsgContentSample(text: "Hello there", fileStatus: .rcvInvitation))
            ChatItemView(chatInfo: ChatInfo.sampleData.direct, chatItem: ChatItem.getFileMsgContentSample(text: "Lorem ipsum dolor sit amet, consectetur adipiscing elit, sed do eiusmod tempor incididunt ut labore et dolore magna aliqua. Ut enim ad minim veniam, quis nostrud exercitation ullamco laboris nisi ut aliquip ex ea commodo consequat. Duis aute irure dolor in reprehenderit in voluptate velit esse cillum dolore eu fugiat nulla pariatur. Excepteur sint occaecat cupidatat non proident, sunt in culpa qui officia deserunt mollit anim id est laborum.", fileStatus: .rcvInvitation))
            ChatItemView(chatInfo: ChatInfo.sampleData.direct, chatItem: fileChatItemWtFile)
        }
        .previewLayout(.fixed(width: 360, height: 360))
    }
}
