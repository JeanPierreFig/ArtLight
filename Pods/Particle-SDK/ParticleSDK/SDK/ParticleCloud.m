//
//  ParticleCloud.m
//  mobile-sdk-ios
//
//  Created by Ido Kleinman on 11/7/14.
//  Copyright (c) 2014-2015 Particle. All rights reserved.
//

#import "ParticleCloud.h"
#import "ParticleSession.h"
#import "EventSource.h"
#import "ParticleErrorHelper.h"

#ifdef USE_FRAMEWORKS
#import <AFNetworking/AFNetworking.h>
#else
#import "AFNetworking.h"
#endif

NS_ASSUME_NONNULL_BEGIN

#define GLOBAL_API_TIMEOUT_INTERVAL     31.0f

NSString *const kParticleAPIBaseURL = @"https://api.particle.io";
NSString *const kEventListenersDictEventSourceKey = @"eventSource";
NSString *const kEventListenersDictHandlerKey = @"eventHandler";
NSString *const kEventListenersDictIDKey = @"id";

static NSString *const kDefaultoAuthClientId = @"particle";
static NSString *const kDefaultoAuthClientSecret = @"particle";

@interface ParticleCloud () <ParticleSessionDelegate>

@property (nonatomic, strong, nonnull) NSURL* baseURL;
@property (nonatomic, strong, nullable) ParticleSession* session;

@property (nonatomic, strong, nonnull) AFHTTPSessionManager *manager;

@property (nonatomic, strong, nonnull) NSMutableDictionary *eventListenersDict;

@property (nonatomic, strong) NSMapTable *devicesMapTable;
@property (nonatomic, strong) id systemEventsListenerId;
@end


@implementation ParticleCloud

#pragma mark Class initialization and singleton instancing

+ (instancetype)sharedInstance;
{
    static ParticleCloud *sharedInstance = nil;
    @synchronized(self) {
        if (sharedInstance == nil)
        {
            sharedInstance = [[self alloc] init];
        }
    }
    return sharedInstance;
}

- (instancetype)init
{
    self = [super init];
    if (self) {
        self.baseURL = [NSURL URLWithString:kParticleAPIBaseURL];
        if (!self.baseURL)
        {
            return nil;
        }

        self.oAuthClientId = kDefaultoAuthClientId;
        self.oAuthClientSecret = kDefaultoAuthClientSecret;

        // try to restore session (user and access token)
        self.session = [[ParticleSession alloc] initWithSavedSession];
        if (self.session)
        {
            self.session.delegate = self;
        }
        
        // Init HTTP manager
        self.manager = [[AFHTTPSessionManager alloc] initWithBaseURL:self.baseURL];
        self.manager.responseSerializer = [AFJSONResponseSerializer serializer];
        [self.manager.requestSerializer setTimeoutInterval:GLOBAL_API_TIMEOUT_INTERVAL];
        if (!self.manager)
        {
            return nil;
        }

        // init event listeners internal dictionary
        self.eventListenersDict = [NSMutableDictionary new];
        if (self.session.accessToken) {
            [self subscribeToDevicesSystemEvents];
        }
    }
    return self;
}


#pragma mark Getter functions

-(nullable NSString *)accessToken
{
    return [self.session accessToken];
}

-(BOOL)injectSessionAccessToken:(NSString * _Nonnull)accessToken
{
    [self logout];
    self.session = [[ParticleSession alloc] initWithToken:accessToken];
    if (self.session) {
        self.session.delegate = self;
        [self subscribeToDevicesSystemEvents];
        return YES;
    } else return NO;
}

-(BOOL)injectSessionAccessToken:(NSString *)accessToken withExpiryDate:(NSDate *)expiryDate
{
    [self logout];
    self.session = [[ParticleSession alloc] initWithToken:accessToken andExpiryDate:expiryDate];
    if (self.session) {
        self.session.delegate = self;
        [self subscribeToDevicesSystemEvents];
        return YES;
    } else return NO;
}

-(BOOL)injectSessionAccessToken:(NSString *)accessToken withExpiryDate:(NSDate *)expiryDate andRefreshToken:(nonnull NSString *)refreshToken
{
    [self logout];
    self.session = [[ParticleSession alloc] initWithToken:accessToken withExpiryDate:expiryDate withRefreshToken:refreshToken];
    if (self.session) {
        self.session.delegate = self;
        [self subscribeToDevicesSystemEvents];
        return YES;
    } else return NO;
}

-(nullable NSString *)loggedInUsername
{
    if ((self.session.username) && (self.session.accessToken))
    {
        return self.session.username;
    }
    else
    {
        return nil;
    }
}

- (BOOL)isLoggedIn
{
    return (self.session.username != nil);
}

- (BOOL)isAuthenticated
{
    return (self.session.accessToken != nil);
}

#pragma mark Setter functions

- (void)setoAuthClientId:(nullable NSString *)oAuthClientId {
    _oAuthClientId = oAuthClientId ?: kDefaultoAuthClientId;
}

- (void)setoAuthClientSecret:(nullable NSString *)oAuthClientSecret {
    _oAuthClientSecret = oAuthClientSecret ?: kDefaultoAuthClientSecret;
}

#pragma mark Delegate functions

