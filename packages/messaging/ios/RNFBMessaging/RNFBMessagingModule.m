/**
 * Copyright (c) 2016-present Invertase Limited & Contributors
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this library except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *   http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 *
 */

#import <os/log.h>
#import <React/RCTUtils.h>
#import <React/RCTConvert.h>
#import <Firebase/Firebase.h>
#import <RNFBApp/RNFBSharedUtils.h>
#import <UserNotifications/UserNotifications.h>

#import "RNFBMessagingModule.h"
#import "RNFBMessagingDelegate.h"
#import "RNFBMessagingSerializer.h"
#import "RNFBMessagingAppDelegateInterceptor.h"


@implementation RNFBMessagingModule
#pragma mark -
#pragma mark Module Setup

RCT_EXPORT_MODULE();

- (id)init {
  self = [super init];
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    // ensure shared instances are initialized early
    [RNFBMessagingDelegate sharedInstance];
    [RNFBMessagingAppDelegateInterceptor sharedInstance];
  });
  return self;
}

- (dispatch_queue_t)methodQueue {
  return dispatch_get_main_queue();
}

+ (BOOL)requiresMainQueueSetup {
  return YES;
}

- (NSDictionary *)constantsToExport {
  NSMutableDictionary *constants = [NSMutableDictionary new];
  constants[@"isAutoInitEnabled"] = @([RCTConvert BOOL:@([FIRMessaging messaging].autoInitEnabled)]);
  constants[@"isRegisteredForRemoteNotifications"] = @([RCTConvert BOOL:@([[UIApplication sharedApplication] isRegisteredForRemoteNotifications])]);
  return constants;
}

#pragma mark -
#pragma mark Firebase Messaging Methods

RCT_EXPORT_METHOD(getInitialNotification:
  (RCTPromiseResolveBlock) resolve
    :(RCTPromiseRejectBlock) reject
) {
  // TODO
  resolve(nil);
}

RCT_EXPORT_METHOD(setAutoInitEnabled:
  (BOOL) enabled
    :(RCTPromiseResolveBlock) resolve
    :(RCTPromiseRejectBlock) reject
) {
  @try {
    [FIRMessaging messaging].autoInitEnabled = enabled;
  } @catch (NSException *exception) {
    return [RNFBSharedUtils rejectPromiseWithExceptionDict:reject exception:exception];
  }

  return resolve([NSNull null]);
}

RCT_EXPORT_METHOD(getToken:
  (NSString *) authorizedEntity
    :(NSString *) scope
    :(RCTPromiseResolveBlock) resolve
    :(RCTPromiseRejectBlock) reject
) {
  if ([UIApplication sharedApplication].isRegisteredForRemoteNotifications == NO) {
    [RNFBSharedUtils rejectPromiseWithUserInfo:reject userInfo:(NSMutableDictionary *) @{
        @"code": @"unregistered",
        @"message": @"You must be registered for remote notifications before calling get token, see messaging().registerForRemoteNotifications() or requestPermission().",
    }];
    return;
  }
    
  if ([scope isEqualToString:@"FCM"] && [authorizedEntity isEqualToString:[FIRApp defaultApp].options.GCMSenderID]) {
      [[FIRInstanceID instanceID] instanceIDWithHandler:^(FIRInstanceIDResult * _Nullable result, NSError * _Nullable error) {
          if (error) {
              [RNFBSharedUtils rejectPromiseWithNSError:reject error:error];
          } else {
              os_log(OS_LOG_DEFAULT, "RNFB: GET FCM TOKEN: %{public}@", result.token);
              resolve(result.token);
          }
      }];
  } else {
      NSDictionary *options = nil;
      if ([FIRMessaging messaging].APNSToken) {
        options = @{@"apns_token": [FIRMessaging messaging].APNSToken};
      }

      [[FIRInstanceID instanceID] tokenWithAuthorizedEntity:authorizedEntity scope:scope options:options handler:^(NSString *_Nullable identity, NSError *_Nullable error) {
        if (error) {
          [RNFBSharedUtils rejectPromiseWithNSError:reject error:error];
        } else {
          os_log(OS_LOG_DEFAULT, "RNFB: GET FCM TOKEN: %{public}@", identity);
          resolve(identity);
        }
      }];
  }
}

