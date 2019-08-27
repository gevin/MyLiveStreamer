//
//  X264Manager.m
//  FFmpeg_X264_Codec
//
//  Created by sunminmin on 15/9/7.
//  Copyright (c) 2015年 suntongmian@163.com. All rights reserved.
//

#import "X264Manager.h"

#ifdef __cplusplus
extern "C" {
#endif
    
#include <libavutil/opt.h>
#include <libavcodec/avcodec.h>
#include <libavformat/avformat.h>
#include <libswscale/swscale.h>

#ifdef __cplusplus
};
#endif


@implementation X264Manager
{
    AVFormatContext                     *outFormatContext;
    AVOutputFormat                      *outFormat; // 似乎沒用到
    AVStream                            *video_stream;
    AVCodecContext                      *pCodecCtx;
    AVCodec                             *pCodec;
    AVPacket                             pkt;
    uint8_t                             *picture_buf;
    AVFrame                             *pFrame;
    int                                  picture_size;
    int                                  y_size;
    int                                  framecnt;
    char                                *out_file;
    
    int                                  encoder_h264_frame_width; // 编码的图像宽度
    int                                  encoder_h264_frame_height; // 编码的图像高度
}



/*
 * 设置编码后文件的文件名，保存路径
 */
- (void)setFileSavedPath:(NSString *)path;
{
    out_file = [self nsstring2char:path];
}

- (char*)nsstring2char:(NSString *)path
{

    NSUInteger len = [path length];
    char *filepath = (char*)malloc(sizeof(char) * (len + 1));
    
    [path getCString:filepath maxLength:len + 1 encoding:[NSString defaultCStringEncoding]];
    
    return filepath;
}


/*
 *  设置X264
 */
