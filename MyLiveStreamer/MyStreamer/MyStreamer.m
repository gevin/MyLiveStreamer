//
//  MyStreamer.m
//  MyLiveStreamer
//
//  Created by GevinChen on 2019/8/27.
//  Copyright © 2019年 GevinChen. All rights reserved.
//

#import "MyStreamer.h"
#include <libyuv.h>
#include <libavutil/opt.h>
#include <libavcodec/avcodec.h>
#include <libavformat/avformat.h>
#include <libswscale/swscale.h>

@interface MyStreamer ()

@end

static BOOL s_hasInitCodec = NO;

@implementation MyStreamer
{
    NSString                 *hostUrl;
    AVFormatContext          *pFormatContext; //

    VideoEncoder             *videoEncoder;
    AudioEncoder             *audioEncoder;
    
}

- (void)dealloc {
    NSLog(@"MyStreamer ... dealloc");
}

- (instancetype)init {
    self = [super init];
    if (self) {
        audioEncoder = [[AudioEncoder alloc] init];
        videoEncoder = [[VideoEncoder alloc] init];
    }
    return self;
}
    
- (BOOL)setupEncoderVideoConfig:(VideoConfig*)videoConfig audioConfig:(AudioConfig*)audioConfig hostUrl:(NSString*)hostUrl
{
    if(!s_hasInitCodec)
    {
        s_hasInitCodec = YES;
        // 注册FFmpeg所有编解码器
        av_register_all();
        // init Network
        avformat_network_init();
    }
    
    //output initialize
    char host_url[500] = {0};
    sprintf(host_url,"%s",[hostUrl UTF8String]);
    avformat_alloc_output_context2(&pFormatContext, NULL, "flv", host_url);
    
    if (!pFormatContext)
    {
        printf("Can not find host\n");
        return NO;
    }
    
    BOOL success = [videoEncoder setupVideoEncoderWithFormatContext:pFormatContext config:videoConfig];
    if(!success)
    {
        return NO;
    }
    
    success = [audioEncoder setupAudioEncoderWithFormatContext:pFormatContext config:audioConfig];
    if(!success) 
    {
        return NO;
    }
    
    //Open output URL
    if (avio_open(&pFormatContext->pb, host_url, AVIO_FLAG_READ_WRITE) < 0)
    {
        printf("Failed to open output file! \n");
        return NO;
    }
    
    //Write File Header
    int ret = avformat_write_header(pFormatContext, NULL);
    if (ret < 0) 
    {
        printf( "Error occurred when opening output URL, %d %s!!\n", ret, av_err2str(ret));
        return NO;
    }
    
    return YES;
}

- (void)encodingVideo:(CVImageBufferRef)pixelBuffer timestamp:(CGFloat)timestamp 
{
    [videoEncoder encodingVideo:pixelBuffer timestamp:timestamp];
}
    
- (void)encodingAudio:(CMSampleBufferRef)sampleBuffer timestamp:(CGFloat)timestamp 
{
    [audioEncoder encodingAudio:sampleBuffer timestamp:timestamp];
}

- (void)destroy 
{
    if(pFormatContext)
    {
        // 寫入結尾
        int ret = av_write_trailer(pFormatContext);
        if(ret < 0)
        {
            printf("write trailer error %d %s!!\n", ret, av_err2str(ret));
        }
        avio_flush(pFormatContext->pb);
        avio_close(pFormatContext->pb);
        avformat_free_context(pFormatContext);
        [videoEncoder destroy];
        [audioEncoder destroy];
        videoEncoder = nil;
        audioEncoder = nil;
        pFormatContext = NULL;
    }
}

@end
