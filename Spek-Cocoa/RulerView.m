//
//  RulerView.m
//  Spek-Cocoa
//
//  Created by SwanCurve on 08/21/17.
//  Copyright © 2017 SwanCurve. All rights reserved.
//

#import "RulerView.h"

@interface RulerView ()

@property (nonatomic, readonly, strong) NSDictionary *textAttributes;

@end

@implementation RulerView

@synthesize textAttributes = _textAttributes;

- (NSDictionary *)textAttributes {
    if (_textAttributes == nil) {
        _textAttributes = @{NSFontAttributeName: [NSFont systemFontOfSize:[NSFont smallSystemFontSize]],
                            NSForegroundColorAttributeName: [NSColor whiteColor]};
    };
    return _textAttributes;
}

- (BOOL)isFlipped {
    return YES;
}

- (BOOL)layoutHorizontal {
    return (self.position == Top || self.position == Bottom);
}

- (CGFloat)scale {
    CGFloat scale = ([self layoutHorizontal] ? self.frame.size.width : self.frame.size.height) / (self.maximum - self.minimum);
    return scale;
}

- (void)drawRect:(NSRect)dirtyRect {
    [super drawRect:dirtyRect];
    
    
    if (self.minimum == self.maximum) return;
    
    NSSize tickSize = [self.labelExample sizeWithAttributes:nil];
    
    NSInteger len = [self layoutHorizontal] ? tickSize.width : tickSize.height;
    
    
    // Select the factor to use, we want some space between the labels.
    NSInteger selectedFactor = 0;
    for (NSNumber *factor in self.factors) {
        NSInteger factorValue = [factor intValue];
        if ([self scale] * factorValue >= self.unitSpacing * len) {
            selectedFactor = factorValue;
            break;
        }
    }
    
    [self drawTick:self.minimum];
    [self drawTick:self.maximum];
    
    if (selectedFactor > 0) {
        for (NSInteger tick = self.minimum + selectedFactor; tick < self.maximum; tick += selectedFactor) {
            if (fabs([self scale] * (self.maximum - tick)) < len * 1.2) {
                break;
            }
            [self drawTick:tick];
        }
    }
}

- (void)drawTick:(NSInteger) tick {
    CGFloat GAP = 10;
    CGFloat TICK_LEN = 4;
    
    NSString *label = self.formatter(tick);
    NSInteger value = [self layoutHorizontal] ? tick : self.maximum + self.minimum - tick;
    CGFloat p = [self scale] * (value - self.minimum);
    NSSize labelSize = [label sizeWithAttributes:self.textAttributes];
    
    [[NSColor whiteColor] set];
    
    CGContextRef ctx = [[NSGraphicsContext currentContext] graphicsPort];
    
    switch (self.position) {
        case Top:
        {
            break;
        }
        case Right:
        {
            CGContextSetLineWidth(ctx, 1.f);
            CGContextMoveToPoint(ctx, 0 + 2, p);
            CGContextAddLineToPoint(ctx, 0 + 2 + 6, p);
            CGContextStrokePath(ctx);
            
            NSInteger y = p;
            if (p - labelSize.height / 2 >= 0) {
                y = p - labelSize.height / 2;
            }
            if (p + labelSize.height / 2 >= self.frame.size.height) {
                y = self.frame.size.height - labelSize.height;
            }
            
            [label drawAtPoint:NSMakePoint(0 + 12, y) withAttributes:self.textAttributes];
            
            break;
        }
        case Bottom:
        {
            NSInteger pAdjusted = p;
//            if (pAdjusted == 0) {
//                pAdjusted = 1;
//            } else if (pAdjusted == self.frame.size.width) {
//                pAdjusted = self.frame.size.width - 1;
//            }
            CGContextSetLineWidth(ctx, 1.f);
            CGContextMoveToPoint(ctx, pAdjusted, 0);
            CGContextAddLineToPoint(ctx, pAdjusted, 6);
            CGContextStrokePath(ctx);
            
            CGContextSetTextDrawingMode(ctx, kCGTextFill);

            NSInteger x = p;
            if (p - labelSize.width / 2 >= 0) {
                x = p - labelSize.width / 2;
            }
            if (p + labelSize.width / 2 >= self.frame.size.width) {
                x = self.frame.size.width - labelSize.width;
            }
            
            [label drawAtPoint:NSMakePoint(x, 0 + 8) withAttributes:self.textAttributes];
            break;
        }
        case Left:
        {
            NSInteger x = self.frame.size.width - 8;
            
            CGContextSetLineWidth(ctx, 1.f);
            CGContextMoveToPoint(ctx, x + 2, p);
            CGContextAddLineToPoint(ctx, x + 2 + 6, p);
            CGContextStrokePath(ctx);
            
            NSInteger y = p;
            if (p - labelSize.height / 2 >= 0) {
                y = p - labelSize.height / 2;
            }
            if (p + labelSize.height / 2 >= self.frame.size.height) {
                y = self.frame.size.height - labelSize.height;
            }
            
            [label drawAtPoint:NSMakePoint(x - labelSize.width - 2, y) withAttributes:self.textAttributes];
            break;
        }
        default:
            break;
    }
}

@end
