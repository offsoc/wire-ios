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



@import ZMUtilities;
@import ZMCSystem;
@import ImageIO;
@import MobileCoreServices;

#import "ZMTransportRequest+Internal.h"
#import "ZMTransportData.h"
#import "ZMTransportResponse.h"
#import "ZMTransportCodec.h"
#import "ZMBackgroundActivity.h"
#import "NSData+Multipart.h"

const NSTimeInterval ZMTransportRequestDefaultExpirationInterval = 60;


@interface ZMCompletionHandler ()

@property (nonatomic) id<ZMSGroupQueue> groupQueue;
@property (nonatomic, copy) ZMCompletionHandlerBlock block;

@end


/// OS X 10.9 does not have uniform type identifiers with JSON support
static BOOL hasUTJSONSupport(void)
{
    return (&UTTypeIsDynamic != NULL);
}



@implementation ZMCompletionHandler

+ (instancetype)handlerOnGroupQueue:(id<ZMSGroupQueue>)groupQueue block:(ZMCompletionHandlerBlock)block;
{
    RequireString(block != nil, "Invalid completion handler");
    RequireString(groupQueue != nil, "Invalid group queue");
    ZMCompletionHandler *handler = [[self alloc] init];
    if (handler != nil) {
        handler.groupQueue = groupQueue;
        handler.block = block;
    }
    return handler;
}

@end;




@interface ZMTransportRequest ()

@property (nonatomic, copy) id<ZMTransportData> payload;
@property (nonatomic, copy) NSString *path;
@property (nonatomic) ZMTransportRequestMethod method;
@property (nonatomic, copy) NSData *binaryData;
@property (nonatomic, copy) NSString *binaryDataType;
@property (nonatomic, copy) NSDictionary *contentDisposition;
@property (nonatomic) NSMutableArray *completionHandlers;
@property (nonatomic) BOOL needsAuthentication;
@property (nonatomic) BOOL responseWillContainAccessToken;
@property (nonatomic) BOOL responseWillContainCookie;
@property (nonatomic) ZMTransportAccept acceptedResponseMediaTypes; ///< C.f. RFC 7231 section 5.3.2 <http://tools.ietf.org/html/rfc7231#section-5.3.2>
@property (nonatomic) NSDate *timeoutDate;
@property (nonatomic) NSMutableArray<NSString *>* debugInformation;
@property (nonatomic) BOOL shouldCompress;
@property (nonatomic) NSDate *startOfUploadTimestamp;
@property (nonatomic) BOOL shouldUseOnlyForegroundSession;

@end



@implementation ZMTransportRequest

- (instancetype)initWithPath:(NSString *)path method:(ZMTransportRequestMethod)method payload:(id <ZMTransportData>)payload
{
    return [self initWithPath:path method:method payload:payload authentication:ZMTransportRequestAuthNeedsAccess shouldCompress:NO];
}

- (instancetype)initWithPath:(NSString *)path method:(ZMTransportRequestMethod)method payload:(id <ZMTransportData>)payload shouldCompress:(BOOL)shouldCompress
{
    return [self initWithPath:path method:method payload:payload authentication:ZMTransportRequestAuthNeedsAccess shouldCompress:shouldCompress];
}

- (instancetype)initWithPath:(NSString *)path method:(ZMTransportRequestMethod)method payload:(id <ZMTransportData>)payload authentication:(ZMTransportRequestAuth)authentication shouldCompress:(BOOL)shouldCompress;
{
    self = [super init];
    if (self) {
        self.payload = payload;
        self.path = path;
        self.method = method;
        self.needsAuthentication = (authentication == ZMTransportRequestAuthNeedsAccess);
        self.responseWillContainAccessToken = (authentication == ZMTransportRequestAuthCreatesCookieAndAccessToken);
        self.responseWillContainCookie = (authentication == ZMTransportRequestAuthCreatesCookieAndAccessToken);
        self.acceptedResponseMediaTypes = ZMTransportAcceptTransportData;
        self.shouldCompress = shouldCompress;
        self.debugInformation = [NSMutableArray array];
    }
    return self;
}

