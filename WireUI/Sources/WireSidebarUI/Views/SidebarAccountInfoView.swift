//
// Wire
// Copyright (C) 2024 Wire Swiss GmbH
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program. If not, see http://www.gnu.org/licenses/.
//

import SwiftUI
import WireFoundation

struct SidebarAccountInfoView<AccountImageView>: View where AccountImageView: View {

    @Environment(\.sidebarAccountInfoViewDisplayNameColor) private var displayNameColor
    @Environment(\.sidebarAccountInfoViewUsernameColor) private var usernameColor

    // MARK: - Life Cycle

    let displayName: String
    let username: String
    let accountImageView: () -> AccountImageView

    @State private var accountImageDiameter: CGFloat = 0

    var body: some View {
        HStack {
            accountImageView()
                .frame(width: accountImageDiameter, height: accountImageDiameter)

            // Let the account image height be exactly the same as one line
            // of the display name plus one line of the username (+ spacing)
            // and not grow with the wrapped texts (otherwise everything
            // together grows exponentially).
            // Therefore layout the texts twice, one preventing to be line-wrapped
            // and being invisible

            ZStack {
                displayNameAndUsername(displayName, username)
                    .lineLimit(1)
                    .layoutPriority(-1)
                    .opacity(0)
                    .disabled(true)
                    .background(GeometryReader { geometryProxy in
                        Color.clear.preference(
                            key: ProfileSwitcherHeightKey.self,
                            value: geometryProxy.size.height
                        )
                    })
                    .onPreferenceChange(ProfileSwitcherHeightKey.self) { height in
                        accountImageDiameter = height
                    }

                displayNameAndUsername(displayName, username)
            }
        }
    }

    @ViewBuilder
    private func displayNameAndUsername(_ displayName: String, _ username: String) -> some View {
        VStack(alignment: .leading) {
            Text(displayName)
                .font(.headline)
                .foregroundStyle(displayNameColor)
            Text(username)
                .font(.subheadline)
                .foregroundStyle(usernameColor)
        }
    }
}

extension SidebarAccountInfoView {

    init(
        _ displayName: String,
        _ username: String,
        _ accountImageView: @escaping () -> AccountImageView
    ) {
        self.init(
            displayName: displayName,
            username: username,
            accountImageView: accountImageView
        )
    }
}

private struct ProfileSwitcherHeightKey: PreferenceKey {
    static var defaultValue: CGFloat { 0 }
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

// MARK: - View Modifiers + Environment

extension View {
    func sidebarAccountInfoViewDisplayNameColor(_ displayNameColor: Color) -> some View {
        modifier(SidebarAccountInfoViewDisplayNameColorViewModifier(sidebarAccountInfoViewDisplayNameColor: displayNameColor))
    }

    func sidebarAccountInfoViewUsernameColor(_ usernameColor: Color) -> some View {
        modifier(SidebarAccountInfoViewUsernameColorViewModifier(sidebarAccountInfoViewUsernameColor: usernameColor))
    }
}

private extension EnvironmentValues {
    var sidebarAccountInfoViewDisplayNameColor: Color {
        get { self[SidebarAccountInfoViewDisplayNameColorKey.self] }
        set { self[SidebarAccountInfoViewDisplayNameColorKey.self] = newValue }
    }

    var sidebarAccountInfoViewUsernameColor: Color {
        get { self[SidebarAccountInfoViewUsernameColorKey.self] }
        set { self[SidebarAccountInfoViewUsernameColorKey.self] = newValue }
    }
}

struct SidebarAccountInfoViewDisplayNameColorViewModifier: ViewModifier {
    var sidebarAccountInfoViewDisplayNameColor: Color
    func body(content: Content) -> some View {
        content
            .environment(\.sidebarAccountInfoViewDisplayNameColor, sidebarAccountInfoViewDisplayNameColor)
    }
}

private struct SidebarAccountInfoViewDisplayNameColorKey: EnvironmentKey {
    static let defaultValue = Color.primary
}

struct SidebarAccountInfoViewUsernameColorViewModifier: ViewModifier {
    var sidebarAccountInfoViewUsernameColor: Color
    func body(content: Content) -> some View {
        content
            .environment(\.sidebarAccountInfoViewUsernameColor, sidebarAccountInfoViewUsernameColor)
    }
}

private struct SidebarAccountInfoViewUsernameColorKey: EnvironmentKey {
    static let defaultValue = Color.primary.opacity(0.7)
}

// MARK: - Previews

#Preview {
    SidebarAccountInfoPreview()
}