- (void)ParticleSession:(ParticleSession *)session didExpireAt:(NSDate *)date
{
    if (self.session.refreshToken) {
        [self refreshToken:self.session.refreshToken];
    }
    else {
        [self logout];
    }
}

- (void)refreshToken:(NSString *)refreshToken
{
    // non default params
    NSDictionary *params = @{
                             @"grant_type": @"refresh_token",
                             @"refresh_token": refreshToken
                             };
    
    [self.manager.requestSerializer setAuthorizationHeaderFieldWithUsername:self.oAuthClientId password:self.oAuthClientSecret];

    // OAuth login
    [self.manager POST:@"oauth/token" parameters:params progress:nil success:^(NSURLSessionDataTask * _Nonnull task, id  _Nullable responseObject) {
        NSMutableDictionary *responseDict = [responseObject mutableCopy];
        
        if (self.session.username)
            responseDict[@"username"] = self.session.username;
        
        self.session = [[ParticleSession alloc] initWithNewSession:responseDict];
        if (self.session) // login was successful
        {
            self.session.delegate = self;
        }
    } failure:^(NSURLSessionDataTask * _Nullable task, NSError * _Nonnull error) {
        NSError *particleError = [ParticleErrorHelper getParticleError:error task:task customMessage:nil];

        NSLog(@"! refreshToken Failed %@ (%ld): %@\r\n%@", task.originalRequest.URL, (long)particleError.code, particleError.localizedDescription, particleError.userInfo[ParticleSDKErrorResponseBodyKey]);
    }];
    
    [self.manager.requestSerializer clearAuthorizationHeader];

}


#pragma mark SDK public functions

-(NSURLSessionDataTask *)loginWithUser:(NSString *)user password:(NSString *)password completion:(nullable ParticleCompletionBlock)completion
{
    // non default params
    NSDictionary *params = @{
                             @"grant_type": @"password",
                             @"username": user,
                             @"password": password,
                             };
    
    [self.manager.requestSerializer setAuthorizationHeaderFieldWithUsername:self.oAuthClientId password:self.oAuthClientSecret];
    // OAuth login
    NSURLSessionDataTask *task = [self.manager POST:@"oauth/token" parameters:params progress:nil success:^(NSURLSessionDataTask * _Nonnull task, id  _Nullable responseObject) {
        
        NSMutableDictionary *responseDict = [responseObject mutableCopy];

        responseDict[@"username"] = user;
        self.session = [[ParticleSession alloc] initWithNewSession:responseDict];
        if (self.session) // login was successful
        {
            self.session.delegate = self;
            [self subscribeToDevicesSystemEvents];
        }
        
        if (completion)
        {
            completion(nil);
        }
    } failure:^(NSURLSessionDataTask * _Nullable task, NSError * _Nonnull error) {
        NSError *particleError = [ParticleErrorHelper getParticleError:error task:task customMessage:nil];

        if (completion)
        {
            completion(particleError);
        }

        NSLog(@"! loginWithUser Failed %@ (%ld): %@\r\n%@", task.originalRequest.URL, (long)particleError.code, particleError.localizedDescription, particleError.userInfo[ParticleSDKErrorResponseBodyKey]);
    }];
    
    [self.manager.requestSerializer clearAuthorizationHeader];
    
    return task;
}


- (NSURLSessionDataTask *)loginWithUser:(NSString *)user mfaToken:(NSString *)mfaToken OTPToken:(NSString *)otpToken completion:(nullable ParticleCompletionBlock)completion {
    // non default params
    NSDictionary *params = @{
            @"grant_type": @"urn:custom:mfa-otp",
            @"mfa_token": mfaToken,
            @"otp": otpToken,
    };

    [self.manager.requestSerializer setAuthorizationHeaderFieldWithUsername:self.oAuthClientId password:self.oAuthClientSecret];
    NSURLSessionDataTask *task = [self.manager POST:@"oauth/token" parameters:params progress:nil success:^(NSURLSessionDataTask * _Nonnull task, id  _Nullable responseObject) {

        NSMutableDictionary *responseDict = [responseObject mutableCopy];

        responseDict[@"username"] = user;
        self.session = [[ParticleSession alloc] initWithNewSession:responseDict];
        if (self.session) // login was successful
        {
            self.session.delegate = self;
            [self subscribeToDevicesSystemEvents];
        }

        if (completion)
        {
            completion(nil);
        }
    } failure:^(NSURLSessionDataTask * _Nullable task, NSError * _Nonnull error) {
        NSError *particleError = [ParticleErrorHelper getParticleError:error task:task customMessage:nil];

        if (completion)
        {
            completion(particleError);
        }

        NSLog(@"! loginWithMFAToken Failed %@ (%ld): %@\r\n%@", task.originalRequest.URL, (long)particleError.code, particleError.localizedDescription, particleError.userInfo[ParticleSDKErrorResponseBodyKey]);
    }];

    [self.manager.requestSerializer clearAuthorizationHeader];

    return task;
}


