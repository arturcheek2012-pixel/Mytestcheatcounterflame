#import <UIKit/UIKit.h>

// ── config ────────────────────────────────────────────────────────────────────
static const CGFloat kMenuHeight   = 52.f;
static const CGFloat kToggleWidth  = 34.f;
static const CGFloat kCornerRadius = 0.f;   // острые углы
static const UIEdgeInsets kSafeMargin = {8, 8, 8, 8};

static UIColor *kColorBG()     { return [UIColor colorWithRed:.08f green:.08f blue:.08f alpha:.96f]; }
static UIColor *kColorAccent() { return [UIColor colorWithRed:1.f  green:.45f blue:.0f  alpha:1.f ]; }
static UIColor *kColorText()   { return [UIColor whiteColor]; }
// ─────────────────────────────────────────────────────────────────────────────

@interface CrezMenuWindow : UIWindow
@end

@interface CrezMenuController : UIViewController
@end

// ── toggle tab (торчит сбоку когда меню скрыто) ──────────────────────────────
@interface CrezToggleTab : UIControl
@property (nonatomic, assign) BOOL menuVisible;
@property (nonatomic, copy)   void (^onTap)(void);
@end

@implementation CrezToggleTab

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (!self) return nil;
    self.backgroundColor = kColorAccent();
    self.layer.cornerRadius = 0;
    self.menuVisible = YES;
    [self addTarget:self action:@selector(_tapped) forControlEvents:UIControlEventTouchUpInside];
    return self;
}

- (void)_tapped { if (self.onTap) self.onTap(); }

- (void)drawRect:(CGRect)rect {
    [super drawRect:rect];
    // стрелка
    UIBezierPath *p = [UIBezierPath new];
    CGFloat cx = rect.size.width  * .5f;
    CGFloat cy = rect.size.height * .5f;
    CGFloat aw = 6.f, ah = 9.f;
    if (self.menuVisible) {
        // ◀  (скрыть)
        [p moveToPoint:    CGPointMake(cx + aw, cy - ah)];
        [p addLineToPoint: CGPointMake(cx - aw, cy)];
        [p addLineToPoint: CGPointMake(cx + aw, cy + ah)];
    } else {
        // ▶  (показать)
        [p moveToPoint:    CGPointMake(cx - aw, cy - ah)];
        [p addLineToPoint: CGPointMake(cx + aw, cy)];
        [p addLineToPoint: CGPointMake(cx - aw, cy + ah)];
    }
    [kColorText() setStroke];
    p.lineWidth    = 2.f;
    p.lineCapStyle = kCGLineCapSquare;
    [p stroke];
}

- (void)setMenuVisible:(BOOL)v {
    _menuVisible = v;
    [self setNeedsDisplay];
}

@end

// ── основная панель ───────────────────────────────────────────────────────────
@interface CrezMenuBar : UIView
@property (nonatomic, strong) CrezToggleTab *toggleTab;
@property (nonatomic, strong) UIScrollView  *itemsScroll;
@property (nonatomic, assign) BOOL           menuVisible;
@end

@implementation CrezMenuBar {
    CGPoint _dragStart;
    CGPoint _originStart;
}

- (instancetype)initWithScreenSize:(CGSize)screen {
    CGFloat w = screen.width - kSafeMargin.left - kSafeMargin.right;
    CGFloat y = kSafeMargin.top;
    self = [super initWithFrame:CGRectMake(kSafeMargin.left, y, w, kMenuHeight)];
    if (!self) return nil;

    self.backgroundColor    = kColorBG();
    self.layer.cornerRadius = kCornerRadius;
    self.layer.borderColor  = kColorAccent().CGColor;
    self.layer.borderWidth  = 1.5f;
    self.clipsToBounds      = YES;
    self.menuVisible        = YES;

    // scroll-область для будущих кнопок
    _itemsScroll = [[UIScrollView alloc] initWithFrame:
                    CGRectMake(0, 0, w - kToggleWidth, kMenuHeight)];
    _itemsScroll.backgroundColor       = [UIColor clearColor];
    _itemsScroll.showsHorizontalScrollIndicator = NO;
    _itemsScroll.showsVerticalScrollIndicator   = NO;
    _itemsScroll.bounces = YES;
    [self addSubview:_itemsScroll];

    // заглушка "пусто"
    UILabel *placeholder = [[UILabel alloc] initWithFrame:_itemsScroll.bounds];
    placeholder.text          = @"— меню пусто —";
    placeholder.textColor     = [UIColor colorWithWhite:1.f alpha:.25f];
    placeholder.font          = [UIFont monospacedSystemFontOfSize:12.f weight:UIFontWeightRegular];
    placeholder.textAlignment = NSTextAlignmentCenter;
    [_itemsScroll addSubview:placeholder];

    // toggle-таб
    _toggleTab = [[CrezToggleTab alloc] initWithFrame:
                  CGRectMake(w - kToggleWidth, 0, kToggleWidth, kMenuHeight)];
    __weak typeof(self) ws = self;
    _toggleTab.onTap = ^{ [ws _toggleVisibility]; };
    [self addSubview:_toggleTab];

    // drag
    UIPanGestureRecognizer *pan =
        [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(_pan:)];
    pan.maximumNumberOfTouches = 1;
    [self addGestureRecognizer:pan];

    return self;
}

