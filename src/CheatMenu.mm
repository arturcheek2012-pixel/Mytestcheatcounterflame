// ScarletWork.mm
// theos: ARCHS = arm64
// frameworks: UIKit QuartzCore
// libs: substrate

#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <substrate.h>
#import <mach-o/dyld.h>
#import <math.h>

// ═══════════════════════════════════════════════════════════════
//  STATE
// ═══════════════════════════════════════════════════════════════
static BOOL  gWH      = NO;
static BOOL  gNC      = NO;
static BOOL  gSpd     = NO;
static float gSpdMul  = 2.0f;
static BOOL  gAmmo    = NO;
static BOOL  gRecoil  = NO;

// ═══════════════════════════════════════════════════════════════
//  BASE / MEM
// ═══════════════════════════════════════════════════════════════
static uintptr_t gBase = 0;
static uintptr_t Base(void) {
    if (gBase) return gBase;
    for (uint32_t i = 0, n = _dyld_image_count(); i < n; i++) {
        const char *s = _dyld_get_image_name(i);
        if (s && strstr(s, "UnityFramework")) {
            gBase = (uintptr_t)_dyld_get_image_header(i);
            return gBase;
        }
    }
    return 0;
}
#define RVA(x)       ((void *)(Base() + (x)))
#define _p(p)        ((uintptr_t)(p) > 0x1000 && (uintptr_t)(p) < 0x00FFFFFFFFFFFFFFull)
#define WF(b,o,v)    do{ if(_p(b)) *(float*)   ((uint8_t*)(b)+(o))=(v);   }while(0)
#define WU8(b,o,v)   do{ if(_p(b)) *((uint8_t*)(b)+(o))=(uint8_t)(v);     }while(0)
#define WI16(b,o,v)  do{ if(_p(b)) *(int16_t*) ((uint8_t*)(b)+(o))=(v);   }while(0)

// ═══════════════════════════════════════════════════════════════
//  GAME FUNCTION POINTERS  (resolved post-load)
// ═══════════════════════════════════════════════════════════════
static void  (*fnSetIsGod) (void *, int)  = NULL; // ArmsController.set_IsGod   0x126FFD4
static void  (*fnEnableNC) (void *)       = NULL; // PlayerMovement.EnableNoclip 0x148B268
static void  (*fnDisableNC)(void *)       = NULL; // PlayerMovement.DisableNoclip 0x14839E0
static void *gPMI = NULL;  // PlayerMovement instance
static void *gWHI = NULL;  // WireframeWallhack instance

// ═══════════════════════════════════════════════════════════════
//  HOOKS
// ═══════════════════════════════════════════════════════════════

// ── ArmsController ─────────────────────────────────────────────
//  field offsets (dump verified)
#define AC_RMUL  0xA0u   // float  recoilMult
#define AC_AMUL  0xA4u   // float  accuracyMult (keep >0)
#define AC_CRV   0x154u  // float  camRecoilV
#define AC_CRH   0x158u  // float  camRecoilH
#define AC_CVV   0x15Cu  // float  camVelV
#define AC_CVH   0x160u  // float  camVelH
#define AC_KV    0x16Cu  // float  kickV
#define AC_KH    0x170u  // float  kickH
#define AC_INF   0x1D0u  // bool   infiniteShots
#define AC_MCAP  0x140u  // int16  MagazineCapacity
#define AC_CAP   0x142u  // int16  Capacity

static void (*_o_AC_Awake)(void *);
static void _h_AC_Awake(void *s) {
    _o_AC_Awake(s);
    // always enable god flag on the game's own field
    if (fnSetIsGod) fnSetIsGod(s, 1);
}

static void (*_o_AC_Update)(void *);
static void _h_AC_Update(void *s) {
    if (gRecoil) {
        WF(s, AC_RMUL, 0.f);   WF(s, AC_AMUL, 0.001f);
        WF(s, AC_CRV,  0.f);   WF(s, AC_CRH,  0.f);
        WF(s, AC_CVV,  0.f);   WF(s, AC_CVH,  0.f);
        WF(s, AC_KV,   0.f);   WF(s, AC_KH,   0.f);
    }
    if (gAmmo) {
        WU8(s,  AC_INF,  1);
        WI16(s, AC_MCAP, 999);
        WI16(s, AC_CAP,  999);
    }
    _o_AC_Update(s);
}