-(NSURLSessionDataTask *)createUser:(NSString *)username
                           password:(NSString *)password
                        accountInfo:(nullable NSDictionary *)accountInfo
                         completion:(nullable ParticleCompletionBlock)completion
{

    //TODO: accountInfo is unclear, refactor into method having separate input parameters for everything that is hinding under account info.

    NSMutableDictionary *params = [@{
                             @"username": username,
                             @"password": password,
                             } mutableCopy];
    

    if (accountInfo) {
        params[@"account_info"] = accountInfo;
    }
        
    NSURLSessionDataTask *task = [self.manager POST:@"/v1/users/" parameters:params progress:nil success:^(NSURLSessionDataTask * _Nonnull task, id  _Nullable responseObject)
                                  {
                                      NSDictionary *responseDict = responseObject;
                                      if (completion) {
                                          if ([responseDict[@"ok"] boolValue])
                                          {
                                              completion(nil);
                                          }
                                          else
                                          {
                                              NSString *errorString;
                                              if (responseDict[@"errors"][0])
                                                  errorString = [NSString stringWithFormat:@"Could not sign up: %@",responseDict[@"errors"][0]];
                                              else
                                                  errorString = @"Error signing up";

                                              NSError *particleError = [ParticleErrorHelper getParticleError:nil task:task customMessage:errorString];

                                              completion(particleError);

                                              NSLog(@"! signupWithUser Failed %@ (%ld): %@\r\n%@", task.originalRequest.URL, (long)particleError.code, particleError.localizedDescription, particleError.userInfo[ParticleSDKErrorResponseBodyKey]);
                                          }
                                      }
                                  } failure:^(NSURLSessionDataTask * _Nullable task, NSError * _Nonnull error)
                                  {
                                      NSError *particleError = [ParticleErrorHelper getParticleError:error task:task customMessage:nil];

                                      if (completion) {
                                          completion(particleError);
                                      }

                                      NSLog(@"! signupWithUser Failed%@ (%ld): %@\r\n%@", task.originalRequest.URL, (long)particleError.code, particleError.localizedDescription, particleError.userInfo[ParticleSDKErrorResponseBodyKey]);
                                  }];
    
    [self.manager.requestSerializer clearAuthorizationHeader];
    
    return task;
    
}


-(NSURLSessionDataTask *)signupWithUser:(NSString *)user password:(NSString *)password completion:(nullable ParticleCompletionBlock)completion
{
    return [self createUser:user password:password accountInfo:nil completion:completion];
    
}


-(nullable NSURLSessionDataTask *)createCustomer:(NSString *)username
                                        password:(NSString *)password
                                       productId:(NSUInteger)productId
                                     accountInfo:(nullable NSDictionary *)accountInfo
                                      completion:(nullable ParticleCompletionBlock)completion
{
    // Make sure we got an orgSlug that was neither nil nor the empty string
    if (productId == 0)
    {
        if (completion)
        {
            NSError *particleError = [ParticleErrorHelper getParticleError:nil task:nil customMessage:@"productId value must be set to a non-zero value"];

            completion(particleError);
        }
        return nil;
    }
    
    if ((!self.oAuthClientId) || (!self.oAuthClientSecret))
    {
        if (completion)
        {
            NSError *particleError = [ParticleErrorHelper getParticleError:nil task:nil customMessage:@"Client OAuth credentials must be set to create a new customer"];

            completion(particleError);
        }
        return nil;
    }
    
    [self.manager.requestSerializer setAuthorizationHeaderFieldWithUsername:self.oAuthClientId password:self.oAuthClientSecret];
    
    NSMutableDictionary *params = [@{
                                     @"email": username,
                                     @"password": password,
                                     @"grant_type" : @"client_credentials",
                                     } mutableCopy];
    
    
    NSString *url = [NSString stringWithFormat:@"/v1/products/%tu/customers", productId];
    
    NSURLSessionDataTask *task = [self.manager POST:url parameters:params progress:nil success:^(NSURLSessionDataTask * _Nonnull task, id  _Nullable responseObject)
                                  {
                                      NSHTTPURLResponse *serverResponse = (NSHTTPURLResponse *)task.response;
                                      NSMutableDictionary *responseDict = [responseObject mutableCopy];
                                      //        NSLog(@"Got status code %d, and response: %@",(int)serverResponse.statusCode,responseDict);
                                      
                                      responseDict[@"username"] = username;
                                      
                                      self.session = [[ParticleSession alloc] initWithNewSession:responseDict];
                                      
                                      if (self.session) // customer login was successful
                                      {
                                          self.session.delegate = self;
                                      }
                                      
                                      if (completion)
                                      {
                                          if (serverResponse.statusCode == 201)
                                          {
                                              completion(nil);
                                          }
                                          else
                                          {
                                              NSError *particleError = [ParticleErrorHelper getParticleError:nil task:task customMessage:[responseDict[@"error"] stringValue]];

                                              completion(particleError);

                                              NSLog(@"! createCustomer Failed %@ (%ld): %@\r\n%@", task.originalRequest.URL, (long)particleError.code, particleError.localizedDescription, particleError.userInfo[ParticleSDKErrorResponseBodyKey]);
                                          }
                                      }
                                  } failure:^(NSURLSessionDataTask * _Nullable task, NSError * _Nonnull error)
                                  {
                                      NSError *particleError = [ParticleErrorHelper getParticleError:error task:task customMessage:nil];

                                      if (completion) {
                                          completion(particleError);
                                      }

                                      NSLog(@"! createCustomer Failed %@ (%ld): %@\r\n%@", task.originalRequest.URL, (long)particleError.code, particleError.localizedDescription, particleError.userInfo[ParticleSDKErrorResponseBodyKey]);
                                  }];

    [self.manager.requestSerializer clearAuthorizationHeader];
    
    return task;

}


