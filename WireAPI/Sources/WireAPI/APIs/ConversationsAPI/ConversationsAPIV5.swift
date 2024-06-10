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

class ConversationsAPIV5: ConversationsAPIV4 {
    override var apiVersion: APIVersion { .v5 }

    override func getConversations(for identifiers: [QualifiedID]) async throws -> ConversationList {
        let parameters = GetConversationsParametersV0(qualifiedIdentifiers: identifiers)
        let body = try JSONEncoder.defaultEncoder.encode(parameters)
        let resourcePath = "\(pathPrefix)/conversations/list"

        let request = HTTPRequest(
            path: resourcePath,
            method: .post,
            body: body
        )
        let response = try await self.httpClient.executeRequest(request)

        // Removed in v5: remove handling of error code 400
        return try ResponseParser()
            .success(code: 200, type: QualifiedConversationListV5.self) // Change in v5
            .parse(response)
    }
}

// MARK: Decodables

private struct QualifiedConversationListV5: Decodable, ToAPIModelConvertible {
    enum CodingKeys: String, CodingKey {
        case found = "found"
        case notFound = "not_found"
        case failed = "failed"
    }

    let found: [ConversationV5]
    let notFound: [QualifiedID]
    let failed: [QualifiedID]

    func toAPIModel() -> ConversationList {
        ConversationList(
            found: found.map { $0.toAPIModel() },
            notFound: notFound,
            failed: failed
        )
    }
}

// MARK: -

private struct ConversationV5: Decodable, ToAPIModelConvertible {
    enum CodingKeys: String, CodingKey {
        case access
        case accessRoles = "access_role"
        case cipherSuite = "cipher_suite"
        case creator
        case epoch
        case epochTimestamp = "epoch_timestamp"
        case id
        case lastEvent = "last_event"
        case lastEventTime = "last_event_time"
        case members
        case messageProtocol = "protocol"
        case messageTimer = "message_timer"
        case mlsGroupID = "group_id"
        case name
        case qualifiedID = "qualified_id"
        case readReceiptMode = "receipt_mode"
        case teamID = "team"
        case type
    }

    var access: [String]?
    var accessRoles: [String]?
    var cipherSuite: UInt16? // New field
    var creator: UUID?
    var epoch: UInt?
    var epochTimestamp: Date? // New field
    var id: UUID?
    var lastEvent: String?
    var lastEventTime: String?
    var members: QualifiedConversationMembers?
    var messageProtocol: String?
    var messageTimer: TimeInterval?
    var mlsGroupID: String?
    var name: String?
    var qualifiedID: QualifiedID?
    var readReceiptMode: Int?
    var teamID: UUID?
    var type: Int?

    func toAPIModel() -> Conversation {
        Conversation(
            access: access,
            accessRoles: accessRoles,
            cipherSuite: cipherSuite,
            creator: creator,
            epoch: epoch,
            epochTimestamp: epochTimestamp,
            id: id,
            lastEvent: lastEvent,
            lastEventTime: lastEventTime,
            legacyAccessRole: nil,
            members: members.map { $0.toAPIModel() },
            messageProtocol: messageProtocol,
            messageTimer: messageTimer,
            mlsGroupID: mlsGroupID,
            name: name,
            qualifiedID: qualifiedID,
            readReceiptMode: readReceiptMode,
            teamID: teamID,
            type: type
        )
    }
}
