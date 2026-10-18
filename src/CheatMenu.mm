// inject: DYLD_INSERT_LIBRARIES=./CheatMenu.dylib ./target  (unsigned)
// signed targets — mach_inject / osxinj
// toggle: Cmd+Shift+M  (CGEventTap, needs Accessibility trust or root)

#import <Cocoa/Cocoa.h>
#import <QuartzCore/QuartzCore.h>
#import <Carbon/Carbon.h>
#import <ApplicationServices/ApplicationServices.h>

// ─── config ───────────────────────────────────────────────────────────────────
static const CGFloat kW   = 260.0f;
static const CGFloat kH   = 360.0f;
static const CGFloat kHdr = 42.0f;
static const CGFloat kR   = 12.0f;
static const NSTimeInterval kDur = 0.20;

static inline NSColor* C(CGFloat r, CGFloat g, CGFloat b, CGFloat a) {
    return [NSColor colorWithSRGBRed:r green:g blue:b alpha:a];
}

// ─── MenuView ─────────────────────────────────────────────────────────────────
@interface MenuView : NSView { NSPoint _drag; BOOL _dragging; }
@end

@implementation MenuView

- (BOOL)isFlipped            { return YES; }
- (BOOL)acceptsFirstMouse:(NSEvent*)e { return YES; }

- (void)drawRect:(NSRect)dirty {
    NSRect b = self.bounds;

    // background — cornerRadius on layer clips this
    [C(0.07f, 0.07f, 0.09f, 0.93f) setFill];
    NSRectFill(b);

    // header fill
    [C(0.10f, 0.10f, 0.13f, 1.0f) setFill];
    NSRectFill(NSMakeRect(0, 0, b.size.width, kHdr));

    // accent line
    [C(0.27f, 0.52f, 1.00f, 0.55f) setFill];
    NSRectFill(NSMakeRect(0, kHdr - 1.0f, b.size.width, 1.0f));

    // title
    NSMutableParagraphStyle* ps = [NSMutableParagraphStyle new];
    ps.alignment = NSTextAlignmentCenter;
    NSDictionary* ta = @{
        NSFontAttributeName:            [NSFont systemFontOfSize:13.0f weight:NSFontWeightSemibold],
        NSForegroundColorAttributeName: C(0.92f, 0.92f, 0.95f, 1.0f),
        NSParagraphStyleAttributeName:  ps
    };
    [@"Cheat Menu" drawInRect:NSMakeRect(0, (kHdr - 15.0f) * 0.5f, b.size.width, 15.0f)
               withAttributes:ta];

    // placeholder row dividers
    [C(0.14f, 0.14f, 0.17f, 1.0f) setFill];
    for (int i = 0; i < 5; i++)
        NSRectFill(NSMakeRect(14, kHdr + 20 + i * 44, b.size.width - 28, 1));

    // empty hint
    NSDictionary* ha = @{
        NSFontAttributeName:            [NSFont monospacedSystemFontOfSize:10.5f
                                                                    weight:NSFontWeightRegular],
        NSForegroundColorAttributeName: C(0.32f, 0.32f, 0.38f, 1.0f),
        NSParagraphStyleAttributeName:  ps
    };
    [@"// no features loaded" drawInRect:NSMakeRect(0, b.size.height * 0.5f - 7.0f,
                                                    b.size.width, 14.0f)
                          withAttributes:ha];

    // outer border (drawn on top, clipped by layer mask)
    NSBezierPath* border = [NSBezierPath bezierPathWithRoundedRect:NSInsetRect(b, 0.5f, 0.5f)
                                                          xRadius:kR yRadius:kR];
    [C(0.22f, 0.22f, 0.28f, 0.65f) setStroke];
    border.lineWidth = 1.0f;
    [border stroke];
}

- (void)mouseDown:(NSEvent*)e {
    NSPoint loc = [self convertPoint:[e locationInWindow] fromView:nil];
    if (loc.y < kHdr) {
        _dragging = YES;
        _drag = [NSEvent mouseLocation];
        _drag.x -= self.window.frame.origin.x;
        _drag.y -= self.window.frame.origin.y;
    }
}
- (void)mouseDragged:(NSEvent*)e {
    if (!_dragging) return;
    NSPoint m = [NSEvent mouseLocation];
    [self.window setFrameOrigin:NSMakePoint(m.x - _drag.x, m.y - _drag.y)];
}
- (void)mouseUp:(NSEvent*)e { _dragging = NO; }