// ── PlayerMovement ─────────────────────────────────────────────
#define PM_NCE  0x38u  // bool   NoclipEnabled
#define PM_NCS  0x3Cu  // float  _noclipSpeed

static void (*_o_PM_Update)(void *);
static void _h_PM_Update(void *s) {
    gPMI = s;
    if (gNC) {
        WU8(s, PM_NCE, 1);
        WF(s,  PM_NCS, 22.f);
    }
    _o_PM_Update(s);
}

// get_MaxPlayerSpeed  RVA 0x1489F58  returns float
static float (*_o_MaxSpd)(void *);
static float _h_MaxSpd(void *s) {
    float v = _o_MaxSpd(s);
    return gSpd ? v * gSpdMul : v;
}

// ── WireframeWallhack ──────────────────────────────────────────
// SetEnabled(bool)   RVA 0x1413318
static void (*_o_WH_Set)(void *, int);
static void _h_WH_Set(void *s, int v) {
    gWHI = s;
    _o_WH_Set(s, gWH ? 1 : v);  // if WH on, block game from disabling it
}

// Refresh()   RVA 0x14135BC  — captures instance on first call
static void (*_o_WH_Ref)(void *);
static void _h_WH_Ref(void *s) {
    if (!gWHI) {
        gWHI = s;
        if (gWH) _o_WH_Set(s, 1);
    }
    _o_WH_Ref(s);
}

// ── install all hooks ──────────────────────────────────────────
static void InstallHooks(void) {
    uintptr_t b = Base();
    if (!b) return;

    fnSetIsGod  = (void(*)(void*,int))(b + 0x126FFD4);
    fnEnableNC  = (void(*)(void*))(b + 0x148B268);
    fnDisableNC = (void(*)(void*))(b + 0x14839E0);

    MSHookFunction(RVA(0x1270464), (void *)_h_AC_Awake,  (void **)&_o_AC_Awake);
    MSHookFunction(RVA(0x12706F0), (void *)_h_AC_Update, (void **)&_o_AC_Update);
    MSHookFunction(RVA(0x1483620), (void *)_h_PM_Update, (void **)&_o_PM_Update);
    MSHookFunction(RVA(0x1489F58), (void *)_h_MaxSpd,    (void **)&_o_MaxSpd);
    MSHookFunction(RVA(0x1413318), (void *)_h_WH_Set,    (void **)&_o_WH_Set);
    MSHookFunction(RVA(0x14135BC), (void *)_h_WH_Ref,    (void **)&_o_WH_Ref);
}

// ═══════════════════════════════════════════════════════════════
//  UI HELPERS
// ═══════════════════════════════════════════════════════════════
static inline UIColor *C(int r, int g, int b, CGFloat a) {
    return [UIColor colorWithRed:r/255.f green:g/255.f blue:b/255.f alpha:a];
}

// ═══════════════════════════════════════════════════════════════
//  PASSTHROUGH WINDOW + VIEW
// ═══════════════════════════════════════════════════════════════
@interface SCWindow : UIWindow @end
@implementation SCWindow
- (UIView *)hitTest:(CGPoint)p withEvent:(UIEvent *)e {
    UIView *v = [super hitTest:p withEvent:e];
    if (!v || v == self || v == self.rootViewController.view) return nil;
    return v.userInteractionEnabled ? v : nil;
}
@end

@interface SCRoot : UIView @end
@implementation SCRoot
- (UIView *)hitTest:(CGPoint)p withEvent:(UIEvent *)e {
    UIView *v = [super hitTest:p withEvent:e];
    return (v == self) ? nil : v;
}
@end

// ═══════════════════════════════════════════════════════════════
//  TOGGLE ROW
// ═══════════════════════════════════════════════════════════════
static const CGFloat ROW_W = 216.f;
static const CGFloat ROW_H = 36.f;

typedef void(^ToggleCB)(BOOL);

