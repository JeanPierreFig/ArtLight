//
//  ParticleDevice.m
//  mobile-sdk-ios
//
//  Created by Ido Kleinman on 11/7/14.
//  Copyright (c) 2014-2015 Particle. All rights reserved.
//

#import "ParticleDevice.h"
#import "ParticleCloud.h"
#import "ParticleErrorHelper.h"
#import <objc/runtime.h>

#ifdef USE_FRAMEWORKS
#import <AFNetworking/AFNetworking.h>
#else
#import "AFNetworking.h"
#endif

#define MAX_SPARK_FUNCTION_ARG_LENGTH 63

NS_ASSUME_NONNULL_BEGIN

@interface ParticleDevice()

@property (strong, nonatomic, nonnull) NSString* id;
@property (nonatomic) BOOL connected; // might be impossible
@property (strong, nonatomic, nonnull) NSArray *functions;
@property (strong, nonatomic, nonnull) NSDictionary *variables;
@property (strong, nonatomic, nullable) NSString *version;
//@property (nonatomic) ParticleDeviceType type;
@property (nonatomic) BOOL requiresUpdate;
@property (nonatomic, strong) AFHTTPSessionManager *manager;
@property (nonatomic) BOOL isFlashing;
@property (nonatomic, strong) NSURL *baseURL;

@property (strong, nonatomic, nullable) NSString *lastIPAdress;
@property (strong, nonatomic, nullable) NSString *lastIccid; // Electron only
@property (strong, nonatomic, nullable) NSString *imei; // Electron only
@property (nonatomic) NSUInteger platformId;
@property (nonatomic) NSUInteger productId;
@property (strong, nonatomic, nullable) NSString *status;
@property (strong, nonatomic, nullable) NSString *appHash;
@end

@implementation ParticleDevice

-(nullable instancetype)initWithParams:(NSDictionary *)params
{
    if (self = [super init])
    {
        _baseURL = [NSURL URLWithString:kParticleAPIBaseURL];
        if (!_baseURL) {
            return nil;
        }
     
        _requiresUpdate = NO;
        
        _name = nil;
        if ([params[@"name"] isKindOfClass:[NSString class]])
        {
            _name = params[@"name"];
        }
        
        _connected = [params[@"connected"] boolValue] == YES;
        
        _functions = params[@"functions"] ?: @[];
        _variables = params[@"variables"] ?: @{};
        
        if (![_functions isKindOfClass:[NSArray class]]) {
            self.functions = @[];
        }

        if (![_variables isKindOfClass:[NSDictionary class]]) {
            _variables = @{};
        }

        _id = params[@"id"];

        _type = ParticleDeviceTypeUnknown;
        if ([params[@"platform_id"] isKindOfClass:[NSNumber class]])
        {
            self.platformId = [params[@"platform_id"] intValue];

            switch (self.platformId) {
                case ParticleDeviceTypeCore:
                case ParticleDeviceTypeElectron:
                case ParticleDeviceTypePhoton: // or P0 - same id
                case ParticleDeviceTypeP1:
                case ParticleDeviceTypeRedBearDuo:
                case ParticleDeviceTypeBluz:
                case ParticleDeviceTypeDigistumpOak:
                    _type = self.platformId;
                    break;
                default:
                    _type = ParticleDeviceTypeUnknown;
                    break;
            }
        }

        
        if ([params[@"product_id"] isKindOfClass:[NSNumber class]])
        {
            _productId = [params[@"product_id"] intValue];
        }
        
        if ((params[@"last_iccid"]) && ([params[@"last_iccid"] isKindOfClass:[NSString class]]))
        {
            _lastIccid = params[@"last_iccid"];
        }

        if ((params[@"imei"]) && ([params[@"imei"] isKindOfClass:[NSString class]]))
        {
            _imei = params[@"imei"];
        }

        if ((params[@"status"]) && ([params[@"status"] isKindOfClass:[NSString class]]))
        {
            _status = params[@"status"];
        }

        
        if ([params[@"last_ip_address"] isKindOfClass:[NSString class]])
        {
            _lastIPAdress = params[@"last_ip_address"];
        }
        
        if ([params[@"last_app"] isKindOfClass:[NSString class]])
        {
            _lastApp = params[@"last_app"];
        }

        if ([params[@"last_heard"] isKindOfClass:[NSString class]])
        {
            // TODO: add to utils class as POSIX time to NSDate
            NSString *dateString = params[@"last_heard"];// "2015-04-18T08:42:22.127Z"
            NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
            [formatter setDateFormat:@"yyyy-MM-dd'T'HH:mm:ss.SSSZ"];
            NSLocale *posix = [[NSLocale alloc] initWithLocaleIdentifier:@"en_US_POSIX"];
            [formatter setLocale:posix];
            _lastHeard = [formatter dateFromString:dateString];
        }

        /// WIP
        /*
        if (params[@"cc3000_patch_version"]) { // Core only
            self.systemFirmwareVersion = (params[@"cc3000_patch_version"]);
        } else if (params[@"current_build_target"]) { // Electron only
            self.systemFirmwareVersion = params[@"current_build_target"];
        }
         */
        
            
        if (params[@"device_needs_update"])
        {
            _requiresUpdate = YES;
        }
        
        self.manager = [[AFHTTPSessionManager alloc] initWithBaseURL:self.baseURL];
        self.manager.responseSerializer = [AFJSONResponseSerializer serializer];

        if (!self.manager) return nil;
        
         
        return self;
    }
    
    return nil;
}



