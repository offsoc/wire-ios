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

import UIKit

@testable import WireMainNavigationUI

struct MockConversationBuilder: MainConversationUIBuilderProtocol {

    typealias Dependencies = MockMainCoordinatorDependencies
    typealias ConversationUI = MockConversationViewController<Dependencies.ConversationModel>

    @MainActor
    func build<MainCoordinator: MainCoordinatorProtocol>(
        conversation: ConversationModel,
        message: ConversationMessageModel?,
        mainCoordinator: MainCoordinator
    ) -> ConversationUI where MainCoordinator.Dependencies == Dependencies {
        .init()
    }
}
