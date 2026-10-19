#import <UIKit/UIKit.h>

// ── config ────────────────────────────────────────────────────────────────────
static const CGFloat kToggleW   = 32.f;
static const CGFloat kTabW      = 80.f;   // ширина одного таба каталога
static const CGFloat kDividerW  = 1.f;    // вертикальная черта между табами и контентом
static const CGFloat kBorder    = 1.5f;
static const CGFloat kMargin    = 10.f;
static const CGFloat kMaxW      = 480.f;

static NSArray<NSString *> *kTabs(void) {
    return @[@"Aim", @"Visuals"];
}

static CGFloat MenuH(void) {
    CGFloat s = MIN(UIScreen.mainScreen.bounds.size.width,
                    UIScreen.mainScreen.bounds.size.height);
    return MAX(44.f, MIN(s * 0.055f, 54.f));
}

static UIColor *BG(void)       { return [UIColor colorWithRed:.08f green:.08f blue:.08f alpha:.97f]; }
static UIColor *Accent(void)   { return [UIColor colorWithRed:1.f  green:.45f blue:.0f  alpha:1.f ]; }
static UIColor *TabBG(void)    { return [UIColor colorWithRed:.12f green:.12f blue:.12f alpha:1.f ]; }
static UIColor *TextDim(void)  { return [UIColor colorWithWhite:1.f alpha:.4f]; }
static UIColor *TextHot(void)  { return [UIColor whiteColor]; }
// ─────────────────────────────────────────────────────────────────────────────

@interface CrezBar : UIView
- (void)relayoutForBounds:(CGRect)wb;
@end
@interface CrezMenuWindow : UIWindow
@property (nonatomic, strong) CrezBar *bar;
@end

// ── ◀/▶ кнопка ───────────────────────────────────────────────────────────────
@interface CrezToggleBtn : UIControl
@property (nonatomic, assign) BOOL expanded;
@property (nonatomic, copy)   void (^action)(void);
@end
@implementation CrezToggleBtn
- (instancetype)initWithFrame:(CGRect)f {
    self = [super initWithFrame:f];
    self.backgroundColor = Accent();
    self.expanded = YES;
    [self addTarget:self action:@selector(_tap) forControlEvents:UIControlEventTouchUpInside];
    return self;
}
- (void)_tap { if (self.action) self.action(); }
- (void)setExpanded:(BOOL)v { _expanded = v; [self setNeedsDisplay]; }
- (void)drawRect:(CGRect)r {
    CGFloat cx = r.size.width*.5f, cy = r.size.height*.5f, aw = 5.f, ah = 8.f;
    UIBezierPath *p = [UIBezierPath new];
    if (_expanded) {
        [p moveToPoint:CGPointMake(cx+aw, cy-ah)];
        [p addLineToPoint:CGPointMake(cx-aw, cy)];
        [p addLineToPoint:CGPointMake(cx+aw, cy+ah)];
    } else {
        [p moveToPoint:CGPointMake(cx-aw, cy-ah)];
        [p addLineToPoint:CGPointMake(cx+aw, cy)];
        [p addLineToPoint:CGPointMake(cx-aw, cy+ah)];
    }
    [[UIColor whiteColor] setStroke];
    p.lineWidth = 2.f; p.lineCapStyle = kCGLineCapSquare;
    [p stroke];
}
@end

// ── таб каталога ──────────────────────────────────────────────────────────────
@interface CrezTabBtn : UIControl
@property (nonatomic, assign) BOOL active;
@property (nonatomic, copy)   NSString *title;
@property (nonatomic, copy)   void (^action)(void);
@end
@implementation CrezTabBtn {
    UILabel *_lbl;
    UIView  *_accent;   // нижняя/левая оранжевая черта
}
- (instancetype)initWithTitle:(NSString *)t {
    self = [super initWithFrame:CGRectZero];
    self.title = t;
    self.backgroundColor = [UIColor clearColor];

    _lbl = [[UILabel alloc] initWithFrame:CGRectZero];
    _lbl.text          = t;
    _lbl.textAlignment = NSTextAlignmentCenter;
    _lbl.font          = [UIFont systemFontOfSize:12.f weight:UIFontWeightSemibold];
    _lbl.textColor     = TextDim();
    [self addSubview:_lbl];

    // левая оранжевая черта (активный таб)
    _accent = [[UIView alloc] initWithFrame:CGRectZero];
    _accent.backgroundColor = Accent();
    _accent.hidden = YES;
    [self addSubview:_accent];

    [self addTarget:self action:@selector(_tap) forControlEvents:UIControlEventTouchUpInside];
    return self;
}
- (void)_tap { if (self.action) self.action(); }
- (void)setActive:(BOOL)v {
    _active = v;
    _lbl.textColor  = v ? TextHot() : TextDim();
    _accent.hidden  = !v;
}
- (void)layoutSubviews {
    [super layoutSubviews];
    _lbl.frame    = self.bounds;
    // левая вертикальная черта 3pt
    _accent.frame = CGRectMake(0, 4.f, 3.f, self.bounds.size.height - 8.f);
}
@end

// ── основная панель ───────────────────────────────────────────────────────────
@implementation CrezBar {
    CrezToggleBtn        *_toggle;
    NSMutableArray       *_tabs;      // CrezTabBtn[]
    UIView               *_divider;
    UIView               *_content;  // правая часть — будущие опции
    UILabel              *_empty;
    NSInteger             _activeTab;
    BOOL                  _expanded;
    CGFloat               _fullWidth;
    CGPoint               _dragStart;
    CGPoint               _originStart;
}

