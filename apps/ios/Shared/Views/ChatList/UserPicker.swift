//
// Created by Avently on 16.01.2023.
// Copyright (c) 2023 SimpleX Chat. All rights reserved.
//

import SwiftUI
import SimpleXChat

struct UserPicker: View {
    @EnvironmentObject var m: ChatModel
    @EnvironmentObject var theme: AppTheme
    @Environment(\.dynamicTypeSize) private var userFont: DynamicTypeSize
    @Environment(\.scenePhase) private var scenePhase: ScenePhase
    @Environment(\.colorScheme) private var colorScheme: ColorScheme
    @Environment(\.dismiss) private var dismiss: DismissAction
    @Binding var activeSheet: UserPickerSheet?
    @State private var currentUser: Int64?
    @State private var switchingProfile = false
    @State private var frameWidth: CGFloat = 0

    // Inset grouped list dimensions
    private let imageSize: CGFloat = 44
    private let rowPadding: CGFloat = 16
    private let sectionSpacing: CGFloat = 35
    private var sectionHorizontalPadding: CGFloat { frameWidth > 375 ? 20 : 16 }
    private let sectionShape = RoundedRectangle(cornerRadius: 10, style: .continuous)

    var body: some View {
        if #available(iOS 16.0, *) {
            let v = viewBody.presentationDetents([.height(400)])
            if #available(iOS 16.4, *) {
                v.scrollBounceBehavior(.basedOnSize)
            } else {
                v
            }
        } else {
            viewBody
        }
    }

    @ViewBuilder
    private var viewBody: some View {
        let otherUsers: [UserInfo] = m.users
            .filter { u in !u.user.hidden && u.user.userId != m.currentUser?.userId }
            .sorted(using: KeyPathComparator<UserInfo>(\.user.activeOrder, order: .reverse))
        let sectionWidth = max(frameWidth - sectionHorizontalPadding * 2, 0)
        let currentUserWidth = max(frameWidth - sectionHorizontalPadding - rowPadding * 2 - 14 - imageSize, 0)
        VStack(spacing: 0) {
            if let user = m.currentUser {
                StickyScrollView {
                    HStack(spacing: rowPadding) {
                        HStack {
                            ProfileImage(imageStr: user.image, size: imageSize, color: Color(uiColor: .tertiarySystemGroupedBackground))
                                .padding(.trailing, 6)
                            profileName(user).lineLimit(1)
                        }
                        .padding(rowPadding)
                        .frame(width: otherUsers.isEmpty ? sectionWidth : currentUserWidth, alignment: .leading)
                        .background(Color(.secondarySystemGroupedBackground))
                        .clipShape(sectionShape)
                        .onTapGesture { activeSheet = .currentProfile }
                        ForEach(otherUsers) { u in
                            userView(u, size: imageSize)
                                .frame(maxWidth: sectionWidth * 0.618)
                                .fixedSize()
                        }
                    }
                    .padding(.horizontal, sectionHorizontalPadding)
                }
                .frame(height: 2 * rowPadding + imageSize)
                .padding(.top, sectionSpacing)
                .overlay(DetermineWidth())
                .onPreferenceChange(DetermineWidth.Key.self) { frameWidth = $0 }
            }
            List {
                Section {
                    openSheetOnTap("qrcode", title: m.userAddress == nil ? "Create SimpleX address" : "Your SimpleX address", sheet: .address)
                    openSheetOnTap("switch.2", title: "Chat preferences", sheet: .chatPreferences)
                    openSheetOnTap("person.crop.rectangle.stack", title: "Your chat profiles", sheet: .chatProfiles)
                    openSheetOnTap("desktopcomputer", title: "Use from desktop", sheet: .useFromDesktop)

                    ZStack(alignment: .trailing) {
                        openSheetOnTap("gearshape", title: "Settings", sheet: .settings)
                        Image(systemName: colorScheme == .light ? "sun.max" : "moon.fill")
                        .resizable()
                        .symbolRenderingMode(.monochrome)
                        .foregroundColor(theme.colors.secondary)
                        .frame(maxWidth: 20, maxHeight: 20)
                        .onTapGesture {
                            if (colorScheme == .light) {
                                ThemeManager.applyTheme(systemDarkThemeDefault.get())
                            } else {
                                ThemeManager.applyTheme(DefaultTheme.LIGHT.themeName)
                            }
                        }
                        .onLongPressGesture {
                            ThemeManager.applyTheme(DefaultTheme.SYSTEM_THEME_NAME)
                        }
                    }
                }
            }
        }
        .onAppear {
            // This check prevents the call of listUsers after the app is suspended, and the database is closed.
            if case .active = scenePhase {
                currentUser = m.currentUser?.userId
                Task {
                    do {
                        let users = try await listUsersAsync()
                        await MainActor.run {
                            m.users = users
                            currentUser = m.currentUser?.userId
                        }
                    } catch {
                        logger.error("Error loading users \(responseError(error))")
                    }
                }
            }
        }
        .modifier(ThemedBackground(grouped: true))
        .disabled(switchingProfile)
    }

    private func userView(_ u: UserInfo, size: CGFloat) -> some View {
        HStack {
            ZStack(alignment: .topTrailing) {
                ProfileImage(imageStr: u.user.image, size: size, color: Color(uiColor: .tertiarySystemGroupedBackground))
                if (u.unreadCount > 0) {
                    unreadBadge(u).offset(x: 4, y: -4)
                }
            }
            .padding(.trailing, 6)
            Text(u.user.displayName).font(.title2).lineLimit(1)
        }
        .padding(rowPadding)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(sectionShape)
        .onTapGesture {
            switchingProfile = true
            dismiss()
            Task {
                do {
                    try await changeActiveUserAsync_(u.user.userId, viewPwd: nil)
                    await MainActor.run { switchingProfile = false }
                } catch {
                    await MainActor.run {
                        switchingProfile = false
                        showAlert(
                            NSLocalizedString("Error switching profile!", comment: "alertTitle"),
                            message: String.localizedStringWithFormat(NSLocalizedString("Error: %@", comment: "alert message"), responseError(error))
                        )
                    }
                }
            }
        }
    }
    
    private func openSheetOnTap(_ icon: String, title: LocalizedStringKey, sheet: UserPickerSheet) -> some View {
        Button {
            activeSheet = sheet
        } label: {
            settingsRow(icon, color: theme.colors.secondary) {
                Text(title).foregroundColor(.primary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }
    
    private func unreadBadge(_ u: UserInfo) -> some View {
        let size = dynamicSize(userFont).chatInfoSize
        return unreadCountText(u.unreadCount)
            .font(userFont <= .xxxLarge ? .caption  : .caption2)
            .foregroundColor(.white)
            .padding(.horizontal, dynamicSize(userFont).unreadPadding)
            .frame(minWidth: size, minHeight: size)
            .background(u.user.showNtfs ? theme.colors.primary : theme.colors.secondary)
            .cornerRadius(dynamicSize(userFont).unreadCorner)
    }
}

struct UserPicker_Previews: PreviewProvider {
    static var previews: some View {
        @State var activeSheet: UserPickerSheet?

        let m = ChatModel()
        m.users = [UserInfo.sampleData, UserInfo.sampleData]
        return UserPicker(
            activeSheet: $activeSheet
        )
        .environmentObject(m)
    }
}
