//
//  ZFAVPlayerManager.m
//  ZFPlayer
//
// Copyright (c) 2016年 任子丰 ( http://github.com/renzifeng )
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
// THE SOFTWARE.

#import "ZFAVPlayerManager.h"
#import <UIKit/UIKit.h>
#if __has_include(<ZFPlayer/ZFPlayer.h>)
#import <ZFPlayer/ZFKVOController.h>
#import <ZFPlayer/ZFPlayerConst.h>
#import <ZFPlayer/ZFReachabilityManager.h>
#else
#import "ZFKVOController.h"
#import "ZFPlayerConst.h"
#import "ZFReachabilityManager.h"
#endif


#pragma clang diagnostic push
#pragma clang diagnostic ignored"-Wdeprecated-declarations"

/*!
 *  Refresh interval for timed observations of AVPlayer
 */
static NSString *const kStatus                   = @"status";
static NSString *const kLoadedTimeRanges         = @"loadedTimeRanges";
static NSString *const kPlaybackBufferEmpty      = @"playbackBufferEmpty";
static NSString *const kPlaybackLikelyToKeepUp   = @"playbackLikelyToKeepUp";
static NSString *const kPresentationSize         = @"presentationSize";

@interface ZFPlayerPresentView : UIView

//@property (nonatomic, strong) AVPlayer *player;
/// default is AVLayerVideoGravityResizeAspect.
@property (nonatomic, strong) AVLayerVideoGravity videoGravity;

@end

@implementation ZFPlayerPresentView

+ (Class)layerClass {
    return [AVPlayerLayer class];
}

- (AVPlayerLayer *)avLayer {
    return (AVPlayerLayer *)self.layer;
}
//
//- (void)setPlayer:(AVPlayer *)player {
//    if (player == _player) return;
//    self.avLayer.player = player;
//}
//
//- (void)setVideoGravity:(AVLayerVideoGravity)videoGravity {
//    if (videoGravity == self.videoGravity) return;
//    [self avLayer].videoGravity = videoGravity;
//}
//
//- (AVLayerVideoGravity)videoGravity {
//    return [self avLayer].videoGravity;
//}

@end

@interface ZFAVPlayerManager ()<AVPDelegate> {
    id _timeObserver;
    id _itemEndObserver;
    //ZFKVOController *_playerItemKVO;
}
@property (nonatomic, strong) AVPlayerLayer *playerLayer;
@property (nonatomic, assign) BOOL isBuffering;
@property (nonatomic, assign) BOOL isReadyToPlay;
@property (nonatomic, strong) AVAssetImageGenerator *imageGenerator;
@property (nonatomic, copy) void(^seekComplete)(BOOL);

@end

@implementation ZFAVPlayerManager

@synthesize view                           = _view;
@synthesize currentTime                    = _currentTime;
@synthesize totalTime                      = _totalTime;
@synthesize playerPlayTimeChanged          = _playerPlayTimeChanged;
@synthesize playerBufferTimeChanged        = _playerBufferTimeChanged;
@synthesize playerDidToEnd                 = _playerDidToEnd;
@synthesize bufferTime                     = _bufferTime;
@synthesize playState                      = _playState;
@synthesize loadState                      = _loadState;
@synthesize assetURL                       = _assetURL;
@synthesize playerPrepareToPlay            = _playerPrepareToPlay;
@synthesize playerReadyToPlay              = _playerReadyToPlay;
@synthesize playerPlayStateChanged         = _playerPlayStateChanged;
@synthesize playerLoadStateChanged         = _playerLoadStateChanged;
@synthesize seekTime                       = _seekTime;
@synthesize muted                          = _muted;
@synthesize volume                         = _volume;
@synthesize presentationSize               = _presentationSize;
@synthesize isPlaying                      = _isPlaying;
@synthesize rate                           = _rate;
@synthesize isPreparedToPlay               = _isPreparedToPlay;
@synthesize shouldAutoPlay                 = _shouldAutoPlay;
@synthesize scalingMode                    = _scalingMode;
@synthesize playerPlayFailed               = _playerPlayFailed;
@synthesize presentationSizeChanged        = _presentationSizeChanged;