RCT_EXPORT_METHOD(deleteToken:
  (NSString *) authorizedEntity
    :(NSString *) scope
    :(RCTPromiseResolveBlock) resolve
    :(RCTPromiseRejectBlock) reject
) {
  [[FIRInstanceID instanceID] deleteTokenWithAuthorizedEntity:authorizedEntity scope:scope handler:^(NSError *_Nullable error) {
    if (error) {
      [RNFBSharedUtils rejectPromiseWithNSError:reject error:error];
    } else {
      resolve([NSNull null]);
    }
  }];
}

RCT_EXPORT_METHOD(getAPNSToken:
  (RCTPromiseResolveBlock) resolve
    : (RCTPromiseRejectBlock) reject
) {
  NSData *apnsToken = [FIRMessaging messaging].APNSToken;
  if (apnsToken) {
    NSString *apnsTokenString = [RNFBMessagingSerializer APNSTokenFromNSData:apnsToken];
    os_log(OS_LOG_DEFAULT, "RNFB: GET APNS TOKEN: %{public}@", apnsTokenString);
    resolve([RNFBMessagingSerializer APNSTokenFromNSData:apnsToken]);
  } else {
    os_log(OS_LOG_DEFAULT, "RNFB: GET APNS TOKEN FAILED - NULL");
    resolve([NSNull null]);
  }
}

RCT_EXPORT_METHOD(requestPermission:
  (NSDictionary *) permissions
                  :(RCTPromiseResolveBlock) resolve
    :(RCTPromiseRejectBlock) reject
) {
  if (RCTRunningInAppExtension()) {
    [RNFBSharedUtils rejectPromiseWithUserInfo:reject userInfo:[@{
        @"code": @"unavailable-in-extension",
        @"message": @"requestPermission can not be called in App Extensions"} mutableCopy]];
    return;
  }


    if (@available(iOS 10.0, *)) {
      UNUserNotificationCenter *center = [UNUserNotificationCenter currentNotificationCenter];
      UNAuthorizationOptions options = UNAuthorizationOptionNone;
        
      if ([permissions[@"alert"] isEqual:@(YES)]) {
        options |= UNAuthorizationOptionAlert;
      }
        
      if ([permissions[@"badge"] isEqual:@(YES)]) {
        options |= UNAuthorizationOptionBadge;
      }
        
      if ([permissions[@"sound"] isEqual:@(YES)]) {
        options |= UNAuthorizationOptionSound;
      }
  
//      Not supported
//      if ([permissions[@"inAppNotificationSettings"] isEqual:@(YES)]) {
//        if (@available(iOS 12.0, *)) {
//          options |= UNAuthorizationOptionProvidesAppNotificationSettings;
//        }
//      }
        
      if ([permissions[@"provisional"] isEqual:@(YES)]) {
        if (@available(iOS 12.0, *)) {
          options |= UNAuthorizationOptionProvisional;
        }
      }
        
      if ([permissions[@"announcement"] isEqual:@(YES)]) {
        if (@available(iOS 13.0, *)) {
          options |= UNAuthorizationOptionAnnouncement;
        }
      }
        
      if ([permissions[@"carPlay"] isEqual:@(YES)]) {
        options |= UNAuthorizationOptionCarPlay;
      }

//      Not supported
//      if ([permissions[@"criticalAlert"] isEqual:@(YES)]) {
//        if (@available(iOS 12.0, *)) {
//          options |= UNAuthorizationOptionCriticalAlert;
//        }
//      }
        
      [[UNUserNotificationCenter currentNotificationCenter] requestAuthorizationWithOptions:options completionHandler:^(BOOL granted, NSError *_Nullable error) {
        if (error) {
          [RNFBSharedUtils rejectPromiseWithNSError:reject error:error];
        } else {
            [self hasPermission:resolve :reject];
        }
      }];
    } else {
      [RNFBSharedUtils rejectPromiseWithUserInfo:reject userInfo:[@{
          @"code": @"unsupported-platform-version",
          @"message": @"requestPermission call failed; minimum supported version requirement not met (iOS 10)."} mutableCopy]];
    }
}

