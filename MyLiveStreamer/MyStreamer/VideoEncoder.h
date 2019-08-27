//
//  VideoEncoder.h
//  MyLiveStreamer
//
//  Created by GevinChen on 2019/8/27.
//  Copyright © 2019 GevinChen. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>
#import <UIKit/UIKit.h>
#include <libyuv.h>
#include <libavutil/opt.h>
#include <libavcodec/avcodec.h>
#include <libavformat/avformat.h>
#include <libswscale/swscale.h>
#import "VideoConfig.h"

NS_ASSUME_NONNULL_BEGIN

@interface VideoEncoder : NSObject

- (BOOL)setupVideoEncoderWithFormatContext:(AVFormatContext*)fmtContext config:(VideoConfig*)config;

- (void)encodingVideo:(CVImageBufferRef)pixelBuffer timestamp:(CGFloat)timestamp; 

- (void)destroy;

@end

NS_ASSUME_NONNULL_END
