//
//  ViewController.m
//  MyLiveStreamer
//
//  Created by GevinChen on 19/8/27.
//  Copyright (c) 2019年 GevinChen. All rights reserved.
//

#import "ViewController.h"
#import "RecordViewController.h"

@interface ViewController () <UITextFieldDelegate>
@property (weak, nonatomic) IBOutlet UITextField *textPublishUrl;
@property (weak, nonatomic) IBOutlet UIButton *btnStart;

@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view, typically from a nib.
    self.textPublishUrl.delegate = self;
    self.textPublishUrl.text = @"rtmp://172.20.10.2/live/test";
}

- (BOOL)textFieldShouldReturn:(UITextField *)textField{
    [textField resignFirstResponder];
    return YES;
}

- (IBAction)pressRecordButton:(id)sender {
    if(self.textPublishUrl.text.length==0){
        UIAlertView *alertView = [[UIAlertView alloc] initWithTitle:@"" message:@"url is empty!" delegate:nil cancelButtonTitle:@"OK" otherButtonTitles: nil];
        [alertView show];
        return;
    }
    RecordViewController *recordViewController = [[RecordViewController alloc] init];
    recordViewController.url = self.textPublishUrl.text;
    [self presentViewController:recordViewController animated:YES completion:nil];
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

@end