-(NSURLSessionDataTask *)refresh:(nullable ParticleCompletionBlock)completion;
{
    return [[ParticleCloud sharedInstance] getDevice:self.id completion:^(ParticleDevice * _Nullable updatedDevice, NSError * _Nullable error) {
        if (!error)
        {
            if (updatedDevice)
            {
                // if we got an updated device from the cloud - overwrite ALL self's properies with the new device properties (except for delegate which should be copied over)
                NSMutableSet *propNames = [NSMutableSet set];
                unsigned int outCount, i;
                objc_property_t *properties = class_copyPropertyList([updatedDevice class], &outCount);
                for (i = 0; i < outCount; i++) {
                    objc_property_t property = properties[i];
                    NSString *propertyName = [[NSString alloc] initWithCString:property_getName(property) encoding:NSStringEncodingConversionAllowLossy];
                    [propNames addObject:propertyName];
                }
                free(properties);
                
                if (self.delegate) {
                    updatedDevice.delegate = self.delegate;
                }
                
                for (NSString *property in propNames)
                {
                    id value = [updatedDevice valueForKey:property];
                    [self setValue:value forKey:property];
                }
            }
            if (completion)
            {
                completion(nil);
            }
        }
        else
        {
            if (completion)
            {
                completion(error);
            }
        }
    }];
}

-(void)setName:(nullable NSString *)name
{
    if (name != nil) {
        [self rename:name completion:nil];
    }
}

-(NSURLSessionDataTask *)getVariable:(NSString *)variableName completion:(nullable void(^)(id _Nullable result, NSError* _Nullable error))completion
{
    // TODO: check variable name exists in list
    // TODO: check response of calling a non existant function
    
    NSURL *url = [self.baseURL URLByAppendingPathComponent:[NSString stringWithFormat:@"v1/devices/%@/%@", self.id, variableName]];
    
    [self setAuthHeaderWithAccessToken];
    
    NSURLSessionDataTask *task = [self.manager GET:[url description] parameters:nil progress:nil success:^(NSURLSessionDataTask * _Nonnull task, id  _Nullable responseObject)
    {
        if (completion)
        {
            NSDictionary *responseDict = responseObject;
            if (![responseDict[@"coreInfo"][@"connected"] boolValue]) // check response
            {
                NSError *particleError = [ParticleErrorHelper getParticleError:nil task:task customMessage:@"Device is not connected"];

                completion(nil,particleError);
            }
            else
            {
                // check
                completion(responseDict[@"result"], nil);
            }
        }
    } failure:^(NSURLSessionDataTask * _Nullable task, NSError * _Nonnull error)
    {
        NSError *particleError = [ParticleErrorHelper getParticleError:error task:task customMessage:nil];

        if (completion)
        {
            completion(nil, particleError);
        }

        NSLog(@"! getVariable Failed %@ (%ld): %@\r\n%@", task.originalRequest.URL, (long)particleError.code, particleError.localizedDescription, particleError.userInfo[ParticleSDKErrorResponseBodyKey]);
    }];
    
    return task;
}