- (int)setX264Resource
{
    framecnt = 0;
    
    // AVCaptureSessionPresetMedium
    encoder_h264_frame_width = 480;
    encoder_h264_frame_height = 360;

    // AVCaptureSessionPresetHigh
//    encoder_h264_frame_width = 1920;
//    encoder_h264_frame_height = 1080;
    
    av_register_all(); // 注册FFmpeg所有编解码器
    //Network
    avformat_network_init();
    
    /*
    //Method1.
    outFormatContext = avformat_alloc_context();
    //Guess Format
    outFormat = av_guess_format(NULL, out_file, NULL);
    if( !outFormat ){
        outFormat = av_guess_format("h264", NULL, NULL);
    }
    outFormatContext->oformat = outFormat;
    */
    
    // Method2.
//     avformat_alloc_output_context2(&pFormatCtx, NULL, NULL, out_file);
    // fmt = pFormatCtx->oformat;
    //output initialize
    avformat_alloc_output_context2(&outFormatContext, NULL, "flv", out_file);
    
    //output encoder initialize
    pCodec = avcodec_find_encoder(AV_CODEC_ID_H264);
    if (!pCodec){
        printf("Can not find encoder! (没有找到合适的编码器！)\n");
        return NO;
    }
    
    // Param that must set
    pCodecCtx = avcodec_alloc_context3(pCodec);//video_stream->codec;
//    pCodecCtx->codec_id = outFormat->video_codec;
    pCodecCtx->codec_type = AVMEDIA_TYPE_VIDEO;
    pCodecCtx->pix_fmt = AV_PIX_FMT_YUV420P;
    pCodecCtx->width = 480;//encoder_h264_frame_width;
    pCodecCtx->height = 360;//encoder_h264_frame_height;
    pCodecCtx->time_base.num = 1;
    pCodecCtx->time_base.den = 25;
    /*  
     ffmpeg项目对视频进行编码时，可手动设置码率，通过设置 AVCodecContext->bit_rate进行赋值。码率单位是kbs
     对于手机直播，分辨率尽量不超过352*288，即保持200kbs以下的码率;对于pc平台则500kbs就行了。 
     context->bit_rate = bit_rate*1000;//bit_rate为整数，传入500则为500kbs，传入200为200kbs；所以乘以1000,方便查看而已。
     注意事项：
     bit_rate不能设置过大，超过1024kbs很容易花屏，这与I帧\B帧间隔设置有一定关系，本人了解不深。
     */
    pCodecCtx->bit_rate = 481 * 1000; // 400kbs
    pCodecCtx->gop_size = 15;//250; // 幾個 frame 做為一個壓縮群組
    
    // H264
    // pCodecCtx->me_range = 16;
    // pCodecCtx->max_qdiff = 4;
    // pCodecCtx->qcompress = 0.6;
    pCodecCtx->qmin = 10;
    pCodecCtx->qmax = 51;
    
    // Optional Param
    pCodecCtx->max_b_frames=3;
    
//    pCodecCtx->rc_max_rate = (int)((96000 * 1.2) / 1000);
//    pCodecCtx->rc_buffer_size = icodec->rc_buffer_size;
    
    /*
     481 kb/s, 24 fps, 24 tbr, 12288 tbn, 48 tbc
     tbn = the time base in AVStream that has come from the container
     tbc = the time base in AVCodecContext for the codec used for a particular stream
     tbr = tbr is guessed from the video stream and is the value users want to see when they look for the video frame rate
     25   tbr代表帧率；
     90k tbn代表文件层（st）的时间精度，即1S=1200k，和duration相关；
     50   tbc代表视频层（st->codec）的时间精度，即1S=50，和strem->duration和时间戳相关。
    */

    // Set Option
    AVDictionary *param = 0;
    
    // H.264
    if(pCodecCtx->codec_id == AV_CODEC_ID_H264) {
        av_dict_set(&param, "preset", "slow", 0);
        av_dict_set(&param, "tune", "zerolatency", 0);
        // av_dict_set(&param, "profile", "main", 0);
    }
    
    // Show some Information
    av_dump_format(outFormatContext, 0, out_file, 1);

    if (avcodec_open2(pCodecCtx, pCodec,&param) < 0) {
        
        printf("Failed to open encoder! \n");
        return -1;
    }
    
    video_stream = avformat_new_stream(outFormatContext, pCodec);
    video_stream->time_base.num = 1;
    video_stream->time_base.den = 25;
    video_stream->codec = pCodecCtx;
    
    if (video_stream==NULL){
        return -1;
    }
    
    //Dump Format------------------
    av_dump_format(outFormatContext, 0, out_file, 1);
    
    //Open output URL , out_file 如果是 rtmp 網址，就是直接廣播
    if (avio_open(&outFormatContext->pb, out_file, AVIO_FLAG_READ_WRITE) < 0){
        printf("Failed to open output file! \n");
        return -1;
    }
    
    pFrame = av_frame_alloc();
//    picture_size = avpicture_get_size(pCodecCtx->pix_fmt, pCodecCtx->width, pCodecCtx->height);
//    picture_buf = (uint8_t *)av_malloc(picture_size);
    avpicture_fill((AVPicture *)pFrame, picture_buf, pCodecCtx->pix_fmt, pCodecCtx->width, pCodecCtx->height);
    
    //Write File Header
    avformat_write_header(outFormatContext, NULL);
    
    av_new_packet(&pkt, picture_size);
    
    y_size = pCodecCtx->width * pCodecCtx->height;
    
    //  設定 start_time_realtime
    AVRational timeBase = video_stream->time_base;
    NSTimeInterval currentTime = [[NSDate date] timeIntervalSince1970];
    printf("realtime:%f\n", currentTime );
    int64_t time = currentTime * timeBase.den / timeBase.num;
    printf("realtime lld:%lld\n", time );
    outFormatContext->start_time_realtime = time;
    
    return 0;
}



/*
 * 将CMSampleBufferRef格式的数据编码成h264并写入文件
 * 
 */
