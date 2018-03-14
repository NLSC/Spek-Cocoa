//
//  PalleteView.m
//  Spek-Cocoa
//
//  Created by SwanCurve on 09/03/17.
//  Copyright © 2017 SwanCurve. All rights reserved.
//

#import "Palette.hpp"

#import "PalleteView.h"

@interface PalleteView ()

@property (nonatomic) u_char *data;

@end

@implementation PalleteView

- (instancetype)initWithFrame:(NSRect)frameRect {
    if (self = [super initWithFrame:frameRect]) {
        [self initData];
    }
    return self;
}

- (instancetype)initWithCoder:(NSCoder *)coder {
    if (self = [super initWithCoder:coder]) {
        [self initData];
    }
    return self;
}

- (void)dealloc {
    free(_data);
}

- (BOOL)isFlipped {
    return YES;
}

- (void)drawRect:(NSRect)dirtyRect {
    [super drawRect:dirtyRect];
    
    // Drawing code here.
    if (!_data) return;
    
    // Drawing code here.
    
    CGContextRef ctx = (CGContextRef)[[NSGraphicsContext currentContext] graphicsPort];
    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
    CGContextRef bitmapContext = CGBitmapContextCreate(_data,
                                                       self.frame.size.width,
                                                       [self bandsForBits:11],
                                                       8,
                                                       [self bitsPerRow],
                                                       colorSpace,
                                                       kCGImageAlphaNoneSkipLast);
    assert(bitmapContext);
    CGImageRef img = CGBitmapContextCreateImage(bitmapContext);
    
    CGContextDrawImage(ctx, NSMakeRect(0, 0, self.frame.size.width, self.frame.size.height), img);
    
    CGImageRelease(img);
    CGContextRelease(bitmapContext);
    CGColorSpaceRelease(colorSpace);
}

- (NSInteger)bitsPerRow {
    return self.frame.size.width * 4;
}

- (NSInteger)bandsForBits:(NSUInteger)bits {
    return (1 << (bits - 1)) + 1;;
}

- (void)initData {
    _data = (u_char *)malloc([self bandsForBits:11] * [self bitsPerRow] * sizeof(u_char));
    memset(_data, 0, [self bandsForBits:11] * [self bitsPerRow] * sizeof(u_char));
    
    for (int y = 0; y < [self bandsForBits:11]; y++) {
        uint32_t color = spek_palette(PALETTE_DEFAULT, y / (double)[self bandsForBits:11]);
        
        for (NSInteger i = 0; i < 20 * 4; i++) {
            NSInteger offset = y * [self bitsPerRow] + i * 4;
            _data[offset + 0] = (color >> 16) & 0xFF;
            _data[offset + 1] = (color >> 8) & 0xFF;
            _data[offset + 2] = color & 0xFF;
        }
    }
}

@end