-(NSURLSessionDataTask *)callFunction:(NSString *)functionName
                        withArguments:(nullable NSArray *)args
                           completion:(nullable void (^)(NSNumber * _Nullable result, NSError * _Nullable error))completion
{
    // TODO: check function name exists in list
    // TODO: check response of calling a non existant function
    NSURL *url = [self.baseURL URLByAppendingPathComponent:[NSString stringWithFormat:@"v1/devices/%@/%@", self.id, functionName]];
    NSMutableDictionary *params = [NSMutableDictionary new]; //[self defaultParams];

    if (args) {
        NSMutableArray *argsStr = [[NSMutableArray alloc] initWithCapacity:args.count];
        for (id arg in args)
        {
            [argsStr addObject:[arg description]];
        }
        NSString *argsValue = [argsStr componentsJoinedByString:@","];
        if (argsValue.length > MAX_SPARK_FUNCTION_ARG_LENGTH)
        {
            NSError *particleError = [ParticleErrorHelper getParticleError:nil task:nil customMessage:[NSString stringWithFormat:@"Maximum argument length cannot exceed %d",MAX_SPARK_FUNCTION_ARG_LENGTH]];
            if (completion)
                completion(nil, particleError);
            return nil;
        }
            
        params[@"args"] = argsValue;
    }
    
    [self setAuthHeaderWithAccessToken];
    
    NSURLSessionDataTask *task = [self.manager POST:[url description] parameters:params progress:nil success:^(NSURLSessionDataTask * _Nonnull task, id  _Nullable responseObject)
    {
        if (completion)
        {
            NSDictionary *responseDict = responseObject;
            if ([responseDict[@"connected"] boolValue]==NO)
            {
                NSError *particleError = [ParticleErrorHelper getParticleError:nil task:task customMessage:@"Device is not connected"];
                completion(nil, particleError);
            }
            else
            {
                // check
                NSNumber *result = responseDict[@"return_value"];
                completion(result,nil);
            }
        }
    } failure:^(NSURLSessionDataTask * _Nullable task, NSError * _Nonnull error)
    {
        NSError *particleError = [ParticleErrorHelper getParticleError:error task:task customMessage:nil];

        if (completion)
        {
            completion(nil, particleError);
        }

        NSLog(@"! callFunction Failed %@ (%ld): %@\r\n%@", task.originalRequest.URL, (long)particleError.code, particleError.localizedDescription, particleError.userInfo[ParticleSDKErrorResponseBodyKey]);
    }];
    
    return task;
}


-(NSURLSessionDataTask *)signal:(BOOL)enable completion:(nullable ParticleCompletionBlock)completion
{
    NSURL *url = [self.baseURL URLByAppendingPathComponent:[NSString stringWithFormat:@"v1/devices/%@", self.id]];
    
    NSMutableDictionary *params = [NSMutableDictionary new];
    params[@"signal"] = enable ? @"1" : @"0";
    
    [self setAuthHeaderWithAccessToken];
    
    NSURLSessionDataTask *task = [self.manager PUT:[url description] parameters:params success:^(NSURLSessionDataTask * _Nonnull task, id  _Nullable responseObject) {
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

        NSLog(@"! signal Failed %@ (%ld): %@\r\n%@", task.originalRequest.URL, (long)particleError.code, particleError.localizedDescription, particleError.userInfo[ParticleSDKErrorResponseBodyKey]);
    }];
    
    return task;
}