- (instancetype)initWithPath:(NSString *)path method:(ZMTransportRequestMethod)method payload:(id <ZMTransportData>)payload authentication:(ZMTransportRequestAuth)authentication;
{
    return [self initWithPath:path method:method payload:payload authentication:authentication shouldCompress:NO];
}

+ (instancetype)requestWithPath:(NSString *)path method:(ZMTransportRequestMethod)method payload:(id <ZMTransportData>)payload
{
    return [[self class] requestWithPath:path method:method payload:payload shouldCompress:NO];
}


+ (instancetype)requestWithPath:(NSString *)path method:(ZMTransportRequestMethod)method payload:(id <ZMTransportData>)payload shouldCompress:(BOOL)shouldCompress
{
    ZMTransportRequest *result = [[self alloc] initWithPath:path method:method payload:payload shouldCompress:shouldCompress];
    Require(result.hasRequiredPayload);
    return result;
}


+ (instancetype)requestGetFromPath:(NSString *)path
{
    return [self requestWithPath:path method:ZMMethodGET payload:nil];
}

+ (instancetype)compressedGetFromPath:(NSString *)path
{
    return [self requestWithPath:path method:ZMMethodGET payload:nil shouldCompress:YES];
}

+ (instancetype)emptyPutRequestWithPath:(NSString *)path;
{
    NSString *type = (hasUTJSONSupport() ? ((__bridge NSString *) kUTTypeJSON) : @"public.json");
    return [[self alloc] initWithPath:path method:ZMMethodPUT binaryData:[NSData data] type:type contentDisposition:nil];
}

+ (instancetype)imageGetRequestFromPath:(NSString *)path;
{
    ZMTransportRequest *r = [self requestGetFromPath:path];
    r.acceptedResponseMediaTypes = ZMTransportAcceptImage;
    Require(r.hasRequiredPayload);
    return r;
}

- (instancetype)initWithPath:(NSString *)path method:(ZMTransportRequestMethod)method binaryData:(NSData *)data type:(NSString *)type contentDisposition:(NSDictionary *)contentDisposition;
{
    return [self initWithPath:path method:method binaryData:data type:type contentDisposition:contentDisposition shouldCompress:NO];
}

- (instancetype)initWithPath:(NSString *)path method:(ZMTransportRequestMethod)method binaryData:(NSData *)data type:(NSString *)type contentDisposition:(NSDictionary *)contentDisposition shouldCompress:(BOOL)shouldCompress;
{
    self = [super init];
    if (self != nil) {
        self.path = path;
        self.method = method;
        self.binaryData = data;
        self.binaryDataType = type;
        self.contentDisposition = contentDisposition;
        self.needsAuthentication = YES;
        self.responseWillContainAccessToken = NO;
        self.acceptedResponseMediaTypes = ZMTransportAcceptTransportData;
        self.shouldCompress = shouldCompress;
        self.debugInformation = [NSMutableArray array];
    }
    return self;
}

- (BOOL)isEqual:(id)other
{
    if (other == self)
        return YES;
    if (!other || ![[other class] isEqual:[self class]])
        return NO;

    return [self isEqualToRequest:other];
}

- (NSString *)methodAsString {
    return [self.class stringForMethod:self.method];
}

- (void)expireAfterInterval:(NSTimeInterval)interval;
{
    [self expireAtDate:[NSDate dateWithTimeIntervalSinceNow:interval]];
}

- (void)expireAtDate:(NSDate *)date;
{
    _expirationDate = date;
}


- (BOOL)hasRequiredPayload;
{
    switch (self.method) {
        case ZMMethodGET:
        case ZMMethodHEAD:
            return ((self.payload == nil) &&
                    (self.binaryData == nil));
        case ZMMethodPOST:
        case ZMMethodDELETE:
            // POST and DELETE payload is optional
            return YES;
        case ZMMethodPUT:
            return ((self.payload != nil) ||
                    (self.binaryData != nil));
    }
}

