//
//  SpekProcessor.h
//  Spek-Cocoa
//
//  Created by SwanCurve on 02/25/17.
//  Copyright © 2017 SwanCurve. All rights reserved.
//

#ifndef SpekProcessor_h
#define SpekProcessor_h

#import <Cocoa/Cocoa.h>

enum WINDOW_FUNCTION {
    WINDOW_HANN = 0,
    WINDOW_HAMMING,
    WINDOW_BLACKMAN_HARRIS,
    WINDOW_COUNT,
    WINDOW_DEFAULT = WINDOW_HANN,
};

struct AudioFileStruct;
struct FFTPlanStruct;

@interface SpekProcesser : NSObject
{
}

- (instancetype)initProcesserWithAudioFile:(struct AudioFileStruct*)file
                                   FFTPlan:(struct FFTPlanStruct*)fft
                                    Stream:(NSUInteger)stream
                                   Channel:(NSUInteger)channel
                            WindowFunction:(enum WINDOW_FUNCTION)window
                                   Samples:(NSUInteger)samples;

@end

#endif /* SpekProcessor_h */