- (instancetype)init {
    self = [super init];
    if (self) {
        _scalingMode = ZFPlayerScalingModeAspectFit;
        _shouldAutoPlay = YES;
    }
    return self;
}

- (void)prepareToPlay {
    if (!_assetURL) return;
    _isPreparedToPlay = YES;
    [self initializePlayer];
    if (self.shouldAutoPlay) {
        [self play];
    }
    self.loadState = ZFPlayerLoadStatePrepare;
    [self.player prepare];
    if (self.playerPrepareToPlay) self.playerPrepareToPlay(self, self.assetURL);
}

- (void)reloadPlayer {
    self.seekTime = self.currentTime;
    [self prepareToPlay];
}

- (void)play {
    if (!_isPreparedToPlay) {
        [self prepareToPlay];
    } else {
        [self.player start];
        self.player.rate = self.rate;
        self->_isPlaying = YES;
        self.playState = ZFPlayerPlayStatePlaying;
    }
}

- (void)pause {
    [self.player pause];
    self->_isPlaying = NO;
    self.playState = ZFPlayerPlayStatePaused;
    //[_playerItem cancelPendingSeeks];
    [_asset cancelLoading];
}

- (void)stop {
    //[_playerItemKVO safelyRemoveAllObservers];
    self.loadState = ZFPlayerLoadStateUnknown;
    self.playState = ZFPlayerPlayStatePlayStopped;
    if (self.player.rate != 0) [self.player pause];
    //[_playerItem cancelPendingSeeks];
    [_asset cancelLoading];
//    [self.player removeTimeObserver:_timeObserver];
//    [self.player replaceCurrentItemWithPlayerItem:nil];
    self.presentationSize = CGSizeZero;
    _timeObserver = nil;
//    [[NSNotificationCenter defaultCenter] removeObserver:_itemEndObserver name:AVPlayerItemDidPlayToEndTimeNotification object:self.playerItem];
    _itemEndObserver = nil;
    _isPlaying = NO;
    _player = nil;
    _assetURL = nil;
    //_playerItem = nil;
    _isPreparedToPlay = NO;
    self->_currentTime = 0;
    self->_totalTime = 0;
    self->_bufferTime = 0;
    self.isReadyToPlay = NO;
}

- (void)replay {
    @zf_weakify(self)
    [self seekToTime:0 completionHandler:^(BOOL finished) {
        @zf_strongify(self)
        if (finished) {
            [self play];
        }
    }];
}

- (void)seekToTime:(NSTimeInterval)time completionHandler:(void (^ __nullable)(BOOL finished))completionHandler {
    if (self.totalTime > 0) {
//        [_player.currentItem cancelPendingSeeks];
//        int32_t timeScale = _player.currentItem.asset.duration.timescale;
//        CMTime seekTime = CMTimeMakeWithSeconds(time, timeScale);
        //[_player seekToTime:seekTime toleranceBefore:kCMTimeZero toleranceAfter:kCMTimeZero completionHandler:completionHandler];
        [_player seekToTime:time * 1000.f seekMode:AVP_SEEKMODE_ACCURATE];
        _seekComplete = completionHandler;
//        if (completionHandler) {
//            completionHandler(YES);
//        }
    } else {
        self.seekTime = time;
    }
}

- (UIImage *)thumbnailImageAtCurrentTime {
    CMTime expectedTime = CMTimeMakeWithSeconds(self.currentTime,1000000);
    CGImageRef cgImage = NULL;
    
    self.imageGenerator.requestedTimeToleranceBefore = kCMTimeZero;
    self.imageGenerator.requestedTimeToleranceAfter = kCMTimeZero;
    cgImage = [self.imageGenerator copyCGImageAtTime:expectedTime actualTime:NULL error:NULL];

    if (!cgImage) {
        self.imageGenerator.requestedTimeToleranceBefore = kCMTimePositiveInfinity;
        self.imageGenerator.requestedTimeToleranceAfter = kCMTimePositiveInfinity;
        cgImage = [self.imageGenerator copyCGImageAtTime:expectedTime actualTime:NULL error:NULL];
    }
    
    UIImage *image = [UIImage imageWithCGImage:cgImage];
    return image;
}