- (void)setAcceptedResponseMediaTypeOnHTTPRequest:(NSMutableURLRequest *)URLRequest;
{
    NSString *accept;
    switch (self.acceptedResponseMediaTypes) {
        case ZMTransportAcceptAnything:
            accept = @"*/*";
            break;
        case ZMTransportAcceptTransportData:
            accept = [ZMTransportCodec encodedContentType];
            break;
        case ZMTransportAcceptImage:
            accept = [[self imageMediaTypes] componentsJoinedByString:@", "];
            break;
    }
    [URLRequest addValue:accept forHTTPHeaderField:@"Accept"];
}

- (void)setBodyDataAndMediaTypeOnHTTPRequest:(NSMutableURLRequest *)URLRequest;
{
    static NSString * const ContentTypeHeader = @"Content-Type";
    
    if ((self.binaryDataType != nil) && (self.binaryData != nil)) {
        NSString *mediaType;
        if (! hasUTJSONSupport()) {
            if ([self.binaryDataType isEqualToString:@"public.json"]) {
                mediaType = [ZMTransportCodec encodedContentType];
            }
        }
        if (mediaType == nil) {
            mediaType = CFBridgingRelease(UTTypeCopyPreferredTagWithClass((__bridge CFStringRef) self.binaryDataType, kUTTagClassMIMEType));
        }
        if (mediaType != nil) {
            [URLRequest addValue:mediaType forHTTPHeaderField:ContentTypeHeader];
        }
        else {
            [URLRequest addValue:self.binaryDataType forHTTPHeaderField:ContentTypeHeader];
        }
        URLRequest.HTTPBody = self.binaryData;
    } else if (self.payload != nil) {
        URLRequest.HTTPBody = [ZMTransportCodec encodedTransportData:self.payload];
        [URLRequest addValue:[ZMTransportCodec encodedContentType] forHTTPHeaderField:ContentTypeHeader];
    }
    
    // Check if we want to use HTTP compression:
    //
    if (self.shouldCompress) {
        static NSUInteger const MaxUncompressedBodyLength = 500;
        
        if ([[URLRequest valueForHTTPHeaderField:ContentTypeHeader] isEqualToString:[ZMTransportCodec encodedContentType]] &&
            (MaxUncompressedBodyLength < URLRequest.HTTPBody.length))
        {
            // https://en.wikipedia.org/wiki/HTTP_compression
            NSData *compressed = [URLRequest.HTTPBody zm_gzipCompressedHTTPBody];
            if (compressed.length < URLRequest.HTTPBody.length) {
                URLRequest.HTTPBody = compressed;
                [URLRequest addValue:@"gzip" forHTTPHeaderField:@"Content-Encoding"];
            }
        }
    }
}

- (void)setContentDispositionOnHTTPRequest:(NSMutableURLRequest *)URLRequest;
{
    if (self.contentDisposition == nil) {
        return;
    }
    NSMutableArray *components = [NSMutableArray array];
    NSArray *keys;
    ZM_ALLOW_MISSING_SELECTOR(keys = [self.contentDisposition.allKeys sortedArrayUsingSelector:@selector(compare:)]);
    for (NSString *key in keys) {
        NSString *stringValue = nil;
        id value = self.contentDisposition[key];
        if (value == [NSNull null]) {
            // nothing;
        } else if ([value isKindOfClass:[NSNumber class]]) {
            if (value == (__bridge id) kCFBooleanTrue) {
                stringValue = @"true";
            } else if (value == (__bridge id) kCFBooleanFalse) {
                stringValue = @"false";
            } else {
                stringValue = [value description];
            }
        } else if ([value isKindOfClass:[NSString class]]) {
            stringValue = value;
        }
        if ((stringValue != nil) && ([stringValue rangeOfString:@" "].location != NSNotFound)) {
            // Not super nice.
            stringValue = [NSString stringWithFormat:@"\"%@\"", stringValue];
        }
        if (stringValue != nil) {
            [components addObject:[NSString stringWithFormat:@"%@=%@", key, stringValue]];
        } else {
            [components insertObject:key atIndex:0];
        }
    }
    NSString *disposition = [components componentsJoinedByString:@";"];
    [URLRequest addValue:disposition forHTTPHeaderField:@"Content-Disposition"];
}

