#import <UIKit/UIKit.h>
#import <dobby.h>
#include <mach/mach.h>
#include <sys/mman.h>

// ═══════════════════════════════════════════════════════════════════════════════
// OFFSETS — CounterFlame / base: 0x112a70000
// ═══════════════════════════════════════════════════════════════════════════════
#define OFF_PC_VIEW         0x80    // _view  → PhotonView*
#define OFF_PC_IS_DEATH     0xA8    // bool
#define OFF_PV_IS_MINE      0x60    // bool <IsMine>k__BackingField
#define RVA_GET_TRANSFORM   0x2BAA1E8
#define RVA_GET_POSITION    0x2BB4894
#define RVA_W2S             0x2B73E5C
#define RVA_CAM_MAIN        0x2B741F0
#define BASE                0x112a70000ULL

// ═══════════════════════════════════════════════════════════════════════════════
// memory helpers
// ═══════════════════════════════════════════════════════════════════════════════
static inline uint64_t ReadU64(uint64_t addr) {
    if (addr < 0x1000) return 0;
    return *(volatile uint64_t *)addr;
}
static inline bool ReadBool(uint64_t addr) {
    if (addr < 0x1000) return false;
    return *(volatile uint8_t *)addr != 0;
}

// ═══════════════════════════════════════════════════════════════════════════════
// Unity typedefs
// ═══════════════════════════════════════════════════════════════════════════════
typedef struct { float x, y, z; } Vec3;

typedef uint64_t (*fn_get_transform_t)(uint64_t component, void *method);
typedef Vec3     (*fn_get_position_t) (uint64_t transform,  void *method);
typedef Vec3     (*fn_w2s_t)          (uint64_t camera, Vec3 worldPos, int32_t eye, void *method);
typedef uint64_t (*fn_cam_main_t)     (void *method);

static fn_get_transform_t fn_get_transform;
static fn_get_position_t  fn_get_position;
static fn_w2s_t           fn_w2s;
static fn_cam_main_t      fn_cam_main;

static void _resolveRVAs(void) {
    fn_get_transform = (fn_get_transform_t)(BASE + RVA_GET_TRANSFORM);
    fn_get_position  = (fn_get_position_t) (BASE + RVA_GET_POSITION);
    fn_w2s           = (fn_w2s_t)          (BASE + RVA_W2S);
    fn_cam_main      = (fn_cam_main_t)     (BASE + RVA_CAM_MAIN);
}

// ═══════════════════════════════════════════════════════════════════════════════
// PlayerController cache — Dobby hooks
// ═══════════════════════════════════════════════════════════════════════════════
static NSMutableArray *gPlayerControllers;

typedef void (*fn_pc_awake_t)  (uint64_t self, void *method);
typedef void (*fn_pc_destroy_t)(uint64_t self, void *method);
static fn_pc_awake_t   orig_pc_awake;
static fn_pc_destroy_t orig_pc_destroy;

static void hook_pc_awake(uint64_t self, void *method) {
    orig_pc_awake(self, method);
    dispatch_async(dispatch_get_main_queue(), ^{
        NSValue *v = [NSValue valueWithBytes:&self objCType:@encode(uint64_t)];
        if (![gPlayerControllers containsObject:v]) [gPlayerControllers addObject:v];
    });
}

static void hook_pc_destroy(uint64_t self, void *method) {
    dispatch_async(dispatch_get_main_queue(), ^{
        NSValue *v = [NSValue valueWithBytes:&self objCType:@encode(uint64_t)];
        [gPlayerControllers removeObject:v];
    });
    orig_pc_destroy(self, method);
}

// ═══════════════════════════════════════════════════════════════════════════════
// w2s
// ═══════════════════════════════════════════════════════════════════════════════
static BOOL w2s(uint64_t cam, Vec3 worldPos, CGPoint *out) {
    if (!cam || !fn_w2s) return NO;
    Vec3 sp = fn_w2s(cam, worldPos, 0, nil);
    if (sp.z <= 0.f) return NO;
    CGSize screen = UIScreen.mainScreen.bounds.size;
    out->x = sp.x;
    out->y = screen.height - sp.y;  // Unity Y снизу → UIKit Y сверху
    return YES;
}

// ═══════════════════════════════════════════════════════════════════════════════
// ESP state
// ═══════════════════════════════════════════════════════════════════════════════
static BOOL g_espOn = NO;