- (void)thumbnailImageAtCurrentTime:(void(^)(UIImage *))handler {
    //CMTime expectedTime = self.playerItem.currentTime;
    CMTime expectedTime = CMTimeMakeWithSeconds(self.currentTime,1000000);
    [self.imageGenerator generateCGImagesAsynchronouslyForTimes:@[[NSValue valueWithCMTime:expectedTime]] completionHandler:^(CMTime requestedTime, CGImageRef  _Nullable image, CMTime actualTime, AVAssetImageGeneratorResult result, NSError * _Nullable error) {
        if (handler) {
            UIImage *finalImage = [UIImage imageWithCGImage:image];
            handler(finalImage);
        }
    }];
}

#pragma mark - private method

/// Calculate buffer progress
- (NSTimeInterval)availableDuration {
    return self.totalTime;
//    NSArray *timeRangeArray = _playerItem.loadedTimeRanges;
//    CMTime currentTime = [_player currentTime];
//    BOOL foundRange = NO;
//    CMTimeRange aTimeRange = {0};
//    if (timeRangeArray.count) {
//        aTimeRange = [[timeRangeArray objectAtIndex:0] CMTimeRangeValue];
//        if (CMTimeRangeContainsTime(aTimeRange, currentTime)) {
//            foundRange = YES;
//        }
//    }
//
//    if (foundRange) {
//        CMTime maxTime = CMTimeRangeGetEnd(aTimeRange);
//        NSTimeInterval playableDuration = CMTimeGetSeconds(maxTime);
//        if (playableDuration > 0) {
//            return playableDuration;
//        }
//    }
//    return 0;
}

- (void)initializePlayer {
    _asset = [AVURLAsset URLAssetWithURL:self.assetURL options:self.requestHeader];
    AVPUrlSource *assetSource = [[AVPUrlSource alloc] urlWithString:self.assetURL.absoluteString];
    _player = [[AliPlayer alloc] init];
    _player.scalingMode = AVP_SCALINGMODE_SCALEASPECTFIT;
    _player.rate = 1;
    AVPConfig *config = [self.player getConfig];
    config.networkTimeout = 1000;
    [self.player setConfig:config];
    _player.delegate = self;
    [_player setUrlSource:assetSource];

    _imageGenerator = [AVAssetImageGenerator assetImageGeneratorWithAsset:_asset];

    //[self enableAudioTracks:YES inPlayerItem:_playerItem];
    
    ZFPlayerPresentView *presentView = [[ZFPlayerPresentView alloc] init];
    //presentView.player = (AVPlayer *)[self.player getPlayer];
    self.view.playerView = presentView;
    _player.playerView = presentView;

    self.scalingMode = _scalingMode;
//    if (@available(iOS 9.0, *)) {
//        _playerItem.canUseNetworkResourcesForLiveStreamingWhilePaused = NO;
//    }
//    if (@available(iOS 10.0, *)) {
//        _playerItem.preferredForwardBufferDuration = 5;
//        /// 关闭AVPlayer默认的缓冲延迟播放策略，提高首屏播放速度
//        //_player.automaticallyWaitsToMinimizeStalling = NO;
//    }
//    [self itemObserving];
}

/// Playback speed switching method
//- (void)enableAudioTracks:(BOOL)enable inPlayerItem:(AVPlayerItem*)playerItem {
//    for (AVPlayerItemTrack *track in playerItem.tracks){
//        if ([track.assetTrack.mediaType isEqual:AVMediaTypeVideo]) {
//            track.enabled = enable;
//        }
//    }
//}

/**
 *  缓冲较差时候回调这里
 */