- (NSString *)descriptionWithMethodAndPath;
{
    NSString *path = self.path;
    if (68 < path.length) {
        path = [[path substringToIndex:66] stringByAppendingFormat:@"[…](%u)", (unsigned) path.length];
    }
    return [NSString stringWithFormat:@"<%@: %p> %@ %@",
            self.class, self, [ZMTransportRequest stringForMethod:self.method], path];
}

- (NSArray *)imageMediaTypes;
{
    NSMutableArray *types = [NSMutableArray array];
    {
        for (NSString *uti in CFBridgingRelease(CGImageSourceCopyTypeIdentifiers())) {
            NSString *mime = CFBridgingRelease(UTTypeCopyPreferredTagWithClass((__bridge CFStringRef) uti, kUTTagClassMIMEType));
            if ((mime == nil) || [mime hasPrefix:@"image/x-"] || [mime hasPrefix:@"application/"]) {
                continue;
            }
            [types addObject:mime];
        }
    }
    return types;
}

- (void)addCompletionHandler:(ZMCompletionHandler *)completionHandler;
{
    VerifyReturn(completionHandler != nil);
    if (self.completionHandlers == nil) {
        self.completionHandlers = [NSMutableArray arrayWithObject:completionHandler];
    } else {
        [self.completionHandlers addObject:completionHandler];
    }
}

- (void)completeWithResponse:(ZMTransportResponse *)response
{
    ZMBackgroundActivity *completeActivity = [ZMBackgroundActivity beginBackgroundActivityWithName:NSStringFromSelector(_cmd)];
    ZMSDispatchGroup *group = response.dispatchGroup;
    ZMSDispatchGroup *group2 = [ZMSDispatchGroup groupWithLabel:@"ZMTransportRequest"];
    [group2 enter];
    for(ZMCompletionHandler *handler in self.completionHandlers) {
        id<ZMSGroupQueue> queue = handler.groupQueue;
        if (queue != nil) {
            if (group) {
                [group enter];
            }
            [group2 enter];
            [queue performGroupedBlock:^{
                NSString *label = [NSString stringWithFormat:@"Completion handler of REQ %@ %@ -> %@ ",
                                   self.methodAsString,
                                   self.path,
                                   @(response.HTTPStatus)
                                   ];
                ZMSTimePoint *tp = [ZMSTimePoint timePointWithInterval:6 label:label];
                handler.block(response);
                [tp warnIfLongerThanInterval];
                if (group) {
                    [group leave];
                }
                [group2 leave];
            }];
        }
    }
    [group2 leave];
    [group2 notifyOnQueue:dispatch_get_main_queue() block:^{
        [completeActivity endActivity];
    }];
}

- (void)forceToForegroundSession
{
    self.shouldUseOnlyForegroundSession = YES;
}

- (NSString *)completionHandlerDescription;
{
    return [NSString stringWithFormat:@"%@ %@", self.methodAsString, self.path];
}

- (BOOL)isEqualToRequest:(ZMTransportRequest *)request
{
    if (self == request) {
        return YES;
    }
    if (request == nil) {
        return NO;
    }
    return ((self.payload == request.payload || [self.payload isEqual:request.payload]) &&
            (self.path == request.path || [self.path isEqualToString:request.path]) &&
            (self.method == request.method) &&
            (self.acceptedResponseMediaTypes == request.acceptedResponseMediaTypes) &&
            (self.responseWillContainAccessToken == request.responseWillContainAccessToken) &&
            (self.responseWillContainCookie == request.responseWillContainCookie));
}

