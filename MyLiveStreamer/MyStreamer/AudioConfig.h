//
//  AudioConfig.h
//  MyLiveStreamer
//
//  Created by GevinChen on 2019/8/27.
//  Copyright © 2019 GevinChen. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface AudioConfig : NSObject

@property (nonatomic) int sample_rate; // 44100
@property (nonatomic) int64_t bitrate; // 64000
@property (nonatomic) uint64_t channel_layout; // AV_CH_LAYOUT_MONO , AV_CH_LAYOUT_STEREO
@property (nonatomic) int sample_fmt; // (AVSampleFormat) AV_SAMPLE_FMT_FLTP AV_SAMPLE_FMT_FLT, AV_SAMPLE_FMT_S16 

@end
