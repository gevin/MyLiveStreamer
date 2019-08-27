//
//  MyStreamer.h
//  MyLiveStreamer
//
//  Created by GevinChen on 2019/8/27.
//  Copyright © 2019年 GevinChen. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
#import "VideoConfig.h"
#import "VideoEncoder.h"
#import "AudioEncoder.h"

@interface MyStreamer : NSObject 

// return YES init success, NO init fail
- (BOOL)setupEncoderVideoConfig:(VideoConfig*)videoConfig audioConfig:(AudioConfig*)audioConfig hostUrl:(NSString*)hostUrl;
- (void)encodingVideo:(CVImageBufferRef)sampleBuffer timestamp:(CGFloat)timestamp;
- (void)encodingAudio:(CMSampleBufferRef)sampleBuffer timestamp:(CGFloat)timestamp;
- (void)destroy;

@end
