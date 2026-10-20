#import "Overlay.h"

// -------------------------------------------------------
// ESPOverlayView — draws boxes + hp bars each display tick
// -------------------------------------------------------
@interface ESPOverlayView () {
    NSArray<NSValue *> *_entities;
}
@end

@implementation ESPOverlayView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor   = [UIColor clearColor];
        self.userInteractionEnabled = NO;
        self.opaque = NO;
        _entities = @[];
    }
    return self;
}

- (void)updateEntities:(NSArray<NSValue *> *)entityValues {
    _entities = entityValues;
    [self setNeedsDisplay];
}

- (void)drawRect:(CGRect)rect {
    CGContextRef ctx = UIGraphicsGetCurrentContext();
    if (!ctx) return;

    for (NSValue *val in _entities) {
        ESPEntity e;
        [val getValue:&e];
        if (!e.isAlive) continue;

        // --- box from hip to head ---
        CGFloat boxW  = fabsf(e.head.x - e.hip.x) * 0.8f + 20.0f;  // rough width
        CGFloat boxH  = fabsf(e.head.y - e.hip.y);
        if (boxH < 4.0f) continue;  // offscreen / degenerate

        CGFloat left  = e.head.x - boxW * 0.5f;
        CGFloat top   = e.head.y;
        CGRect  box   = CGRectMake(left, top, boxW, boxH);

        // enemy = red, teammate = green
        UIColor *boxColor = (e.team == 1) // Tr
            ? [UIColor colorWithRed:1 green:0.2f blue:0.2f alpha:0.9f]
            : [UIColor colorWithRed:0.2f green:1 blue:0.2f alpha:0.9f];

        CGContextSetStrokeColorWithColor(ctx, boxColor.CGColor);
        CGContextSetLineWidth(ctx, 1.5f);
        CGContextStrokeRect(ctx, box);

        // --- corner brackets (cleaner look) ---
        CGFloat cLen = boxW * 0.25f;
        CGContextSetLineWidth(ctx, 2.5f);
        // TL
        CGContextMoveToPoint(ctx,    left,          top);
        CGContextAddLineToPoint(ctx, left + cLen,   top);
        CGContextMoveToPoint(ctx,    left,          top);
        CGContextAddLineToPoint(ctx, left,           top + cLen);
        // TR
        CGContextMoveToPoint(ctx,    left + boxW,   top);
        CGContextAddLineToPoint(ctx, left + boxW - cLen, top);
        CGContextMoveToPoint(ctx,    left + boxW,   top);
        CGContextAddLineToPoint(ctx, left + boxW,    top + cLen);
        // BL
        CGContextMoveToPoint(ctx,    left,          top + boxH);
        CGContextAddLineToPoint(ctx, left + cLen,   top + boxH);
        CGContextMoveToPoint(ctx,    left,          top + boxH);
        CGContextAddLineToPoint(ctx, left,           top + boxH - cLen);
        // BR
        CGContextMoveToPoint(ctx,    left + boxW,   top + boxH);
        CGContextAddLineToPoint(ctx, left + boxW - cLen, top + boxH);
        CGContextMoveToPoint(ctx,    left + boxW,   top + boxH);
        CGContextAddLineToPoint(ctx, left + boxW,    top + boxH - cLen);
        CGContextStrokePath(ctx);

        // --- HP bar (left side) ---
        CGFloat barX   = left - 6.0f;
        CGFloat barH   = boxH;
        CGFloat fillH  = barH * (CGFloat)e.healthPct;

        // bg
        CGContextSetFillColorWithColor(ctx,
            [UIColor colorWithWhite:0.1f alpha:0.7f].CGColor);
        CGContextFillRect(ctx, CGRectMake(barX - 3.0f, top, 3.0f, barH));

        // fill — green→yellow→red based on hp
        CGFloat r = 1.0f - (CGFloat)e.healthPct;
        CGFloat g = (CGFloat)e.healthPct;
        CGContextSetFillColorWithColor(ctx,
            [UIColor colorWithRed:r green:g blue:0 alpha:1].CGColor);
        CGContextFillRect(ctx,
            CGRectMake(barX - 3.0f, top + (barH - fillH), 3.0f, fillH));

        // --- head dot ---
        CGContextSetFillColorWithColor(ctx, boxColor.CGColor);
        CGContextFillEllipseInRect(ctx, CGRectMake(e.head.x - 3, e.head.y - 3, 6, 6));

        // --- snap line (bottom center → head) ---
        CGContextSetStrokeColorWithColor(ctx,
            [UIColor colorWithWhite:1 alpha:0.3f].CGColor);
        CGContextSetLineWidth(ctx, 1.0f);
        CGPoint screenBottom = CGPointMake(self.bounds.size.width  * 0.5f,
                                           self.bounds.size.height);
        CGContextMoveToPoint(ctx, screenBottom.x, screenBottom.y);
        CGContextAddLineToPoint(ctx, e.head.x, e.head.y);
        CGContextStrokePath(ctx);
    }
}
@end


// -------------------------------------------------------
// ESPOverlayWindow
// -------------------------------------------------------
static ESPOverlayWindow *_sharedESPWindow = nil;

@interface ESPOverlayWindow () {
    ESPOverlayView *_espView;
    CADisplayLink  *_displayLink;
    BOOL            _espEnabled;
}
@end

@implementation ESPOverlayWindow

+ (instancetype)sharedWindow {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        CGRect screen = [UIScreen mainScreen].bounds;
        _sharedESPWindow = [[ESPOverlayWindow alloc] initWithFrame:screen];
        _sharedESPWindow.windowLevel     = UIWindowLevelStatusBar + 100.0f;
        _sharedESPWindow.backgroundColor = [UIColor clearColor];
        _sharedESPWindow.userInteractionEnabled = NO;
        _sharedESPWindow.hidden = YES;

        UIViewController *vc = [UIViewController new];
        vc.view.backgroundColor = [UIColor clearColor];
        _sharedESPWindow.rootViewController = vc;

        _sharedESPWindow->_espView = [[ESPOverlayView alloc] initWithFrame:screen];
        [vc.view addSubview:_sharedESPWindow->_espView];
    });
    return _sharedESPWindow;
}

- (void)setESPEnabled:(BOOL)enabled {
    _espEnabled = enabled;
    self.hidden = !enabled;

    if (enabled && !_displayLink) {
        _displayLink = [CADisplayLink displayLinkWithTarget:self
                                                   selector:@selector(_tick:)];
        _displayLink.preferredFramesPerSecond = 60;
        [_displayLink addToRunLoop:[NSRunLoop mainRunLoop]
                           forMode:NSRunLoopCommonModes];
    } else if (!enabled && _displayLink) {
        [_displayLink invalidate];
        _displayLink = nil;
        [_espView updateEntities:@[]];
    }
}

// called each frame — calls back into Tweak.mm to collect entities
extern NSArray<NSValue *> *SRESPCollectEntities(void);

- (void)_tick:(CADisplayLink *)link {
    if (!_espEnabled) return;
    NSArray<NSValue *> *ents = SRESPCollectEntities();
    [_espView updateEntities:ents];
}

// pass-through all touches to the game
- (BOOL)pointInside:(CGPoint)point withEvent:(UIEvent *)event {
    return NO;
}
@end
