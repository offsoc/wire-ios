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
// along with this program. If not, see <http://www.gnu.org/licenses/>.
// 


import Foundation
import ZMCDataModel

private let zmLog = ZMSLog(tag: "Pingback")

// MARK: - AuthenticationStatusProvider

@objc public protocol AuthenticationStatusProvider {
    var currentPhase: ZMAuthenticationPhase { get }
}

extension ZMAuthenticationStatus: AuthenticationStatusProvider {}


// MARK: - LocalNotificationDispatchType

@objc public protocol LocalNotificationDispatchType {
    func didReceiveUpdateEvents(events: [ZMUpdateEvent]?)
}

extension ZMLocalNotificationDispatcher: LocalNotificationDispatchType {}


// MARK: - EventsWithIdentifier

@objc public class EventsWithIdentifier: NSObject  {
    public let events: [ZMUpdateEvent]?
    public let identifier: NSUUID
    public let isNotice : Bool
    
    public init(events: [ZMUpdateEvent]?, identifier: NSUUID, isNotice: Bool) {
        self.events = events
        self.identifier = identifier
        self.isNotice = isNotice
    }
    
    public func filteredWithoutPreexistingNonces(nonces: [NSUUID]) -> EventsWithIdentifier {
        let filteredEvents = events?.filter { event in
            guard let nonce = event.messageNonce() else { return true }
            return !nonces.contains(nonce)
        }
        return EventsWithIdentifier(events: filteredEvents, identifier: identifier, isNotice: isNotice)
    }
}

extension EventsWithIdentifier {
    override public var debugDescription: String {
        return "<EventsWithIdentifier>: identifier: \(identifier), events: \(events)"
    }
}


// MARK: - BackgroundAPNSPingBackStatus

@objc public enum PingBackStatus: Int  {
    case Pinging, FetchingNotice, Done
}

@objc public class BackgroundAPNSPingBackStatus: NSObject {

    public typealias PingBackResultHandler = (ZMPushPayloadResult, [ZMUpdateEvent]) -> Void
    public typealias EventsWithHandler = (events: [ZMUpdateEvent]?, handler: PingBackResultHandler)
    
    public private(set) var eventsWithHandlerByNotificationID: [NSUUID: EventsWithHandler] = [:]
    public private(set) var backgroundActivity: ZMBackgroundActivity?
    public var status: PingBackStatus = .Done

    public var hasNotificationIDs: Bool {
        return !notificationIDs.isEmpty
    }
    
    public var hasNoticeNotificationIDs: Bool {
        return !noticeNotificationIDs.isEmpty
    }
    
    private var notificationIDs: [NSUUID] = []
    private var noticeNotificationIDs: [NSUUID] = []
    private var notificationIDToEventsMap : [NSUUID : [ZMUpdateEvent]] = [:]
    
    private var syncManagedObjectContext: NSManagedObjectContext
    private weak var authenticationStatusProvider: AuthenticationStatusProvider?
    private weak var notificationDispatcher: LocalNotificationDispatchType?
    
    public init(
        syncManagedObjectContext moc: NSManagedObjectContext,
        authenticationProvider: AuthenticationStatusProvider,
        localNotificationDispatcher: LocalNotificationDispatchType
        ) {
        syncManagedObjectContext = moc
        authenticationStatusProvider = authenticationProvider
        notificationDispatcher = localNotificationDispatcher
        super.init()
    }
    
    deinit {
        backgroundActivity?.endActivity()
    }
    
    public func nextNotificationID() -> NSUUID? {
        return notificationIDs.isEmpty ? .None : notificationIDs.removeFirst()
    }
    
    public func nextNoticeNotificationID() -> NSUUID? {
        return noticeNotificationIDs.isEmpty ? .None : noticeNotificationIDs.removeFirst()
    }
    
    public func didReceiveVoIPNotification(eventsWithID: EventsWithIdentifier, handler: PingBackResultHandler) {
        let identifier = eventsWithID.identifier
        notificationIDs.append(identifier)
        if eventsWithID.isNotice {
            noticeNotificationIDs.append(identifier)
        }
        eventsWithHandlerByNotificationID[identifier] = (eventsWithID.events, handler)
        
        if authenticationStatusProvider?.currentPhase == .Authenticated {
            backgroundActivity = backgroundActivity ?? ZMBackgroundActivity.beginBackgroundActivityWithName("Ping back to BE")
        }
        if status == .Done {
            updateStatus()
        }
        
        ZMOperationLoop.notifyNewRequestsAvailable(self)
    }
    
    public func didPerfomPingBackRequest(notificationID: NSUUID, success: Bool) {
        let eventsWithHandler = eventsWithHandlerByNotificationID.removeValueForKey(notificationID)
        defer { eventsWithHandler?.handler(.Success, notificationIDToEventsMap[notificationID] ?? []) }

        updateStatus()
    
        zmLog.debug("Pingback \(success ? "succeeded" : "failed") for notification ID: \(notificationID)")
        guard let unwrappedEvents = eventsWithHandler?.events where success else { return }
        notificationDispatcher?.didReceiveUpdateEvents(unwrappedEvents)
    }
    
    
    public func didFetchNoticeNotification(notificationID: NSUUID, success: Bool, events: [ZMUpdateEvent]) {
        var finalEvents = events
        if let idx = notificationIDs.indexOf(notificationID) where idx != NSNotFound {
            if success {
                // we fetched the event and want to ping back
                status = .Pinging
                let cryptoBox = syncManagedObjectContext.zm_cryptKeyStore.box
                let decryptedEvents = events.flatMap{cryptoBox.decryptUpdateEventAndAddClient($0, managedObjectContext: syncManagedObjectContext)}
                finalEvents = decryptedEvents
                notificationIDToEventsMap[notificationID] = decryptedEvents
            } else {
                // we could't fetch the event and want the fallback
                notificationIDs.removeAtIndex(idx)
                let eventsWithHandler = eventsWithHandlerByNotificationID.removeValueForKey(notificationID)
                defer { eventsWithHandler?.handler(.Failure, []) }
                updateStatus()
            }
        } else {
            zmLog.error("id for notice notification has already been removed from pingBack IDs - something went wrong")
            updateStatus()
        }
        
        zmLog.debug("Fetching notification \(success ? "succeeded" : "failed") for notification ID: \(notificationID)")
        notificationDispatcher?.didReceiveUpdateEvents(finalEvents)
    }
    
    func updateStatus() {
        if !hasNotificationIDs {
            backgroundActivity?.endActivity()
            backgroundActivity = nil
            status = .Done
            if hasNoticeNotificationIDs {
                zmLog.error("has no id to ping back, but id for notice left - something went wrong - removing noticeIds")
                noticeNotificationIDs.removeAll()
            }
        } else {
            let nextIDIsNoticeID = hasNoticeNotificationIDs && noticeNotificationIDs.first == notificationIDs.first
            status = nextIDIsNoticeID ? .FetchingNotice : .Pinging
        }
    }
    
}


