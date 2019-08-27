//
//  RecordViewController.m
//  MyLiveStreamer
//
//  Created by GevinChen on 2019/8/27.
//  Copyright © 2017年 GevinChen. All rights reserved.
//

#import "RecordViewController.h"
#import <AVFoundation/AVFoundation.h>
#import "MyStreamer.h"
#import "MyLiveStreamer-Swift.h"
@class OpenGLESHandler;

@interface RecordViewController () <AVCaptureVideoDataOutputSampleBufferDelegate, AVCaptureAudioDataOutputSampleBufferDelegate>
@property (weak, nonatomic) IBOutlet UIButton *btnBack;
@property (weak, nonatomic) IBOutlet UIButton *btnPublish;
@property (weak, nonatomic) IBOutlet UIView *cameraView;
@property (weak, nonatomic) IBOutlet UIImageView *imageView;
@property (weak, nonatomic) IBOutlet UISwitch *filterSwitch;

@end

@implementation RecordViewController
{
    AVCaptureSession               *captureSession;
    AVCaptureDevice                *videoDevice;
    AVCaptureDevice                *audioDevice;
    // input device
    AVCaptureDeviceInput           *videoInputDevice;
    AVCaptureDeviceInput           *audioInputDevice;
    // ouput
    AVCaptureVideoDataOutput       *captureVideoDataOutput;
    AVCaptureConnection            *videoConnection;
    AVCaptureAudioDataOutput       *captureAudioDataOutput;
    AVCaptureConnection            *audioConnection;
    AVCaptureVideoPreviewLayer     *previewLayer;
    
    BOOL                            isRecording;
    VideoConfig                    *videoConfig;
    AudioConfig                    *audioConfig;
    MyStreamer                     *streamer;
    BOOL                            isVideoPortrait;
    CGSize                          captureVideoSize;
    
    OpenGLESHandler                *glHandler;
    BOOL                            enableFilter;
}

- (void)dealloc 
{
    NSLog(@"");
}

- (void)viewDidLoad {
    [super viewDidLoad];
    
    videoConfig = [[VideoConfig alloc] init];
    audioConfig = [[AudioConfig alloc] init];
    
#pragma mark -- set capture settings
    isVideoPortrait = YES;
    AVCaptureSessionPreset sessionPreset = AVCaptureSessionPreset640x480; //AVCaptureSessionPresetMedium; //AVCaptureSessionPreset1280x720;
    captureVideoSize = [self getVideoSize:sessionPreset isVideoPortrait:isVideoPortrait];
    
#pragma mark -- AVCaptureSession init
    captureSession = [[AVCaptureSession alloc] init];
    captureSession.sessionPreset = sessionPreset;

    NSError *error = nil;
    
    // capture device
    videoDevice = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeVideo];
    videoInputDevice = [AVCaptureDeviceInput deviceInputWithDevice:videoDevice error:&error];
    
    // mic
    audioDevice = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeAudio];
    audioInputDevice = [AVCaptureDeviceInput deviceInputWithDevice:audioDevice error:nil];
    
    dispatch_queue_t outputQueue = dispatch_queue_create("outputQueue", NULL);
    
    // output 
    captureVideoDataOutput = [[AVCaptureVideoDataOutput alloc] init];
    [captureVideoDataOutput setSampleBufferDelegate:self queue:outputQueue];

    captureAudioDataOutput = [[AVCaptureAudioDataOutput alloc] init];
    [captureAudioDataOutput setSampleBufferDelegate:self queue:outputQueue];
    
    BOOL supportsFullYUVRange = NO;
    NSArray *supportedPixelFormats = captureVideoDataOutput.availableVideoCVPixelFormatTypes;
    for (NSNumber *currentPixelFormat in supportedPixelFormats) {
        if ([currentPixelFormat intValue] == kCVPixelFormatType_420YpCbCr8BiPlanarFullRange) {
            supportsFullYUVRange = YES;
            videoConfig.supportsFullYUVRange = YES;
        }
    }
    
    // nv12 
    if (supportsFullYUVRange) {
        videoConfig.cameraOutputFormat = [NSNumber numberWithInt:kCVPixelFormatType_420YpCbCr8BiPlanarFullRange];
        captureVideoDataOutput.videoSettings = @{(__bridge_transfer NSString*)kCVPixelBufferPixelFormatTypeKey: [NSNumber numberWithInt:kCVPixelFormatType_420YpCbCr8BiPlanarFullRange]};
    } else {
        videoConfig.cameraOutputFormat = [NSNumber numberWithInt:kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange];
        captureVideoDataOutput.videoSettings = @{(__bridge_transfer NSString*)kCVPixelBufferPixelFormatTypeKey: [NSNumber numberWithInt:kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange]};
    }

    captureVideoDataOutput.alwaysDiscardsLateVideoFrames = YES;
 
    if([captureSession canAddInput:videoInputDevice]) {
        [captureSession addInput:videoInputDevice];
    } else {
        NSLog(@"Error: %@", error);
    }
    
    if ([captureSession canAddInput:audioInputDevice]) {
        [captureSession addInput:audioInputDevice];
    }
    
    if ([captureSession canAddOutput:captureVideoDataOutput]) {
        [captureSession addOutput:captureVideoDataOutput];
    }
    
    if([captureSession canAddOutput:captureAudioDataOutput]){
        [captureSession addOutput:captureAudioDataOutput];
    }
    
    videoConnection = [captureVideoDataOutput connectionWithMediaType:AVMediaTypeVideo];
    audioConnection = [captureAudioDataOutput connectionWithMediaType:AVMediaTypeAudio];
    
    if (isVideoPortrait) {
        videoConnection.videoOrientation = AVCaptureVideoOrientationPortrait;
    } else {
        videoConnection.videoOrientation = AVCaptureVideoOrientationLandscapeRight;
    }
    
    // setup glView
    [self setupGLHandler];
    
