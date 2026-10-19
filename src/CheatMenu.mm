// src/CheatMenu.mm
// xcrun -sdk iphoneos clang++ -arch arm64 -dynamiclib
//   -framework UIKit -framework QuartzCore -framework Foundation
//   -o CheatMenu.dylib src/CheatMenu.mm

#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <mach-o/dyld.h>
#import <mach/mach.h>
#import <sys/mman.h>
#import <math.h>
#import <dlfcn.h>

// ═══════════════════════════════════════════════════════════════
//  ARM64 HOOK  (no substrate)
//  stub: LDR X17, #8 ; BR X17 ; <8-byte addr>  = 16 bytes
// ═══════════════════════════════════════════════════════════════
static void _write_jump(void *at, void *to) {
    uint32_t *w = (uint32_t *)at;
    w[0] = 0x58000051U;                     // LDR X17, #8
    w[1] = 0xD61F0220U;                     // BR  X17
    ((uint64_t *)at)[1] = (uint64_t)to;     // absolute target
    __builtin___clear_cache((char*)at, (char*)at + 16);
}

static void *_exec_alloc(size_t size) {
    size = (size + vm_page_size - 1) & ~(vm_page_size - 1);
    vm_address_t addr = 0;
    if (vm_allocate(mach_task_self(), &addr, size, VM_FLAGS_ANYWHERE) != KERN_SUCCESS)
        return NULL;
    vm_protect(mach_task_self(), addr, size, NO,
               VM_PROT_READ | VM_PROT_WRITE | VM_PROT_EXECUTE | VM_PROT_COPY);
    return (void *)addr;
}

static void _hook(void *target, void *hook, void **orig) {
    // trampoline: [0..15] = original first 16 bytes, [16..31] = jump back
    uint8_t *tramp = (uint8_t *)_exec_alloc(32);
    if (!tramp) return;

    memcpy(tramp, target, 16);
    _write_jump(tramp + 16, (uint8_t *)target + 16);
    if (orig) *orig = tramp;

    // unprotect target page
    vm_address_t page = (vm_address_t)target & ~(vm_page_size - 1);
    vm_protect(mach_task_self(), page, vm_page_size, NO,
               VM_PROT_READ | VM_PROT_WRITE | VM_PROT_EXECUTE | VM_PROT_COPY);

    _write_jump(target, hook);
}

#define HOOK(rva, hook, orig) _hook((void*)(Base()+(rva)), (void*)(hook), (void**)(orig))

// ═══════════════════════════════════════════════════════════════
//  STATE
// ═══════════════════════════════════════════════════════════════
static BOOL  gWH     = NO;
static BOOL  gNC     = NO;
static BOOL  gSpd    = NO;
static float gSpdMul = 2.0f;
static BOOL  gAmmo   = NO;
static BOOL  gRecoil = NO;

static void *gPMI = NULL;   // PlayerMovement instance
static void *gWHI = NULL;   // WireframeWallhack instance

// ═══════════════════════════════════════════════════════════════
//  BASE
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

// ═══════════════════════════════════════════════════════════════
//  MEM HELPERS
// ═══════════════════════════════════════════════════════════════
#define _OK(p)       ((uintptr_t)(p) > 0x1000U)
#define WF(b,o,v)    do{ if(_OK(b)) *(float*)  ((uint8_t*)(b)+(o))=(v); }while(0)
#define WU8(b,o,v)   do{ if(_OK(b)) *(uint8_t*)((uint8_t*)(b)+(o))=(uint8_t)(v); }while(0)
#define WI16(b,o,v)  do{ if(_OK(b)) *(int16_t*)((uint8_t*)(b)+(o))=(v); }while(0)

// ═══════════════════════════════════════════════════════════════
//  GAME FUNCTION POINTERS
// ═══════════════════════════════════════════════════════════════
static void (*fnSetIsGod) (void *, int) = NULL;  // 0x126FFD4
static void (*fnEnableNC) (void *)      = NULL;  // 0x148B268
static void (*fnDisableNC)(void *)      = NULL;  // 0x14839E0

// ═══════════════════════════════════════════════════════════════
//  ArmsController offsets  (dump-verified)
// ═══════════════════════════════════════════════════════════════
#define AC_RMUL  0xA0u
#define AC_AMUL  0xA4u
#define AC_CRV   0x154u
#define AC_CRH   0x158u
#define AC_CVV   0x15Cu
#define AC_CVH   0x160u
#define AC_KV    0x16Cu
#define AC_KH    0x170u
#define AC_INF   0x1D0u
#define AC_MCAP  0x140u
#define AC_CAP   0x142u

// PlayerMovement offsets
#define PM_NCE   0x38u
#define PM_NCS   0x3Cu

