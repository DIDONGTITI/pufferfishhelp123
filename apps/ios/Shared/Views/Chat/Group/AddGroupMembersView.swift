//
//  AddGroupMembersView.swift
//  SimpleX (iOS)
//
//  Created by JRoberts on 22.07.2022.
//  Copyright © 2022 SimpleX Chat. All rights reserved.
//

import SwiftUI
import SimpleXChat

struct AddGroupMembersView: View {
    @EnvironmentObject var chatModel: ChatModel
    @Environment(\.dismiss) var dismiss: DismissAction
    var chat: Chat
    var groupInfo: GroupInfo
    var showSkip: Bool = false
    var addedMembersCb: ((Set<Int64>) -> Void)? = nil
    @State private var selectedContacts = Set<Int64>()
    @State private var selectedRole: GroupMemberRole = .admin

    var body: some View {
        NavigationView {
            let membersToAdd = filterMembersToAdd(chatModel.groupMembers)

            let v = List {
                ChatInfoToolbar(chat: chat, imageSize: 48)
                .frame(maxWidth: .infinity, alignment: .center)
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)

                if (membersToAdd.isEmpty) {
                    Text("No contacts to add")
                        .foregroundColor(.secondary)
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .center)
                        .listRowBackground(Color.clear)
                } else {
                    let count = selectedContacts.count
                    Section {
                        rolePicker()
                        inviteMembersButton()
                            .disabled(count < 1)
                    } footer: {
                        if (count >= 1) {
                            HStack {
                                Button { selectedContacts.removeAll() } label: { Text("Clear") }
                                Spacer()
                                Text("\(count) contact(s) selected")
                            }
                        } else {
                            Text("No contacts selected")
                                .frame(maxWidth: .infinity, alignment: .trailing)
                        }
                    }

                    Section {
                        ForEach(membersToAdd) { contact in
                            contactCheckView(contact)
                        }
                    }
                }
            }

            if (showSkip) {
                v.toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        if showSkip {
                            Button ("Skip") {
                                if let cb = addedMembersCb { cb(selectedContacts) }
                            }
                        }
                    }
                }
            } else {
                v.navigationBarHidden(true)
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }

    func inviteMembersButton() -> some View {
        Button {
            Task {
                do {
                    for contactId in selectedContacts {
                        try await apiAddMember(groupInfo.groupId, contactId, selectedRole)
                        // await MainActor.run { ChatModel.shared.upsertGroupMember(groupInfo, member) }
                    }
                    await MainActor.run { dismiss() }
                    if let cb = addedMembersCb { cb(selectedContacts) }
                } catch {
                    AlertManager.shared.showAlert(
                        Alert(
                            title: Text("Error adding member(s)"),
                            message: Text(responseError(error))
                        )
                    )
                }
            }
        } label: {
            HStack {
                Text("Invite to group")
                Image(systemName: "checkmark")
            }
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
    }

    func rolePicker() -> some View {
        Picker("New member role", selection: $selectedRole) {
            ForEach(GroupMemberRole.allCases) { role in
                if role <= groupInfo.membership.memberRole {
                    Text(role.text)
                }
            }
        }
    }

    func contactCheckView(_ contact: Contact) -> some View {
        let checked = selectedContacts.contains(contact.apiId)
        return Button {
            if checked {
                selectedContacts.remove(contact.apiId)
            } else {
                selectedContacts.insert(contact.apiId)
            }
        } label: {
            HStack{
                ProfileImage(imageStr: contact.image)
                    .frame(width: 30, height: 30)
                    .padding(.trailing, 2)
                Text(ChatInfo.direct(contact: contact).chatViewName)
                    .foregroundColor(.primary)
                    .lineLimit(1)
                Spacer()
                Image(systemName: checked ? "checkmark.circle.fill": "circle")
                    .foregroundColor(checked ? .accentColor : Color(uiColor: .tertiaryLabel))
            }
        }
    }
}

struct AddGroupMembersView_Previews: PreviewProvider {
    static var previews: some View {
        AddGroupMembersView(chat: Chat(chatInfo: ChatInfo.sampleData.group), groupInfo: GroupInfo.sampleData)
    }
}