-(NSURLSessionDataTask *)unclaim:(nullable ParticleCompletionBlock)completion
{

    NSURL *url = [self.baseURL URLByAppendingPathComponent:[NSString stringWithFormat:@"v1/devices/%@", self.id]];

    [self setAuthHeaderWithAccessToken];

    NSURLSessionDataTask *task = [self.manager DELETE:[url description] parameters:nil success:^(NSURLSessionDataTask * _Nonnull task, id  _Nullable responseObject)
    {
        if (completion)
        {
            NSDictionary *responseDict = responseObject;
            if ([responseDict[@"ok"] boolValue])
                completion(nil);
            else {
                NSError *particleError = [ParticleErrorHelper getParticleError:nil task:task customMessage:@"Could not unclaim device"];

                if (completion)
                {
                    completion(particleError);
                }

                NSLog(@"! unclaim Failed %@ (%ld): %@\r\n%@", task.originalRequest.URL, (long)particleError.code, particleError.localizedDescription, particleError.userInfo[ParticleSDKErrorResponseBodyKey]);
            }

        }
    } failure:^(NSURLSessionDataTask * _Nullable task, NSError * _Nonnull error)
    {
        NSError *particleError = [ParticleErrorHelper getParticleError:error task:task customMessage:nil];

        if (completion)
        {
            completion(particleError);
        }

        NSLog(@"! unclaim Failed %@ (%ld): %@\r\n%@", task.originalRequest.URL, (long)particleError.code, particleError.localizedDescription, particleError.userInfo[ParticleSDKErrorResponseBodyKey]);
    }];
    
    return task;
}

-(NSURLSessionDataTask *)rename:(NSString *)newName completion:(nullable ParticleCompletionBlock)completion
{
    NSURL *url = [self.baseURL URLByAppendingPathComponent:[NSString stringWithFormat:@"v1/devices/%@", self.id]];

    // TODO: check name validity before calling API
    NSMutableDictionary *params = [NSMutableDictionary new];
    params[@"name"] = newName;

    [self setAuthHeaderWithAccessToken];

    NSURLSessionDataTask *task = [self.manager PUT:[url description] parameters:params success:^(NSURLSessionDataTask * _Nonnull task, id  _Nullable responseObject) {
        self.name = newName;
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

        NSLog(@"! rename Failed %@ (%ld): %@\r\n%@", task.originalRequest.URL, (long)particleError.code, particleError.localizedDescription, particleError.userInfo[ParticleSDKErrorResponseBodyKey]);
    }];
    
    return task;
}



#pragma mark Internal use methods
- (NSMutableDictionary *)defaultParams
{
    // TODO: change access token to be passed in header not in body
    if ([ParticleCloud sharedInstance].accessToken)
    {
        return [@{@"access_token" : [ParticleCloud sharedInstance].accessToken} mutableCopy];
    }
    else return nil;
}

-(void)setAuthHeaderWithAccessToken
{
    if ([ParticleCloud sharedInstance].accessToken) {
        NSString *authorization = [NSString stringWithFormat:@"Bearer %@",[ParticleCloud sharedInstance].accessToken];
        [self.manager.requestSerializer setValue:authorization forHTTPHeaderField:@"Authorization"];
    }
}


-(NSString *)description
{
    NSString *desc = [NSString stringWithFormat:@"<ParticleDevice 0x%lx, type: %@, id: %@, name: %@, connected: %@, variables: %@, functions: %@, version: %@, requires update: %@, last app: %@, last heard: %@>",
                      (unsigned long)self,
                      (self.type == ParticleDeviceTypeCore) ? @"Core" : @"Photon",
                      self.id,
                      self.name,
                      (self.connected) ? @"true" : @"false",
                      self.variables,
                      self.functions,
                      self.version,
                      (self.requiresUpdate) ? @"true" : @"false",
                      self.lastApp,
                      self.lastHeard];
    
    return desc;
    
}