-(nullable NSURLSessionDataTask *)signupWithCustomer:(NSString *)email password:(NSString *)password orgSlug:(NSString *)orgSlug completion:(nullable ParticleCompletionBlock)completion
{
    return [self createCustomer:email password:password productId:[orgSlug integerValue] accountInfo:nil completion:completion];
}

-(void)logout
{
    [self.session removeSession];
    [self unsubscribeToDevicesSystemEvents];
}

-(NSURLSessionDataTask *)claimDevice:(NSString *)deviceID completion:(nullable ParticleCompletionBlock)completion
{
    if (self.session.accessToken) {
        NSString *authorization = [NSString stringWithFormat:@"Bearer %@",self.session.accessToken];
        [self.manager.requestSerializer setValue:authorization forHTTPHeaderField:@"Authorization"];
    }

    NSMutableDictionary *params = [NSMutableDictionary new]; //[self defaultParams];
    params[@"id"] = deviceID;
    
    NSURLSessionDataTask *task = [self.manager POST:@"/v1/devices" parameters:params progress:nil success:^(NSURLSessionDataTask * _Nonnull task, id  _Nullable responseObject)
    {
        if (completion)
        {
            NSMutableDictionary *responseDict = responseObject;
            
            if ([responseDict[@"ok"] boolValue])
            {
                completion(nil);
            } else
            {
                NSError *particleError = [ParticleErrorHelper getParticleError:nil task:task customMessage:@"Could not claim device"];

                if (completion) {
                    completion(particleError);
                }

                NSLog(@"! claimDevice Failed %@ (%ld): %@\r\n%@", task.originalRequest.URL, (long)particleError.code, particleError.localizedDescription, particleError.userInfo[ParticleSDKErrorResponseBodyKey]);
            }
            
        }
    } failure:^(NSURLSessionDataTask * _Nullable task, NSError * _Nonnull error) {
        NSError *particleError = [ParticleErrorHelper getParticleError:error task:task customMessage:nil];

        if (completion) {
            completion(particleError);
        }

        NSLog(@"! claimDevice Failed %@ (%ld): %@\r\n%@", task.originalRequest.URL, (long)particleError.code, particleError.localizedDescription, particleError.userInfo[ParticleSDKErrorResponseBodyKey]);
    }];
    
    return task;
}

-(NSURLSessionDataTask *)getDevice:(NSString *)deviceID
                        completion:(nullable void (^)(ParticleDevice * _Nullable device, NSError * _Nullable error))completion
{
    if (self.session.accessToken) {
        NSString *authorization = [NSString stringWithFormat:@"Bearer %@",self.session.accessToken];
        [self.manager.requestSerializer setValue:authorization forHTTPHeaderField:@"Authorization"];
    }

    NSString *urlPath = [NSString stringWithFormat:@"/v1/devices/%@",deviceID];
    
    NSURLSessionDataTask *task = [self.manager GET:urlPath parameters:nil progress:nil success:^(NSURLSessionDataTask * _Nonnull task, id  _Nullable responseObject)
    {
         if (completion)
         {
             NSMutableDictionary *responseDict = responseObject;
             ParticleDevice *device = [[ParticleDevice alloc] initWithParams:responseDict];
             
             if (device) { // new 0.5.0 local storage of devices for reporting system events
                 if (!self.devicesMapTable) {
                     self.devicesMapTable = [NSMapTable mapTableWithKeyOptions:NSMapTableStrongMemory valueOptions:NSMapTableObjectPointerPersonality]; // let the user decide when to release ParticleDevice objects
                 }
                 [self.devicesMapTable setObject:device forKey:device.id];
             }
             
             if (completion)
             {
                completion(device, nil);
             }
             
         }
    } failure:^(NSURLSessionDataTask * _Nullable task, NSError * _Nonnull error)
    {
        NSError *particleError = [ParticleErrorHelper getParticleError:error task:task customMessage:nil];

        if (completion)
        {
            completion(nil, particleError);
        }

        NSLog(@"! getDevice Failed %@ (%ld): %@\r\n%@", task.originalRequest.URL, (long)particleError.code, particleError.localizedDescription, particleError.userInfo[ParticleSDKErrorResponseBodyKey]);
    }];
    
    return task;
}