@interface SCRow : UIControl
@property (nonatomic) BOOL isOn;
@property (copy)     ToggleCB onChange;
@end

@implementation SCRow {
    UILabel *_title;
    UIView  *_badge;
    UILabel *_badgeLbl;
}

- (instancetype)initWithTitle:(NSString *)t {
    self = [super initWithFrame:CGRectMake(0, 0, ROW_W, ROW_H)];
    self.layer.cornerRadius = 6;
    self.clipsToBounds = YES;
    self.backgroundColor = C(19, 19, 24, 1);

    _title = [[UILabel alloc] initWithFrame:CGRectMake(10, 0, 128, ROW_H)];
    _title.font = [UIFont systemFontOfSize:12 weight:UIFontWeightMedium];
    _title.text = t;
    _title.userInteractionEnabled = NO;
    [self addSubview:_title];

    _badge = [[UIView alloc] initWithFrame:CGRectMake(ROW_W - 50, 11, 40, 14)];
    _badge.layer.cornerRadius = 7;
    _badge.userInteractionEnabled = NO;
    [self addSubview:_badge];

    _badgeLbl = [[UILabel alloc] initWithFrame:_badge.bounds];
    _badgeLbl.font = [UIFont systemFontOfSize:9 weight:UIFontWeightBold];
    _badgeLbl.textAlignment = NSTextAlignmentCenter;
    _badgeLbl.userInteractionEnabled = NO;
    [_badge addSubview:_badgeLbl];

    [self _refresh];
    [self addTarget:self action:@selector(_tap)
   forControlEvents:UIControlEventTouchUpInside];
    return self;
}

- (void)setIsOn:(BOOL)on { _isOn = on; [self _refresh]; }

- (void)_refresh {
    BOOL on = _isOn;
    _badge.backgroundColor     = on ? C(22, 160, 72, 1) : C(45, 45, 55, 1);
    _badgeLbl.text             = on ? @"ON" : @"OFF";
    _badgeLbl.textColor        = on ? C(185, 255, 185, 1) : C(95, 95, 105, 1);
    _title.textColor           = on ? C(215, 215, 225, 1) : C(135, 135, 145, 1);
}

- (void)_tap {
    _isOn = !_isOn;
    [self _refresh];
    if (_onChange) _onChange(_isOn);
    [UIView animateWithDuration:0.05 animations:^{ self.alpha = 0.55f; }
                     completion:^(BOOL f){ [UIView animateWithDuration:0.08 animations:^{ self.alpha = 1.f; }]; }];
}

- (void)touchesBegan:(NSSet *)t withEvent:(UIEvent *)e {
    [super touchesBegan:t withEvent:e];
    self.backgroundColor = C(28, 28, 35, 1);
}
- (void)touchesEnded:(NSSet *)t withEvent:(UIEvent *)e {
    [super touchesEnded:t withEvent:e];
    self.backgroundColor = C(19, 19, 24, 1);
}
- (void)touchesCancelled:(NSSet *)t withEvent:(UIEvent *)e {
    [super touchesCancelled:t withEvent:e];
    self.backgroundColor = C(19, 19, 24, 1);
}
@end