-(NSURLSessionDataTask *)flashKnownApp:(NSString *)knownAppName completion:(nullable ParticleCompletionBlock)completion
{
    NSURL *url = [self.baseURL URLByAppendingPathComponent:[NSString stringWithFormat:@"v1/devices/%@", self.id]];
    
    NSMutableDictionary *params = [NSMutableDictionary new];
    params[@"app"] = knownAppName;
    [self setAuthHeaderWithAccessToken];
    
    NSURLSessionDataTask *task = [self.manager PUT:[url description] parameters:params success:^(NSURLSessionDataTask * _Nonnull task, id  _Nullable responseObject)
    {
        NSDictionary *responseDict = responseObject;
        if (responseDict[@"errors"])
        {
            if (completion) {
                NSError *particleError = [ParticleErrorHelper getParticleError:nil task:task customMessage:responseDict[@"errors"][@"error"]];

                completion(particleError);
            }
        }
        else
        {
            if (completion) {
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

        NSLog(@"! flashKnownApp Failed %@ (%ld): %@\r\n%@", task.originalRequest.URL, (long)particleError.code, particleError.localizedDescription, particleError.userInfo[ParticleSDKErrorResponseBodyKey]);
    }];
    
    return task;
}


-(nullable NSURLSessionDataTask *)flashFiles:(NSDictionary *)filesDict completion:(nullable ParticleCompletionBlock)completion // binary
{
    NSURL *url = [self.baseURL URLByAppendingPathComponent:[NSString stringWithFormat:@"v1/devices/%@", self.id]];
    
    [self setAuthHeaderWithAccessToken];
    
    NSError *reqError;
    NSMutableURLRequest *request = [self.manager.requestSerializer multipartFormRequestWithMethod:@"PUT" URLString:url.description parameters:@{@"file_type" : @"binary"} constructingBodyWithBlock:^(id<AFMultipartFormData> formData) {
        // check this:
        for (NSString *key in filesDict.allKeys)
        {
            [formData appendPartWithFileData:filesDict[key] name:@"file" fileName:key mimeType:@"application/octet-stream"];
        }
    } error:&reqError];
    
    if (!reqError)
    {
        __block NSURLSessionDataTask *task = [self.manager dataTaskWithRequest:request
                uploadProgress: nil
                downloadProgress: nil
                completionHandler:^(NSURLResponse * _Nonnull response, id  _Nullable responseObject, NSError * _Nullable error)
        {
            if (error == nil)
            {
                NSDictionary *responseDict = responseObject;
                if (responseDict[@"error"])
                {
                    if (completion)
                    {
                        NSError *particleError = [ParticleErrorHelper getParticleError:nil task:task customMessage:responseDict[@"error"]];

                        completion(particleError);
                    }
                }
                else if (completion)
                {
                    completion(nil);
                }
            }
            else
            {
                NSError *particleError = [ParticleErrorHelper getParticleError:error task:task customMessage:nil];

                if (completion)
                {
                    completion(particleError);
                }

                NSLog(@"! flashFiles Failed %@ (%ld): %@\r\n%@", task.originalRequest.URL, (long)particleError.code, particleError.localizedDescription, particleError.userInfo[ParticleSDKErrorResponseBodyKey]);
            }
        }];
        
        [task resume];
        return task;
    }
    else
    {
        if (completion)
        {
            completion(reqError);
        }

        return nil;
    }
}




-(nullable id)subscribeToEventsWithPrefix:(nullable NSString *)eventNamePrefix handler:(nullable ParticleEventHandler)eventHandler
{
    return [[ParticleCloud sharedInstance] subscribeToDeviceEventsWithPrefix:eventNamePrefix deviceID:self.name handler:eventHandler]; // DEBUG TODO self.id
}

-(void)unsubscribeFromEventWithID:(id)eventListenerID
{
    [[ParticleCloud sharedInstance] unsubscribeFromEventWithID:eventListenerID];
}

-(NSURLSessionDataTask *)getCurrentDataUsage:(nullable void(^)(float dataUsed, NSError* _Nullable error))completion
{
    if (self.type != ParticleDeviceTypeElectron) {
        if (completion)
        {
            NSError *particleError = [ParticleErrorHelper getParticleError:nil task:nil customMessage:@"Command supported only for Electron device"];
            completion(-1, particleError);
        }
        return nil;
    }
    
    //curl https://api.particle.io/v1/sims/8934076500002586576/data_usage\?access_token\=5451a5d6c6c54f6b20e3a109ee764596dc38a520
    NSURL *url = [self.baseURL URLByAppendingPathComponent:[NSString stringWithFormat:@"v1/sims/%@/data_usage", self.lastIccid]];
    
    [self setAuthHeaderWithAccessToken];
    
    NSURLSessionDataTask *task = [self.manager GET:[url description] parameters:nil progress:nil success:^(NSURLSessionDataTask * _Nonnull task, id  _Nullable responseObject)
                                  {
                                      if (completion)
                                      {
                                          NSDictionary *responseDict = responseObject;
                                          NSDictionary *responseUsageDict = responseDict[@"usage_by_day"];
                                          float maxUsage = 0;
                                          for (NSDictionary *usageDict in responseUsageDict) {
                                              if (usageDict[@"mbs_used_cumulative"]) {
                                                  float usage = [usageDict[@"mbs_used_cumulative"] floatValue];
                                                  if (usage > maxUsage) {
                                                      maxUsage = usage;
                                                  }
                                              }
                                          }
                                          completion(maxUsage, nil);
                                      }
                                  } failure:^(NSURLSessionDataTask * _Nullable task, NSError * _Nonnull error)
                                  {
                                      NSError *particleError = [ParticleErrorHelper getParticleError:error task:task customMessage:nil];

                                      if (completion)
                                      {
                                          completion(-1, particleError);
                                      }

                                      NSLog(@"! getCurrentDataUsage Failed %@ (%ld): %@\r\n%@", task.originalRequest.URL, (long)particleError.code, particleError.localizedDescription, particleError.userInfo[ParticleSDKErrorResponseBodyKey]);
                                  }];
    
    return task;
}

-(void)__receivedSystemEvent:(ParticleEvent *)event {
    //{"name":"spark/status","data":"online","ttl":"60","published_at":"2016-07-13T06:20:07.300Z","coreid":"25002a001147353230333635"}
    //        {"name":"spark/flash/status","data":"started ","ttl":"60","published_at":"2016-07-13T06:30:47.130Z","coreid":"25002a001147353230333635"}
    //        {"name":"spark/flash/status","data":"success ","ttl":"60","published_at":"2016-07-13T06:30:47.702Z","coreid":"25002a001147353230333635"}
    //
    //        {"name":"spark/status/safe-mode", "data":"{\"f\":[],\"v\":{},\"p\":6,\"m\":[{\"s\":16384,\"l\":\"m\",\"vc\":30,\"vv\":30,\"f\":\"b\",\"n\":\"0\",\"v\":7,\"d\":[]},{\"s\":262144,\"l\":\"m\",\"vc\":30,\"vv\":30,\"f\":\"s\",\"n\":\"1\",\"v\":15,\"d\":[]},{\"s\":262144,\"l\":\"m\",\"vc\":30,\"vv\":30,\"f\":\"s\",\"n\":\"2\",\"v\":15,\"d\":[{\"f\":\"s\",\"n\":\"1\",\"v\":15,\"_\":\"\"}]},{\"s\":131072,\"l\":\"m\",\"vc\":30,\"vv\":26,\"u\":\"48ABD2D957D0B66069F0BCB04C8591BC8CA01FD1760F1BD47915B2C0D68070B5\",\"f\":\"u\",\"n\":\"1\",\"v\":4,\"d\":[{\"f\":\"s\",\"n\":\"2\",\"v\":17,\"_\":\"\"}]},{\"s\":131072,\"l\":\"f\",\"vc\":30,\"vv\":0,\"d\":[]}]}","ttl":"60","published_at":"2016-07-13T06:39:17.214Z","coreid":"25002a001147353230333635"}
    //        {"name":"spark/device/app-hash", "data":"48ABD2D957D0B66069F0BCB04C8591BC8CA01FD1760F1BD47915B2C0D68070B5","ttl":"60","published_at":"2016-07-13T06:39:17.215Z","coreid":"25002a001147353230333635"}
    //        {"name":"spark/status/safe-mode", "data":"{\"f\":[],\"v\":{},\"p\":6,\"m\":[{\"s\":16384,\"l\":\"m\",\"vc\":30,\"vv\":30,\"f\":\"b\",\"n\":\"0\",\"v\":7,\"d\":[]},{\"s\":262144,\"l\":\"m\",\"vc\":30,\"vv\":30,\"f\":\"s\",\"n\":\"1\",\"v\":15,\"d\":[]},{\"s\":262144,\"l\":\"m\",\"vc\":30,\"vv\":30,\"f\":\"s\",\"n\":\"2\",\"v\":15,\"d\":[{\"f\":\"s\",\"n\":\"1\",\"v\":15,\"_\":\"\"}]},{\"s\":131072,\"l\":\"m\",\"vc\":30,\"vv\":26,\"u\":\"48ABD2D957D0B66069F0BCB04C8591BC8CA01FD1760F1BD47915B2C0D68070B5\",\"f\":\"u\",\"n\":\"1\",\"v\":4,\"d\":[{\"f\":\"s\",\"n\":\"2\",\"v\":17,\"_\":\"\"}]},{\"s\":131072,\"l\":\"f\",\"vc\":30,\"vv\":0,\"d\":[]}]}","ttl":"60","published_at":"2016-07-13T06:39:17.113Z","coreid":"25002a001147353230333635"}
    //        {"name":"spark/safe-mode-updater/updating","data":"1","ttl":"60","published_at":"2016-07-13T06:39:19.467Z","coreid":"particle-internal"}
    //        {"name":"spark/safe-mode-updater/updating","data":"1","ttl":"60","published_at":"2016-07-13T06:39:19.560Z","coreid":"particle-internal"}
    //        {"name":"spark/flash/status","data":"started ","ttl":"60","published_at":"2016-07-13T06:39:21.581Z","coreid":"25002a001147353230333635"}
    
    
    if ([event.event isEqualToString:@"spark/status"]) {
        if ([event.data isEqualToString:@"online"]) {
            self.connected = YES;
            self.isFlashing = NO;
            if ([self.delegate respondsToSelector:@selector(particleDevice:didReceiveSystemEvent:)]) {
                [self.delegate particleDevice:self didReceiveSystemEvent:ParticleDeviceSystemEventCameOnline];
                
            }
        }
        
        if ([event.data isEqualToString:@"offline"]) {
            self.connected = NO;
            self.isFlashing = NO;
            if ([self.delegate respondsToSelector:@selector(particleDevice:didReceiveSystemEvent:)]) {
                [self.delegate particleDevice:self didReceiveSystemEvent:ParticleDeviceSystemEventWentOffline];
            }
        }
    }
    
    if ([event.event isEqualToString:@"spark/flash/status"]) {
        if ([event.data containsString:@"started"]) {
            self.isFlashing = YES;
            if ([self.delegate respondsToSelector:@selector(particleDevice:didReceiveSystemEvent:)]) {
                [self.delegate particleDevice:self didReceiveSystemEvent:ParticleDeviceSystemEventFlashStarted];
                
            }
        }
        
        if ([event.data containsString:@"success"]) {
            self.isFlashing = NO;
            if ([self.delegate respondsToSelector:@selector(particleDevice:didReceiveSystemEvent:)]) {
                [self.delegate particleDevice:self didReceiveSystemEvent:ParticleDeviceSystemEventFlashSucceeded];
            }
        }
    }
    
    
    if ([event.event isEqualToString:@"spark/device/app-hash"]) {
        self.appHash = event.data;
        self.isFlashing = NO;
        if ([self.delegate respondsToSelector:@selector(particleDevice:didReceiveSystemEvent:)]) {
            [self.delegate particleDevice:self didReceiveSystemEvent:ParticleDeviceSystemEventAppHashUpdated];
        }
    }
    
    
    if ([event.event isEqualToString:@"particle/status/safe-mode"]) {
        if ([self.delegate respondsToSelector:@selector(particleDevice:didReceiveSystemEvent:)]) {
            [self.delegate particleDevice:self didReceiveSystemEvent:ParticleDeviceSystemEventSafeModeUpdater];
        }
    }
    
    if ([event.event isEqualToString:@"spark/safe-mode-updater/updating"]) {
        if ([self.delegate respondsToSelector:@selector(particleDevice:didReceiveSystemEvent:)]) {
            [self.delegate particleDevice:self didReceiveSystemEvent:ParticleDeviceSystemEventSafeModeUpdater];
        }
    }
    
    
    
    
    
    
}


@end

NS_ASSUME_NONNULL_END
