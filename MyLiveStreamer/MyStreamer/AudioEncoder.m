//
//  AudioEncoder.m
//  MyLiveStreamer
//
//  Created by GevinChen on 2019/8/27.
//  Copyright © 2019 GevinChen. All rights reserved.
//

#import "AudioEncoder.h"

@implementation AudioEncoder
{
    AVFormatContext          *pFormatContext; //
    AVStream                 *pAudioStream;
    AVCodecContext           *pAudioCodecCtx;
    AVCodec                  *pAudioCodec;
    //AVPacket                  audioPacket;
    AVPacket                 *pAudioPacket;
    AVFrame                  *pAudioFrame;
    size_t                    pcmBufferSize;
    int                       audioFrameCounter;
    char                     *pcmBuffer;
    AVBitStreamFilterContext *aacbsfc;  
    AudioConfig              *audioConfig;
}

- (void)dealloc {
    NSLog(@"AudioEncoder ... dealloc");
}

- (BOOL)setupAudioEncoderWithFormatContext:(AVFormatContext*)fmtContext config:(AudioConfig*)config {
    
    pFormatContext = fmtContext;
    audioConfig = config;
    
    // output encoder initialize
    // pAudioCodec = avcodec_find_encoder(AV_CODEC_ID_AAC);
    pAudioCodec = avcodec_find_encoder_by_name("libfdk_aac");
    if (!pAudioCodec)
    {
        printf("Can not find audio encoder!\n");
        return NO;
    }
    
    printf("aac codec support fmt: %d\n",pAudioCodec->sample_fmts[0]);
    // 1 設定 codec
    pAudioCodecCtx = avcodec_alloc_context3(pAudioCodec);
    pAudioCodecCtx->codec_type      = AVMEDIA_TYPE_AUDIO;
    pAudioCodecCtx->sample_fmt      = config.sample_fmt; //AV_SAMPLE_FMT_S16; // AV_SAMPLE_FMT_FLTP AV_SAMPLE_FMT_FLT, AV_SAMPLE_FMT_S16
    pAudioCodecCtx->sample_rate     = config.sample_rate; // 44100;
    pAudioCodecCtx->channel_layout  = config.channel_layout; // AV_CH_LAYOUT_MONO // AV_CH_LAYOUT_STEREO, AV_CH_LAYOUT_MONO;, select_channel_layout(pAudioCodec)
    pAudioCodecCtx->channels        = av_get_channel_layout_nb_channels(pAudioCodecCtx->channel_layout);
    pAudioCodecCtx->bit_rate        = config.bitrate; // 64000;
    
    /* open it */
    if (avcodec_open2(pAudioCodecCtx, pAudioCodec, NULL) < 0)
    {
        printf("can not open auido encoder!\n");
        return -1;
    }
    
    pAudioStream = avformat_new_stream(pFormatContext, pAudioCodec);
    pAudioStream->codec = pAudioCodecCtx;
    
    pAudioFrame = av_frame_alloc();
    pAudioFrame->nb_samples     = pAudioCodecCtx->frame_size;
    pAudioFrame->format         = pAudioCodecCtx->sample_fmt;
    pAudioFrame->channel_layout = pAudioCodecCtx->channel_layout; 
    pAudioFrame->channels       = pAudioCodecCtx->channels;
    pAudioFrame->sample_rate    = pAudioCodecCtx->sample_rate;
    
    pcmBufferSize = av_samples_get_buffer_size(NULL, pAudioCodecCtx->channels, pAudioFrame->nb_samples, pAudioFrame->format, 1);
    pcmBuffer = (char *)av_malloc(pcmBufferSize);
    avcodec_fill_audio_frame(pAudioFrame, pAudioCodecCtx->channels, pAudioCodecCtx->sample_fmt, (unsigned char *)pcmBuffer, (int)pcmBufferSize, 1);
    pAudioPacket = av_packet_alloc();
    av_new_packet(pAudioPacket, (int)pcmBufferSize);
    
    // aac bit stream filter
    aacbsfc = av_bitstream_filter_init("aac_adtstoasc");
    
    return YES;
}

- (void)encodingAudio:(CMSampleBufferRef)sampleBuffer timestamp:(CGFloat)timestamp 
{
    
    CMBlockBufferRef blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer);
    CFRetain(blockBuffer);
    
    OSStatus status = CMBlockBufferGetDataPointer(blockBuffer, 0, NULL, &pcmBufferSize, &pcmBuffer);
    NSError *error = nil;
    if (status != kCMBlockBufferNoErr) {
        error = [NSError errorWithDomain:NSOSStatusErrorDomain code:status userInfo:nil];
        NSLog(@"%@", error);
        CFRelease(blockBuffer);
        return;
    }
    int ret = 0;
    
    pAudioFrame->data[0] = (unsigned char *)pcmBuffer;
    // #Gevin_Note: 這個是雷神大大原始碼裡加的，但如果是推 mic 收到的 pcm data，加這個會讓接收端的聲音出問題，不知道原因
    //pAudioFrame->pts = audioFrameCounter * 100;
    
    int got_frame = 0;
    
    ret = avcodec_encode_audio2(pAudioCodecCtx, pAudioPacket, pAudioFrame, &got_frame);
    
    if (ret < 0) {
        fprintf(stderr, "Error during audio encoding! ret:%d\n", ret);
        CFRelease(blockBuffer);
        return;
    }
    
    if (got_frame == 1) {  
        av_bitstream_filter_filter(aacbsfc, pAudioStream->codec, NULL, &pAudioPacket->data, &pAudioPacket->size, pAudioPacket->data, pAudioPacket->size, 0);  
        printf("success to encode audio frame!\tsize:%5d\n", pAudioPacket->size);
        pAudioPacket->stream_index = pAudioStream->index;
        ret = av_interleaved_write_frame(pFormatContext, pAudioPacket);
    }
    
    CFRelease(blockBuffer);
}

- (void)destroy {
    
    av_frame_free(&pAudioFrame);
    av_packet_free(&pAudioPacket);
}

@end