// ═══════════════════════════════════════════════════════════════════════════════
// CrezESPView
// ═══════════════════════════════════════════════════════════════════════════════
@interface CrezESPView : UIView @end
@implementation CrezESPView

- (instancetype)init {
    self = [super initWithFrame:UIScreen.mainScreen.bounds];
    self.backgroundColor = [UIColor clearColor];
    self.userInteractionEnabled = NO;
    return self;
}

- (void)drawRect:(CGRect)r {
    if (!g_espOn) return;
    CGContextRef ctx = UIGraphicsGetCurrentContext(); if (!ctx) return;
    if (!fn_cam_main || !fn_get_transform || !fn_get_position || !fn_w2s) return;

    uint64_t cam = fn_cam_main(nil); if (!cam) return;

    for (NSValue *v in [gPlayerControllers copy]) {
        uint64_t pc = 0; [v getValue:&pc]; if (!pc) continue;
        if (ReadBool(pc + OFF_PC_IS_DEATH)) continue;
        uint64_t pv = ReadU64(pc + OFF_PC_VIEW);
        if (pv && ReadBool(pv + OFF_PV_IS_MINE)) continue;

        uint64_t tfm = fn_get_transform(pc, nil); if (!tfm) continue;
        Vec3 pos = fn_get_position(tfm, nil);
        Vec3 top = { pos.x, pos.y + 1.8f, pos.z };

        CGPoint scBot, scTop;
        if (!w2s(cam, pos, &scBot)) continue;
        if (!w2s(cam, top, &scTop)) continue;

        CGFloat bh = scBot.y - scTop.y; if (bh < 4.f) continue;
        CGFloat bw = bh * 0.45f;
        CGFloat bx = scBot.x - bw * .5f;
        CGRect  box = CGRectMake(bx, scTop.y, bw, bh);

        // тень
        CGContextSetRGBStrokeColor(ctx, 0, 0, 0, 0.65f);
        CGContextSetLineWidth(ctx, 2.5f);
        CGContextStrokeRect(ctx, CGRectInset(box, -0.5f, -0.5f));

        // зелёный бокс
        CGContextSetRGBStrokeColor(ctx, 0.12f, 0.95f, 0.32f, 0.95f);
        CGContextSetLineWidth(ctx, 1.5f);
        CGContextStrokeRect(ctx, box);

        // синий акцент — верхняя линия (совпадает с акцентом меню)
        CGContextSetRGBStrokeColor(ctx, 0.27f, 0.52f, 1.0f, 0.90f);
        CGContextSetLineWidth(ctx, 2.0f);
        CGContextMoveToPoint(ctx, bx, scTop.y);
        CGContextAddLineToPoint(ctx, bx + bw, scTop.y);
        CGContextStrokePath(ctx);
    }
}
@end

// ═══════════════════════════════════════════════════════════════════════════════
// UI constants & color helper
// ═══════════════════════════════════════════════════════════════════════════════
static inline UIColor *C(CGFloat r, CGFloat g, CGFloat b, CGFloat a) {
    return [UIColor colorWithRed:r green:g blue:b alpha:a];
}

static const CGFloat kMenuW = 260.f;
static const CGFloat kMenuH = 158.f;  // header 42 + gap 14 + card 88 + gap 14
static const CGFloat kHdr   = 42.f;
static const CGFloat kR     = 12.f;
static const NSTimeInterval kDur = 0.22;