- (void)bufferingSomeSecond {
    // playbackBufferEmpty会反复进入，因此在bufferingOneSecond延时播放执行完之前再调用bufferingSomeSecond都忽略
    if (self.isBuffering || self.playState == ZFPlayerPlayStatePlayStopped) return;
    /// 没有网络
    if ([ZFReachabilityManager sharedManager].networkReachabilityStatus == ZFReachabilityStatusNotReachable) return;
    self.isBuffering = YES;
    
    // 需要先暂停一小会之后再播放，否则网络状况不好的时候时间在走，声音播放不出来
    [self pause];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        // 如果此时用户已经暂停了，则不再需要开启播放了
        if (!self.isPlaying && self.loadState == ZFPlayerLoadStateStalled) {
            self.isBuffering = NO;
            return;
        }
        [self play];
        // 如果执行了play还是没有播放则说明还没有缓存好，则再次缓存一段时间
        self.isBuffering = NO;
        //if (!self.playerItem.isPlaybackLikelyToKeepUp) [self bufferingSomeSecond];
    });
}

- (void)itemObserving {
//    [_playerItemKVO safelyRemoveAllObservers];
//    _playerItemKVO = [[ZFKVOController alloc] initWithTarget:_playerItem];
//    [_playerItemKVO safelyAddObserver:self
//                           forKeyPath:kStatus
//                              options:NSKeyValueObservingOptionNew
//                              context:nil];
//    [_playerItemKVO safelyAddObserver:self
//                           forKeyPath:kPlaybackBufferEmpty
//                              options:NSKeyValueObservingOptionNew
//                              context:nil];
//    [_playerItemKVO safelyAddObserver:self
//                           forKeyPath:kPlaybackLikelyToKeepUp
//                              options:NSKeyValueObservingOptionNew
//                              context:nil];
//    [_playerItemKVO safelyAddObserver:self
//                           forKeyPath:kLoadedTimeRanges
//                              options:NSKeyValueObservingOptionNew
//                              context:nil];
//    [_playerItemKVO safelyAddObserver:self
//                           forKeyPath:kPresentationSize
//                              options:NSKeyValueObservingOptionNew
//                              context:nil];
    
//    CMTime interval = CMTimeMakeWithSeconds(self.timeRefreshInterval > 0 ? self.timeRefreshInterval : 0.1, NSEC_PER_SEC);
//    @zf_weakify(self)
//    _timeObserver = [self.player addPeriodicTimeObserverForInterval:interval queue:dispatch_get_main_queue() usingBlock:^(CMTime time) {
//        @zf_strongify(self)
//        if (!self) return;
//        NSArray *loadedRanges = self.playerItem.seekableTimeRanges;
//        if (self.isPlaying && self.loadState == ZFPlayerLoadStateStalled) self.player.rate = self.rate;
//        if (loadedRanges.count > 0) {
//            if (self.playerPlayTimeChanged) self.playerPlayTimeChanged(self, self.currentTime, self.totalTime);
//        }
//    }];
    
//    _itemEndObserver = [[NSNotificationCenter defaultCenter] addObserverForName:AVPlayerItemDidPlayToEndTimeNotification object:self.playerItem queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification * _Nonnull note) {
//        @zf_strongify(self)
//        if (!self) return;
//        self.playState = ZFPlayerPlayStatePlayStopped;
//        if (self.playerDidToEnd) self.playerDidToEnd(self);
//    }];
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary<NSKeyValueChangeKey,id> *)change context:(void *)context {
//    dispatch_async(dispatch_get_main_queue(), ^{
//        if ([keyPath isEqualToString:kStatus]) {
//            if (self.player.currentItem.status == AVPlayerItemStatusReadyToPlay) {
//                if (!self.isReadyToPlay) {
//                    self.isReadyToPlay = YES;
//                    self.loadState = ZFPlayerLoadStatePlaythroughOK;
//                    if (self.playerReadyToPlay) self.playerReadyToPlay(self, self.assetURL);
//                }
//                if (self.seekTime) {
//                    if (self.shouldAutoPlay) [self pause];
//                    @zf_weakify(self)
//                    [self seekToTime:self.seekTime completionHandler:^(BOOL finished) {
//                        @zf_strongify(self)
//                        if (finished) {
//                            if (self.shouldAutoPlay) [self play];
//                        }
//                    }];
//                    self.seekTime = 0;
//                } else {
//                    if (self.shouldAutoPlay && self.isPlaying) [self play];
//                }
//                self.player.muted = self.muted;
//                NSArray *loadedRanges = self.playerItem.seekableTimeRanges;
//                if (loadedRanges.count > 0) {
//                    if (self.playerPlayTimeChanged) self.playerPlayTimeChanged(self, self.currentTime, self.totalTime);
//                }
//            } else if (self.player.currentItem.status == AVPlayerItemStatusFailed) {
//                self.playState = ZFPlayerPlayStatePlayFailed;
//                self->_isPlaying = NO;
//                NSError *error = self.player.currentItem.error;
//                if (self.playerPlayFailed) self.playerPlayFailed(self, error);
//            }
//        } else if ([keyPath isEqualToString:kPlaybackBufferEmpty]) {
//            // When the buffer is empty
//            if (self.playerItem.playbackBufferEmpty) {
//                self.loadState = ZFPlayerLoadStateStalled;
//                [self bufferingSomeSecond];
//            }
//        } else if ([keyPath isEqualToString:kPlaybackLikelyToKeepUp]) {
//            // When the buffer is good
//            if (self.playerItem.playbackLikelyToKeepUp) {
//                self.loadState = ZFPlayerLoadStatePlayable;
//                if (self.isPlaying) [self.player play];
//            }
//        } else if ([keyPath isEqualToString:kLoadedTimeRanges]) {
//            NSTimeInterval bufferTime = [self availableDuration];
//            self->_bufferTime = bufferTime;
//            if (self.playerBufferTimeChanged) self.playerBufferTimeChanged(self, bufferTime);
//        } else if ([keyPath isEqualToString:kPresentationSize]) {
//            self.presentationSize = self.playerItem.presentationSize;
//        } else {
//            [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
//        }
//    });
}
#pragma mark - AVPDelegate
-(void)onPlayerEvent:(AliPlayer*)player eventType:(AVPEventType)eventType {
    switch (eventType) {
        case AVPEventPrepareDone: {
            if (!self.isReadyToPlay) {
                self.isReadyToPlay = YES;
                self.loadState = ZFPlayerLoadStatePlaythroughOK;
                if (self.playerReadyToPlay) self.playerReadyToPlay(self, self.assetURL);
            }
            if (self.seekTime) {
                if (self.shouldAutoPlay) [self pause];
                @zf_weakify(self)
                [self seekToTime:self.seekTime completionHandler:^(BOOL finished) {
                    @zf_strongify(self)
                    if (finished) {
                        if (self.shouldAutoPlay) [self play];
                    }
                }];
                self.seekTime = 0;
            } else {
                if (self.shouldAutoPlay && self.isPlaying) [self play];
            }
            self.player.muted = self.muted;
            NSTimeInterval currentTime = self.currentTime;
            NSTimeInterval durationTime = self.totalTime;
            if (self.playerPlayTimeChanged) self.playerPlayTimeChanged(self, currentTime, durationTime);
        }
            break;
        case AVPEventFirstRenderedStart: {
        }
            break;
        case AVPEventCompletion: {
            self.playState = ZFPlayerPlayStatePlayStopped;
            if (self.playerDidToEnd) self.playerDidToEnd(self);
        }
            
            break;
        case AVPEventLoadingStart: {
        }
            break;
        case AVPEventLoadingEnd: {
        }
            break;
        case AVPEventSeekEnd:{
            if (self.seekComplete) {
                self.seekComplete(YES);
                _seekComplete = nil;
            }
        }
            break;
        case AVPEventLoopingStart:
            break;
        default:
            break;
    }
}

