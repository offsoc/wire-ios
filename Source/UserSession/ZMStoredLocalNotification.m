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


@import WireTransport;
@import WireDataModel;

#import "ZMStoredLocalNotification.h"
#import "ZMOperationLoop+Background.h"
#import "UILocalNotification+UserInfo.h"
#import <WireSyncEngine/WireSyncEngine-Swift.h>

@implementation ZMStoredLocalNotification

- (instancetype)initWithNotification:(UILocalNotification *)notification
                managedObjectContext:(NSManagedObjectContext *)managedObjectContext
                    actionIdentifier:(NSString *)identifier
                           textInput:(NSString*)textInput;
{
    ZMConversation *conversation = [notification conversationInManagedObjectContext:managedObjectContext];
    ZMMessage *message;
    if (conversation != nil) {
        message = [notification messageInConversation:conversation inManagedObjectContext:managedObjectContext];
    }
        
    return [self initWithConversation:conversation
                              message:message
                           senderUUID:notification.zm_senderUUID
                             category:notification.category
                     actionIdentifier:identifier
                            textInput:textInput];
}

- (instancetype)initWithConversation:(ZMConversation *)conversation
                             message:(ZMMessage *)message
                          senderUUID:(NSUUID *)senderUUID
                            category:(NSString *)category
                    actionIdentifier:(NSString *)identifier
                           textInput:(NSString*)textInput;
{
    self = [super init];
    if (self != nil) {
        _conversation = conversation;
        _message = message;
        _senderUUID = senderUUID;
        _category = category;
        _actionIdentifier = identifier;
        _textInput = textInput;
    }
    return self;
    
}


@end

