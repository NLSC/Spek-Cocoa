//
//  SpectrogramView.m
//  Spek-Cocoa
//
//  Created by SwanCurve on 09/03/17.
//  Copyright © 2017 SwanCurve. All rights reserved.
//

#import "Palette.hpp"

#import "SpectrogramView.h"

#import <CoreVideo/CoreVideo.h>

@interface SpectrogramView ()

@property (nonatomic) u_char *data;

@property (nonatomic) CVDisplayLinkRef displayLink;

@property (nonatomic) BOOL isDirty;

@property (nonatomic) dispatch_queue_t drawingQueue;

@property NSInteger bitsPerRow;
@property CGSize imageSize;

@end

@implementation SpectrogramView

- (instancetype)initWithFrame:(NSRect)frameRect {
    if (self = [super initWithFrame:frameRect]) {
//        self.layer = [CALayer layer];
//        self.wantsLayer = YES;
//        CALayer *layer = self.layer;
//        self.layerContentsRedrawPolicy = NSViewLayerContentsRedrawOnSetNeedsDisplay;
//        self.layer.delegate = self;
        _data = NULL;
        _range = 120;
    }
    return self;
}

- (instancetype)initWithCoder:(NSCoder *)coder {
    if (self = [super initWithCoder:coder]) {
        self.isDirty = false;
        CVDisplayLinkCreateWithActiveCGDisplays(&_displayLink);
        CVDisplayLinkRetain(self.displayLink);

        __weak SpectrogramView *wSelf = self;
        CVDisplayLinkSetOutputHandler(_displayLink, ^CVReturn(CVDisplayLinkRef  _Nonnull displayLink, const CVTimeStamp * _Nonnull inNow, const CVTimeStamp * _Nonnull inOutputTime, CVOptionFlags flagsIn, CVOptionFlags * _Nonnull flagsOut) {
            __strong SpectrogramView *sSelf = wSelf;

            CGRect rect = CGRectMake(.0, .0, sSelf.imageSize.width, sSelf.imageSize.height);            
            dispatch_async(self.drawingQueue, ^{
                CGImageRef img = [self imageForRect:rect];
                dispatch_async(dispatch_get_main_queue(), ^{
                    CGImageRef old = (__bridge CGImageRef)self.layer.contents;
                    CGImageRelease(old);
                    
                    self.layer.contents = (__bridge id)img;
                    [self.layer setNeedsDisplay];
                });
            });
            return kCVReturnSuccess;
        });
        
        _data = NULL;
        _range = 120;
        
        _drawingQueue = dispatch_queue_create("com.spek.drawingQueue", NULL);
    }
    return self;
}

- (void)dealloc {
    free(_data);
    CVDisplayLinkStop(_displayLink);
    CVDisplayLinkRelease(_displayLink);
}

- (BOOL)wantsLayer {
    return YES;
}

- (CGImageRef)imageForRect:(CGRect)rect {
    if (!_data) return NULL;
    
    CGFloat width = rect.size.width;
    CGFloat height = [self bandsForBits:11];
    
    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
    CGContextRef bitmapContext = CGBitmapContextCreateWithData(_data,
                                                               width,
                                                               height,
                                                               8,
                                                               width * 4,
                                                               colorSpace,
                                                               kCGImageAlphaPremultipliedLast,
                                                               //  kCGImageAlphaNoneSkipLast,
                                                               NULL,
                                                               NULL);
    assert(bitmapContext);
    CGImageRef img = CGBitmapContextCreateImage(bitmapContext);
    
    CGContextRelease(bitmapContext);
    CGColorSpaceRelease(colorSpace);
    return img;
}

- (NSInteger)bandsForBits:(NSUInteger)bits {
    return (1 << (bits - 1)) + 1;;
}

- (void)setDataAtSample:(NSInteger)sample bands:(NSInteger)bands withData:(float *)data {
    if (!_data) return;
    self.isDirty = true;
    // flip image data
    for (NSInteger i = 0; i < bands; i++) {
        double value = fmin(0, fmax(-120, data[i]));
        double level = (value - (-120)) / 120;
        uint32_t color = spek_palette(PALETTE_DEFAULT, level);
        NSInteger offset = (bands - i - 1) * self.bitsPerRow + sample * 4;
        
        char r = 0, g = 0, b = 0, gray = 0;
        r = (color >> 16) & 0xFF;
        g = (color >> 8) & 0xFF;
        b = (color) & 0xFF;
        gray = (((int16_t)r * 38 + (int16_t)g * 75 + (int16_t)b * 15) >> 7) & 0xFF;
        _data[offset + 0] = r;
        _data[offset + 1] = g;
        _data[offset + 2] = b;
        _data[offset + 3] = 255;
    }
}

- (void)reset {
    free(_data);
    self.bitsPerRow = self.frame.size.width * 4;
    self.imageSize = self.frame.size;
    
    _data = (u_char *)malloc([self bandsForBits:11] * [self bitsPerRow] * sizeof(u_char));
    memset(_data, 0, [self bandsForBits:11] * self.bitsPerRow * sizeof(u_char));
    
    [self setNeedsDisplay:YES];
    self.isDirty = true;
    CVDisplayLinkStop(_displayLink);
    CVDisplayLinkStart(_displayLink);
}

- (void)finish { 
//    dispatch_sync(dispatch_get_main_queue(), ^{
        CVReturn res = CVDisplayLinkStop(_displayLink);
        assert(res == kCVReturnSuccess);
//    });
}

@end