- (void)onCurrentPositionUpdate:(AliPlayer*)player position:(int64_t)position {
    NSTimeInterval currentTime = self.currentTime;
    NSTimeInterval durationTime = self.totalTime;
    if (self.playerPlayTimeChanged) self.playerPlayTimeChanged(self, currentTime, durationTime);
}


- (void)onError:(AliPlayer*)player errorModel:(AVPErrorModel *)errorModel {
    self.playState = ZFPlayerPlayStatePlayFailed;
    self->_isPlaying = NO;
    if (self.playerPlayFailed) self.playerPlayFailed(self, errorModel);
}

- (void)onLoadingProgress:(AliPlayer*)player progress:(float)progress {
//    if (progress >= 100.f) {
//        self.loadState = ZFPlayerLoadStateStalled;
//        [self bufferingSomeSecond];
//    }
}

- (void)onVideoSizeChanged:(AliPlayer*)player width:(int)width height:(int)height rotation:(int)rotation {
    self.presentationSize = CGSizeMake(width, height);
}
#pragma mark - getter

- (ZFPlayerView *)view {
    if (!_view) {
        ZFPlayerView *view = [[ZFPlayerView alloc] init];
        _view = view;
    }
    return _view;
}

- (AVPlayerLayer *)avPlayerLayer {
    ZFPlayerPresentView *view = (ZFPlayerPresentView *)self.view.playerView;
    return [view avLayer];
}