// ── drag ─────────────────────────────────────────────────────────────────────
- (void)_pan:(UIPanGestureRecognizer *)gr {
    UIView *sv = self.superview;
    if (!sv) return;

    switch (gr.state) {
        case UIGestureRecognizerStateBegan:
            _dragStart  = [gr locationInView:sv];
            _originStart = self.frame.origin;
            break;
        case UIGestureRecognizerStateChanged: {
            CGPoint cur   = [gr locationInView:sv];
            CGFloat dx    = cur.x - _dragStart.x;
            CGFloat dy    = cur.y - _dragStart.y;
            CGRect  frame = self.frame;
            frame.origin.x = _originStart.x + dx;
            frame.origin.y = _originStart.y + dy;
            // clamp внутрь экрана
            CGFloat maxX = sv.bounds.size.width  - frame.size.width  - kSafeMargin.right;
            CGFloat maxY = sv.bounds.size.height - frame.size.height - kSafeMargin.bottom;
            frame.origin.x = MAX(kSafeMargin.left, MIN(frame.origin.x, maxX));
            frame.origin.y = MAX(kSafeMargin.top,  MIN(frame.origin.y, maxY));
            self.frame = frame;
            break;
        }
        default: break;
    }
}

// ── toggle ────────────────────────────────────────────────────────────────────
- (void)_toggleVisibility {
    _menuVisible = !_menuVisible;
    _toggleTab.menuVisible = _menuVisible;

    [UIView animateWithDuration:.22f
                          delay:0
                        options:UIViewAnimationOptionCurveEaseInOut
                     animations:^{
        if (self->_menuVisible) {
            // полная ширина
            CGRect f = self.frame;
            UIView *sv = self.superview;
            f.size.width = sv.bounds.size.width
                         - kSafeMargin.left - kSafeMargin.right;
            // clamp x
            CGFloat maxX = sv.bounds.size.width - f.size.width - kSafeMargin.right;
            f.origin.x = MAX(kSafeMargin.left, MIN(f.origin.x, maxX));
            self.frame = f;
            self->_itemsScroll.alpha = 1.f;
        } else {
            // схлопнуть до ширины таба
            CGRect f = self.frame;
            f.size.width = kToggleWidth;
            self.frame   = f;
            self->_itemsScroll.alpha = 0.f;
        }
        // перепозиционировать таб внутри
        CGRect tf = self->_toggleTab.frame;
        tf.origin.x = self.bounds.size.width - kToggleWidth;
        self->_toggleTab.frame = tf;
    } completion:nil];
}

// при изменении bounds двигаем таб и scroll
- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat w = self.bounds.size.width;
    _itemsScroll.frame = CGRectMake(0, 0, w - kToggleWidth, kMenuHeight);
    _toggleTab.frame   = CGRectMake(w - kToggleWidth, 0, kToggleWidth, kMenuHeight);
}

@end

// ── window / controller ───────────────────────────────────────────────────────
@implementation CrezMenuController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor clearColor];

    CGSize screen = UIScreen.mainScreen.bounds.size;
    CrezMenuBar *bar = [[CrezMenuBar alloc] initWithScreenSize:screen];
    [self.view addSubview:bar];
}

@end

@implementation CrezMenuWindow

- (instancetype)init {
    self = [super initWithFrame:UIScreen.mainScreen.bounds];
    if (!self) return nil;
    self.windowLevel              = UIWindowLevelAlert + 100;
    self.backgroundColor          = [UIColor clearColor];
    self.rootViewController       = [CrezMenuController new];
    self.hidden                   = NO;
    return self;
}

// передаём тачи сквозь прозрачные зоны
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *hit = [super hitTest:point withEvent:event];
    return (hit == self || hit == self.rootViewController.view) ? nil : hit;
}

@end

// ── inject ────────────────────────────────────────────────────────────────────
static CrezMenuWindow *gMenuWindow;

static void _spawnMenu() {
    dispatch_async(dispatch_get_main_queue(), ^{
        gMenuWindow = [[CrezMenuWindow alloc] init];
    });
}

%ctor {
    _spawnMenu();
}
