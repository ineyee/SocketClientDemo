//
//  ViewController.m
//  SocketClientDemo
//
//  Created by 意一yiyi on 2018/3/26.
//  Copyright © 2018年 意一yiyi. All rights reserved.
//

#import "ViewController.h"
#import "ProjectSocket.h"

@interface ViewController ()

@property (weak, nonatomic) IBOutlet UITextField *tf;

@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    
}

- (IBAction)connect:(id)sender {
    
    [[ProjectSocket sharedSocket] connect];
}

- (IBAction)disconnect:(id)sender {
    
    [[ProjectSocket sharedSocket] disconnect];
}

- (IBAction)send:(id)sender {
    
    [[ProjectSocket sharedSocket] sendData:self.tf.text];
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

@end
