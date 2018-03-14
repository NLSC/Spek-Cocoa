//
//  SpectrogramView.h
//  Spek-Cocoa
//
//  Created by SwanCurve on 09/03/17.
//  Copyright © 2017 SwanCurve. All rights reserved.
//

#import <Cocoa/Cocoa.h>

@interface SpectrogramView : NSView

@property (nonatomic) CGFloat range;

- (void)reset;

- (void)setDataAtSample:(NSInteger)sample bands:(NSInteger)bands withData:(float *)data;

- (void)finish;

@end
