// inject: DYLD_INSERT_LIBRARIES / Live Container
// toggle: hide → плавающая пилюля → тап → меню обратно

#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>

static const CGFloat kW   = 260.0f;
static const CGFloat kH   = 360.0f;
static const CGFloat kHdr = 42.0f;
static const CGFloat kR   = 12.0f;
static const NSTimeInterval kDur = 0.20;

static inline UIColor* C(CGFloat r, CGFloat g, CGFloat b, CGFloat a) {
    return [UIColor colorWithRed:r green:g blue:b alpha:a];
}

// ─── pill toggle button (показывается когда меню скрыто) ─────────────────────
@interface PillButton : UIView
@property (copy) dispatch_block_t action;
@end

@implementation PillButton {
    CGPoint _dragOffset;
    BOOL    _dragging;
}

- (instancetype)init {
    self = [super initWithFrame:CGRectMake(20, 120, 44, 28)];
    self.backgroundColor = C(0.10f, 0.10f, 0.13f, 0.92f);
    self.layer.cornerRadius = 14;
    self.layer.borderColor  = C(0.27f, 0.52f, 1.00f, 0.45f).CGColor;
    self.layer.borderWidth  = 1.0f;

    UILabel* lbl = [[UILabel alloc] initWithFrame:self.bounds];
    lbl.text          = @"☰";
    lbl.textAlignment = NSTextAlignmentCenter;
    lbl.font          = [UIFont systemFontOfSize:13];
    lbl.textColor     = C(0.75f, 0.75f, 0.80f, 1.0f);
    [self addSubview:lbl];

    UIPanGestureRecognizer* pan = [[UIPanGestureRecognizer alloc]
        initWithTarget:self action:@selector(pan:)];
    [self addGestureRecognizer:pan];
    return self;
}

- (void)pan:(UIPanGestureRecognizer*)g {
    CGPoint loc = [g locationInView:self.superview];
    if (g.state == UIGestureRecognizerStateBegan) {
        _dragging = YES;
        _dragOffset = CGPointMake(loc.x - self.frame.origin.x,
                                  loc.y - self.frame.origin.y);
    } else if (g.state == UIGestureRecognizerStateChanged) {
        CGRect f = self.frame;
        f.origin = CGPointMake(loc.x - _dragOffset.x,
                               loc.y - _dragOffset.y);
        self.frame = f;
    } else {
        _dragging = NO;
    }
}

- (void)touchesEnded:(NSSet*)t withEvent:(UIEvent*)e {
    if (!_dragging && _action) _action();
}

@end

// ─── MenuView ─────────────────────────────────────────────────────────────────
@interface MenuView : UIView
@property (strong) UIButton* hideBtn;
@property (strong) UIButton* closeBtn;
@end

@implementation MenuView {
    UIView* _hdrView;
    CGPoint _dragOffset;
}

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    self.backgroundColor       = C(0.07f, 0.07f, 0.09f, 0.93f);
    self.layer.cornerRadius    = kR;
    self.layer.masksToBounds   = YES;

    // header
    _hdrView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, kW, kHdr)];
    _hdrView.backgroundColor = C(0.10f, 0.10f, 0.13f, 1.0f);
    [self addSubview:_hdrView];

    // accent line
    UIView* line = [[UIView alloc] initWithFrame:CGRectMake(0, kHdr - 1, kW, 1)];
    line.backgroundColor = C(0.27f, 0.52f, 1.00f, 0.55f);
    [self addSubview:line];

    // title
    UILabel* title = [[UILabel alloc] initWithFrame:CGRectMake(0, (kHdr-17)*.5f, kW, 17)];
    title.text          = @"Cheat Menu";
    title.font          = [UIFont systemFontOfSize:13 weight:UIFontWeightSemibold];
    title.textColor     = C(0.92f, 0.92f, 0.95f, 1.0f);
    title.textAlignment = NSTextAlignmentCenter;
    [self addSubview:title];

    // row dividers
    for (int i = 0; i < 5; i++) {
        UIView* d = [[UIView alloc] initWithFrame:CGRectMake(14, kHdr+20+i*44, kW-28, 1)];
        d.backgroundColor = C(0.14f, 0.14f, 0.17f, 1.0f);
        [self addSubview:d];
    }

    // empty hint
    UILabel* hint = [[UILabel alloc] initWithFrame:CGRectMake(0, kH*.5f-7, kW, 14)];
    hint.text          = @"// no features loaded";
    hint.font          = [UIFont monospacedSystemFontOfSize:10.5 weight:UIFontWeightRegular];
    hint.textColor     = C(0.32f, 0.32f, 0.38f, 1.0f);
    hint.textAlignment = NSTextAlignmentCenter;
    [self addSubview:hint];

    // border (не clip'ится layer'ом, рисуем сверху)
    CALayer* border = [CALayer layer];
    border.frame       = CGRectMake(0, 0, kW, kH);
    border.borderColor = C(0.22f, 0.22f, 0.28f, 0.65f).CGColor;
    border.borderWidth = 1.0f;
    border.cornerRadius = kR;
    [self.layer addSublayer:border];

    // кнопки в хедере
    self.hideBtn  = [self makeHdrBtn:@"−" x:kW-58 bg:C(0.28f,0.28f,0.36f,1)];
    self.closeBtn = [self makeHdrBtn:@"×" x:kW-30 bg:C(0.80f,0.22f,0.22f,1)];

    // drag только за хедер
    UIPanGestureRecognizer* pan = [[UIPanGestureRecognizer alloc]
        initWithTarget:self action:@selector(pan:)];
    [_hdrView addGestureRecognizer:pan];

    return self;
}