- (NSString *)description
{
    NSMutableString *description = [NSMutableString stringWithFormat:@"<%@: %p>", [self class], self];
    [description appendFormat:@" \"%@\"", self.methodAsString];
    if (self.path) {
        [description appendFormat:@" path \"%@\"", self.path];
    }
    
    [description appendFormat:@" %lu completionHandler(s)", (unsigned long)self.completionHandlers.count];
    
    if (self.payload) {
        [description appendFormat:@" payload: %@", self.payload];
    }
    if (self.binaryData) {
        [description appendFormat:@" binary data: %llu", (unsigned long long) self.binaryData.length];
    }
    
    for (ZMMultipartBodyItem *bodyItem in self.multipartBodyItems) {
        [description appendString:[NSString stringWithFormat:@"\n----\nBody item: \n%@", bodyItem.description]];
    }
    
    if (self.debugInformation.count > 0) {
        [description appendString:@"\n"];
        for(NSString *info in self.debugInformation) {
            [description appendString:info];
            [description appendString:@"\n"];
        }
    }
    
    return description;
}

- (NSUInteger)hash
{
    NSUInteger hash = [self.payload hash];
    hash = hash * 31u + [self.path hash];
    hash = hash * 31u + [self.methodAsString hash];
    return hash;
}

+ (ZMTransportRequestMethod)methodFromString:(NSString *)string
{
    if([string isEqualToString:@"GET"]) {
        return ZMMethodGET;
    }
    if([string isEqualToString:@"POST"]) {
        return ZMMethodPOST;
    }
    if([string isEqualToString:@"DELETE"]) {
        return ZMMethodDELETE;
    }
    if([string isEqualToString:@"PUT"]) {
        return ZMMethodPUT;
    }
    if([string isEqualToString:@"HEAD"]) {
        return ZMMethodHEAD;
    }

    RequireString(false, "Invalid HTTP method string");
    return ZMMethodGET;
}

+ (NSString *)stringForMethod:(ZMTransportRequestMethod)method
{
    if(method == ZMMethodGET) {
        return @"GET";
    }
    if(method == ZMMethodPOST) {
        return @"POST";
    }
    if(method == ZMMethodDELETE) {
        return @"DELETE";
    }
    if(method == ZMMethodPUT) {
        return @"PUT";
    }
    if(method == ZMMethodHEAD) {
        return @"HEAD";
    }
    
    RequireString(false, "Invalid HTTP method: %lu", (unsigned long) method);
    return @"GET";
}

@end



@implementation ZMTransportRequest (ImageUpload)

+ (instancetype)postRequestWithPath:(NSString *)path imageData:(NSData *)data contentDisposition:(NSDictionary *)contentDisposition;
{
    VerifyReturnNil(data != nil);
    CGImageSourceRef source = CGImageSourceCreateWithData((__bridge CFDataRef) data, NULL);
    VerifyReturnNil(source != NULL);
    NSString *type = CFBridgingRelease(CGImageSourceGetType(source));
    CFRelease(source);
    if (! UTTypeConformsTo((__bridge CFStringRef) type, kUTTypeImage)) {
        return nil;
    }
    ZMTransportRequest *result = [[self alloc] initWithPath:path method:ZMMethodPOST binaryData:data type:type contentDisposition:contentDisposition];
    Require(result.hasRequiredPayload);
    return result;
}

+ (instancetype)multipartRequestWithPath:(NSString *)path imageData:(NSData *)imageData metaData:(NSDictionary *)metaData
{
    VerifyReturnNil(imageData != nil);
    CGImageSourceRef source = CGImageSourceCreateWithData((__bridge CFDataRef) imageData, NULL);
    VerifyReturnNil(source != NULL);
    NSString *type = CFBridgingRelease(CGImageSourceGetType(source));
    NSString *mediaType = CFBridgingRelease(UTTypeCopyPreferredTagWithClass((__bridge CFStringRef) type, kUTTagClassMIMEType));
    CFRelease(source);
    if (! UTTypeConformsTo((__bridge CFStringRef) type, kUTTypeImage)) {
        return nil;
    }

    return [self multipartRequestWithPath:path imageData:imageData metaData:metaData mediaContentType:mediaType];
}

