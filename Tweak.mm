#import <UIKit/UIKit.h>

// ── config ────────────────────────────────────────────────────────────────────
static const CGFloat kToggleW  = 32.f;   // ширина кнопки скрыть
static const CGFloat kBorder   = 1.5f;
static const CGFloat kMargin   = 10.f;   // отступ от краёв экрана
static const CGFloat kMaxW     = 460.f;  // макс ширина панели

static CGFloat MenuH(void) {
    // 5.5% короткой стороны экрана, зажато в [44, 54]
    CGFloat s = MIN(UIScreen.mainScreen.bounds.size.width,
                    UIScreen.mainScreen.bounds.size.height);
    return MAX(44.f, MIN(s * 0.055f, 54.f));
}

static UIColor *BG(void)     { return [UIColor colorWithRed:.08f green:.08f blue:.08f alpha:.96f]; }
static UIColor *Accent(void) { return [UIColor colorWithRed:1.f  green:.45f blue:.0f  alpha:1.f]; }
// ─────────────────────────────────────────────────────────────────────────────

@interface CrezBar : UIView
- (void)relayoutForBounds:(CGRect)windowBounds;
@end

@interface CrezMenuWindow : UIWindow
@property (nonatomic, strong) CrezBar *bar;
@end

// ── кнопка ◀ / ▶ ─────────────────────────────────────────────────────────────
@interface CrezToggleBtn : UIControl
@property (nonatomic, assign) BOOL expanded;   // YES = меню открыто
@property (nonatomic, copy)   void (^action)(void);
@end

@implementation CrezToggleBtn

- (instancetype)initWithFrame:(CGRect)f {
    self = [super initWithFrame:f];
    self.backgroundColor = Accent();
    self.expanded = YES;
    [self addTarget:self action:@selector(_tap)
   forControlEvents:UIControlEventTouchUpInside];
    return self;
}
- (void)_tap { if (self.action) self.action(); }
- (void)setExpanded:(BOOL)v { _expanded = v; [self setNeedsDisplay]; }
- (void)drawRect:(CGRect)r {
    CGFloat cx = r.size.width*.5f, cy = r.size.height*.5f;
    CGFloat aw = 5.f, ah = 8.f;
    UIBezierPath *p = [UIBezierPath new];
    if (_expanded) {            // ◀ скрыть
        [p moveToPoint:CGPointMake(cx+aw, cy-ah)];
        [p addLineToPoint:CGPointMake(cx-aw, cy)];
        [p addLineToPoint:CGPointMake(cx+aw, cy+ah)];
    } else {                    // ▶ показать
        [p moveToPoint:CGPointMake(cx-aw, cy-ah)];
        [p addLineToPoint:CGPointMake(cx+aw, cy)];
        [p addLineToPoint:CGPointMake(cx-aw, cy+ah)];
    }
    [[UIColor whiteColor] setStroke];
    p.lineWidth = 2.f; p.lineCapStyle = kCGLineCapSquare;
    [p stroke];
}
@end

// ── панель ────────────────────────────────────────────────────────────────────
@implementation CrezBar {
    CrezToggleBtn *_btn;
    UIScrollView  *_scroll;
    UILabel       *_placeholder;
    BOOL           _expanded;
    CGPoint        _dragStart;
    CGPoint        _originStart;
    CGFloat        _fullWidth;   // ширина в развёрнутом виде
}

- (instancetype)initWithBounds:(CGRect)wb {
    self = [super initWithFrame:CGRectZero];
    if (!self) return nil;

    self.backgroundColor    = BG();
    self.layer.borderColor  = Accent().CGColor;
    self.layer.borderWidth  = kBorder;
    self.layer.cornerRadius = 0;
    self.clipsToBounds      = YES;
    _expanded = YES;

    // scroll
    _scroll = [[UIScrollView alloc] initWithFrame:CGRectZero];
    _scroll.backgroundColor = [UIColor clearColor];
    _scroll.showsHorizontalScrollIndicator = NO;
    _scroll.showsVerticalScrollIndicator   = NO;
    _scroll.bounces = YES;
    [self addSubview:_scroll];

    // placeholder
    _placeholder = [[UILabel alloc] initWithFrame:CGRectZero];
    _placeholder.text          = @"— пусто —";
    _placeholder.textColor     = [UIColor colorWithWhite:1.f alpha:.22f];
    _placeholder.font          = [UIFont monospacedSystemFontOfSize:11.f
                                                             weight:UIFontWeightRegular];
    _placeholder.textAlignment = NSTextAlignmentCenter;
    [_scroll addSubview:_placeholder];

    // кнопка
    _btn = [[CrezToggleBtn alloc] initWithFrame:CGRectZero];
    __weak CrezBar *ws = self;
    _btn.action = ^{ [ws _toggle]; };
    [self addSubview:_btn];

    // drag — только по самой панели, не по scroll
    UIPanGestureRecognizer *pan =
        [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(_pan:)];
    pan.maximumNumberOfTouches = 1;
    [self addGestureRecognizer:pan];

    [self relayoutForBounds:wb];
    return self;
}