-(NSURLSessionDataTask *)getDevices:(nullable void (^)(NSArray<ParticleDevice *> * _Nullable particleDevices, NSError * _Nullable error))completion
{
    if (self.session.accessToken) {
        NSString *authorization = [NSString stringWithFormat:@"Bearer %@", self.session.accessToken];
        [self.manager.requestSerializer setValue:authorization forHTTPHeaderField:@"Authorization"];
    }
    
    NSURLSessionDataTask *task = [self.manager GET:@"/v1/devices" parameters:nil progress:nil success:^(NSURLSessionDataTask * _Nonnull task, id  _Nullable responseObject)
    {
        
         if (completion)
         {
             NSArray *responseList = responseObject;
             NSMutableArray *queryDeviceIDList = [[NSMutableArray alloc] init];
             __block NSMutableArray *deviceList = [[NSMutableArray alloc] init];
             __block NSError *deviceError = nil;
             // analyze
             for (NSDictionary *deviceDict in responseList)
             {
                 if (deviceDict[@"id"])   // ignore <null> device listings that sometimes return from /v1/devices API call
                 {
                     if (![deviceDict[@"id"] isKindOfClass:[NSNull class]])
                     {
                         if ([deviceDict[@"connected"] boolValue]==YES) // do inquiry only for online devices (otherwise we waste time on request timeouts and get no new info)
                         {
                             // if it's online then add it to the query list so we can get additional information about it
                             [queryDeviceIDList addObject:deviceDict[@"id"]];
                         }
                         else
                         {
                             // if it's offline just make an instance for it with the limited data with have
                             ParticleDevice *device = [[ParticleDevice alloc] initWithParams:deviceDict];
                             [deviceList addObject:device];
                             
                             if (device) { // new 0.5.0 local storage of devices for reporting system events
                                 if (!self.devicesMapTable) {
                                     self.devicesMapTable = [NSMapTable mapTableWithKeyOptions:NSMapTableStrongMemory valueOptions:NSMapTableObjectPointerPersonality]; // let the user decide when to release ParticleDevice objects
                                 }
                                 [self.devicesMapTable setObject:device forKey:device.id];
                             }

                         }
                     }
                     
                 }
             }
             
             // iterate thru deviceList and create ParticleDevice instances through query
             __block dispatch_group_t group = dispatch_group_create();
             
             for (NSString *deviceID in queryDeviceIDList)
             {
                 dispatch_group_enter(group);
                 [self getDevice:deviceID completion:^(ParticleDevice *device, NSError *error) {
                     if ((!error) && (device))
                         [deviceList addObject:device];
                     
                     if ((error) && (!deviceError)) // if there wasn't an error before cache it
                         deviceError = error;
                     
                     dispatch_group_leave(group);
                 }];
             }
             
             // call user's completion block on main thread after all concurrent GET requests finished and ParticleDevice instances created
             dispatch_group_notify(group, dispatch_get_main_queue(), ^{
                 if (completion)
                 {
                     if (deviceError && (deviceList.count==0)) // empty list? error? report it
                     {
                         completion(nil, deviceError);
                     }
                     else if (deviceList.count > 0)  // if some devices reported error but some not, then return at least the ones that didn't report error, ditch error
                     {
                         completion(deviceList, nil);
                     }
                     else
                     {
                         completion(nil, nil);
                     }
                 }
             });
             
             
             
         }
    } failure:^(NSURLSessionDataTask * _Nullable task, NSError * _Nonnull error)
    {
        NSError *particleError = [ParticleErrorHelper getParticleError:error task:task customMessage:nil];

        if (completion)
        {
            completion(nil, particleError);
        }

        NSLog(@"! getDevices Failed %@ (%ld): %@\r\n%@", task.originalRequest.URL, (long)particleError.code, particleError.localizedDescription, particleError.userInfo[ParticleSDKErrorResponseBodyKey]);
    }];
    
    return task;
}



-(NSURLSessionDataTask *)generateClaimCode:(nullable void(^)(NSString * _Nullable claimCode, NSArray * _Nullable userClaimedDeviceIDs, NSError * _Nullable error))completion
{
    if (self.session.accessToken) {
        NSString *authorization = [NSString stringWithFormat:@"Bearer %@",self.session.accessToken];
        [self.manager.requestSerializer setValue:authorization forHTTPHeaderField:@"Authorization"];
    }

    NSString *urlPath = [NSString stringWithFormat:@"/v1/device_claims"];
    NSURLSessionDataTask *task = [self.manager POST:urlPath parameters:nil progress:nil success:^(NSURLSessionDataTask * _Nonnull task, id  _Nullable responseObject)
    {
        if (completion)
        {
            NSDictionary *responseDict = responseObject;
            if (responseDict[@"claim_code"])
            {
                NSArray *claimedDeviceIDs = responseDict[@"device_ids"];
                if ((claimedDeviceIDs) && (claimedDeviceIDs.count > 0))
                {
                    completion(responseDict[@"claim_code"], responseDict[@"device_ids"], nil);
                }
                else
                {
                    completion(responseDict[@"claim_code"], nil, nil);
                }
            }
            else
            {
                NSError *particleError = [ParticleErrorHelper getParticleError:nil task:task customMessage:@"Could not generate a claim code"];

                completion(nil, nil, particleError);

                NSLog(@"! generateClaimCode Failed %@ (%ld): %@\r\n%@", task.originalRequest.URL, (long)particleError.code, particleError.localizedDescription, particleError.userInfo[ParticleSDKErrorResponseBodyKey]);
            }
        }
        
    } failure:^(NSURLSessionDataTask * _Nullable task, NSError * _Nonnull error)
    {
        NSError *particleError = [ParticleErrorHelper getParticleError:error task:task customMessage:nil];

        if (completion)
        {
            completion(nil, nil, particleError);
        }

        NSLog(@"! generateClaimCode Failed %@ (%ld): %@\r\n%@", task.originalRequest.URL, (long)particleError.code, particleError.localizedDescription, particleError.userInfo[ParticleSDKErrorResponseBodyKey]);
    }];
    
    return task;
}