//    previewLayer = [AVCaptureVideoPreviewLayer layerWithSession:captureSession];
//    previewLayer.frame = self.view.layer.bounds;
//    previewLayer.videoGravity = AVLayerVideoGravityResizeAspectFill; // 设置预览时的视频缩放方式
//    [[previewLayer connection] setVideoOrientation:AVCaptureVideoOrientationPortrait]; // 设置视频的朝向
//    [self.cameraView.layer addSublayer:previewLayer];
    
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    
    
    [captureSession startRunning];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    
    [captureSession stopRunning];
}

- (void)didReceiveMemoryWarning 
{
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

#pragma mark - Setup

- (void)setupGLHandler {
    glHandler = [[OpenGLESHandler alloc] init];
    glHandler.glView = [[GLView alloc] initWithFrame:(CGRect){0,0,captureVideoSize}];
    [self.cameraView addSubview:glHandler.glView];
    glHandler.glView.bounds = self.cameraView.bounds;
    glHandler.glView.frame = self.cameraView.bounds;
    glHandler.glView.layer.transform = CATransform3DRotate(CATransform3DIdentity, M_PI, 1.0, 0.0, 0.0);
    NSLog(@"glView: %@", NSStringFromCGRect(glHandler.glView.frame));
    glHandler.glView.backgroundColor = [UIColor clearColor];//[UIColor colorWithRed:0.4620226622 green:0.8382837176 blue:1.0 alpha:0.2502140411];
    [glHandler setupGLWithFramebufferSize:captureVideoSize];
    
    self.filterSwitch.on = false;
    glHandler.enableFilter = self.filterSwitch.on;
}

#pragma mark - Action

- (IBAction)backButtonEvent:(id)sender {
    isRecording = NO;
    [streamer destroy];
    [glHandler.glView removeFromSuperview];
    [glHandler destoryFrameBuffer];
    
    if (captureSession) {
        [captureSession removeInput:audioInputDevice];
        [captureSession removeInput:videoInputDevice];
        [captureSession removeOutput:captureVideoDataOutput];
        [captureSession removeOutput:captureAudioDataOutput];
    }
    captureSession = nil;
    
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (IBAction)recordVideo:(UIButton *)button {
    button.selected = !button.selected;
    
    if (button.selected) {
        [self startPublishStreaming];
    } else {
        [self stopStreaming];
    }
}

- (IBAction)switchClicked:(id)sender {
    glHandler.enableFilter = self.filterSwitch.on;
}

- (void)startPublishStreaming {

    NSLog(@"recordVideo....");

    videoConfig.videoSize = captureVideoSize; // 隨 camera 設定的解晰度
    videoConfig.frameRate = 24;
    videoConfig.maxKeyframeInterval = 20;//60;
    videoConfig.bitrate = 481*1000;
    videoConfig.preset = @"slow";
    videoConfig.tune = @"zerolatency";
    
    audioConfig.sample_rate = 44100; // 44100
    audioConfig.bitrate = 6400; // 64000
    audioConfig.channel_layout = AV_CH_LAYOUT_MONO; // AV_CH_LAYOUT_MONO , AV_CH_LAYOUT_STEREO
    audioConfig.sample_fmt = AV_SAMPLE_FMT_S16; // AV_SAMPLE_FMT_FLTP AV_SAMPLE_FMT_FLT, AV_SAMPLE_FMT_S16 
    
    streamer = [[MyStreamer alloc] init];
    isRecording = [streamer setupEncoderVideoConfig:videoConfig audioConfig:audioConfig hostUrl:self.url];
    if (!isRecording) {
        streamer = nil;
    }

}

- (void)stopStreaming {
    isRecording = NO;
    
    [streamer destroy];
    streamer = nil;
}

- (CGSize)getVideoSize:(NSString *)sessionPreset isVideoPortrait:(BOOL)isVideoPortrait {
    CGSize size = CGSizeZero;
    if ([sessionPreset isEqualToString:AVCaptureSessionPresetMedium]) {
        if (isVideoPortrait)
            size = CGSizeMake(360, 480);
        else
            size = CGSizeMake(480, 360);
    } else if ([sessionPreset isEqualToString:AVCaptureSessionPreset1920x1080]) {
        if (isVideoPortrait)
            size = CGSizeMake(1080, 1920);
        else
            size = CGSizeMake(1920, 1080);
    } else if ([sessionPreset isEqualToString:AVCaptureSessionPreset1280x720]) {
        if (isVideoPortrait)
            size = CGSizeMake(720, 1280);
        else
            size = CGSizeMake(1280, 720);
    } else if ([sessionPreset isEqualToString:AVCaptureSessionPreset640x480]) {
        if (isVideoPortrait)
            size = CGSizeMake(480, 640);
        else
            size = CGSizeMake(640, 480);
    }
    
    return size;
}

#pragma mark --  AVCaptureVideo(Audio)DataOutputSampleBufferDelegate method
    
- (void)captureOutput:(AVCaptureOutput *)captureOutput didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer fromConnection:(AVCaptureConnection *)connection {
    
    if (connection == videoConnection) {
        [glHandler processingVideoSampleBufferWithSampleBuffer:sampleBuffer isFullYUVRange:YES];
    }
    
    if (isRecording) {
        if (connection == videoConnection) {
            CMTime ptsTime = CMSampleBufferGetOutputPresentationTimeStamp(sampleBuffer);
            CGFloat pts = CMTimeGetSeconds(ptsTime);
            if (glHandler.enableFilter) {
                CVPixelBufferRef processedBuffer = [glHandler getPixellatePixelBuffer];
                [streamer encodingVideo:processedBuffer timestamp:pts];
            } else {
                CVPixelBufferRef pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer);
                [streamer encodingVideo:pixelBuffer timestamp:pts];
            }
            //  UIImage *image = [glHandler getBufferImage];
            //  __weak typeof(self) weakSelf = self;
            //  dispatch_async(dispatch_get_main_queue(), ^{
            //      weakSelf.imageView.image = image;
            //  });
        } else if (connection == audioConnection) {
            CMTime ptsTime = CMSampleBufferGetOutputPresentationTimeStamp(sampleBuffer);
            CGFloat pts = CMTimeGetSeconds(ptsTime);
            [streamer encodingAudio:sampleBuffer timestamp:pts];
        }
    }
}

@end