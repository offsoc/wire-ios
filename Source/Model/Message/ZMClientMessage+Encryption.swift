//
// Wire
// Copyright (C) 2016 Wire Swiss GmbH
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
import Cryptobox

// MARK: - Encrypted data for recipients

/// Strategy for missing clients.
/// When sending a message through the backend, the backend might warn
/// us that some user clients that were supposed to be there are missing (e.g.
/// another user added a new client that we don't yet know about). The various
/// strategies give a hint to the backend of how we want to handle missing clients.
public enum MissingClientsStrategy {
    
    /// Fail the request if there is any missing client
    case doNotIgnoreAnyMissingClient
    /// Fail the request if there is any missing client for the given user,
    /// but ignore missing clients of any other user
    case ignoreAllMissingClientsNotFromUser(user: ZMUser)
    /// Do not fail the request, no matter which clients are missing
    case ignoreAllMissingClients
}

extension ZMClientMessage {
    
    /// Returns the payload encrypted for each recipients, and the strategy
    /// to use to handle missing clients
    public func encryptedMessagePayloadData() -> (data: Data, strategy: MissingClientsStrategy)? {
        guard let genericMessage = self.genericMessage, let conversation = self.conversation else {
            return nil
        }
        return genericMessage.encryptedMessagePayloadData(conversation, externalData: nil)
    }
}

extension ZMGenericMessage {
    
    /// Returns the payload encrypted for each recipients in the conversation, 
    /// and the strategy to use to handle missing clients
    func encryptedMessagePayloadData(_ conversation: ZMConversation,
                                             externalData: Data?)
        -> (data: Data, strategy: MissingClientsStrategy)?
    {
        guard let context = conversation.managedObjectContext
        else { return nil }
        guard let selfClient = ZMUser.selfUser(in: context).selfClient(), selfClient.remoteIdentifier != nil
        else { return nil }
        
        let encryptionContext = selfClient.keysStore.encryptionContext
        var messageDataAndStrategy : (data: Data, strategy: MissingClientsStrategy)?
        
        encryptionContext.perform { (sessionsDirectory) in
            let messageAndStrategy = self.otrMessage(selfClient,
                conversation: conversation,
                externalData: externalData,
                sessionDirectory: sessionsDirectory
            )
            var messageData = messageAndStrategy.message.data()
            
            // message too big?
            if let data = messageData, UInt(data.count) > ZMClientMessageByteSizeExternalThreshold && externalData == nil {
                // The payload is too big, we therefore rollback the session since we won't use the message we just encrypted.
                // This will prevent us advancing sender chain multiple time before sending a message, and reduce the risk of TooDistantFuture.
                sessionsDirectory.discardCache()
                messageData = self.encryptedMessageDataWithExternalDataBlob(conversation)!.data
            }
            if let data = messageData {
                messageDataAndStrategy = (data: data, strategy: messageAndStrategy.strategy)
            }
        }
        return messageDataAndStrategy
    }
    
    /// Returns a message with recipients and a strategy to handle missing clients
    fileprivate func otrMessage(_ selfClient: UserClient,
                            conversation: ZMConversation,
                            externalData: Data?,
                            sessionDirectory: EncryptionSessionsDirectory) -> (message: ZMNewOtrMessage, strategy: MissingClientsStrategy) {
        
        var recipientUsers : [ZMUser] = []
        let replyOnlyToSender = self.hasConfirmation()
        if replyOnlyToSender {
            // Reply is only supported on 1-to-1 conversations
            assert(conversation.conversationType == .oneOnOne)
            
            // In case of confirmation messages, we want to send the confirmation only to the clients of the sender of the original message, 
            // not to the other clients of the selfUser
            recipientUsers = [conversation.connectedUser!]
        } else {
            recipientUsers = conversation.activeParticipants.array as! [ZMUser]
        }
        
        let recipients = self.recipientsWithEncryptedData(selfClient, recipients: recipientUsers, sessionDirectory: sessionDirectory)

        let nativePush = !hasConfirmation() // We do not want to send pushes for delivery receipts
        let message = ZMNewOtrMessage.message(withSender: selfClient, nativePush: nativePush, recipients: recipients, blob: externalData)
        
        let strategy : MissingClientsStrategy =
            replyOnlyToSender ?
                .ignoreAllMissingClientsNotFromUser(user: recipientUsers.first!)
                : .doNotIgnoreAnyMissingClient
        return (message: message, strategy: strategy)
    }
    
    /// Returns the recipients and the encrypted data for each recipient
    func recipientsWithEncryptedData(_ selfClient: UserClient,
                                             recipients: [ZMUser],
                                             sessionDirectory: EncryptionSessionsDirectory
        ) -> [ZMUserEntry]
    {
        let userEntries = recipients.flatMap { user -> ZMUserEntry? in
                let clientsEntries = user.clients.flatMap { client -> ZMClientEntry? in
                if client != selfClient {
                    guard let clientRemoteIdentifier = client.remoteIdentifier else { return nil }
                    
                    let corruptedClient = client.failedToEstablishSession
                    client.failedToEstablishSession = false
                    
                    let hasSessionWithClient = sessionDirectory.hasSessionForID(clientRemoteIdentifier)
                    if !hasSessionWithClient {
                        // if the session is corrupted, will send a special payload
                        if corruptedClient {
                            let data = ZMFailedToCreateEncryptedMessagePayloadString.data(using: String.Encoding.utf8)!
                            return ZMClientEntry.entry(withClient: client, data: data)
                        }
                        else {
                            // does not have session, will need to fetch prekey and create client
                            return nil
                        }
                    }
                    
                    guard let encryptedData = try? sessionDirectory.encrypt(self.data(), recipientClientId: clientRemoteIdentifier) else {
                        return nil
                    }
                    return ZMClientEntry.entry(withClient: client, data: encryptedData)
                } else {
                    return nil
                }
            }
            
            if clientsEntries.isEmpty {
                return nil
            }
            return ZMUserEntry.entry(withUser: user, clientEntries: clientsEntries)
        }
        return userEntries
    }
    
}

// MARK: - External
extension ZMGenericMessage {
    
    /// Returns a message with recipients, with the content stored externally, and a strategy to handle missing clients
    fileprivate func encryptedMessageDataWithExternalDataBlob(_ conversation: ZMConversation) -> (data: Data, strategy: MissingClientsStrategy)? {
        
        guard let encryptedDataWithKeys = ZMGenericMessage.encryptedDataWithKeys(from: self)
        else {return nil}
        
        let externalGenericMessage = ZMGenericMessage.genericMessage(withKeyWithChecksum: encryptedDataWithKeys.keys, messageID: NSUUID().transportString())
        return externalGenericMessage.encryptedMessagePayloadData(conversation, externalData: encryptedDataWithKeys.data)
    }
}