- (UIButton*)makeHdrBtn:(NSString*)g x:(CGFloat)x bg:(UIColor*)bg {
    UIButton* btn = [UIButton buttonWithType:UIButtonTypeCustom];
    btn.frame = CGRectMake(x, (kHdr-24)*.5f, 24, 24);
    btn.layer.cornerRadius  = 12;
    btn.layer.masksToBounds = YES;
    [btn setTitle:g forState:UIControlStateNormal];
    btn.titleLabel.font = [UIFont systemFontOfSize:11 weight:UIFontWeightMedium];
    [btn setTitleColor:C(0.55f,0.55f,0.60f,1) forState:UIControlStateNormal];
    [btn setTitleColor:[UIColor whiteColor]     forState:UIControlStateHighlighted];
    btn.backgroundColor = C(0.17f,0.17f,0.21f,1);
    [btn addTarget:self action:@selector(btnDown:) forControlEvents:UIControlEventTouchDown];
    [btn addTarget:self action:@selector(btnUp:)   forControlEvents:UIControlEventTouchUpInside|UIControlEventTouchUpOutside];
    // тег: сохраняем hover-цвет через tag → не будем, просто animation
    [self addSubview:btn];
    return btn;
}

- (void)btnDown:(UIButton*)b {
    [UIView animateWithDuration:0.08 animations:^{ b.backgroundColor = C(0.28f,0.28f,0.36f,1); }];
}
- (void)btnUp:(UIButton*)b {
    [UIView animateWithDuration:0.12 animations:^{ b.backgroundColor = C(0.17f,0.17f,0.21f,1); }];
}

- (void)pan:(UIPanGestureRecognizer*)g {
    CGPoint loc = [g locationInView:self.superview];
    if (g.state == UIGestureRecognizerStateBegan)
        _dragOffset = CGPointMake(loc.x - self.frame.origin.x,
                                  loc.y - self.frame.origin.y);
    else if (g.state == UIGestureRecognizerStateChanged) {
        CGRect f = self.frame;
        f.origin = CGPointMake(loc.x - _dragOffset.x,
                               loc.y - _dragOffset.y);
        self.frame = f;
    }
}

@end

// ─── Controller ───────────────────────────────────────────────────────────────
@interface CheatController : NSObject
+ (instancetype)shared;
- (void)toggle;
@end

@implementation CheatController {
    UIWindow*   _win;
    MenuView*   _menu;
    PillButton* _pill;
    BOOL        _visible;
}

+ (instancetype)shared {
    static CheatController* i;
    static dispatch_once_t t;
    dispatch_once(&t, ^{ i = [CheatController new]; });
    return i;
}

- (instancetype)init {
    self = [super init];
    [self build];
    return self;
}

- (void)build {
    UIWindowScene* scene = nil;
    for (UIScene* s in [UIApplication sharedApplication].connectedScenes)
        if ([s isKindOfClass:[UIWindowScene class]]) { scene = (UIWindowScene*)s; break; }

    _win = scene ? [[UIWindow alloc] initWithWindowScene:scene]
                 : [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
    _win.windowLevel      = UIWindowLevelAlert + 200;
    _win.backgroundColor  = [UIColor clearColor];

    UIViewController* vc  = [UIViewController new];
    vc.view.backgroundColor = [UIColor clearColor];
    _win.rootViewController = vc;
    [_win makeKeyAndVisible];

    CGSize sz = [UIScreen mainScreen].bounds.size;
    _menu = [[MenuView alloc] initWithFrame:
        CGRectMake((sz.width-kW)*.5f, (sz.height-kH)*.5f, kW, kH)];
    [vc.view addSubview:_menu];

    [_menu.hideBtn  addTarget:self action:@selector(doHide)  forControlEvents:UIControlEventTouchUpInside];
    [_menu.closeBtn addTarget:self action:@selector(doClose) forControlEvents:UIControlEventTouchUpInside];

    __weak typeof(self) ws = self;
    _pill = [PillButton new];
    _pill.action = ^{ [ws doShow]; };
    _pill.hidden = YES;
    [vc.view addSubview:_pill];
}

- (void)doShow {
    _pill.hidden = YES;
    _menu.alpha     = 0;
    _menu.transform = CGAffineTransformMakeScale(0.88f, 0.88f);
    _menu.hidden    = NO;
    [UIView animateWithDuration:kDur delay:0
                        options:UIViewAnimationOptionCurveEaseOut
                     animations:^{
        self->_menu.alpha     = 1;
        self->_menu.transform = CGAffineTransformIdentity;
    } completion:nil];
    _visible = YES;
}

- (void)doHide {
    [UIView animateWithDuration:kDur delay:0
                        options:UIViewAnimationOptionCurveEaseIn
                     animations:^{
        self->_menu.alpha     = 0;
        self->_menu.transform = CGAffineTransformMakeScale(0.94f, 0.94f);
    } completion:^(BOOL _) {
        self->_menu.hidden    = YES;
        self->_menu.transform = CGAffineTransformIdentity;
        self->_pill.hidden    = NO;
        self->_visible        = NO;
    }];
}

- (void)doClose {
    [UIView animateWithDuration:kDur delay:0
                        options:UIViewAnimationOptionCurveEaseIn
                     animations:^{
        self->_menu.alpha     = 0;
        self->_menu.transform = CGAffineTransformMakeScale(0.88f, 0.88f);
    } completion:^(BOOL _) {
        self->_menu.hidden    = YES;
        self->_menu.transform = CGAffineTransformIdentity;
        self->_pill.hidden    = NO;
        self->_visible        = NO;
    }];
}

- (void)toggle {
    _visible ? [self doHide] : [self doShow];
}

@end

// ─── entry ────────────────────────────────────────────────────────────────────
__attribute__((constructor))
static void Init(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0*NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            [[CheatController shared] toggle];
        });
    });
}