// ═══════════════════════════════════════════════════════════════
//  HOOKS
// ═══════════════════════════════════════════════════════════════
static void (*_o_AC_Awake) (void *) = NULL;
static void  _h_AC_Awake  (void *s) {
    _o_AC_Awake(s);
    if (fnSetIsGod) fnSetIsGod(s, 1);          // game's own god flag
}

static void (*_o_AC_Update)(void *) = NULL;
static void  _h_AC_Update (void *s) {
    if (gRecoil) {
        WF(s, AC_RMUL, 0.f); WF(s, AC_AMUL, 0.001f);
        WF(s, AC_CRV,  0.f); WF(s, AC_CRH,  0.f);
        WF(s, AC_CVV,  0.f); WF(s, AC_CVH,  0.f);
        WF(s, AC_KV,   0.f); WF(s, AC_KH,   0.f);
    }
    if (gAmmo) {
        WU8(s,  AC_INF,  1);
        WI16(s, AC_MCAP, 999);
        WI16(s, AC_CAP,  999);
    }
    _o_AC_Update(s);
}

static void (*_o_PM_Update)(void *) = NULL;
static void  _h_PM_Update (void *s) {
    gPMI = s;
    if (gNC) { WU8(s, PM_NCE, 1); WF(s, PM_NCS, 22.f); }
    _o_PM_Update(s);
}

static float (*_o_MaxSpd)(void *) = NULL;
static float  _h_MaxSpd (void *s) {
    float v = _o_MaxSpd(s);
    return gSpd ? v * gSpdMul : v;
}

static void (*_o_WH_Set)(void *, int) = NULL;
static void  _h_WH_Set (void *s, int v) {
    gWHI = s;
    _o_WH_Set(s, gWH ? 1 : v);
}

static void (*_o_WH_Ref)(void *) = NULL;
static void  _h_WH_Ref (void *s) {
    if (!gWHI) { gWHI = s; if (gWH && _o_WH_Set) _o_WH_Set(s, 1); }
    _o_WH_Ref(s);
}

static void InstallHooks(void) {
    uintptr_t b = Base();
    if (!b) return;

    fnSetIsGod  = (void(*)(void*,int)) (b + 0x126FFD4);
    fnEnableNC  = (void(*)(void*))     (b + 0x148B268);
    fnDisableNC = (void(*)(void*))     (b + 0x14839E0);

    HOOK(0x1270464, _h_AC_Awake,  &_o_AC_Awake);
    HOOK(0x12706F0, _h_AC_Update, &_o_AC_Update);
    HOOK(0x1483620, _h_PM_Update, &_o_PM_Update);
    HOOK(0x1489F58, _h_MaxSpd,    &_o_MaxSpd);
    HOOK(0x1413318, _h_WH_Set,    &_o_WH_Set);
    HOOK(0x14135BC, _h_WH_Ref,    &_o_WH_Ref);
}

// ═══════════════════════════════════════════════════════════════
//  UI HELPERS
// ═══════════════════════════════════════════════════════════════
static UIColor *C(int r, int g, int b, CGFloat a) {
    return [UIColor colorWithRed:r/255.f green:g/255.f blue:b/255.f alpha:a];
}

// ═══════════════════════════════════════════════════════════════
//  PASSTHROUGH WINDOW / VIEW
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
    return v == self ? nil : v;
}
@end

// ═══════════════════════════════════════════════════════════════
//  TOGGLE ROW
// ═══════════════════════════════════════════════════════════════
typedef void(^ToggleCB)(BOOL);

@interface SCRow : UIControl
@property (nonatomic) BOOL      isOn;
@property (copy)      ToggleCB  onChange;
- (instancetype)initWithTitle:(NSString *)t;
@end

@implementation SCRow {
    UILabel *_lbl;
    UIView  *_badge;
    UILabel *_badgeLbl;
}

- (instancetype)initWithTitle:(NSString *)t {
    self = [super initWithFrame:CGRectMake(0,0,216,36)];
    self.layer.cornerRadius = 6;
    self.clipsToBounds = YES;
    self.backgroundColor = C(19,19,24,1);

    _lbl = [[UILabel alloc] initWithFrame:CGRectMake(10,0,130,36)];
    _lbl.font = [UIFont systemFontOfSize:12 weight:UIFontWeightMedium];
    _lbl.text = t;
    _lbl.userInteractionEnabled = NO;
    [self addSubview:_lbl];

    _badge = [[UIView alloc] initWithFrame:CGRectMake(166,11,40,14)];
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
    _badge.backgroundColor = on ? C(22,160,72,1) : C(42,42,52,1);
    _badgeLbl.text         = on ? @"ON" : @"OFF";
    _badgeLbl.textColor    = on ? C(185,255,185,1) : C(90,90,100,1);
    _lbl.textColor         = on ? C(215,215,225,1) : C(130,130,140,1);
}

