//
//  AppDelegate.m
//  Spek-Cocoa
//
//  Created by SwanCurve on 02/11/17.
//  Copyright © 2017 SwanCurve. All rights reserved.
//

#import "AppDelegate.h"
#import "SpekCocoa.h"

@interface AppDelegate ()

//@property IBOutlet NSWindow *window;
@property (assign) IBOutlet SpekCocoa *spek;

@end

@implementation AppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification {
    // Insert code here to initialize your application
    [self.spek.window makeKeyAndOrderFront:self.spek.window];
}

- (BOOL)applicationShouldHandleReopen:(NSApplication *)sender hasVisibleWindows:(BOOL)flag {
    if (flag)
        return NO;
    else {
        [self.spek.window makeKeyAndOrderFront:self.spek.window];
        return YES;
    }
}

- (void)applicationWillTerminate:(NSNotification *)aNotification {
    // Insert code here to tear down your application
}

- (BOOL)application:(NSApplication *)sender openFile:(NSString *)filename {
    if ([filename length]) {
        [self.spek startWithPath:filename];
        return YES;
    }
    return NO;
}

- (IBAction)openDocument:(id)sender {
    NSOpenPanel* panel = [NSOpenPanel openPanel];
    
    [panel setCanChooseDirectories:NO];
    [panel setCanChooseFiles:YES];
    [panel setAllowsMultipleSelection:NO];
    
    [panel beginSheetModalForWindow:self.spek.window completionHandler:^(NSInteger res) {
        if (res == NSFileHandlingPanelOKButton) {
            NSString* path = [[panel URL] path];
            if ([path length])
                [self.spek startWithPath:path];
        }
    }];
}

@end
