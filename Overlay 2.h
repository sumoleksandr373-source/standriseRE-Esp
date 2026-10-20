#pragma once
#import <UIKit/UIKit.h>
#import <CoreGraphics/CoreGraphics.h>

// One draw-entity per visible enemy this frame
typedef struct {
    CGPoint head;       // screen coords
    CGPoint hip;        // screen coords (box bottom)
    float   healthPct;  // 0.0 – 1.0  (1.0 if unknown)
    int     team;       // Team enum
    BOOL    isAlive;
} ESPEntity;

@interface ESPOverlayView : UIView
- (void)updateEntities:(NSArray<NSValue *> *)entityValues; // NSValue wrapping ESPEntity
@end

@interface ESPOverlayWindow : UIWindow
+ (instancetype)sharedWindow;
- (void)setESPEnabled:(BOOL)enabled;
@end