@end

// ─── HdrButton ────────────────────────────────────────────────────────────────
@interface HdrButton : NSView {
    NSString* _glyph;
    NSColor*  _hoverColor;
    BOOL      _over;
}
@property (copy) dispatch_block_t action;
- (instancetype)initWithGlyph:(NSString*)g hover:(NSColor*)h;
@end

@implementation HdrButton

- (instancetype)initWithGlyph:(NSString*)g hover:(NSColor*)h {
    self = [super initWithFrame:NSMakeRect(0, 0, 24, 24)];
    _glyph = g; _hoverColor = h;
    [self addTrackingArea:[[NSTrackingArea alloc]
        initWithRect:self.bounds
             options:NSTrackingMouseEnteredAndExited | NSTrackingActiveAlways
               owner:self userInfo:nil]];
    return self;
}

- (BOOL)acceptsFirstMouse:(NSEvent*)e { return YES; }

- (void)drawRect:(NSRect)r {
    NSBezierPath* pill = [NSBezierPath bezierPathWithOvalInRect:NSInsetRect(self.bounds, 2, 2)];
    [(_over ? _hoverColor : C(0.17f, 0.17f, 0.21f, 1.0f)) setFill];
    [pill fill];

    NSDictionary* a = @{
        NSFontAttributeName: [NSFont systemFontOfSize:9.5f weight:NSFontWeightMedium],
        NSForegroundColorAttributeName: _over ? [NSColor whiteColor] : C(0.50f, 0.50f, 0.55f, 1.0f)
    };
    NSSize sz = [_glyph sizeWithAttributes:a];
    [_glyph drawAtPoint:NSMakePoint((self.bounds.size.width  - sz.width)  * 0.5f,
                                    (self.bounds.size.height - sz.height) * 0.5f)
         withAttributes:a];
}

- (void)mouseEntered:(NSEvent*)e { _over = YES;  [self setNeedsDisplay:YES]; }
- (void)mouseExited:(NSEvent*)e  { _over = NO;   [self setNeedsDisplay:YES]; }
- (void)mouseDown:(NSEvent*)e    { if (_action) _action(); }

@end

// ─── CheatPanel ───────────────────────────────────────────────────────────────
@interface CheatPanel : NSPanel
@property (nonatomic, assign) BOOL visible;
- (void)animateIn;
- (void)animateHide;
- (void)animateClose;
@end

@implementation CheatPanel

- (BOOL)canBecomeKeyWindow  { return YES; }
- (BOOL)canBecomeMainWindow { return YES; }

- (void)_outWithScale:(CGFloat)s done:(void(^)(void))done {
    [NSAnimationContext runAnimationGroup:^(NSAnimationContext* ctx) {
        ctx.duration = kDur;
        ctx.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseIn];
        self.animator.alphaValue = 0.0f;
    } completionHandler:done];

    [CATransaction begin];
    [CATransaction setAnimationDuration:kDur];
    [CATransaction setAnimationTimingFunction:
        [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseIn]];
    self.contentView.layer.transform = CATransform3DMakeScale(s, s, 1.0f);
    [CATransaction commit];
}

- (void)animateIn {
    self.contentView.layer.transform = CATransform3DMakeScale(0.88f, 0.88f, 1.0f);
    [self setAlphaValue:0.0f];
    [self makeKeyAndOrderFront:nil];

    [NSAnimationContext runAnimationGroup:^(NSAnimationContext* ctx) {
        ctx.duration = kDur;
        ctx.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseOut];
        self.animator.alphaValue = 1.0f;
    }];
    [CATransaction begin];
    [CATransaction setAnimationDuration:kDur];
    [CATransaction setAnimationTimingFunction:
        [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseOut]];
    self.contentView.layer.transform = CATransform3DIdentity;
    [CATransaction commit];

    self.visible = YES;
}

// − : hide, re-toggle shows it again
- (void)animateHide {
    [self _outWithScale:0.94f done:^{
        [self orderOut:nil];
        self.visible = NO;
    }];
}

// × : close (same toggle behaviour, different scale)
- (void)animateClose {
    [self _outWithScale:0.88f done:^{
        [self orderOut:nil];
        self.visible = NO;
    }];
}

@end

