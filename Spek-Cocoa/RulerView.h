//
//  RulerView.h
//  Spek-Cocoa
//
//  Created by SwanCurve on 08/21/17.
//  Copyright © 2017 SwanCurve. All rights reserved.
//

#import <Cocoa/Cocoa.h>

typedef NS_ENUM(NSInteger, RulerPosition) {
    Top,
    Right,
    Bottom,
    Left
};

NS_ASSUME_NONNULL_BEGIN

@interface RulerView : NSView

@property (nonatomic) enum RulerPosition position;
@property (retain, nonatomic, nonnull) NSArray<NSNumber *> *factors;
@property (nonatomic) NSInteger minimum;
@property (nonatomic) NSInteger maximum;
@property (nonatomic) CGFloat unitSpacing;

@property (nonatomic, copy, nonnull) NSString *labelExample;

typedef NSString *_Nonnull(^formatter)(NSInteger unit);
@property (nonatomic, copy, nonnull) formatter formatter;

NS_ASSUME_NONNULL_END

@end