// вызывается при init и при каждом повороте
- (void)relayoutForBounds:(CGRect)wb {
    CGFloat h  = MenuH();
    CGFloat sw = wb.size.width - kMargin * 2.f;
    _fullWidth  = MIN(sw, kMaxW);
    CGFloat x  = kMargin + (sw - _fullWidth) * .5f;

    // сохраняем Y если уже позиционировали, иначе — верх
    CGFloat y = (self.frame.size.height > 0) ? self.frame.origin.y : kMargin;
    // clamp y
    y = MAX(kMargin, MIN(y, wb.size.height - h - kMargin));

    CGFloat curW = _expanded ? _fullWidth : kToggleW;
    self.frame = CGRectMake(x, y, curW, h);
    [self _applyInternalLayout];
}

- (void)_applyInternalLayout {
    CGFloat w = self.bounds.size.width;
    CGFloat h = self.bounds.size.height;
    _scroll.frame       = CGRectMake(0, 0, w - kToggleW, h);
    _placeholder.frame  = _scroll.bounds;
    _btn.frame          = CGRectMake(w - kToggleW, 0, kToggleW, h);
}

- (void)layoutSubviews {
    [super layoutSubviews];
    [self _applyInternalLayout];
}

// ── drag ──────────────────────────────────────────────────────────────────────
- (void)_pan:(UIPanGestureRecognizer *)gr {
    UIView *sv = self.superview;
    if (!sv) return;
    switch (gr.state) {
        case UIGestureRecognizerStateBegan:
            _dragStart   = [gr locationInView:sv];
            _originStart = self.frame.origin;
            break;
        case UIGestureRecognizerStateChanged: {
            CGPoint c = [gr locationInView:sv];
            CGRect  f = self.frame;
            f.origin.x = _originStart.x + (c.x - _dragStart.x);
            f.origin.y = _originStart.y + (c.y - _dragStart.y);
            CGFloat maxX = sv.bounds.size.width  - f.size.width  - kMargin;
            CGFloat maxY = sv.bounds.size.height - f.size.height - kMargin;
            f.origin.x = MAX(kMargin, MIN(f.origin.x, maxX));
            f.origin.y = MAX(kMargin, MIN(f.origin.y, maxY));
            self.frame = f;
            break;
        }
        default: break;
    }
}

// ── toggle ────────────────────────────────────────────────────────────────────
- (void)_toggle {
    _expanded = !_expanded;
    _btn.expanded = _expanded;

    UIView *sv = self.superview;
    CGFloat targetW = _expanded ? _fullWidth : kToggleW;

    // при открытии — clamp x чтобы не вылезло за экран
    CGRect f = self.frame;
    if (_expanded) {
        CGFloat maxX = sv.bounds.size.width - targetW - kMargin;
        f.origin.x = MAX(kMargin, MIN(f.origin.x, maxX));
    }
    f.size.width = targetW;

    [UIView animateWithDuration:.2f
                          delay:0
                        options:UIViewAnimationOptionCurveEaseInOut
                     animations:^{
        self.frame = f;
        self->_scroll.alpha = self->_expanded ? 1.f : 0.f;
    } completion:nil];
}

@end

// ── window ────────────────────────────────────────────────────────────────────
@implementation CrezMenuWindow

- (instancetype)init {
    self = [super initWithFrame:UIScreen.mainScreen.bounds];
    if (!self) return nil;
    self.windowLevel        = UIWindowLevelAlert + 100;
    self.backgroundColor    = [UIColor clearColor];
    self.rootViewController = [UIViewController new];
    self.rootViewController.view.backgroundColor = [UIColor clearColor];
    self.hidden = NO;

    _bar = [[CrezBar alloc] initWithBounds:UIScreen.mainScreen.bounds];
    [self.rootViewController.view addSubview:_bar];

    [[NSNotificationCenter defaultCenter]
        addObserver:self
           selector:@selector(_orientationChanged)
               name:UIApplicationDidChangeStatusBarOrientationNotification
             object:nil];
    return self;
}

- (void)_orientationChanged {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(.15f * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        CGRect wb = UIScreen.mainScreen.bounds;
        self.frame = wb;
        self.rootViewController.view.frame = wb;
        [self->_bar relayoutForBounds:wb];
    });
}

- (UIView *)hitTest:(CGPoint)p withEvent:(UIEvent *)e {
    UIView *hit = [super hitTest:p withEvent:e];
    return (hit == self || hit == self.rootViewController.view) ? nil : hit;
}

@end

// ── init ──────────────────────────────────────────────────────────────────────
static CrezMenuWindow *gWin;

__attribute__((constructor)) static void _init(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        gWin = [[CrezMenuWindow alloc] init];
    });
}