RCT_EXPORT_METHOD(registerForRemoteNotifications:
  (RCTPromiseResolveBlock) resolve
    : (RCTPromiseRejectBlock) reject
) {
  if (@available(iOS 10.0, *)) {
      if ([UIApplication sharedApplication].isRegisteredForRemoteNotifications == YES) {
        resolve(@([RCTConvert BOOL:@(YES)]));
      } else {
        [[RNFBMessagingAppDelegateInterceptor sharedInstance] setPromiseResolve:resolve andPromiseReject:reject];
      }
      
    dispatch_async(dispatch_get_main_queue(), ^{
      [[UIApplication sharedApplication] registerForRemoteNotifications];
    });
  } else {
    [RNFBSharedUtils rejectPromiseWithUserInfo:reject userInfo:[@{
        @"code": @"unsupported-platform-version",
        @"message": @"registerDeviceForRemoteMessages call failed; minimum supported version requirement not met (iOS 10)."} mutableCopy]];
  }
}

RCT_EXPORT_METHOD(unregisterForRemoteNotifications:
  (RCTPromiseResolveBlock) resolve
    :(RCTPromiseRejectBlock) reject
) {
  [[UIApplication sharedApplication] unregisterForRemoteNotifications];
  resolve(nil);
}

RCT_EXPORT_METHOD(hasPermission:
  (RCTPromiseResolveBlock) resolve
    :(RCTPromiseRejectBlock) reject
) {
  if (@available(iOS 10.0, *)) {
    [[UNUserNotificationCenter currentNotificationCenter] getNotificationSettingsWithCompletionHandler:^(UNNotificationSettings *_Nonnull settings) {
        
        NSNumber *authorizedStatus = @-1;
        if (settings.authorizationStatus == UNAuthorizationStatusNotDetermined) {
          authorizedStatus = @-1;
        } else if (settings.authorizationStatus == UNAuthorizationStatusDenied) {
          authorizedStatus = @0;
        } else if (settings.authorizationStatus == UNAuthorizationStatusAuthorized) {
          authorizedStatus = @1;
        }
        
        if (@available(iOS 12.0, *)) {
          if (settings.authorizationStatus == UNAuthorizationStatusProvisional) {
            authorizedStatus = @2;
          }
        }
        
      resolve(authorizedStatus);
    }];
  } else {
    [RNFBSharedUtils rejectPromiseWithUserInfo:reject userInfo:[@{
        @"code": @"unsupported-platform-version",
        @"message": @"hasPermission call failed; minimum supported version requirement not met (iOS 10)."} mutableCopy]];
  }
}

RCT_EXPORT_METHOD(sendMessage:
  (NSDictionary *) message
    :(RCTPromiseResolveBlock) resolve
    :(RCTPromiseRejectBlock) reject
) {
  NSString *to = message[@"to"];
  NSNumber *ttl = message[@"ttl"];
  NSDictionary *data = message[@"data"];
  NSString *messageId = message[@"messageId"];
  [[FIRMessaging messaging] sendMessage:data to:to withMessageID:messageId timeToLive:[ttl intValue]];
  resolve(nil);
}

RCT_EXPORT_METHOD(subscribeToTopic:
  (NSString *) topic
    :(RCTPromiseResolveBlock) resolve
    :(RCTPromiseRejectBlock) reject
) {
  [[FIRMessaging messaging] subscribeToTopic:topic completion:^(NSError *error) {
    if (error) {
      [RNFBSharedUtils rejectPromiseWithNSError:reject error:error];
    } else {
      resolve(nil);
    }
  }];
}

RCT_EXPORT_METHOD(unsubscribeFromTopic:
  (NSString *) topic
    :(RCTPromiseResolveBlock) resolve
    :(RCTPromiseRejectBlock) reject
) {
  [[FIRMessaging messaging] unsubscribeFromTopic:topic completion:^(NSError *error) {
    if (error) {
      [RNFBSharedUtils rejectPromiseWithNSError:reject error:error];
    } else {
      resolve(nil);
    }
  }];
}

@end
