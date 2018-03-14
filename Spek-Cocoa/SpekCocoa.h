//
//  SpekCocoa.h
//  Spek-Cocoa
//
//  Created by SwanCurve on 02/22/17.
//  Copyright © 2017 SwanCurve. All rights reserved.
//

#import <Cocoa/Cocoa.h>

#pragma mark - DragNDropDelegate
@protocol DragNDropDelegate <NSObject>

@optional
- (NSDragOperation)draggingEntered:(id<NSDraggingInfo>)sender;
- (BOOL)performDragOperation:(id<NSDraggingInfo>)sender;

@end

#pragma mark - SpekWindow
@interface SpekWindow: NSWindow <NSDraggingDestination>

@property (nonatomic, weak) id<DragNDropDelegate> dragNDropDelegate;

@end

#pragma mark - SpekCocoa
@interface SpekCocoa: NSObject <NSWindowDelegate, DragNDropDelegate>

@property (nonatomic, weak) IBOutlet SpekWindow *window;

- (instancetype)init;
- (void)dealloc;
- (void)startWithPath:(NSString *)path;

@end