// ─── Controller ───────────────────────────────────────────────────────────────
@interface CheatController : NSObject
+ (instancetype)shared;
- (void)toggle;
@end

static CFMachPortRef gTap = NULL;

static CGEventRef tapCB(CGEventTapProxy proxy, CGEventType type,
                         CGEventRef event, void* ctx) {
    if (type == kCGEventTapDisabledByTimeout || type == kCGEventTapDisabledByUserInput) {
        if (gTap) CGEventTapEnable(gTap, YES);
        return event;
    }
    if (type == kCGEventKeyDown) {
        CGKeyCode    key   = (CGKeyCode)CGEventGetIntegerValueField(event, kCGKeyboardEventKeycode);
        CGEventFlags flags = CGEventGetFlags(event);
        BOOL cmd   = (flags & kCGEventFlagMaskCommand) != 0;
        BOOL shift = (flags & kCGEventFlagMaskShift)   != 0;
        if (cmd && shift && key == kVK_ANSI_M) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [[CheatController shared] toggle];
            });
        }
    }
    return event;
}

@implementation CheatController { CheatPanel* _panel; }

+ (instancetype)shared {
    static CheatController* inst;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ inst = [CheatController new]; });
    return inst;
}

- (instancetype)init {
    self = [super init];
    [self buildPanel];
    [self startHotkey];
    return self;
}

- (void)buildPanel {
    NSScreen* scr = [NSScreen mainScreen];
    CGFloat x = (scr.frame.size.width  - kW) * 0.5f;
    CGFloat y = (scr.frame.size.height - kH) * 0.5f;

    _panel = [[CheatPanel alloc]
        initWithContentRect:NSMakeRect(x, y, kW, kH)
                  styleMask:NSWindowStyleMaskBorderless
                    backing:NSBackingStoreBuffered
                      defer:NO];
    _panel.level                  = NSFloatingWindowLevel + 1;
    _panel.backgroundColor        = [NSColor clearColor];
    _panel.opaque                 = NO;
    _panel.hasShadow              = YES;
    _panel.becomesKeyOnlyIfNeeded = YES;

    MenuView* mv = [[MenuView alloc] initWithFrame:NSMakeRect(0, 0, kW, kH)];
    mv.wantsLayer          = YES;
    mv.layer.masksToBounds = YES;
    mv.layer.cornerRadius  = kR;

    __weak CheatPanel* wp = _panel;

    HdrButton* hideBtn  = [[HdrButton alloc] initWithGlyph:@"−"
                                                     hover:C(0.28f, 0.28f, 0.36f, 1.0f)];
    hideBtn.frame  = NSMakeRect(kW - 58.0f, (kHdr - 24.0f) * 0.5f, 24, 24);
    hideBtn.action = ^{ [wp animateHide]; };

    HdrButton* closeBtn = [[HdrButton alloc] initWithGlyph:@"×"
                                                     hover:C(0.80f, 0.22f, 0.22f, 1.0f)];
    closeBtn.frame  = NSMakeRect(kW - 30.0f, (kHdr - 24.0f) * 0.5f, 24, 24);
    closeBtn.action = ^{ [wp animateClose]; };

    [mv addSubview:hideBtn];
    [mv addSubview:closeBtn];
    [_panel setContentView:mv];
}

- (void)startHotkey {
    // kCGEventTapOptionListenOnly — не потребляет эвент, но всё равно нужен Accessibility trust
    // если вернёт NULL — hotkey не работает, кнопки в меню работают
    gTap = CGEventTapCreate(
        kCGSessionEventTap,
        kCGHeadInsertEventTap,
        kCGEventTapOptionListenOnly,
        CGEventMaskBit(kCGEventKeyDown),
        tapCB,
        NULL
    );
    if (!gTap) {
        NSLog(@"[CheatMenu] CGEventTap failed — add process to Accessibility or run as root");
        return;
    }
    CFRunLoopSourceRef src = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, gTap, 0);
    CFRunLoopAddSource(CFRunLoopGetMain(), src, kCFRunLoopCommonModes);
    CGEventTapEnable(gTap, YES);
    CFRelease(src);
}

- (void)toggle {
    if (_panel.visible) [_panel animateHide];
    else                [_panel animateIn];
}

@end

// ─── entry ────────────────────────────────────────────────────────────────────
__attribute__((constructor))
static void Init(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.4 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            [[CheatController shared] toggle];
        });
    });
}