- (void)_tap {
    _isOn = !_isOn;
    [self _refresh];
    if (_onChange) _onChange(_isOn);
    [UIView animateWithDuration:0.05 animations:^{ self.alpha = 0.5f; }
                     completion:^(BOOL f){
        [UIView animateWithDuration:0.08 animations:^{ self.alpha = 1.f; }];
    }];
}

- (void)touchesBegan:(NSSet *)t withEvent:(UIEvent *)e {
    [super touchesBegan:t withEvent:e];
    self.backgroundColor = C(28,28,36,1);
}
- (void)touchesEnded:(NSSet *)t withEvent:(UIEvent *)e {
    [super touchesEnded:t withEvent:e];
    self.backgroundColor = C(19,19,24,1);
}
- (void)touchesCancelled:(NSSet *)t withEvent:(UIEvent *)e {
    [super touchesCancelled:t withEvent:e];
    self.backgroundColor = C(19,19,24,1);
}
@end

// ═══════════════════════════════════════════════════════════════
//  SPEED STEPPER ROW
// ═══════════════════════════════════════════════════════════════
@interface SCSpeedCtrl : UIView @end
@implementation SCSpeedCtrl {
    UILabel *_val;
}
- (instancetype)init {
    self = [super initWithFrame:CGRectMake(0,0,216,30)];
    self.backgroundColor = [UIColor clearColor];

    UILabel *lbl = [[UILabel alloc] initWithFrame:CGRectMake(14,0,72,30)];
    lbl.font = [UIFont monospacedSystemFontOfSize:9 weight:UIFontWeightRegular];
    lbl.textColor = C(75,75,90,1);
    lbl.text = @"SPD MULT";
    [self addSubview:lbl];

    _val = [[UILabel alloc] initWithFrame:CGRectMake(88,0,56,30)];
    _val.font = [UIFont monospacedSystemFontOfSize:11 weight:UIFontWeightBold];
    _val.textColor = C(80,155,255,1);
    _val.textAlignment = NSTextAlignmentCenter;
    [self addSubview:_val];

    [self addSubview:[self _btn:@"−" x:152 sel:@selector(_dec)]];
    [self addSubview:[self _btn:@"+" x:180 sel:@selector(_inc)]];
    [self _refresh];
    return self;
}
- (UIButton *)_btn:(NSString *)t x:(CGFloat)x sel:(SEL)s {
    UIButton *b = [UIButton buttonWithType:UIButtonTypeCustom];
    b.frame = CGRectMake(x,5,22,20);
    b.backgroundColor = C(28,28,38,1);
    b.layer.cornerRadius = 4;
    [b setTitle:t forState:UIControlStateNormal];
    b.titleLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightMedium];
    [b setTitleColor:C(125,125,150,1) forState:UIControlStateNormal];
    [b setTitleColor:C(200,200,255,1) forState:UIControlStateHighlighted];
    [b addTarget:self action:s forControlEvents:UIControlEventTouchUpInside];
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
    // layout calculation
    // hdr=40, top_pad=14, section_label=12, sec_gap=6
    // 5 rows × (36+8) = 220, minus last gap = 212
    // spd_ctrl=30, spd_gap=10, bot_pad=14
    // total ≈ 40+14+12+6+212+30+10+14 = 338
    const CGFloat H = 338.f;
    CGSize sc = [UIScreen mainScreen].bounds.size;
    self = [super initWithFrame:CGRectMake((sc.width  - MW) * .5f,
                                           (sc.height - H)  * .5f,
                                           MW, H)];
    self.backgroundColor = C(11,11,15,0.95f);
    self.layer.cornerRadius = 10;
    self.clipsToBounds = YES;

    // ── header ──────────────────────────────────────────────────
    UIView *hdr = [[UIView alloc] initWithFrame:CGRectMake(0,0,MW,40)];
    hdr.backgroundColor = C(17,17,22,1);
    [self addSubview:hdr];

    UIView *sep = [[UIView alloc] initWithFrame:CGRectMake(0,39,MW,1)];
    sep.backgroundColor = C(35,75,190,0.5f);
    [self addSubview:sep];

    UILabel *ttl = [[UILabel alloc] initWithFrame:CGRectMake(12,0,MW-44,40)];
    ttl.text = @"✦  CHEAT MENU";
    ttl.font = [UIFont systemFontOfSize:11 weight:UIFontWeightSemibold];
    ttl.textColor = C(180,185,205,1);
    [hdr addSubview:ttl];

    UIButton *cls = [UIButton buttonWithType:UIButtonTypeCustom];
    cls.frame = CGRectMake(MW-30,9,22,22);
    cls.backgroundColor = C(50,18,18,1);
    cls.layer.cornerRadius = 11;
    [cls setTitle:@"✕" forState:UIControlStateNormal];
    cls.titleLabel.font = [UIFont systemFontOfSize:10 weight:UIFontWeightBold];
    [cls setTitleColor:C(200,75,75,1) forState:UIControlStateNormal];
    [cls setTitleColor:C(255,110,110,1) forState:UIControlStateHighlighted];
    [cls addTarget:self action:@selector(_doClose)
  forControlEvents:UIControlEventTouchUpInside];
    [hdr addSubview:cls];

    [hdr addGestureRecognizer:
        [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(_pan:)]];

    // ── section label ────────────────────────────────────────────
    CGFloat y = 40 + 14;
    UILabel *sec = [[UILabel alloc] initWithFrame:CGRectMake(12, y, 100, 12)];
    sec.font = [UIFont systemFontOfSize:8 weight:UIFontWeightBold];
    sec.textColor = C(40,75,185,1);
    sec.text = @"FEATURES";
    [self addSubview:sec];
    y += 12 + 6;

    // ── toggle rows ──────────────────────────────────────────────
    SCRow *rWH   = [self _row:@"Wallhack"      y:y]; y += 36 + 8;
    SCRow *rNC   = [self _row:@"Noclip"        y:y]; y += 36 + 8;
    SCRow *rSpd  = [self _row:@"Speed Hack"    y:y]; y += 36 + 6;

    SCSpeedCtrl *sc2 = [SCSpeedCtrl new];
    sc2.frame = CGRectMake(12, y, 216, 30);
    [self addSubview:sc2];
    y += 30 + 10;

    SCRow *rAmmo = [self _row:@"Infinite Ammo" y:y]; y += 36 + 8;
    SCRow *rRec  = [self _row:@"No Recoil"     y:y];

    // ── callbacks ────────────────────────────────────────────────
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
    rSpd.onChange  = ^(BOOL on) { gSpd    = on; };
    rAmmo.onChange = ^(BOOL on) { gAmmo   = on; };
    rRec.onChange  = ^(BOOL on) { gRecoil = on; };

    // outer rim
    CALayer *rim = [CALayer layer];
    rim.frame = CGRectMake(0,0,MW,H);
    rim.borderColor = C(30,30,42,0.9f).CGColor;
    rim.borderWidth = 1;
    rim.cornerRadius = 10;
    [self.layer addSublayer:rim];

    return self;
}

