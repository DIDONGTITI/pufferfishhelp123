//
// Created by Avently on 16.01.2023.
// Copyright (c) 2023 SimpleX Chat. All rights reserved.
//

import SwiftUI
import SimpleXChat

private let fillColorDark = Color(uiColor: UIColor(red: 0.11, green: 0.11, blue: 0.11, alpha: 255))
private let fillColorLight = Color(uiColor: UIColor(red: 0.99, green: 0.99, blue: 0.99, alpha: 255))

struct UserPicker: View {
    @EnvironmentObject var m: ChatModel
    @Environment(\.colorScheme) var colorScheme
    @Binding var showSettings: Bool
    @Binding var userPickerVisible: Bool
    @State var scrollViewContentSize: CGSize = .zero
    @State var disableScrolling: Bool = true
    private let menuButtonHeight: CGFloat = 68
    @State var chatViewNameWidth: CGFloat = 0

    var fillColor: Color {
        colorScheme == .dark ? fillColorDark : fillColorLight
    }

    var body: some View {
        VStack { // .sorted({ first, _ in first.user.activeUser })
            Spacer().frame(height: 1)
            VStack(spacing: 0) {
                ScrollView {
                    ScrollViewReader { sp in
                        VStack(spacing: 0) {
                            ForEach(Array(m.users.sorted(by: { u, _ in u.user.activeUser }))) { u in
                                userView(u)
                                Divider()
                            }
                        }
                        .overlay {
                            GeometryReader { geo -> Color in
                                DispatchQueue.main.async {
                                    scrollViewContentSize = geo.size
                                    let scenes = UIApplication.shared.connectedScenes
                                    if let windowScene = scenes.first as? UIWindowScene {
                                        let layoutFrame = windowScene.windows[0].safeAreaLayoutGuide.layoutFrame
                                        disableScrolling = scrollViewContentSize.height + menuButtonHeight + 10 < layoutFrame.height
                                    }
                                }
                                return Color.clear
                            }
                        }
                        .onChange(of: userPickerVisible) { visible in
                            if visible {
                                sp.scrollTo(0)
                            }
                        }
                    }
                }
                .simultaneousGesture(DragGesture(minimumDistance: disableScrolling ? 0 : 10000000))
                .frame(maxHeight: scrollViewContentSize.height)

                menuButton("Settings", icon: "gearshape") {
                    showSettings = true
                    withAnimation {
                        userPickerVisible.toggle()
                    }
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .background(
            Rectangle()
                .fill(fillColor)
                .cornerRadius(16)
                .shadow(color: .black.opacity(0.12), radius: 24, x: 0, y: 0)
        )
        .onPreferenceChange(DetermineWidth.Key.self) { chatViewNameWidth = $0 }
        .frame(maxWidth: chatViewNameWidth > 0 ? min(300, chatViewNameWidth + 130) : 300)
        .padding(8)
        .opacity(userPickerVisible ? 1.0 : 0.0)
        .onAppear {
            do {
                m.users = try listUsers()
            } catch let error {
                logger.error("Error updating users \(responseError(error))")
            }
        }
    }

    private func userView(_ u: UserInfo) -> some View {
        let user = u.user
        return Button(action: {
            if !user.activeUser {
                changeActiveUser(user.userId)
                userPickerVisible = false
            }
        }, label: {
            HStack(spacing: 0) {
                ProfileImage(imageStr: user.image)
                    .frame(width: 44, height: 44)
                    .padding(.trailing, 12)
                Text(user.chatViewName)
                    .fontWeight(user.activeUser ? .medium : .regular)
                    .foregroundColor(.primary)
                    .overlay(DetermineWidth())
                Spacer()
                if user.activeUser {
                    Image(systemName: "checkmark")
                } else if u.unreadCount > 0 {
                    unreadCounter(u.unreadCount)
                }
            }
            .padding(.trailing)
            .padding([.leading, .vertical], 12)
        })
        .buttonStyle(PressedButtonStyle(defaultColor: fillColor, pressedColor: Color(uiColor: .secondarySystemFill)))
    }

    private func menuButton(_ title: LocalizedStringKey, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 0) {
                Text(title)
                    .overlay(DetermineWidth())
                Spacer()
                Image(systemName: icon)
//                    .frame(width: 24, alignment: .center)
            }
            .padding(.horizontal)
            .padding(.vertical, 22)
            .frame(height: menuButtonHeight)
        }
        .buttonStyle(PressedButtonStyle(defaultColor: fillColor, pressedColor: Color(uiColor: .secondarySystemFill)))
    }
}

func unreadCounter(_ unread: Int64) -> some View {
    unreadCountText(Int(truncatingIfNeeded: unread))
    .font(.caption)
    .foregroundColor(.white)
    .padding(.horizontal, 4)
    .frame(minWidth: 18, minHeight: 18)
    .background(Color.accentColor)
    .cornerRadius(10)
}

struct UserPicker_Previews: PreviewProvider {
    static var previews: some View {
        let m = ChatModel()
        m.users = [UserInfo.sampleData, UserInfo.sampleData]
        return UserPicker(
            showSettings: Binding.constant(false),
            userPickerVisible: Binding.constant(true)
        )
        .environmentObject(m)
    }
}
