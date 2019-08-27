//
//  VideoEncoder.m
//  MyLiveStreamer
//
//  Created by GevinChen on 2019/8/27.
//  Copyright © 2019 GevinChen. All rights reserved.
//

#import "VideoEncoder.h"

@implementation VideoEncoder
{
    AVFormatContext         *pFormatContext;
    AVStream                *pVideoStream;
    AVCodecContext          *pVideoCodecCtx;
    AVCodec                 *pVideoCodec;
    AVPacket                *pVideoPacket;
    AVFrame                 *pVideoFrame;
    int                      pictureSize;
    int                      frameCounter;
    CGSize                   videoSize;
    
    VideoConfig         *streamingConfig;
}

- (void)dealloc {
    NSLog(@"VideoEncoder ... dealloc");
}

- (BOOL)setupVideoEncoderWithFormatContext:(AVFormatContext*)fmtContext config:(VideoConfig*)config
{
    pFormatContext = fmtContext;
    streamingConfig = config;
    
    // output encoder initialize
    pVideoCodec = avcodec_find_encoder(AV_CODEC_ID_H264);
    if (!pVideoCodec)
    {
        printf("Can not find encoder!\n");
        return NO;
    }
    
    frameCounter = 0;
    videoSize = streamingConfig.videoSize;
    // Param that must set
    pVideoCodecCtx = avcodec_alloc_context3(pVideoCodec);
    pVideoCodecCtx->codec_type = AVMEDIA_TYPE_VIDEO;
    pVideoCodecCtx->pix_fmt = AV_PIX_FMT_YUV420P;
    pVideoCodecCtx->width = videoSize.width;
    pVideoCodecCtx->height = videoSize.height;
    pVideoCodecCtx->time_base.num = 1;
    pVideoCodecCtx->time_base.den = streamingConfig.frameRate; // 24
    // 各解晰度建議的 bitrate
    // https://videochat-scripts.com/recommended-h264-video-bitrate-based-on-resolution/
    pVideoCodecCtx->bit_rate = streamingConfig.bitrate; // 481*1000 影響圖像壓縮品質
    pVideoCodecCtx->gop_size = streamingConfig.maxKeyframeInterval; // 20 幾個 frame 做為一個壓縮群組
    pVideoCodecCtx->qmin = 10;
    pVideoCodecCtx->qmax = 51;
    //    pVideoCodecCtx->me_range = 16;
    //    pVideoCodecCtx->max_qdiff = 4;
    //    pVideoCodecCtx->qcompress = 0.6;
    // Optional Param
    //    pVideoCodecCtx->max_b_frames = 3;
    
    // Set Option
    AVDictionary *param = NULL;
    if(pVideoCodecCtx->codec_id == AV_CODEC_ID_H264)
    {
        if (streamingConfig.preset != nil) { 
            // preset https://trac.ffmpeg.org/wiki/Encode/H.264
            // ultrafast, superfast, veryfast, faster, fast, medium, slow, slower, veryslow and placebo. 
            av_dict_set(&param, "preset", [streamingConfig.preset UTF8String], 0); // slow 編碼速度，編碼越快，意味著信息遺失越嚴重，輸出圖像品質越差。
        }
        if (streamingConfig.tune != nil) {
            // film, animation, grain, stillimage, fastdecode, zerolatency, psnr, ssim
            av_dict_set(&param, "tune", [streamingConfig.tune UTF8String], 0); // zerolatency
        }
        if (streamingConfig.profile != nil) {
            // baseline < main < high
            av_dict_set(&param, "profile", [streamingConfig.profile UTF8String], 0); // baseline
        }
        if (streamingConfig.level != nil) {
            av_dict_set(&param, "level", [streamingConfig.level UTF8String], 0); // 3.1
        }
    }
    
    if (avcodec_open2(pVideoCodecCtx, pVideoCodec, &param) < 0)
    {
        NSLog(@"Failed to open encoder!");
        return NO;
    }
    
    pVideoStream = avformat_new_stream(pFormatContext, pVideoCodec);
    pVideoStream->time_base.num = 1;
    pVideoStream->time_base.den = streamingConfig.frameRate;
    pVideoStream->codec = pVideoCodecCtx;
    
    pVideoFrame = av_frame_alloc();
    pVideoFrame->width = videoSize.width;
    pVideoFrame->height = videoSize.height;
    pVideoFrame->format = AV_PIX_FMT_YUV420P;
    
    avpicture_fill((AVPicture *)pVideoFrame, NULL, pVideoCodecCtx->pix_fmt, pVideoCodecCtx->width, pVideoCodecCtx->height);
    pictureSize = avpicture_get_size(pVideoCodecCtx->pix_fmt, pVideoCodecCtx->width, pVideoCodecCtx->height);
    pVideoPacket = av_packet_alloc();
    int ret = av_new_packet(pVideoPacket, pictureSize);
    if(ret<0) {
        NSLog(@"** Failed to create packet! %d, %s", ret, av_err2str(ret));
    }
    return YES;
}

