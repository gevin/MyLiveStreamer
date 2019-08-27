//
//  AudioEncoder.h
//  MyLiveStreamer
//
//  Created by GevinChen on 2019/8/27.
//  Copyright © 2019 GevinChen. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
#include <libyuv.h>
#include <libavutil/opt.h>
#include <libavcodec/avcodec.h>
#include <libavformat/avformat.h>
#include <libswscale/swscale.h>
#import "AudioConfig.h"

NS_ASSUME_NONNULL_BEGIN

@interface AudioEncoder : NSObject

- (BOOL)setupAudioEncoderWithFormatContext:(AVFormatContext*)fmtContext config:(AudioConfig*)config;

- (void)encodingAudio:(CMSampleBufferRef)sampleBuffer timestamp:(CGFloat)timestamp; 

- (void)destroy;

@end

NS_ASSUME_NONNULL_END
