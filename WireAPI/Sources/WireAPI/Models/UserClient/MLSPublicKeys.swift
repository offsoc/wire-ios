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

import Foundation

/// A container of MLS public keys.

public struct MLSPublicKeys: Equatable, Codable {

    /// The key for the ed25519 ciphersuite.

    public let ed25519: String?

    /// The key for the ed448 ciphersuite.

    public let ed448: String?

    /// The key for the p256 ciphersuite.

    public let p256: String?

    /// The key for the p384 ciphersuite.

    public let p384: String?

    /// The key for the p512 ciphersuite.

    public let p512: String?

    enum CodingKeys: String, CodingKey {

        case ed25519
        case ed448
        case p256 = "ecdsa_secp256r1_sha256"
        case p384 = "ecdsa_secp384r1_sha384"
        case p512 = "ecdsa_secp512r1_sha512"

    }

}