// ═══════════════════════════════════════════════════════════════════════════════
// PillButton — показывается когда меню спрятано
// ═══════════════════════════════════════════════════════════════════════════════
@interface PillButton : UIView
@property (copy) dispatch_block_t action;
@end
@implementation PillButton { CGPoint _off; BOOL _moved; }
- (instancetype)init {
    self = [super initWithFrame:CGRectMake(20, 120, 44, 28)];
    self.backgroundColor    = C(0.10f, 0.10f, 0.13f, 0.92f);
    self.layer.cornerRadius = 14;
    self.layer.borderColor  = C(0.27f, 0.52f, 1.00f, 0.45f).CGColor;
    self.layer.borderWidth  = 1;
    UILabel *l = [[UILabel alloc] initWithFrame:self.bounds];
    l.text = @"☰"; l.textAlignment = NSTextAlignmentCenter;
    l.font = [UIFont systemFontOfSize:13]; l.textColor = C(0.75f, 0.75f, 0.80f, 1);
    [self addSubview:l];
    [self addGestureRecognizer:[[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(pan:)]];
    return self;
}
- (void)pan:(UIPanGestureRecognizer *)g {
    CGPoint loc = [g locationInView:self.superview];
    if (g.state == UIGestureRecognizerStateBegan) {
        _moved = NO;
        _off = CGPointMake(loc.x - self.frame.origin.x, loc.y - self.frame.origin.y);
    } else if (g.state == UIGestureRecognizerStateChanged) {
        _moved = YES;
        CGRect f = self.frame;
        f.origin = CGPointMake(loc.x - _off.x, loc.y - _off.y);
        self.frame = f;
    }
}
- (void)touchesEnded:(NSSet *)t withEvent:(UIEvent *)e {
    if (!_moved && _action) _action();
}
@end

// ═══════════════════════════════════════════════════════════════════════════════
// CrezToggle — кастомный свич с синим акцентом
// ═══════════════════════════════════════════════════════════════════════════════
@interface CrezToggle : UIControl
@property (nonatomic, assign) BOOL on;
@property (nonatomic, copy)   void (^onChange)(BOOL);
@end
@implementation CrezToggle { UIView *_track, *_thumb; }
- (instancetype)init {
    self = [super initWithFrame:CGRectMake(0, 0, 44, 24)];
    _track = [[UIView alloc] initWithFrame:self.bounds];
    _track.layer.cornerRadius = 12.f;
    _track.backgroundColor = C(0.25f, 0.25f, 0.30f, 1);
    [self addSubview:_track];
    _thumb = [[UIView alloc] initWithFrame:CGRectMake(2, 2, 20, 20)];
    _thumb.layer.cornerRadius = 10.f;
    _thumb.backgroundColor = [UIColor whiteColor];
    [self addSubview:_thumb];
    [self addTarget:self action:@selector(_tap) forControlEvents:UIControlEventTouchUpInside];
    return self;
}
- (void)_tap {
    self.on = !self.on;
    [UIView animateWithDuration:.18f animations:^{
        self->_thumb.frame = self.on ? CGRectMake(22,2,20,20) : CGRectMake(2,2,20,20);
        self->_track.backgroundColor = self.on
            ? C(0.27f, 0.52f, 1.00f, 1) : C(0.25f, 0.25f, 0.30f, 1);
    }];
    if (self.onChange) self.onChange(self.on);
}
@end

// ═══════════════════════════════════════════════════════════════════════════════
// MenuView
// ═══════════════════════════════════════════════════════════════════════════════
@interface MenuView : UIView
@property (strong) UIButton    *hideBtn;
@property (strong) CrezToggle  *espToggle;
@property (strong) UILabel     *espStatus;
@end
@implementation MenuView { CGPoint _drag; }

- (instancetype)initWithFrame:(CGRect)f {
    self = [super initWithFrame:f];
    self.backgroundColor    = C(0.07f, 0.07f, 0.09f, 0.93f);
    self.layer.cornerRadius = kR;
    self.layer.masksToBounds = YES;

    // ── header ────────────────────────────────────────────────────────────────
    UIView *hdr = [[UIView alloc] initWithFrame:CGRectMake(0, 0, kMenuW, kHdr)];
    hdr.backgroundColor = C(0.10f, 0.10f, 0.13f, 1);
    [self addSubview:hdr];

    // синяя линия под хедером
    UIView *acc = [[UIView alloc] initWithFrame:CGRectMake(0, kHdr-1, kMenuW, 1)];
    acc.backgroundColor = C(0.27f, 0.52f, 1.00f, 0.55f);
    [self addSubview:acc];

    UILabel *ttl = [[UILabel alloc] initWithFrame:CGRectMake(0, (kHdr-17)*.5f, kMenuW, 17)];
    ttl.text = @"☰  Cheat Menu";
    ttl.textAlignment = NSTextAlignmentCenter;
    ttl.font = [UIFont systemFontOfSize:13 weight:UIFontWeightSemibold];
    ttl.textColor = C(0.92f, 0.92f, 0.95f, 1);
    [self addSubview:ttl];

    // drag по хедеру
    [hdr addGestureRecognizer:[[UIPanGestureRecognizer alloc]
        initWithTarget:self action:@selector(pan:)]];

    // кнопка −
    self.hideBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    self.hideBtn.frame = CGRectMake(kMenuW-30, (kHdr-24)*.5f, 24, 24);
    self.hideBtn.layer.cornerRadius = 12;
    self.hideBtn.layer.masksToBounds = YES;
    self.hideBtn.backgroundColor = C(0.17f, 0.17f, 0.21f, 1);
    self.hideBtn.titleLabel.font = [UIFont systemFontOfSize:11 weight:UIFontWeightMedium];
    [self.hideBtn setTitle:@"−" forState:UIControlStateNormal];
    [self.hideBtn setTitleColor:C(0.55f, 0.55f, 0.60f, 1) forState:UIControlStateNormal];
    [self addSubview:self.hideBtn];

    // ── card ──────────────────────────────────────────────────────────────────
    CGFloat cw = kMenuW - 24;
    UIView *card = [[UIView alloc] initWithFrame:CGRectMake(12, kHdr+14, cw, 88)];
    card.backgroundColor = C(0.10f, 0.10f, 0.13f, 1);
    card.layer.cornerRadius = 8;
    [self addSubview:card];

    UILabel *sl = [[UILabel alloc] initWithFrame:CGRectMake(10, 10, cw-20, 12)];
    sl.text = @"VISUALS";
    sl.font = [UIFont systemFontOfSize:9 weight:UIFontWeightSemibold];
    sl.textColor = C(0.27f, 0.52f, 1.00f, 1);
    [card addSubview:sl];

    // ESP label + toggle
    UILabel *espLbl = [[UILabel alloc] initWithFrame:CGRectMake(10, 34, 80, 20)];
    espLbl.text = @"ESP";
    espLbl.font = [UIFont systemFontOfSize:12 weight:UIFontWeightMedium];
    espLbl.textColor = C(0.80f, 0.80f, 0.90f, 1);
    [card addSubview:espLbl];

    self.espToggle = [[CrezToggle alloc] init];
    self.espToggle.frame = CGRectMake(cw-20-44, 33, 44, 24);
    [card addSubview:self.espToggle];

    // статус строка
    self.espStatus = [[UILabel alloc] initWithFrame:CGRectMake(10, 62, cw-20, 14)];
    self.espStatus.text = @"выключен";
    self.espStatus.font = [UIFont monospacedSystemFontOfSize:9 weight:UIFontWeightRegular];
    self.espStatus.textColor = C(0.35f, 0.35f, 0.40f, 1);
    [card addSubview:self.espStatus];

    // внешняя рамка поверх всего
    CALayer *bdr = [CALayer layer];
    bdr.frame = CGRectMake(0, 0, kMenuW, kMenuH);
    bdr.borderColor = C(0.22f, 0.22f, 0.28f, 0.65f).CGColor;
    bdr.borderWidth = 1; bdr.cornerRadius = kR;
    [self.layer addSublayer:bdr];

    return self;
}

- (void)pan:(UIPanGestureRecognizer *)g {
    CGPoint loc = [g locationInView:self.superview];
    if (g.state == UIGestureRecognizerStateBegan)
        _drag = CGPointMake(loc.x - self.frame.origin.x, loc.y - self.frame.origin.y);
    else if (g.state == UIGestureRecognizerStateChanged) {
        CGRect r = self.frame;
        r.origin = CGPointMake(loc.x - _drag.x, loc.y - _drag.y);
        self.frame = r;
    }
}
@end

// ═══════════════════════════════════════════════════════════════════════════════
// PassthroughWindow / PassthroughView
// ═══════════════════════════════════════════════════════════════════════════════
@interface PassthroughWindow : UIWindow @end
@implementation PassthroughWindow
- (UIView *)hitTest:(CGPoint)p withEvent:(UIEvent *)e {
    UIView *v = [super hitTest:p withEvent:e];
    if (!v || v == self || v == self.rootViewController.view) return nil;
    if (!v.userInteractionEnabled) return nil;
    return v;
}
@end

@interface PassthroughView : UIView @end
@implementation PassthroughView
- (UIView *)hitTest:(CGPoint)p withEvent:(UIEvent *)e {
    UIView *v = [super hitTest:p withEvent:e];
    return v == self ? nil : v;
}
@end

// ═══════════════════════════════════════════════════════════════════════════════
// CheatController
// ═══════════════════════════════════════════════════════════════════════════════
@interface CheatController : NSObject
+ (instancetype)shared;
- (void)show;
@end

@implementation CheatController {
    PassthroughWindow *_win;
    MenuView          *_menu;
    CrezESPView       *_espView;
    PillButton        *_pill;
    CADisplayLink     *_dl;
}

+ (instancetype)shared {
    static CheatController *inst; static dispatch_once_t once;
    dispatch_once(&once, ^{ inst = [CheatController new]; });
    return inst;
}

- (instancetype)init { self = [super init]; [self build]; return self; }

- (void)build {
    UIWindowScene *scene = nil;
    for (UIScene *s in [UIApplication sharedApplication].connectedScenes)
        if ([s isKindOfClass:[UIWindowScene class]]) { scene = (UIWindowScene *)s; break; }

    _win = scene
        ? [[PassthroughWindow alloc] initWithWindowScene:scene]
        : [[PassthroughWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
    _win.windowLevel = UIWindowLevelAlert + 200;
    _win.backgroundColor = [UIColor clearColor];

    PassthroughView *pv = [[PassthroughView alloc] initWithFrame:UIScreen.mainScreen.bounds];
    pv.backgroundColor = [UIColor clearColor];
    UIViewController *vc = [UIViewController new]; vc.view = pv;
    _win.rootViewController = vc; _win.hidden = NO;

    _espView = [[CrezESPView alloc] init];
    [pv addSubview:_espView];

    CGSize sz = UIScreen.mainScreen.bounds.size;
    _menu = [[MenuView alloc] initWithFrame:
        CGRectMake((sz.width - kMenuW) * .5f, (sz.height - kMenuH) * .5f, kMenuW, kMenuH)];
    [pv addSubview:_menu];

    __weak CheatController *ws = self;
    _pill = [PillButton new];
    _pill.action = ^{ [ws doShow]; };
    _pill.hidden = YES;
    [pv addSubview:_pill];

    [_menu.hideBtn addTarget:self action:@selector(doHide)
         forControlEvents:UIControlEventTouchUpInside];

    _menu.espToggle.onChange = ^(BOOL on) {
        g_espOn = on;
        ws->_menu.espStatus.text      = on ? @"активен"  : @"выключен";
        ws->_menu.espStatus.textColor = on
            ? C(0.35f, 0.70f, 0.40f, 1) : C(0.35f, 0.35f, 0.40f, 1);
        if (!on) [ws->_espView setNeedsDisplay];
    };

    // один displayLink на всё время жизни, redraw только когда ESP включён
    _dl = [CADisplayLink displayLinkWithTarget:self selector:@selector(tick)];
    _dl.preferredFramesPerSecond = 30;
    [_dl addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
}

- (void)tick {
    if (g_espOn) [_espView setNeedsDisplay];
}

- (void)doShow {
    _pill.hidden = YES; _menu.hidden = NO; _menu.alpha = 0;
    _menu.transform = CGAffineTransformMakeScale(0.88f, 0.88f);
    [UIView animateWithDuration:kDur delay:0 options:UIViewAnimationOptionCurveEaseOut animations:^{
        self->_menu.alpha = 1; self->_menu.transform = CGAffineTransformIdentity;
    } completion:nil];
}

- (void)doHide {
    [UIView animateWithDuration:kDur delay:0 options:UIViewAnimationOptionCurveEaseIn animations:^{
        self->_menu.alpha = 0; self->_menu.transform = CGAffineTransformMakeScale(0.94f, 0.94f);
    } completion:^(BOOL _) {
        self->_menu.hidden = YES; self->_menu.transform = CGAffineTransformIdentity;
        self->_pill.hidden = NO;
    }];
}

- (void)show { [self doShow]; }
@end

// ═══════════════════════════════════════════════════════════════════════════════
// Init
// ═══════════════════════════════════════════════════════════════════════════════
__attribute__((constructor)) static void _init(void) {
    gPlayerControllers = [NSMutableArray new];
    _resolveRVAs();

    // RVA: PlayerController.Awake = 0x157AB60, OnDestroy = 0x157C050
    DobbyHook((void *)(BASE + 0x157AB60), (void *)hook_pc_awake,   (void **)&orig_pc_awake);
    DobbyHook((void *)(BASE + 0x157C050), (void *)hook_pc_destroy, (void **)&orig_pc_destroy);

    dispatch_async(dispatch_get_main_queue(), ^{
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            [[CheatController shared] show];
        });
    });
}