-(NSURLSessionDataTask *)generateClaimCodeForOrganization:(NSString *)orgSlug
                                               andProduct:(NSString *)productSlug
                                       withActivationCode:(nullable NSString *)activationCode
                                               completion:(nullable void(^)(NSString * _Nullable claimCode, NSArray * _Nullable userClaimedDeviceIDs, NSError * _Nullable error))completion
{
    return [self generateClaimCodeForProduct:[productSlug integerValue] completion:completion];
}


-(NSURLSessionDataTask *)generateClaimCodeForProduct:(NSUInteger)productId
                                          completion:(nullable void(^)(NSString *_Nullable claimCode, NSArray * _Nullable userClaimedDeviceIDs, NSError * _Nullable error))completion
{
    if (self.session.accessToken) {
        NSString *authorization = [NSString stringWithFormat:@"Bearer %@",self.session.accessToken];
        [self.manager.requestSerializer setValue:authorization forHTTPHeaderField:@"Authorization"];
    }
    
    NSString *urlPath = [NSString stringWithFormat:@"/v1/products/%tu/device_claims", productId];
    
    NSURLSessionDataTask *task = [self.manager POST:urlPath parameters:nil progress:nil success:^(NSURLSessionDataTask * _Nonnull task, id  _Nullable responseObject)
                                  {
                                      if (completion)
                                      {
                                          NSDictionary *responseDict = responseObject;
                                          if (responseDict[@"claim_code"])
                                          {
                                              NSArray *claimedDeviceIDs = responseDict[@"device_ids"];
                                              if ((claimedDeviceIDs) && (claimedDeviceIDs.count > 0))
                                              {
                                                  completion(responseDict[@"claim_code"], responseDict[@"device_ids"], nil);
                                              }
                                              else
                                              {
                                                  completion(responseDict[@"claim_code"], nil, nil);
                                              }
                                          }
                                          else
                                          {
                                              NSError *particleError = [ParticleErrorHelper getParticleError:nil task:task customMessage:@"Could not generate a claim code"];

                                              completion(nil, nil, particleError);

                                              NSLog(@"! generateClaimCodeForOrganization Failed %@ (%ld): %@\r\n%@", task.originalRequest.URL, (long)particleError.code, particleError.localizedDescription, particleError.userInfo[ParticleSDKErrorResponseBodyKey]);
                                          }
                                      }
                                      
                                  } failure:^(NSURLSessionDataTask * _Nullable task, NSError * _Nonnull error)
                                  {
                                      NSError *particleError = [ParticleErrorHelper getParticleError:error task:task customMessage:nil];

                                      if (completion)
                                      {
                                          completion(nil, nil, particleError);
                                      }

                                      NSLog(@"! generateClaimCodeForOrganization Failed %@ (%ld): %@\r\n%@", task.originalRequest.URL, (long)particleError.code, particleError.localizedDescription, particleError.userInfo[ParticleSDKErrorResponseBodyKey]);
                                  }];
    
    return task;
}


-(NSURLSessionDataTask *)requestPasswordResetForCustomer:(NSString *)email
                                               productId:(NSUInteger)productId
                                              completion:(nullable ParticleCompletionBlock)completion

{
    NSDictionary *params = @{@"email": email};
    
    NSString *urlPath = [NSString stringWithFormat:@"/v1/products/%tu/customers/reset_password", productId];
    
    
    NSURLSessionDataTask *task = [self.manager POST:urlPath parameters:params progress:nil success:^(NSURLSessionDataTask * _Nonnull task, id  _Nullable responseObject)
                                  {
                                      if (completion) // TODO: check responses
                                      {
                                          completion(nil);
                                      }
                                  } failure:^(NSURLSessionDataTask * _Nullable task, NSError * _Nonnull error)
                                  {
                                      NSError *particleError = [ParticleErrorHelper getParticleError:error task:task customMessage:nil];

                                      if (completion)
                                      {
                                          completion(particleError);
                                      }

                                      NSLog(@"! requestPasswordReset Failed %@ (%ld): %@\r\n%@", task.originalRequest.URL, (long)particleError.code, particleError.localizedDescription, particleError.userInfo[ParticleSDKErrorResponseBodyKey]);
                                  }];
    
    return task;
    
}

-(NSURLSessionDataTask *)requestPasswordResetForCustomer:(NSString *)orgSlug
                                                   email:(NSString *)email
                                              completion:(nullable ParticleCompletionBlock)completion
{
    return [self requestPasswordResetForCustomer:email productId:[orgSlug integerValue] completion:completion];
}


-(NSURLSessionDataTask *)requestPasswordResetForUser:(NSString *)email
                                          completion:(nullable ParticleCompletionBlock)completion
{
    NSDictionary *params = @{@"username": email};
    NSString *urlPath = [NSString stringWithFormat:@"/v1/user/password-reset"];
    
    NSURLSessionDataTask *task = [self.manager POST:urlPath parameters:params progress:nil success:^(NSURLSessionDataTask * _Nonnull task, id  _Nullable responseObject)
    {
        if (completion) // TODO: check responses
        {
            completion(nil);
        }
    } failure:^(NSURLSessionDataTask * _Nullable task, NSError * _Nonnull error) {
        NSError *particleError = [ParticleErrorHelper getParticleError:error task:task customMessage:nil];

        if (completion)
        {
            completion(particleError);
        }

        NSLog(@"! requestPasswordResetForUser Failed %@ (%ld): %@\r\n%@", task.originalRequest.URL, (long)particleError.code, particleError.localizedDescription, particleError.userInfo[ParticleSDKErrorResponseBodyKey]);
    }];
    
    return task;
}

