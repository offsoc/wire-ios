//
// Wire
// Copyright (C) 2020 Wire Swiss GmbH
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

import Foundation

public extension ManagedObjectContextDirectory {

    /// Synchronously stores the given encryption keys in each managed object context.

    func storeEncryptionKeysInAllContexts(encryptionKeys: EncryptionKeys) {
        for context in [uiContext, syncContext, searchContext] {
            context?.performAndWait { context?.encryptionKeys = encryptionKeys }
        }
    }

    /// Synchronously clears the encryption keys in each managed object context.

    func clearEncryptionKeysInAllContexts() {
        for context in [uiContext, syncContext, searchContext] {
            context?.performAndWait { context?.encryptionKeys = nil }
        }
    }

}