- (instancetype)initWithBounds:(CGRect)wb {
    self = [super initWithFrame:CGRectZero];
    if (!self) return nil;

    self.backgroundColor    = BG();
    self.layer.borderColor  = Accent().CGColor;
    self.layer.borderWidth  = kBorder;
    self.layer.cornerRadius = 0;
    self.clipsToBounds      = YES;
    _expanded  = YES;
    _activeTab = 0;

    // ── левая колонка табов ───────────────────────────────────────────────────
    NSArray *names = kTabs();
    _tabs = [NSMutableArray new];
    for (NSString *n in names) {
        CrezTabBtn *t = [[CrezTabBtn alloc] initWithTitle:n];
        NSInteger idx = [names indexOfObject:n];
        __weak CrezBar *ws = self;
        t.action = ^{ [ws _selectTab:idx]; };
        [self addSubview:t];
        [_tabs addObject:t];
    }
    ((CrezTabBtn *)_tabs[0]).active = YES;

    // ── разделитель ───────────────────────────────────────────────────────────
    _divider = [[UIView alloc] initWithFrame:CGRectZero];
    _divider.backgroundColor = [UIColor colorWithWhite:1.f alpha:.1f];
    [self addSubview:_divider];

    // ── контент (правая часть) ────────────────────────────────────────────────
    _content = [[UIView alloc] initWithFrame:CGRectZero];
    _content.backgroundColor = [UIColor clearColor];
    [self addSubview:_content];

    _empty = [[UILabel alloc] initWithFrame:CGRectZero];
    _empty.text          = @"— пусто —";
    _empty.textColor     = [UIColor colorWithWhite:1.f alpha:.18f];
    _empty.font          = [UIFont monospacedSystemFontOfSize:11.f weight:UIFontWeightRegular];
    _empty.textAlignment = NSTextAlignmentCenter;
    [_content addSubview:_empty];

    // ── кнопка скрыть ─────────────────────────────────────────────────────────
    _toggle = [[CrezToggleBtn alloc] initWithFrame:CGRectZero];
    __weak CrezBar *ws = self;
    _toggle.action = ^{ [ws _toggleVisibility]; };
    [self addSubview:_toggle];

    // drag
    UIPanGestureRecognizer *pan =
        [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(_pan:)];
    pan.maximumNumberOfTouches = 1;
    [self addGestureRecognizer:pan];

    [self relayoutForBounds:wb];
    return self;
}

- (void)_selectTab:(NSInteger)idx {
    _activeTab = idx;
    for (NSInteger i = 0; i < (NSInteger)_tabs.count; i++)
        ((CrezTabBtn *)_tabs[i]).active = (i == idx);
    // здесь будет переключение контента
}

// ── layout ────────────────────────────────────────────────────────────────────
- (void)relayoutForBounds:(CGRect)wb {
    CGFloat h  = MenuH();
    CGFloat sw = wb.size.width - kMargin * 2.f;
    _fullWidth  = MIN(sw, kMaxW);
    CGFloat x  = kMargin + (sw - _fullWidth) * .5f;
    CGFloat y  = (self.frame.size.height > 0) ? self.frame.origin.y : kMargin;
    y = MAX(kMargin, MIN(y, wb.size.height - h - kMargin));
    CGFloat curW = _expanded ? _fullWidth : kToggleW;
    self.frame = CGRectMake(x, y, curW, h);
    [self _applyLayout];
}

- (void)_applyLayout {
    CGFloat w = self.bounds.size.width;
    CGFloat h = self.bounds.size.height;
    NSInteger n = (NSInteger)_tabs.count;

    // ширина левой колонки = n * kTabW, но не больше 40% панели
    CGFloat tabsAreaW = MIN(n * kTabW, w * .4f);
    CGFloat tabW      = (n > 0) ? tabsAreaW / n : kTabW;

    for (NSInteger i = 0; i < n; i++) {
        UIView *t = _tabs[i];
        t.frame = CGRectMake(i * tabW, 0, tabW, h);
        t.hidden = !_expanded;
    }

    _divider.frame  = CGRectMake(tabsAreaW, 0, kDividerW, h);
    _divider.hidden = !_expanded;

    CGFloat contentX = tabsAreaW + kDividerW;
    CGFloat contentW = MAX(0, w - contentX - kToggleW);
    _content.frame   = CGRectMake(contentX, 0, contentW, h);
    _content.hidden  = !_expanded;
    _empty.frame     = _content.bounds;

    _toggle.frame    = CGRectMake(w - kToggleW, 0, kToggleW, h);
}

- (void)layoutSubviews {
    [super layoutSubviews];
    [self _applyLayout];
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
- (void)_toggleVisibility {
    _expanded = !_expanded;
    _toggle.expanded = _expanded;

    UIView *sv = self.superview;
    CGFloat targetW = _expanded ? _fullWidth : kToggleW;
    CGRect f = self.frame;
    if (_expanded) {
        CGFloat maxX = sv.bounds.size.width - targetW - kMargin;
        f.origin.x = MAX(kMargin, MIN(f.origin.x, maxX));
    }
    f.size.width = targetW;

    [UIView animateWithDuration:.2f delay:0
                        options:UIViewAnimationOptionCurveEaseInOut
                     animations:^{
        self.frame = f;
        [self _applyLayout];
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
