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
import WireAPI
import WireDataModel

/// Access update events.

protocol UpdateEventsRepositoryProtocol {

    /// Pull pending events from the server, decrypt if needed, and store locally.
    ///
    /// Pending events are events that have been buffered by the server while
    /// the self client has not had an active push channel.

    func pullPendingEvents() async throws

    /// Fetch the next batch pending events from the database.
    /// 
    /// The batch is already sorted, such that the first element is the oldest
    /// stored event. This method does not delete any events, so invoking this
    /// method again will return the same batch.
    ///
    /// - Parameter limit: The maximum number of events to fetch.
    /// - Returns: Decrypted update event envelopes ready for processing.

    func fetchNextPendingEvents(limit: UInt) async throws -> [UpdateEventEnvelope]

}

final class UpdateEventsRepository: UpdateEventsRepositoryProtocol {

    private let selfClientID: String
    private let updateEventsAPI: any UpdateEventsAPI
    private let updateEventDecryptor: any UpdateEventDecryptorProtocol
    private let eventContext: NSManagedObjectContext
    private let lastEventIDRepository: any LastEventIDRepositoryInterface

    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(
        selfClientID: String,
        updateEventsAPI: any UpdateEventsAPI,
        updateEventDecryptor: any UpdateEventDecryptorProtocol,
        eventContext: NSManagedObjectContext,
        lastEventIDRepository: any LastEventIDRepositoryInterface
    ) {
        self.selfClientID = selfClientID
        self.updateEventsAPI = updateEventsAPI
        self.updateEventDecryptor = updateEventDecryptor
        self.eventContext = eventContext
        self.lastEventIDRepository = lastEventIDRepository
    }

    // MARK: - Pull pending events

    func pullPendingEvents() async throws {
        // We want all events since this event.
        guard let lastEventID = lastEventIDRepository.fetchLastEventID() else {
            throw UpdateEventsRepositoryError.lastEventIDMissing
        }

        // We'll insert new events from this index.
        var currentIndex = try await indexOfLastEventEnvelope() + 1

        // Events are fetched in batches.
        for try await envelopes in updateEventsAPI.getUpdateEvents(
            selfClientID: selfClientID,
            sinceEventID: lastEventID
        ) {
            for envelope in envelopes {
                // We can only decrypt once so store the decrypted events for later retrieval.
                var decryptedEnvelope = envelope
                decryptedEnvelope.events = try await updateEventDecryptor.decryptEvents(in: envelope)

                try await persistEventEnvelope(
                    decryptedEnvelope,
                    index: currentIndex
                )

                currentIndex += 1

                if !envelope.isTransient {
                    // Update the last event id so we don't refetch the same events.
                    // Transient events aren't stored in the backend's event stream.
                    lastEventIDRepository.storeLastEventID(envelope.id)
                }
            }
        }
    }

    private func indexOfLastEventEnvelope() async throws -> Int64 {
        try await eventContext.perform { [eventContext] in
            let request = StoredUpdateEventEnvelope.sortedFetchRequest(asending: false)
            request.fetchBatchSize = 1
            let lastEnvelope = try eventContext.fetch(request).first
            return lastEnvelope?.sortIndex ?? 0
        }
    }

    private func persistEventEnvelope(
        _ eventEnvelope: UpdateEventEnvelope,
        index: Int64
    ) async throws {
        try await eventContext.perform { [eventContext, encoder] in
            let data = try encoder.encode(eventEnvelope)

            if let string = String(data: data, encoding: .utf8) {
                print("persisting event: \(string)")
            }

            let storedEventEnvelope = StoredUpdateEventEnvelope(context: eventContext)
            storedEventEnvelope.data = data
            storedEventEnvelope.sortIndex = index
            try eventContext.save()
        }
    }

    // MARK: - Fetch pending events

    func fetchNextPendingEvents(limit: UInt) async throws -> [UpdateEventEnvelope] {
        let payloads = try await fetchStoredEventEnvelopePayloads(limit: limit)
        return try decodeEventEnvelopes(payloads)
    }

    private func fetchStoredEventEnvelopePayloads(limit: UInt) async throws -> [Data] {
        try await eventContext.perform { [eventContext] in
            do {
                let request = StoredUpdateEventEnvelope.sortedFetchRequest(asending: true)
                request.fetchLimit = Int(limit)
                request.returnsObjectsAsFaults = false
                let storedEventEnvelopes = try eventContext.fetch(request)
                return storedEventEnvelopes.map(\.data)
            } catch {
                throw UpdateEventsRepositoryError.failedToFetchStoredEvents(error)
            }
        }
    }

    private func decodeEventEnvelopes(_ payloads: [Data]) throws -> [UpdateEventEnvelope] {
        try payloads.map {
            do {
                return try decoder.decode(UpdateEventEnvelope.self, from: $0)
            } catch {
                throw UpdateEventsRepositoryError.failedToDecodeStoredEvent(error)
            }
        }
    }

}
