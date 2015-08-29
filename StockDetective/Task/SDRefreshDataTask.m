//
//  SDRefreshDataTask.m
//  StockDetective
//
//  Created by GoKu on 7/25/15.
//  Copyright (c) 2015 GoKuStudio. All rights reserved.
//

#import "AFNetworking.h"
#import "SDRefreshDataTask.h"
#import "SDStockInfo.h"
#import "SDUtilities.h"
#import "LogFormatter.h"

static NSString * const kQueryDaPanRealtimeFormatURL = @"http://s1.dfcfw.com/allXML/index.xml";
static NSString * const kQueryDaPanHistoryFormatURL = @"http://s1.dfcfw.com/History/index.xml";

static NSString * const kQueryRealtimeFormatURL = @"http://s1.dfcfw.com/allXML/%@.xml";
static NSString * const kQueryHistoryFormatURL = @"http://data.eastmoney.com/zjlx/graph/his_%@.html";

@interface SDRefreshDataTask ()

@property (nonatomic, strong) NSDate *refreshDataTaskStartDate;

@property (nonatomic, strong) AFURLSessionManager *sessionManagerToRefreshData;

@end

@implementation SDRefreshDataTask

- (instancetype)init
{
    self = [super init];
    if (self) {
        _refreshDataTaskStartDate = [NSDate distantPast];
    }
    return self;
}

- (void)refreshDataTask:(TaskType)taskType
              stockCode:(NSString *)stockCode
         successHandler:(void (^)(NSData *data))successHandler
         failureHandler:(void (^)(NSError *error))failureHandler
{
    if (self.taskManager) {
        NSURL *url;

        switch (taskType) {
            case TaskTypeRealtime:
            {
                if ([stockCode isEqualToString:kSDStockDaPanFullCode]) {
                    url = [NSURL URLWithString:kQueryDaPanRealtimeFormatURL];
                } else {
                    url = [NSURL URLWithString:[NSString stringWithFormat:kQueryRealtimeFormatURL, stockCode]];
                }
                break;
            }
            case TaskTypeHistory:
            {
                if ([stockCode isEqualToString:kSDStockDaPanFullCode]) {
                    url = [NSURL URLWithString:kQueryDaPanHistoryFormatURL];
                } else {
                    url = [NSURL URLWithString:[NSString stringWithFormat:kQueryHistoryFormatURL, stockCode]];
                }
                break;
            }
            default:
                break;
        }

        self.refreshDataTaskStartDate = [NSDate date];

        [self fetchDataOfURL:url
              successHandler:^(NSData *data) {
                  // if manager has already refreshed by another newer task (by network factor), ignore this old task.
                  if (!self.taskManager.lastRefreshedByDataTaskStartDate ||
                      ([self.taskManager.lastRefreshedByDataTaskStartDate compare:self.refreshDataTaskStartDate] == NSOrderedAscending)) {

                      self.taskManager.lastRefreshedByDataTaskStartDate = self.refreshDataTaskStartDate;
                      if (successHandler) {
                          successHandler(data);
                      }
                      DDLogDebug(@"data refreshed");

                  } else {
                      DDLogDebug(@"ignore old task");
                  }
              }
              failureHandler:^(NSError *error) {
                  if (failureHandler) {
                      failureHandler(error);
                  }
              }];
    }
}

- (void)fetchDataOfURL:(NSURL *)url
        successHandler:(void (^)(NSData *data))successHandler
        failureHandler:(void (^)(NSError *error))failureHandler
{
    if (!url) {
        return;
    }

    if (![SDUtilities isStockMarketOnBusiness]) {
        NSData *refreshData = [SDUtilities loadCachedRefreshDataForURL:url.absoluteString];
        if (refreshData) {
            DDLogDebug(@"using cached refresh data");
            successHandler(refreshData);

            return;
        }
    }

    NSURLSessionConfiguration *configuration = [NSURLSessionConfiguration defaultSessionConfiguration];
    configuration.requestCachePolicy = NSURLRequestReloadIgnoringCacheData;

    if (!self.sessionManagerToRefreshData) {
        self.sessionManagerToRefreshData = [[AFURLSessionManager alloc] initWithSessionConfiguration:configuration];
        self.sessionManagerToRefreshData.completionQueue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0);
        self.sessionManagerToRefreshData.responseSerializer = [AFHTTPResponseSerializer serializer]; // non json
    }

    NSURLRequest *request = [NSURLRequest requestWithURL:url];

    NSURLSessionDataTask *dataTask = [self.sessionManagerToRefreshData dataTaskWithRequest:request
                                                                         completionHandler:^(NSURLResponse *response, id responseObject, NSError *error) {
                                                                             if (error) {
                                                                                 failureHandler(error);

                                                                             } else {
                                                                                 NSData *data = (NSData *)responseObject;

                                                                                 [SDUtilities cacheRefreshData:([SDUtilities isStockMarketOnBusiness] ? nil : data)
                                                                                                        forURL:url.absoluteString];

                                                                                 successHandler(data);
                                                                             }
                                                                         }];
    [dataTask resume];
}

@end