+ (instancetype)multipartRequestWithPath:(NSString *)path imageData:(NSData *)imageData metaData:(NSDictionary *)metaData mediaContentType:(NSString *)mediaContentType
{
    NSData *metaDataData = [NSJSONSerialization dataWithJSONObject:metaData options:0 error:NULL];
    return [self multipartRequestWithPath:path imageData:imageData metaData:metaDataData metaDataContentType:@"application/json; charset=utf-8" mediaContentType:mediaContentType];
}

+ (instancetype)multipartRequestWithPath:(NSString *)path imageData:(NSData *)imageData metaData:(NSData *)metaData metaDataContentType:(NSString *)metaDataContentType mediaContentType:(NSString *)mediaContentType;
{
    VerifyReturnNil(imageData != nil);
    
    NSString *boundary = @"frontier";
    NSString *contentType = [NSString stringWithFormat:@"multipart/mixed; boundary=%@", boundary];
    NSData *multipartData = [self multipartDataWithImageData:imageData
                                                    metaData:metaData
                                         metaDataContentType:metaDataContentType
                                                   mediaType:mediaContentType
                                                    boundary:boundary];
    
    ZMTransportRequest *result = [[self alloc] initWithPath:path
                                                     method:ZMMethodPOST
                                                 binaryData:multipartData
                                                       type:contentType
                                         contentDisposition:nil];
    Require(result.hasRequiredPayload);
    return result;
}

+ (NSData *)multipartDataWithImageData:(NSData *)imageData metaData:(NSData *)metaData metaDataContentType:(NSString *)metaDataContentType mediaType:(NSString *)mediaType boundary:(NSString *)boundary
{
    ZMMultipartBodyItem *metaDataBodyItem = [[ZMMultipartBodyItem alloc] initWithData:metaData
                                                                          contentType:metaDataContentType
                                                                              headers:nil];
    
    ZMMultipartBodyItem *imageBodyItem = [[ZMMultipartBodyItem alloc] initWithData:imageData
                                                                       contentType:mediaType
                                                                           headers:@{
                                                                                     @"Content-MD5": [[imageData zmMD5Digest] base64EncodedStringWithOptions:0]
                                                                                     }];
    
    return [NSData multipartDataWithItems:@[metaDataBodyItem, imageBodyItem] boundary:boundary];
}

- (NSArray *)multipartBodyItems
{
    if ([self.binaryDataType hasPrefix:@"multipart/mixed"]) {
        NSString *boundary = [[self.binaryDataType componentsSeparatedByString:@";"] lastObject];
        boundary = [[boundary componentsSeparatedByString:@"="] lastObject];
        return [self.binaryData multipartDataItemsSeparatedWithBoundary:boundary];
    }
    else {
        return nil;
    }
}

@end



@implementation ZMTransportRequest (Debugging)

- (void)setDebugInformationTranscoder:(NSObject *)transcoder;
{
    [self.debugInformation addObject:[NSString stringWithFormat:@"Transcoder: <%@> %p", NSStringFromClass(transcoder.class), transcoder]];
}

- (void)setDebugInformationState:(NSObject *)state;
{
    [self.debugInformation addObject:[NSString stringWithFormat:@"Sync state: <%@> %p", NSStringFromClass(state.class), state]];
}

- (void)appendDebugInformation:(NSString *)debugInformation
{
    [self.debugInformation addObject:debugInformation];
}

- (void)markStartOfUploadTimestamp {
    self.startOfUploadTimestamp = [NSDate date];
}

@end