#pragma mark Internal use methods

-(NSURLSessionDataTask *)listTokens:(NSString *)user password:(NSString *)password
{
    [self.manager.requestSerializer setAuthorizationHeaderFieldWithUsername:user password:password];
    
    NSURLSessionDataTask *task = [self.manager GET:@"/v1/access_tokens" parameters:nil progress:nil success:^(NSURLSessionDataTask * _Nonnull task, id  _Nullable responseObject)
    {
//        NSArray *responseArr = responseObject;
    } failure:^(NSURLSessionDataTask * _Nullable task, NSError * _Nonnull error)
    {
        NSLog(@"listTokens %@",[error localizedDescription]);
    }];
    
    [self.manager.requestSerializer clearAuthorizationHeader];
    
    return task;
}

#pragma mark Events subsystem implementation

-(nullable id)subscribeToEventWithURL:(NSURL *)url handler:(nullable ParticleEventHandler)eventHandler
{
    if (!self.accessToken)
    {
        NSError *particleError = [ParticleErrorHelper getParticleError:nil task:nil customMessage:@"No active access token"];

        eventHandler(nil, particleError);
        return nil;
    }

    // TODO: add eventHandler + source to an internal dictionary so it will be removeable later by calling removeEventListener on saved Source
    EventSource *source = [EventSource eventSourceWithURL:url timeoutInterval:300.0f queue:dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0)];
    
    //    if (eventName == nil)
    //        eventName = @"no_name";
    
    // - event example -
    // event: Temp
    // data: {"data":"Temp1 is 41.900002 F, Temp2 is $f F","ttl":"60","published_at":"2015-01-13T01:23:12.269Z","coreid":"53ff6e066667574824151267"}
    
    //    [source addEventListener:@"" handler:^(Event *event) { //event name
//    [source onMessage:
    
     EventSourceEventHandler handler = ^void(Event *event) {
        if (eventHandler)
        {
            if (event.error)
                eventHandler(nil, event.error);
            else
            {
                // deserialize event payload into dictionary
                NSError *error;
                NSDictionary *jsonDict;
                NSMutableDictionary *eventDict;
                if (event.data)
                {
                    jsonDict = [NSJSONSerialization JSONObjectWithData:event.data options:0 error:&error];
                    eventDict = [jsonDict mutableCopy];
                }
                
                if ((eventDict) && (!error))
                {
                    if (event.name)
                    {
                        eventDict[@"event"] = event.name; // add event name to dict
                    }
                    ParticleEvent *particleEvent = [[ParticleEvent alloc] initWithEventDict:eventDict];
                    eventHandler(particleEvent ,nil); // callback with parsed data
                }
                else if (error)
                {
                    eventHandler(nil, error);
                }
            }
        }
        
    };
    
    [source onMessage:handler]; // bind the handler
    
    id eventListenerID = [NSUUID UUID]; // create the eventListenerID
    self.eventListenersDict[eventListenerID] = @{kEventListenersDictHandlerKey : handler,
                                                 kEventListenersDictEventSourceKey : source}; // save it in the internal dictionary for future unsubscribing
    
    return eventListenerID;
    
}


-(void)unsubscribeFromEventWithID:(id)eventListenerID
{
    NSDictionary *eventListenerDict = [self.eventListenersDict objectForKey:eventListenerID];
    if (eventListenerDict)
    {
        EventSource *source = [eventListenerDict objectForKey:kEventListenersDictEventSourceKey];
        EventSourceEventHandler handler = [eventListenerDict objectForKey:kEventListenersDictHandlerKey];
        [source removeEventListener:MessageEvent handler:handler];
        [source close];
        [self.eventListenersDict removeObjectForKey:eventListenerID];
    }
}


-(nullable id)subscribeToAllEventsWithPrefix:(nonnull NSString *)eventNamePrefix handler:(nullable ParticleEventHandler)eventHandler
{
    // GET /v1/events[/:event_name]
    NSString *endpoint;
    if ((!eventNamePrefix) || [eventNamePrefix isEqualToString:@""])
    {
        NSLog(@"! subscribeToAllEventsWithPrefix Failed: eventNamePrefix is no longer optional and cannot be empty for this event stream.");
        return nil;
    }
    else
    {
        // URL encode name prefix
        NSCharacterSet *set = [NSCharacterSet URLHostAllowedCharacterSet];
        NSString *encodedEventPrefix = [eventNamePrefix stringByAddingPercentEncodingWithAllowedCharacters:set];
        endpoint = [NSString stringWithFormat:@"%@/v1/events/%@?access_token=%@", self.baseURL, encodedEventPrefix, self.accessToken];
    }
    
    return [self subscribeToEventWithURL:[NSURL URLWithString:endpoint] handler:eventHandler];
}


