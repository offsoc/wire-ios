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

#import <Foundation/Foundation.h>
#import <WireSystem/WireSystem.h>


@interface NSArray (ZMFunctional)

- (NSArray *)mapWithBlock:(id(^)(id obj))block ZM_NON_NULL(1);
- (NSArray *)filterWithBlock:(BOOL(^)(id obj))block ZM_NON_NULL(1);

- (NSArray *)flattenWithBlock:(NSArray *(^)(id obj))block;

- (NSDictionary *)mapToDictionaryWithBlock:(NSDictionary * (^)(id obj))block;

- (NSArray *)objectsOfClass:(Class)desiredClass;

- (id)firstObjectMatchingWithBlock:(BOOL(^)(id obj))evaluator ZM_NON_NULL(1);
- (BOOL)containsObjectMatchingWithBlock:(BOOL(^)(id obj))evaluator ZM_NON_NULL(1);

@end


@interface NSSet (ZMFunctional)

- (NSSet *)mapWithBlock:(id(^)(id obj))block;
- (NSSet *)objectsOfClass:(Class)desiredClass;
- (id)anyObjectMatchingWithBlock:(BOOL(^)(id obj))evaluator ZM_NON_NULL(1);

@end