// ═══════════════════════════════════════════════════════════════
//  SPEED CONTROL ROW  (label + "−"/"+" stepper)
// ═══════════════════════════════════════════════════════════════
@interface SCSpeedCtrl : UIView @end
@implementation SCSpeedCtrl {
    UILabel *_val;
}
- (instancetype)init {
    self = [super initWithFrame:CGRectMake(0, 0, ROW_W, 30)];
    self.backgroundColor = [UIColor clearColor];

    UILabel *lbl = [[UILabel alloc] initWithFrame:CGRectMake(14, 0, 70, 30)];
    lbl.font = [UIFont monospacedSystemFontOfSize:9 weight:UIFontWeightRegular];
    lbl.textColor = C(80, 80, 95, 1);
    lbl.text = @"SPD MULT";
    [self addSubview:lbl];

    _val = [[UILabel alloc] initWithFrame:CGRectMake(88, 0, 60, 30)];
    _val.font = [UIFont monospacedSystemFontOfSize:11 weight:UIFontWeightBold];
    _val.textColor = C(80, 160, 255, 1);
    _val.textAlignment = NSTextAlignmentCenter;
    [self addSubview:_val];

    UIButton *dec = [self _btn:@"−" x:158];
    UIButton *inc = [self _btn:@"+" x:184];
    [dec addTarget:self action:@selector(_dec) forControlEvents:UIControlEventTouchUpInside];
    [inc addTarget:self action:@selector(_inc) forControlEvents:UIControlEventTouchUpInside];

    [self _refresh];
    return self;
}
- (UIButton *)_btn:(NSString *)t x:(CGFloat)x {
    UIButton *b = [UIButton buttonWithType:UIButtonTypeCustom];
    b.frame = CGRectMake(x, 5, 22, 20);
    b.backgroundColor = C(28, 28, 38, 1);
    b.layer.cornerRadius = 4;
    [b setTitle:t forState:UIControlStateNormal];
    b.titleLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightMedium];
    [b setTitleColor:C(130, 130, 155, 1) forState:UIControlStateNormal];
    [b setTitleColor:C(200, 200, 255, 1) forState:UIControlStateHighlighted];
    [self addSubview:b];
    return b;
}
- (void)_dec { gSpdMul = MAX(1.1f, gSpdMul - 0.5f); [self _refresh]; }
- (void)_inc { gSpdMul = MIN(10.f, gSpdMul + 0.5f); [self _refresh]; }
- (void)_refresh { _val.text = [NSString stringWithFormat:@"%.1fx", gSpdMul]; }
@end

// ═══════════════════════════════════════════════════════════════
//  MENU VIEW
// ═══════════════════════════════════════════════════════════════
static const CGFloat MW = 240.f;

@interface SCMenu : UIView
@property (copy) dispatch_block_t onClose;
@end

@implementation SCMenu {
    CGPoint _drag;
}

