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

#import <React/RCTConvert.h>
#import <RNFBApp/RNFBSharedUtils.h>
#import <RNFBApp/RNFBRCTEventEmitter.h>
#import <GoogleUtilities/GULAppDelegateSwizzler.h>

#import "RNFBMessagingAppDelegateInterceptor.h"
#import "RNFBMessagingSerializer.h"

@implementation RNFBMessagingAppDelegateInterceptor

+ (instancetype)sharedInstance {
  static dispatch_once_t once;
  static RNFBMessagingAppDelegateInterceptor *sharedInstance;
  dispatch_once(&once, ^{
    sharedInstance = [[RNFBMessagingAppDelegateInterceptor alloc] init];
    [GULAppDelegateSwizzler proxyOriginalDelegateIncludingAPNSMethods];
    [GULAppDelegateSwizzler registerAppDelegateInterceptor:sharedInstance];
  });
  return sharedInstance;
}

// used to temporarily store a promise instance to resolve calls to `registerForRemoteNotifications`
- (void)setPromiseResolve:(RCTPromiseResolveBlock)resolve andPromiseReject:(RCTPromiseRejectBlock)reject {
  _registerPromiseResolver = resolve;
  _registerPromiseRejecter = reject;
}

// called when `registerForRemoteNotifications` completes successfully
- (void)application:(UIApplication *)application didRegisterForRemoteNotificationsWithDeviceToken:(NSData *)deviceToken {
  [FIRMessaging messaging].APNSToken = deviceToken;
  if (_registerPromiseResolver != nil) {
    _registerPromiseResolver(@([RCTConvert BOOL:@([UIApplication sharedApplication].isRegisteredForRemoteNotifications)]));
    _registerPromiseResolver = nil;
    _registerPromiseRejecter = nil;
  }
}

// called when `registerForRemoteNotifications` fails to complete
- (void)application:(UIApplication *)application didFailToRegisterForRemoteNotificationsWithError:(NSError *)error {
  if (_registerPromiseRejecter != nil) {
    [RNFBSharedUtils rejectPromiseWithNSError:_registerPromiseRejecter error:error];
    _registerPromiseResolver = nil;
    _registerPromiseRejecter = nil;
  }
}

// Without content-available via APNS
//- (void)application:(UIApplication *)application didReceiveRemoteNotification:(NSDictionary *)userInfo {
//    // Message ID available = FCM message. Could be a APN message which would be ignored.
//    if (userInfo[@"gcm.message_id"]) {
//      [[RNFBRCTEventEmitter shared] sendEventWithName:@"messaging_message_received" body:[RNFBMessagingSerializer remoteMessageAppDataToDict:userInfo withMessageId:nil]];
//    }
//}

// With content-available via APNS
- (void)application:(UIApplication *)application didReceiveRemoteNotification:(NSDictionary *)userInfo fetchCompletionHandler:(void (^)(UIBackgroundFetchResult result))completionHandler {
  // Message ID available = FCM message. Could be a APN message which would be ignored.
  if (userInfo[@"gcm.message_id"]) {
    [[RNFBRCTEventEmitter shared] sendEventWithName:@"messaging_message_received" body:[RNFBMessagingSerializer remoteMessageAppDataToDict:userInfo withMessageId:nil]];
  }
   
  completionHandler(UIBackgroundFetchResultNoData);
}

@end
