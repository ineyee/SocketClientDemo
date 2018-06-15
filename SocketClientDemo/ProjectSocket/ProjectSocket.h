//
//  ProjectSocket.h
//  SocketClientDemo
//
//  Created by 意一yiyi on 2018/5/8.
//  Copyright © 2018年 意一yiyi. All rights reserved.
//

#import <Foundation/Foundation.h>

typedef NS_ENUM(NSUInteger, DisconnectType) {
    
    DisconnectTypeByClient = 0,// 客户端断开连接
    DisconnectTypeByServer = 1,// 服务端断开连接
};

@interface ProjectSocket : NSObject

+ (instancetype)sharedSocket;

- (void)connect;
- (void)disconnect;

- (void)sendData:(NSString *)data;

@end