- (instancetype)init {
    // layout: hdr 40 + pad 12 + 5×(36+8) − last_gap 8 + spdctrl 30 + gap 6 + bot 14 = 314
    const CGFloat H = 40 + 12 + (36+8)*5 - 8 + 30 + 6 + 14;
    CGSize sc = [UIScreen mainScreen].bounds.size;
    self = [super initWithFrame:CGRectMake((sc.width - MW) * .5f,
                                           (sc.height - H)  * .5f,
                                           MW, H)];
    self.backgroundColor = C(12, 12, 16, 0.95f);
    self.layer.cornerRadius = 10;
    self.clipsToBounds = YES;

    // ── header ──────────────────────────────────────────────
    UIView *hdr = [[UIView alloc] initWithFrame:CGRectMake(0, 0, MW, 40)];
    hdr.backgroundColor = C(17, 17, 22, 1);
    [self addSubview:hdr];

    UIView *sep = [[UIView alloc] initWithFrame:CGRectMake(0, 39, MW, 1)];
    sep.backgroundColor = C(35, 75, 190, 0.55f);
    [self addSubview:sep];

    UILabel *ttl = [[UILabel alloc] initWithFrame:CGRectMake(12, 0, MW - 44, 40)];
    ttl.text = @"✦ CHEAT MENU";
    ttl.font = [UIFont systemFontOfSize:11 weight:UIFontWeightSemibold];
    ttl.textColor = C(185, 190, 205, 1);
    [hdr addSubview:ttl];

    UIButton *cls = [UIButton buttonWithType:UIButtonTypeCustom];
    cls.frame = CGRectMake(MW - 30, 10, 22, 22);
    cls.backgroundColor = C(50, 18, 18, 1);
    cls.layer.cornerRadius = 11;
    [cls setTitle:@"✕" forState:UIControlStateNormal];
    cls.titleLabel.font = [UIFont systemFontOfSize:10 weight:UIFontWeightBold];
    [cls setTitleColor:C(200, 80, 80, 1) forState:UIControlStateNormal];
    [cls setTitleColor:C(255, 120, 120, 1) forState:UIControlStateHighlighted];
    [cls addTarget:self action:@selector(_doClose)
  forControlEvents:UIControlEventTouchUpInside];
    [hdr addSubview:cls];

    [hdr addGestureRecognizer:
        [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(_pan:)]];

    // ── section label ────────────────────────────────────────
    CGFloat y = 40 + 12;
    UILabel *sec = [[UILabel alloc] initWithFrame:CGRectMake(12, y - 10, 100, 10)];
    sec.font = [UIFont systemFontOfSize:8 weight:UIFontWeightBold];
    sec.textColor = C(45, 80, 185, 1);
    sec.text = @"FEATURES";
    [self addSubview:sec];

    // ── feature rows ─────────────────────────────────────────
    SCRow *rWH   = [self _row:@"Wallhack"      y:y]; y += ROW_H + 8;
    SCRow *rNC   = [self _row:@"Noclip"        y:y]; y += ROW_H + 8;
    SCRow *rSpd  = [self _row:@"Speed Hack"    y:y]; y += ROW_H + 6;

    // speed stepper (indented under Speed row)
    SCSpeedCtrl *sc2 = [SCSpeedCtrl new];
    sc2.frame = CGRectMake(12, y, ROW_W, 30);
    [self addSubview:sc2];
    y += 30 + 8;

    SCRow *rAmmo = [self _row:@"Infinite Ammo" y:y]; y += ROW_H + 8;
    SCRow *rRec  = [self _row:@"No Recoil"     y:y];

    // ── callbacks ────────────────────────────────────────────
    rWH.onChange = ^(BOOL on) {
        gWH = on;
        if (gWHI && _o_WH_Set) _o_WH_Set(gWHI, on ? 1 : 0);
    };
    rNC.onChange = ^(BOOL on) {
        gNC = on;
        if (gPMI) {
            if (on  && fnEnableNC)  fnEnableNC(gPMI);
            if (!on && fnDisableNC) fnDisableNC(gPMI);
        }
    };
    rSpd.onChange  = ^(BOOL on) { gSpd   = on; };
    rAmmo.onChange = ^(BOOL on) { gAmmo  = on; };
    rRec.onChange  = ^(BOOL on) { gRecoil = on; };

    // border rim
    CALayer *rim = [CALayer layer];
    rim.frame = CGRectMake(0, 0, MW, H);
    rim.borderColor = C(32, 32, 44, 0.9f).CGColor;
    rim.borderWidth = 1;
    rim.cornerRadius = 10;
    [self.layer addSublayer:rim];

    return self;
}

- (SCRow *)_row:(NSString *)t y:(CGFloat)y {
    SCRow *r = [[SCRow alloc] initWithTitle:t];
    r.frame = CGRectMake(12, y, ROW_W, ROW_H);
    [self addSubview:r];
    return r;
}

- (void)_pan:(UIPanGestureRecognizer *)g {
    CGPoint loc = [g locationInView:self.superview];
    if (g.state == UIGestureRecognizerStateBegan)
        _drag = CGPointMake(loc.x - self.frame.origin.x,
                            loc.y - self.frame.origin.y);
    else if (g.state == UIGestureRecognizerStateChanged) {
        CGRect f = self.frame;
        f.origin = CGPointMake(loc.x - _drag.x, loc.y - _drag.y);
        self.frame = f;
    }
}

- (void)_doClose {
    if (_onClose) _onClose();
}
@end

