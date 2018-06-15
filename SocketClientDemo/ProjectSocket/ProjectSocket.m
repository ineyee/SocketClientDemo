//
//  ProjectSocket.m
//  SocketClientDemo
//
//  Created by 意一yiyi on 2018/5/8.
//  Copyright © 2018年 意一yiyi. All rights reserved.
//

#import "ProjectSocket.h"
#import "GCDAsyncSocket.h"// 基于TCP协议

#define kServerIPAddress @"192.168.0.133"
#define kServerPort 8080

#define kHeartBeatTime 60 * 3// 心跳间隔

@interface ProjectSocket ()<GCDAsyncSocketDelegate>

@property (strong, nonatomic) GCDAsyncSocket *clientSocket;// 客户端socket

@property (assign, nonatomic) BOOL isConnected;// 客户端socket已连接服务端socket

@property (strong, nonatomic) NSDictionary *currentPacketHead;// 包头

@property (strong, nonatomic) NSTimer *heartBeatTimer;// 心跳保活定时器
@property (assign, nonatomic) NSTimeInterval reconnectTime;// 重连时间

@end

@implementation ProjectSocket

static ProjectSocket *pSocket = nil;
+ (instancetype)sharedSocket {
    
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        
        pSocket = [[ProjectSocket alloc] init];
        
        pSocket.isConnected = NO;
        pSocket.reconnectTime = 0.0;
    });
    
    return pSocket;
}


#pragma mark - public methods

// 连接到服务端socket
- (void)connect {
    
    [self initClientSocket];
}

// 断开与服务端socket的连接
- (void)disconnect {
    
    [self.clientSocket disconnect];
}

// 向服务端socket写数据
- (void)sendData:(NSString *)data {
    
    NSData *sendData = [data dataUsingEncoding:NSUTF8StringEncoding];
    [self.clientSocket writeData:sendData withTimeout:-1 tag:0];// tag：消息标记
}

// 发送数据前给每条数据添加一个包头
- (void)sendData:(NSData *)data msgType:(NSString *)type {
    
    NSInteger dataSize = data.length;
    
    // 包头
    NSMutableDictionary *headDict = [@{} mutableCopy];
    [headDict setObject:type forKey:@"type"];// 消息的类型，比如说文本消息、图片消息、语音消息、视频消息等
    [headDict setObject:[NSString stringWithFormat:@"%ld", dataSize] forKey:@"size"];// 消息体的大小
    // 包头转化成jsonStr
    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:headDict options:NSJSONWritingPrettyPrinted error:nil];
    NSString *jsonStr = [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
    // 包头转化为data
    NSData *tempData = [jsonStr dataUsingEncoding:NSUTF8StringEncoding];
    
    NSMutableData *sendData = [NSMutableData dataWithData:tempData];
    // 分界，拼接“\r\n”两个字符在包头后面，用来标志包头的结束
    [sendData appendData:[GCDAsyncSocket CRLFData]];
    
    // 包头后面拼接上原数据
    [sendData appendData:data];
    
    [self.clientSocket writeData:sendData withTimeout:-1 tag:0];// tag：消息标记
}


#pragma mark - private methods

// 读取服务端socket的数据
- (void)receiveData {
    
//    [self.clientSocket readDataWithTimeout:-1 tag:0];
    [self.clientSocket readDataToData:[GCDAsyncSocket CRLFData] withTimeout:-1 tag:0];
}


#pragma mark - GCDAsyncSocketDelegate

// 客户端socket连接服务端socket成功的回调
- (void)socket:(GCDAsyncSocket *)sock didConnectToHost:(NSString *)host port:(uint16_t)port {
    
    NSLog(@"===========>连接服务端成功\n");
    
    self.isConnected = YES;
    
    // 由于CocoaAsyncSocket支持排队读写，所以我们在连接成功后，立马读取来自服务端的数据，所有读/写操作将排队，并且在socket连接时，操作将按顺序出列和处理
    [self receiveData];

    // 心跳写在这：连接成功后添加心跳，保证socket一直处于活跃状态
    [self addHeartBeat];
    // 重新开始一次正常连接的时候，要清零重连时间
    self.reconnectTime = 0;
}

// 客户端socket读取服务端socket数据成功后的回调
- (void)socket:(GCDAsyncSocket *)sock didReadData:(NSData *)data withTag:(long)tag {
    
    // 先读取到当前数据包头部信息
    if (self.currentPacketHead == nil) {
        
        self.currentPacketHead = [NSJSONSerialization JSONObjectWithData:data options:NSJSONReadingMutableContainers error:nil];
        
        if (self.currentPacketHead == nil) {
            
            NSLog(@"===========>数据格式出错了：包头数据为空");
            return;
        }
        
        // 获取包头中真正数据的长度
        NSInteger packetLength = [self.currentPacketHead[@"size"] integerValue];
        // 读取指定长度的真正数据
        [sock readDataToLength:packetLength withTimeout:-1 tag:0];
        
        return;
    }
    
    // 正式的包处理
    NSInteger packetLength = [self.currentPacketHead[@"size"] integerValue];
    // 说明数据有问题
    if (packetLength <= 0 || data.length != packetLength) {
        
        NSLog(@"===========>数据格式出错了：数据包数据大小不正确");
        return;
    }
    
    NSString *type = self.currentPacketHead[@"type"];
    
    if ([type isEqualToString:@"img"]) {
        
        NSLog(@"===========>收到了图片消息");
    }else{
        
        NSLog(@"===========>收到了文字消息：%@", [[NSString alloc]initWithData:data encoding:NSUTF8StringEncoding]);
    }
    
    self.currentPacketHead = nil;
    
    // 注意：我们在读取到数据后，需要在这里再次调用[self.clientSocket readDataWithTimeout:-1 tag:0];方法来读取数据，框架本身就是这么设计的，否则我们就只能接收一次数据，之后再也接收不到数据
    [self receiveData];
}