-(nullable id)subscribeToMyDevicesEventsWithPrefix:(nullable NSString *)eventNamePrefix handler:(nullable ParticleEventHandler)eventHandler
{
    // GET /v1/devices/events[/:event_name]
    NSString *endpoint;
    if ((!eventNamePrefix) || [eventNamePrefix isEqualToString:@""])
    {
        endpoint = [NSString stringWithFormat:@"%@/v1/devices/events?access_token=%@", self.baseURL, self.accessToken];
    }
    else
    {
        // URL encode name prefix
        NSCharacterSet *set = [NSCharacterSet URLHostAllowedCharacterSet];
        NSString *encodedEventPrefix = [eventNamePrefix stringByAddingPercentEncodingWithAllowedCharacters:set];
        endpoint = [NSString stringWithFormat:@"%@/v1/devices/events/%@?access_token=%@", self.baseURL, encodedEventPrefix, self.accessToken];
    }
    
    return [self subscribeToEventWithURL:[NSURL URLWithString:endpoint] handler:eventHandler];
    
}

-(nullable id)subscribeToDeviceEventsWithPrefix:(nullable NSString *)eventNamePrefix deviceID:(NSString *)deviceID handler:(nullable ParticleEventHandler)eventHandler
{
    // GET /v1/devices/:device_id/events[/:event_name]
    NSString *endpoint;
    if ((!eventNamePrefix) || [eventNamePrefix isEqualToString:@""])
    {
        endpoint = [NSString stringWithFormat:@"%@/v1/devices/%@/events?access_token=%@", self.baseURL, deviceID, self.accessToken];
    }
    else
    {
        // URL encode name prefix
        NSCharacterSet *set = [NSCharacterSet URLHostAllowedCharacterSet];
        NSString *encodedEventPrefix = [eventNamePrefix stringByAddingPercentEncodingWithAllowedCharacters:set];
        endpoint = [NSString stringWithFormat:@"%@/v1/devices/%@/events/%@?access_token=%@", self.baseURL, deviceID, encodedEventPrefix, self.accessToken];
    }
    
    return [self subscribeToEventWithURL:[NSURL URLWithString:endpoint] handler:eventHandler];
}



-(NSURLSessionDataTask *)publishEventWithName:(NSString *)eventName
                                         data:(NSString *)data
                                    isPrivate:(BOOL)isPrivate
                                          ttl:(NSUInteger)ttl
                                   completion:(nullable ParticleCompletionBlock)completion
{
    NSMutableDictionary *params = [NSMutableDictionary new];
    if (self.session.accessToken) {
        NSString *authorization = [NSString stringWithFormat:@"Bearer %@",self.session.accessToken];
        [self.manager.requestSerializer setValue:authorization forHTTPHeaderField:@"Authorization"];
    }
    
    params[@"name"] = eventName;
    params[@"data"] = data;
    params[@"private"] = isPrivate ? @"true" : @"false";
    params[@"ttl"] = [NSString stringWithFormat:@"%lu", (unsigned long)ttl];
    
    NSURLSessionDataTask *task = [self.manager POST:@"/v1/devices/events" parameters:params progress:nil success:^(NSURLSessionDataTask * _Nonnull task, id  _Nullable responseObject)
    {
        if (completion)
        {
            // TODO: check server response for that
            NSDictionary *responseDict = responseObject;
            if (![responseDict[@"ok"] boolValue])
            {
                NSError *particleError = [ParticleErrorHelper getParticleError:nil task:task customMessage:@"Server reported error publishing event"];

                completion(particleError);

                NSLog(@"! publishEventWithName Failed %@ (%ld): %@\r\n%@", task.originalRequest.URL, (long)particleError.code, particleError.localizedDescription, particleError.userInfo[ParticleSDKErrorResponseBodyKey]);
            }
            else
            {
                completion(nil);
            }
        }
    } failure:^(NSURLSessionDataTask * _Nullable task, NSError * _Nonnull error)
    {
        NSError *particleError = [ParticleErrorHelper getParticleError:error task:task customMessage:nil];

        if (completion)
        {
            completion(particleError);
        }

        NSLog(@"! publishEventWithName Failed %@ (%ld): %@\r\n%@", task.originalRequest.URL, (long)particleError.code, particleError.localizedDescription, particleError.userInfo[ParticleSDKErrorResponseBodyKey]);
    }];
    
    return task;
}



-(void)subscribeToDevicesSystemEvents {
    
    __weak ParticleCloud *weakSelf = self;
    self.systemEventsListenerId = [self subscribeToMyDevicesEventsWithPrefix:@"particle" handler:^(ParticleEvent * _Nullable event, NSError * _Nullable error) {

        if (!error) {
            ParticleDevice *device = [weakSelf.devicesMapTable objectForKey:event.deviceID];
            if (device) {
                [device __receivedSystemEvent:event];
            }
        } else {
            NSLog(@"! ParticleCloud could not subscribeToEvents to devices system events %@",error.localizedDescription);
        }
    }];

}

-(void)unsubscribeToDevicesSystemEvents {
    if (self.systemEventsListenerId) {
        [self unsubscribeFromEventWithID:self.systemEventsListenerId];
    }
}


-(void)dealloc {
    [self unsubscribeToDevicesSystemEvents];
}

@end

NS_ASSUME_NONNULL_END
