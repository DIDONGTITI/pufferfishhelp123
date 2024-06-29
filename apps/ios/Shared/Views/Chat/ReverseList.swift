//
//  ReverseList.swift
//  SimpleX (iOS)
//
//  Created by Levitating Pineapple on 11/06/2024.
//  Copyright © 2024 SimpleX Chat. All rights reserved.
//

import SwiftUI
import Combine

/// A List, which displays it's items in reverse order - from bottom to top
struct ReverseList<Item: Identifiable & Hashable & Sendable, Content: View>: UIViewControllerRepresentable {

    let items: Array<Item>

    @Binding var scrollState: ReverseListScrollModel<Item>.State

    /// Closure, that returns user interface for a given item
    let content: (Item) -> Content

    func makeUIViewController(context: Context) -> Controller {
        Controller(representer: self)
    }

    func updateUIViewController(_ controller: Controller, context: Context) {
        if case let .scrollingTo(destination) = scrollState, !items.isEmpty {
            switch destination {
            case let .item(id):
                controller.scroll(to: items.firstIndex(where: { $0.id == id }))
            case .bottom:
                controller.scroll(to: .zero)
            case .top:
                controller.scroll(to: items.count - 1)
            }
        } else {
            controller.update(items: items)
        }
    }

    /// Controller, which hosts SwiftUI cells
    class Controller: UITableViewController {
        private enum Section { case main }
        private let representer: ReverseList
        private var dataSource: UITableViewDiffableDataSource<Section, Item>!
        private var itemCount: Int = .zero
        private var bag = Set<AnyCancellable>()

        init(representer: ReverseList) {
            self.representer = representer
            super.init(style: .plain)

            // 1. Style
            tableView.separatorStyle = .none
            tableView.transform = .verticalFlip

            // 2. Register cells
            if #available(iOS 16.0, *) {
                tableView.register(
                    UITableViewCell.self,
                    forCellReuseIdentifier: cellReuseId
                )
            } else {
                tableView.register(
                    HostingCell<Content>.self,
                    forCellReuseIdentifier: cellReuseId
                )
            }

            // 3. Configure data source
            self.dataSource = UITableViewDiffableDataSource<Section, Item>(
                tableView: tableView
            ) { (tableView, indexPath, item) -> UITableViewCell? in
                let cell = tableView.dequeueReusableCell(withIdentifier: cellReuseId, for: indexPath)
                if #available(iOS 16.0, *) {
                    cell.contentConfiguration = UIHostingConfiguration { self.representer.content(item) }
                        .margins(.all, .zero)
                        .minSize(height: 1) // Passing zero will result in system default of 44 points being used
                } else {
                    if let cell = cell as? HostingCell<Content> {
                        cell.set(content: self.representer.content(item), parent: self)
                    } else {
                        fatalError("Unexpected Cell Type for: \(item)")
                    }
                }
                cell.transform = .verticalFlip
                cell.selectionStyle = .none
                return cell
            }

            // 5. External state changes will require manual layout updates
            NotificationCenter.default
                .addObserver(
                    self,
                    selector: #selector(updateLayout),
                    name: notificationName,
                    object: nil
                )
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError() }

        deinit { NotificationCenter.default.removeObserver(self) }

        @objc private func updateLayout() {
            tableView.setNeedsLayout()
            tableView.layoutIfNeeded()
        }

        /// Hides keyboard, when user begins to scroll.
        /// Equivalent to `.scrollDismissesKeyboard(.immediately)`
        override func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
            UIApplication.shared
                .sendAction(
                    #selector(UIResponder.resignFirstResponder),
                    to: nil,
                    from: nil,
                    for: nil
                )
        }

        /// Scrolls to Item at index path
        /// - Parameter indexPath: Item to scroll to - will scroll to beginning of the list, if `nil`
        func scroll(to index: Int?) {
            if let index {
                tableView.scrollToRow(
                    at: IndexPath(row: index, section: .zero),
                    at: .middle,
                    animated: true
                )
                Task { representer.scrollState = .atDestination }
            }
        }

        func update(items: Array<Item>) {
            var snapshot = NSDiffableDataSourceSnapshot<Section, Item>()
            snapshot.appendSections([.main])
            snapshot.appendItems(items)
            dataSource.defaultRowAnimation = .none
            var animatingDifferences = false
            if #available(iOS 16.0, *) {
                animatingDifferences = itemCount != .zero && abs(items.count - itemCount) == 1
            }
            dataSource.apply(snapshot, animatingDifferences: animatingDifferences)
            itemCount = items.count
        }
    }

    /// `UIHostingConfiguration` back-port for iOS14 and iOS15
    /// Implemented as a `UITableViewCell` that wraps and manages a generic `UIHostingController`
    private final class HostingCell<Hosted: View>: UITableViewCell {
        private let hostingController = UIHostingController<Hosted?>(rootView: nil)

        /// Updates content of the cell
        /// For reference: https://noahgilmore.com/blog/swiftui-self-sizing-cells/
        func set(content: Hosted, parent: UIViewController) {
            hostingController.rootView = content
            if let hostingView = hostingController.view {
                hostingView.invalidateIntrinsicContentSize()
                if hostingController.parent != parent { parent.addChild(hostingController) }
                if !contentView.subviews.contains(hostingController.view) {
                    contentView.addSubview(hostingController.view)
                    hostingView.translatesAutoresizingMaskIntoConstraints = false
                    NSLayoutConstraint.activate([
                        hostingView.leadingAnchor
                            .constraint(equalTo: contentView.leadingAnchor),
                        hostingView.trailingAnchor
                            .constraint(equalTo: contentView.trailingAnchor),
                        hostingView.topAnchor
                            .constraint(equalTo: contentView.topAnchor),
                        hostingView.bottomAnchor
                            .constraint(equalTo: contentView.bottomAnchor)
                    ])
                }
                if hostingController.parent != parent { hostingController.didMove(toParent: parent) }
            } else {
                fatalError("Hosting View not loaded \(hostingController)")
            }
        }
    }
}

/// Manages ``ReverseList`` scrolling
class ReverseListScrollModel<Item: Identifiable>: ObservableObject {
    /// Represents Scroll State of ``ReverseList``
    enum State: Equatable {
        enum Destination: Equatable {
            case top
            case item(Item.ID)
            case bottom
        }

        case scrollingTo(Destination)
        case atDestination
    }

    @Published var state: State = .atDestination

    func scrollToTop() {
        state = .scrollingTo(.top)
    }

    func scrollToBottom() {
        state = .scrollingTo(.bottom)
    }

    func scrollToItem(id: Item.ID) {
        state = .scrollingTo(.item(id))
    }
}

fileprivate let cellReuseId = "hostingCell"

fileprivate let notificationName = NSNotification.Name(rawValue: "reverseListNeedsLayout")

fileprivate extension CGAffineTransform {
    /// Transform that vertically flips the view, preserving it's location
    static let verticalFlip = CGAffineTransform(scaleX: 1, y: -1)
}

extension NotificationCenter {
    static func postReverseListNeedsLayout() {
        NotificationCenter.default.post(
            name: notificationName,
            object: nil
        )
    }
}