- (SCRow *)_row:(NSString *)t y:(CGFloat)y {
    SCRow *r = [[SCRow alloc] initWithTitle:t];
    r.frame = CGRectMake(12, y, 216, 36);
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
- (void)_doClose { if (_onClose) _onClose(); }
@end

// ═══════════════════════════════════════════════════════════════
//  PILL BUTTON
// ═══════════════════════════════════════════════════════════════
@interface SCPill : UIView
@property (copy) dispatch_block_t onTap;
@end

@implementation SCPill { CGPoint _drag; BOOL _moved; }

- (instancetype)init {
    self = [super initWithFrame:CGRectMake(10,110,46,28)];
    self.backgroundColor = C(17,17,26,0.92f);
    self.layer.cornerRadius = 14;
    self.layer.borderColor = C(40,75,185,0.55f).CGColor;
    self.layer.borderWidth = 1;

    UILabel *l = [[UILabel alloc] initWithFrame:self.bounds];
    l.text = @"☰";
    l.textAlignment = NSTextAlignmentCenter;
    l.font = [UIFont systemFontOfSize:13];
    l.textColor = C(135,135,158,1);
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
        _drag  = CGPointMake(loc.x - self.frame.origin.x,
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

    _pill = [SCPill new];
    _pill.hidden = YES;
    __weak SCCtrl *ws = self;
    _pill.onTap = ^{ [ws _show]; };
    [rv addSubview:_pill];

    _menu = [SCMenu new];
    _menu.onClose = ^{ [ws _hide]; };
    [rv addSubview:_menu];

    [self _show];
}

- (void)_show {
    _pill.hidden = YES;
    _menu.hidden = NO;
    _menu.alpha = 0;
    _menu.transform = CGAffineTransformMakeScale(0.88f, 0.88f);
    [UIView animateWithDuration:0.20 delay:0
                        options:UIViewAnimationOptionCurveEaseOut
                     animations:^{
        self->_menu.alpha = 1;
        self->_menu.transform = CGAffineTransformIdentity;
    } completion:nil];
}

- (void)_hide {
    [UIView animateWithDuration:0.16 delay:0
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
static void CheatInit(void) {
    InstallHooks();
    dispatch_after(
        dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)),
        dispatch_get_main_queue(),
        ^{ [SCCtrl shared]; }
    );
}