// ═══════════════════════════════════════════════════════════════
//  PILL BUTTON (floating toggle)
// ═══════════════════════════════════════════════════════════════
@interface SCPill : UIView
@property (copy) dispatch_block_t onTap;
@end
@implementation SCPill { CGPoint _drag; BOOL _moved; }
- (instancetype)init {
    self = [super initWithFrame:CGRectMake(10, 110, 46, 28)];
    self.backgroundColor = C(17, 17, 26, 0.92f);
    self.layer.cornerRadius = 14;
    self.layer.borderColor = C(45, 80, 185, 0.55f).CGColor;
    self.layer.borderWidth = 1;

    UILabel *l = [[UILabel alloc] initWithFrame:self.bounds];
    l.text = @"☰";
    l.textAlignment = NSTextAlignmentCenter;
    l.font = [UIFont systemFontOfSize:13];
    l.textColor = C(140, 140, 160, 1);
    l.userInteractionEnabled = NO;
    [self addSubview:l];

    [self addGestureRecognizer:
        [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(_pan:)]];
    return self;
}
- (void)_pan:(UIPanGestureRecognizer *)g {
    CGPoint loc = [g locationInView:self.superview];
    if (g.state == UIGestureRecognizerStateBegan) {
        _moved = NO;
        _drag = CGPointMake(loc.x - self.frame.origin.x,
                            loc.y - self.frame.origin.y);
    } else if (g.state == UIGestureRecognizerStateChanged) {
        _moved = YES;
        CGRect f = self.frame;
        f.origin = CGPointMake(loc.x - _drag.x, loc.y - _drag.y);
        self.frame = f;
    }
}
- (void)touchesEnded:(NSSet *)t withEvent:(UIEvent *)e {
    if (!_moved && _onTap) _onTap();
    _moved = NO;
}
@end

// ═══════════════════════════════════════════════════════════════
//  CHEAT CONTROLLER
// ═══════════════════════════════════════════════════════════════
@interface SCCtrl : NSObject
+ (instancetype)shared;
@end

@implementation SCCtrl {
    SCWindow *_win;
    SCMenu   *_menu;
    SCPill   *_pill;
}

+ (instancetype)shared {
    static SCCtrl *s; static dispatch_once_t o;
    dispatch_once(&o, ^{ s = [SCCtrl new]; });
    return s;
}

- (instancetype)init {
    self = [super init];
    dispatch_async(dispatch_get_main_queue(), ^{ [self _build]; });
    return self;
}

- (void)_build {
    UIWindowScene *scene = nil;
    for (UIScene *s in [UIApplication sharedApplication].connectedScenes)
        if ([s isKindOfClass:[UIWindowScene class]]) { scene = (UIWindowScene *)s; break; }

    _win = scene
        ? [[SCWindow alloc] initWithWindowScene:scene]
        : [[SCWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
    _win.windowLevel = UIWindowLevelAlert + 300;
    _win.backgroundColor = [UIColor clearColor];

    SCRoot *rv = [[SCRoot alloc] initWithFrame:[UIScreen mainScreen].bounds];
    rv.backgroundColor = [UIColor clearColor];
    UIViewController *vc = [UIViewController new];
    vc.view = rv;
    _win.rootViewController = vc;
    _win.hidden = NO;

    // pill
    __weak SCCtrl *ws = self;
    _pill = [SCPill new];
    _pill.hidden = YES;
    _pill.onTap = ^{ [ws _show]; };
    [rv addSubview:_pill];

    // menu
    _menu = [SCMenu new];
    _menu.onClose = ^{ [ws _hide]; };
    [rv addSubview:_menu];

    // open immediately
    [self _show];
}

- (void)_show {
    _pill.hidden = YES;
    _menu.hidden = NO;
    _menu.alpha = 0;
    _menu.transform = CGAffineTransformMakeScale(0.88f, 0.88f);
    [UIView animateWithDuration:0.20
                          delay:0
                        options:UIViewAnimationOptionCurveEaseOut
                     animations:^{
        self->_menu.alpha = 1;
        self->_menu.transform = CGAffineTransformIdentity;
    } completion:nil];
}

- (void)_hide {
    [UIView animateWithDuration:0.16
                          delay:0
                        options:UIViewAnimationOptionCurveEaseIn
                     animations:^{
        self->_menu.alpha = 0;
        self->_menu.transform = CGAffineTransformMakeScale(0.92f, 0.92f);
    } completion:^(BOOL f) {
        self->_menu.hidden = YES;
        self->_menu.transform = CGAffineTransformIdentity;
        self->_pill.hidden = NO;
    }];
}
@end

// ═══════════════════════════════════════════════════════════════
//  ENTRY POINT
// ═══════════════════════════════════════════════════════════════
__attribute__((constructor))
static void Init(void) {
    InstallHooks();
    dispatch_after(
        dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)),
        dispatch_get_main_queue(),
        ^{ [SCCtrl shared]; }
    );
}
