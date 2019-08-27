//
//  VideoConfig.h
//  MyLiveStreamer
//
//  Created by GevinChen on 2019/8/27.
//  Copyright © 2019 GevinChen. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

@interface VideoConfig: NSObject

@property (assign, nonatomic) CGSize videoSize;
@property (assign, nonatomic) CGFloat frameRate;
@property (assign, nonatomic) CGFloat maxKeyframeInterval;
@property (assign, nonatomic) CGFloat bitrate;
@property (strong, nonatomic) NSString *preset;
@property (strong, nonatomic) NSString *profile;
@property (strong, nonatomic) NSString *level;
@property (strong, nonatomic) NSString *tune;
@property (strong, nonatomic) NSNumber *cameraOutputFormat; // kCVPixelFormatType_420YpCbCr8BiPlanarFullRange, kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
@property (nonatomic) BOOL supportsFullYUVRange;
//@property (strong) NSString *host_url;

@end