- (void)encoderToH264:(CMSampleBufferRef)sampleBuffer
{
    CVPixelBufferRef imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer);
    
    if (CVPixelBufferLockBaseAddress(imageBuffer, 0) == kCVReturnSuccess) {
        
//        int pixelFormat = CVPixelBufferGetPixelFormatType(imageBuffer);
//        switch (pixelFormat) {
//            case kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange:
//                NSLog(@"Capture pixel format=NV12");
//                break;
//            case kCVPixelFormatType_422YpCbCr8:
//                NSLog(@"Capture pixel format=UYUY422");
//                break;
//            default:
//                NSLog(@"Capture pixel format=RGB32");
//                break;
//        }
        
        UInt8 *bufferbasePtr = (UInt8 *)CVPixelBufferGetBaseAddress(imageBuffer);
        UInt8 *bufferPtr = (UInt8 *)CVPixelBufferGetBaseAddressOfPlane(imageBuffer,0);
        UInt8 *bufferPtr1 = (UInt8 *)CVPixelBufferGetBaseAddressOfPlane(imageBuffer,1);
        size_t buffeSize = CVPixelBufferGetDataSize(imageBuffer);
        size_t width = CVPixelBufferGetWidth(imageBuffer);
        size_t height = CVPixelBufferGetHeight(imageBuffer);
        size_t bytesPerRow = CVPixelBufferGetBytesPerRow(imageBuffer);
        size_t bytesrow0 = CVPixelBufferGetBytesPerRowOfPlane(imageBuffer,0);
        size_t bytesrow1  = CVPixelBufferGetBytesPerRowOfPlane(imageBuffer,1);
        size_t bytesrow2 = CVPixelBufferGetBytesPerRowOfPlane(imageBuffer,2);
        UInt8 *yuv420_data = (UInt8 *)malloc(width * height *3/ 2); // buffer to store YUV with layout YYYYYYYYUUVV
        
        /* convert NV12 data to YUV420*/
        UInt8 *pY = bufferPtr ;
        UInt8 *pUV = bufferPtr1;
        UInt8 *pU = yuv420_data + width*height;
        UInt8 *pV = pU + width*height/4;
        for(int i =0;i<height;i++){
            memcpy(yuv420_data+i*width,pY+i*bytesrow0,width);
        }
        for(int j = 0;j<height/2;j++){
            for(int i =0;i<width/2;i++){
                *(pU++) = pUV[i<<1];
                *(pV++) = pUV[(i<<1) + 1];
            }
            pUV+=bytesrow1;
        }

        
        // add code to push yuv420_data to video encoder here
        
        // scale
        // add code to scale image here
        // ...
        
        //Read raw YUV data
        picture_buf = yuv420_data;
        pFrame->data[0] = picture_buf;              // Y
        pFrame->data[1] = picture_buf+ y_size;      // U
        pFrame->data[2] = picture_buf+ y_size*5/4;  // V
        
        // PTS
        pFrame->pts = framecnt;

        int got_picture = 0;
        
        // Encode
        pFrame->width = encoder_h264_frame_width;
        pFrame->height = encoder_h264_frame_height;
        pFrame->format = AV_PIX_FMT_YUV420P;
        
        int ret = avcodec_encode_video2(pCodecCtx, &pkt, pFrame, &got_picture);
        if(ret < 0) {
            printf("Failed to encode! \n");
        }
        
        if (got_picture==1) {
            
            pkt.stream_index = video_stream->index;
            
            //----------------------
            //Write PTS
            AVRational time_base = video_stream->time_base;//{ 1, 1000 }; // 最小的時間單位
            AVRational r_framerate1 = { 50, 2 }; // 每秒幾個 frame
            AVRational time_base_q = { 1, AV_TIME_BASE }; // ffmpeg 裡的最小時間單位
            //Duration between 2 frames (us)
            // fps * ffmpeg 最小時間單位 = ffmpeg 裡的 fps 單位
            int64_t calc_duration = (double)(AV_TIME_BASE)*(1 / av_q2d(r_framerate1));  //内部時間戳
            //Parameters
            //enc_pkt.pts = (double)(framecnt*calc_duration)*(double)(av_q2d(time_base_q)) / (double)(av_q2d(time_base));
            pkt.pts = av_rescale_q(framecnt*calc_duration, time_base_q, time_base);
            pkt.dts = pkt.pts;
            pkt.duration = av_rescale_q(calc_duration, time_base_q, time_base); //(double)(calc_duration)*(double)(av_q2d(time_base_q)) / (double)(av_q2d(time_base));
            pkt.pos = -1;
            
            //----------------------
            printf("Succeed to encode frame: %5d\tsize:%5d pts:%lld\n", framecnt, pkt.size, pkt.pts );
            framecnt++;
            //  送出一個封包
//            ret = av_write_frame(outFormatContext, &pkt);
//            av_free_packet(&pkt);
            ret = av_interleaved_write_frame(outFormatContext, &pkt);
            av_packet_unref(&pkt);
        }

        free(yuv420_data);
    }
    
    CVPixelBufferUnlockBaseAddress(imageBuffer, 0);
}



/*
 * 释放资源
 */
- (void)freeX264Resource
{
    //Flush Encoder
    int ret = flush_encoder(outFormatContext,0);
    if (ret < 0) {
        
        printf("Flushing encoder failed\n");
    }
    
    //Write file trailer
    av_write_trailer(outFormatContext);
    
    //Clean
    if (video_stream){
        avcodec_close(video_stream->codec);
        av_free(pFrame);
//        av_free(picture_buf);
    }
    avio_close(outFormatContext->pb);
    avformat_free_context(outFormatContext);
}


@end