- (float)rate {
    return _rate == 0 ?1:_rate;
}

- (NSTimeInterval)totalTime {
    NSTimeInterval sec = self.player.duration/1000.f;
    if (isnan(sec)) {
        return 0;
    }
    return sec;
}

- (NSTimeInterval)currentTime {
    //NSTimeInterval sec = CMTimeGetSeconds(self.playerItem.currentTime);
    NSTimeInterval sec = self.player.currentPosition/1000.f;
    if (isnan(sec) || sec < 0) {
        return 0;
    }
    return sec;
}

#pragma mark - setter

- (void)setPlayState:(ZFPlayerPlaybackState)playState {
    _playState = playState;
    if (self.playerPlayStateChanged) self.playerPlayStateChanged(self, playState);
}

- (void)setLoadState:(ZFPlayerLoadState)loadState {
    _loadState = loadState;
    if (self.playerLoadStateChanged) self.playerLoadStateChanged(self, loadState);
}

- (void)setAssetURL:(NSURL *)assetURL {
    if (self.player) [self stop];
    _assetURL = assetURL;
    [self prepareToPlay];
}

- (void)setRate:(float)rate {
    _rate = rate;
    if (self.player && fabsf(_player.rate) > 0.00001f) {
        self.player.rate = rate;
    }
}

- (void)setMuted:(BOOL)muted {
    _muted = muted;
    self.player.muted = muted;
}

- (void)setScalingMode:(ZFPlayerScalingMode)scalingMode {
    _scalingMode = scalingMode;
    ZFPlayerPresentView *presentView = (ZFPlayerPresentView *)self.view.playerView;
    self.view.scalingMode = scalingMode;
    switch (scalingMode) {
        case ZFPlayerScalingModeNone:
            self.player.scalingMode = AVP_SCALINGMODE_SCALEASPECTFIT;
            presentView.videoGravity = AVLayerVideoGravityResizeAspect;
            break;
        case ZFPlayerScalingModeAspectFit:
            self.player.scalingMode = AVP_SCALINGMODE_SCALEASPECTFIT;
            presentView.videoGravity = AVLayerVideoGravityResizeAspect;
            break;
        case ZFPlayerScalingModeAspectFill:
            self.player.scalingMode = AVP_SCALINGMODE_SCALEASPECTFILL;
            presentView.videoGravity = AVLayerVideoGravityResizeAspectFill;
            break;
        case ZFPlayerScalingModeFill:
            self.player.scalingMode = AVP_SCALINGMODE_SCALETOFILL;
            presentView.videoGravity = AVLayerVideoGravityResize;
            break;
        default:
            break;
    }
}

- (void)setVolume:(float)volume {
    _volume = MIN(MAX(0, volume), 1);
    self.player.volume = _volume;
}

- (void)setPresentationSize:(CGSize)presentationSize {
    _presentationSize = presentationSize;
    self.view.presentationSize = presentationSize;
    if (self.presentationSizeChanged) {
        self.presentationSizeChanged(self, self.presentationSize);
    }
}

@end

#pragma clang diagnostic pop
