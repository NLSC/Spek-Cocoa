//
//  Palette.hpp
//  Spek-Cocoa
//
//  Created by SwanCurve on 03/01/17.
//  Copyright © 2017 SwanCurve. All rights reserved.
//

#ifndef Palette_h
#define Palette_h

#include <stdlib.h>

enum palette {
    PALETTE_SPECTRUM,
    PALETTE_SOX,
    PALETTE_MONO,
    PALETTE_COUNT,
    PALETTE_DEFAULT = PALETTE_SOX,
};

uint32_t spek_palette(enum palette palette, double level);

#endif /* Palette_h */