// 客户端socket与服务端socket断开连接的回调
- (void)socketDidDisconnect:(GCDAsyncSocket *)sock withError:(NSError *)err {
    
    NSLog(@"%@", [NSString stringWithFormat:@"===========>与服务端断开连接：%@\n", err]);
    
    // sokect断开连接时，需要清空代理和客户端本身的socket
    self.clientSocket.delegate = nil;
    self.clientSocket = nil;
    self.isConnected = NO;
    
    // 断开连接时，移除心跳保活
    [self removeHeartBeat];
    
    // 如果是被用户自己中断的那么直接断开连接，否则启用断线重连
    if (err == nil) {

        [self disconnect];
    }else {

        [self reconnect];
    }
}


#pragma mark - 初始化客户端socket

// 初始化客户端socket
- (void)initClientSocket {
    
    if (!self.isConnected) {// 客户端socket未连接服务端socket的情况下，才创建客户端socket，并发起向服务端socket的连接请求
        
        [self createClientSocket];
        [self connectToServerSocket];
    }
}

// 创建客户端socket
- (void)createClientSocket {
    
    // 创建客户端socket，并指定代理对象为self，代理队列必须为主队列
    self.clientSocket = [[GCDAsyncSocket alloc] initWithDelegate:self delegateQueue:dispatch_get_main_queue()];
}

// 连接到服务端socket
- (void)connectToServerSocket {
    
    NSError *error = nil;
    
    // 向指定IP地址和端口号的服务端socket发起连接请求，注意是IP地址而不是DNS名称，可以设定连接的超时时间，如果不想设置超时时间可设置为负数
    // 如果检测到错误，此方法将返回NO，并设置错误指针(可能的错误是无主机，无效接口或套接字已连接)
    // 如果未检测到错误，则此方法将启动后台连接操作并立即返回YES。但这里未检测到错误不一定是连接成功了，也有可能是主机无法访问，主机无法访问的时候也会返回YES的，所以连接成功与否是要看下面的回调的
    self.isConnected = [self.clientSocket connectToHost:kServerIPAddress onPort:kServerPort viaInterface:nil withTimeout:-1 error:&error];
    
    if(!self.isConnected) {
        
        self.isConnected = NO;
        NSLog(@"%@", [NSString stringWithFormat:@"===========>连接服务端失败：%@\n", error]);
    }
}


#pragma mark - 心跳保活

// 添加心跳
- (void)addHeartBeat {
    
    [self removeHeartBeat];
    
    // 心跳时间设置为3分钟，NAT超时一般为3~5分钟
    self.heartBeatTimer = [NSTimer scheduledTimerWithTimeInterval:kHeartBeatTime repeats:YES block:^(NSTimer * _Nonnull timer) {
        
        // 和服务端约定好发送什么作为心跳标识，尽可能的减小心跳包的大小
        [self sendData:@"HeartBeat===我是海燕"];
    }];
    [[NSRunLoop currentRunLoop]addTimer:self.heartBeatTimer forMode:NSRunLoopCommonModes];
}

// 取消心跳
- (void)removeHeartBeat {
    
    [self.heartBeatTimer invalidate];
    self.heartBeatTimer = nil;
}


#pragma mark - 断线重连

// 断线重连
- (void)reconnect {
    
    [self disconnect];
    
    // 重连时间以2的指数级增长，比如说检测到socket连接断开后，就立刻进行第一次重连，如果第一次重连没连成功，则2秒后进行第二次重连，以次类推，再隔4秒后进行第三次重连，再隔8秒后进行第四次重连......一共进行6次重连，总耗时62秒钟，直到大于62秒后就不再重连，认为服务端出了问题。而任意的一次重连成功，都会重置这个重连时间。
    if (self.reconnectTime > 62) {// 已经经过6次重连了
        
        NSLog(@"==================>服务端出问题了，重连不上啊");
        return;
    }
    
    NSLog(@"==================>reconnectTime：%f", self.reconnectTime);
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(self.reconnectTime * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        
        [self initClientSocket];
    });
    
    // 重连时间以2指数级增长
    if (self.reconnectTime == 0) {
        
        self.reconnectTime = 2;
    }else {
        
        self.reconnectTime *= 2;
    }
}

@end