- (void)encodingVideo:(CVImageBufferRef)pixelBuffer timestamp:(CGFloat)timestamp 
{
    
    CVPixelBufferLockBaseAddress(pixelBuffer, 0);
    
    UInt8 *pYUV420P; // buffer to store YUV with layout YYYYYYYYUUVV
    
    int pixelFormat = CVPixelBufferGetPixelFormatType(pixelBuffer);
    switch (pixelFormat) 
    {
        case kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange:
            //            NSLog(@"pixel format NV12");
            //            break;
        case kCVPixelFormatType_420YpCbCr8BiPlanarFullRange:
        {
            /* convert NV12 data to YUV420*/
            size_t width = CVPixelBufferGetWidth(pixelBuffer);
            size_t height = CVPixelBufferGetHeight(pixelBuffer);
            // y plane
            UInt8 *pY_src = (UInt8 *)CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 0);
            // uv plane
            UInt8 *pUV_src = (UInt8 *)CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 1);
            //y stride
            size_t planeY_stride = CVPixelBufferGetBytesPerRowOfPlane (pixelBuffer, 0);
            //uv stride
            size_t planeUV_stride = CVPixelBufferGetBytesPerRowOfPlane (pixelBuffer, 1);
            //y_size
            size_t planeY_size = planeY_stride * CVPixelBufferGetHeightOfPlane(pixelBuffer, 0);
            //uv_size
            size_t planeUV_size = CVPixelBufferGetBytesPerRowOfPlane (pixelBuffer, 1) * CVPixelBufferGetHeightOfPlane(pixelBuffer, 1);
            
            // buffer to store YUV with layout YYYYYYYYUUVV
            pYUV420P = (UInt8 *)malloc(width * height * 3 / 2);
            UInt8 *pU_dst = pYUV420P + (width * height);
            UInt8 *pV_dst = pU_dst + (width * height / 4);
            NV12ToI420(pY_src, planeY_stride, pUV_src, planeUV_stride, pYUV420P, planeY_stride, pU_dst, planeUV_stride/2, pV_dst, planeUV_stride/2, width, height);
            
            //Read raw YUV data
            pVideoFrame->data[0] = pYUV420P;                                     // Y
            pVideoFrame->data[1] = pVideoFrame->data[0] + width * height;        // U
            pVideoFrame->data[2] = pVideoFrame->data[1] + (width * height) / 4;  // V
            
            break;
        }
        case kCVPixelFormatType_32BGRA:
        {
            // #Gevin_Note: 
            //  在實作這邊時，遇到個問題就是我設定 h264 編碼的 frame size 是 480 * 640
            //  但我執行 filter 時，opengles 的 framebuffer 是 375 * 667
            //  最後從 framebuffer 拿出來的 image size 就是 375 * 667
            //  再拿來做轉換，顯示上就會出錯
            //  所以要注意兩邊 size 有沒有一致
            int width = CVPixelBufferGetWidth(pixelBuffer);
            int height = CVPixelBufferGetHeight(pixelBuffer);
            size_t bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer); // 通常會 padding 至 16 的倍數，為了增加記憶體處理的效率
            
            int half_width = (width + 1) / 2;
            int half_height = (height + 1) / 2;
            
            const int y_size = width * height;
            const int uv_size = half_width * half_height * 2 ;
            const size_t total_size = y_size + uv_size;
            
            pYUV420P = calloc(1,total_size);
            uint8_t* pU_dst = pYUV420P + y_size;
            uint8_t* pV_dst = pYUV420P + y_size + y_size/4;
            
            uint8_t *srcAddress = CVPixelBufferGetBaseAddress(pixelBuffer);
            
            ARGBToI420(srcAddress,
                       width * 4,
                       pYUV420P,
                       half_width * 2,
                       pU_dst,
                       half_width,
                       pV_dst,
                       half_width,
                       width, height);
            
            //Read raw YUV data
            pVideoFrame->data[0] = pYUV420P;  // Y
            pVideoFrame->data[1] = pU_dst;        // U
            pVideoFrame->data[2] = pV_dst;        // V
            
            break;
        }
        default:
            NSLog(@"pixel format unknown");
            break;
    }
    
    // PTS
    pVideoFrame->pts = frameCounter;
    
    // Encode
    pVideoFrame->width = videoSize.width;
    pVideoFrame->height = videoSize.height;
    pVideoFrame->format = AV_PIX_FMT_YUV420P;
    int got_frame = 0;
    if (!pVideoCodecCtx) 
    {
        CVPixelBufferUnlockBaseAddress(pixelBuffer, 0);
        free(pYUV420P);
        return;
    }
    // 轉成 h264
    int ret = avcodec_encode_video2(pVideoCodecCtx, pVideoPacket, pVideoFrame, &got_frame);
    if(ret < 0)
    {
        NSLog(@"** Failed to encode video frame! %d, %s", ret, av_err2str(ret));
    }
    
    if (got_frame == 1) 
    {
        //----------------------
        pVideoPacket->stream_index = pVideoStream->index;
        
        //Write PTS
        AVRational time_base = pVideoStream->time_base;//{ 1, 1000 }; // 最小的時間單位
        AVRational r_framerate1 = { 60, 2 }; // 每秒幾個 frame, AVRational 在 ffmpeg 裡，都代表 param1 / param2 得到的值
        AVRational time_base_q = { 1, AV_TIME_BASE }; // ffmpeg 裡的最小時間單位
        //Duration between 2 frames (us)
        // fps * ffmpeg 最小時間單位 = ffmpeg 裡的 fps 單位
        int64_t calc_duration   = (double)(AV_TIME_BASE)*(1 / av_q2d(r_framerate1));  //内部時間戳
        pVideoPacket->pts       = av_rescale_q(frameCounter*calc_duration, time_base_q, time_base);
        pVideoPacket->dts       = pVideoPacket->pts;
        pVideoPacket->duration  = av_rescale_q(calc_duration, time_base_q, time_base); //(double)(calc_duration)*(double)(av_q2d(time_base_q)) / (double)(av_q2d(time_base));
        pVideoPacket->pos       = -1;
        //printf("packet pts:%lld , dts:%lld , duration:%lld\n", packet.pts,packet.dts, (int)packet.duration);
        //----------------------
        NSLog(@"Succeed to encode frame: %5d\tsize:%5d", frameCounter, pVideoPacket->size);
        frameCounter++;
        //  送出一個封包
        ret = av_interleaved_write_frame(pFormatContext, pVideoPacket);
        if(ret < 0)
        {
            printf("** write frame error %d %s!!\n", ret, av_err2str(ret));
        }
        
    }
    
    free(pYUV420P);
    
    CVPixelBufferUnlockBaseAddress(pixelBuffer, 0);
}

- (void)destroy {
    
    av_frame_free(&pVideoFrame);
    av_packet_free(&pVideoPacket);
}

@end
