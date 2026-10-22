// Tweak.mm — CounterFlame ESP
// Target : com.ScarletWork.CounterFlame.app
// Runtime: LiveContainer, iOS 16-26, arm64
// Offsets verified against dump_cs.txt (base 0x112a70000)

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wc++11-extensions"
#pragma clang diagnostic ignored "-Wabsolute-value"
#pragma clang diagnostic ignored "-Wdeprecated-declarations"

#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <QuartzCore/QuartzCore.h>
#include <objc/runtime.h>
#include <mach-o/dyld.h>
#include <mach/mach.h>
#include <stdint.h>
#include <cmath>
#include <signal.h>
#include <setjmp.h>

// ═══════════════════════════════════════════════════════════
// MARK: — IL2CPP types
// ═══════════════════════════════════════════════════════════

typedef void*  Il2CppObject;
typedef void*  Transform;
typedef void*  Camera_t;
typedef void*  Il2CppArray;

struct Vector3 { float x, y, z; };

// ═══════════════════════════════════════════════════════════
// MARK: — Offsets (verified from dump_cs.txt, base 0x112a70000)
// ═══════════════════════════════════════════════════════════

#define OFF_PLAYER_TAG      0x48
#define OFF_PC_NETWORK      0x88
#define OFF_PC_ANIM_CTRL    0x98
#define OFF_PC_IS_DEATH     0xA8
#define OFF_PN_POSITION     0xBC
#define OFF_PAC_SKELETON    0x68
#define OFF_SK_HEAD         0xA8
#define OFF_SK_CHEST        0xB0
#define OFF_SK_PELVIS       0xB8
#define OFF_SK_L_UPPER_ARM  0xC0
#define OFF_SK_R_UPPER_ARM  0xC8
#define OFF_SK_L_THIGH      0xD0
#define OFF_SK_R_THIGH      0xD8
#define OFF_SK_L_FOREARM    0x38
#define OFF_SK_L_HAND       0x40
#define OFF_ARRAY_LEN       0x18
#define OFF_ARRAY_DATA      0x20

// ═══════════════════════════════════════════════════════════
// MARK: — RVAs (verified from dump_cs.txt)
// ═══════════════════════════════════════════════════════════

#define DUMP_BASE                 0x112a70000ULL
#define RVA_TRANSFORM_GETPOS_INJ  0x2BB48F4ULL   // Transform::get_position_Injected p:1
#define RVA_WORLD2SCREEN          0x2B74024ULL   // Camera::WorldToScreenPoint(Vector3) p:1
#define RVA_CAMERA_MAIN           0x2B741F0ULL   // Camera::get_main p:0
#define RVA_GET_PLAYERLIST        0x24BC978ULL   // PhotonNetwork::get_PlayerList p:0

// ═══════════════════════════════════════════════════════════
// MARK: — Config
// ═══════════════════════════════════════════════════════════

static bool  g_espBox   = true;
static bool  g_espSkel  = true;
static float g_boxAlpha = 0.9f;

// ═══════════════════════════════════════════════════════════
// MARK: — Safe memory read
// Читаем через vm_read_overwrite — не крашится на невалидных адресах
// ═══════════════════════════════════════════════════════════

template<typename T>
static inline bool safeRead(uintptr_t addr, T *out) {
    if (addr == 0 || addr < 0x1000) return false;
    // выравнивание: адрес должен быть кратен размеру типа (минимум 4)
    if (sizeof(T) >= 4 && (addr & 3) != 0) return false;
    vm_size_t readSize = sizeof(T);
    kern_return_t kr = vm_read_overwrite(mach_task_self(),
                                         (vm_address_t)addr,
                                         sizeof(T),
                                         (vm_address_t)out,
                                         &readSize);
    return (kr == KERN_SUCCESS && readSize == sizeof(T));
}

template<typename T>
static inline T rd(uintptr_t addr) {
    T out; memset(&out, 0, sizeof(out));
    safeRead(addr, &out);
    return out;
}

static inline uintptr_t rdPtr(uintptr_t addr) {
    return rd<uintptr_t>(addr);
}

// ═══════════════════════════════════════════════════════════
// MARK: — Slide resolution
// ═══════════════════════════════════════════════════════════

static uintptr_t s_slide      = 0;
static bool      s_slideFound = false;

static uintptr_t getSlide() {
    if (s_slideFound) return s_slide;
    for (uint32_t i = 0, n = _dyld_image_count(); i < n; i++) {
        const char *nm = _dyld_get_image_name(i);
        if (nm && strstr(nm, "UnityFramework")) {
            s_slide      = (uintptr_t)_dyld_get_image_vmaddr_slide(i);
            s_slideFound = true;
            return s_slide;
        }
    }
    return 0;
}

// ═══════════════════════════════════════════════════════════
// MARK: — Function pointers
// ═══════════════════════════════════════════════════════════

typedef void         (*PFN_GetPosInj)(Transform self, Vector3 *out, void *method);
typedef Vector3      (*PFN_W2S)(Camera_t self, Vector3 pos, void *method);
typedef Camera_t     (*PFN_CamMain)(void *method);
typedef Il2CppArray *(*PFN_PlayerList)(void *method);

static PFN_GetPosInj  s_getPosInj  = NULL;
static PFN_W2S        s_w2s        = NULL;
static PFN_CamMain    s_camMain    = NULL;
static PFN_PlayerList s_playerList = NULL;
static bool           s_resolved   = false;

static void resolveSymbols() {
    if (s_resolved) return;
    uintptr_t slide = getSlide();
    if (!slide) return;
#define BIND(fn, abs_rva) \
    fn = (__typeof__(fn))((uintptr_t)((abs_rva) - DUMP_BASE + slide))
    BIND(s_getPosInj,  RVA_TRANSFORM_GETPOS_INJ);
    BIND(s_w2s,        RVA_WORLD2SCREEN);
    BIND(s_camMain,    RVA_CAMERA_MAIN);
    BIND(s_playerList, RVA_GET_PLAYERLIST);
#undef BIND
    s_resolved = true;
}

// ═══════════════════════════════════════════════════════════
// MARK: — Helpers
// ═══════════════════════════════════════════════════════════

static CGSize g_screen;

static inline Vector3 boneWorldPos(Transform bone) {
    Vector3 out; memset(&out, 0, sizeof(out));
    if (!bone || !s_getPosInj) return out;
    @try { s_getPosInj(bone, &out, NULL); } @catch (...) {}
    return out;
}

static bool w2s(Camera_t cam, Vector3 world, CGPoint *out) {
    if (!cam || !s_w2s) return false;
    Vector3 s;
    @try { s = s_w2s(cam, world, NULL); } @catch (...) { return false; }
    if (s.z <= 0.f) return false;
    out->x = (CGFloat)s.x;
    out->y = g_screen.height - (CGFloat)s.y;
    return (s.x > 0.f && s.x < (float)g_screen.width &&
            s.y > 0.f && s.y < (float)g_screen.height);
}

// ═══════════════════════════════════════════════════════════
// MARK: — ESP data
// ═══════════════════════════════════════════════════════════

typedef struct {
    CGRect  box;
    bool    hasBox;
    CGPoint head, chest, pelvis;
    CGPoint lShoulder, rShoulder;
    CGPoint lElbow,    rElbow;
    CGPoint lHand,     rHand;
    CGPoint lHip,      rHip;
    bool    hasSkel;
    float   headR;
    bool    valid;
} PlayerESPData;

// двойной буфер — пишем в back, читаем front, атомарно свапаем
static NSArray *g_frontBuf = nil;
static NSArray *g_backBuf  = nil;

// ═══════════════════════════════════════════════════════════
// MARK: — Frame collection (вызывается на main thread)
// ═══════════════════════════════════════════════════════════

static void collectFrame() {
    if (!s_resolved || !s_playerList || !s_camMain) return;

    Camera_t cam = NULL;
    @try { cam = s_camMain(NULL); } @catch (...) { return; }
    if (!cam) return;

    Il2CppArray *arr = NULL;
    @try { arr = s_playerList(NULL); } @catch (...) { return; }
    if (!arr) return;

    int32_t count = 0;
    if (!safeRead((uintptr_t)arr + OFF_ARRAY_LEN, &count)) return;
    if (count <= 0 || count > 32) return;

    NSMutableArray *nd = [NSMutableArray arrayWithCapacity:(NSUInteger)count];

    for (int32_t i = 0; i < count; i++) {
        uintptr_t playerPtr = rdPtr((uintptr_t)arr + OFF_ARRAY_DATA + (uintptr_t)(i * 8));
        if (!playerPtr) continue;

        uintptr_t pcPtr = rdPtr(playerPtr + OFF_PLAYER_TAG);
        if (!pcPtr) continue;

        bool dead = false;
        safeRead(pcPtr + OFF_PC_IS_DEATH, &dead);
        if (dead) continue;

        uintptr_t netPtr = rdPtr(pcPtr + OFF_PC_NETWORK);
        if (!netPtr) continue;

        uintptr_t acPtr = rdPtr(pcPtr + OFF_PC_ANIM_CTRL);
        uintptr_t skPtr = acPtr ? rdPtr(acPtr + OFF_PAC_SKELETON) : 0;

        PlayerESPData d; memset(&d, 0, sizeof(d));

        if (skPtr) {
            uintptr_t boneOffsets[9] = {
                OFF_SK_HEAD, OFF_SK_CHEST, OFF_SK_PELVIS,
                OFF_SK_L_UPPER_ARM, OFF_SK_R_UPPER_ARM,
                OFF_SK_L_FOREARM, OFF_SK_L_HAND,
                OFF_SK_L_THIGH, OFF_SK_R_THIGH,
            };
            CGPoint pts[9];
            bool ok = true;
            for (int j = 0; j < 9 && ok; j++) {
                Transform bone = NULL;
                if (!safeRead(skPtr + boneOffsets[j], &bone) || !bone) { ok = false; break; }
                ok &= w2s(cam, boneWorldPos(bone), &pts[j]);
            }

            if (ok) {
                d.head       = pts[0]; d.chest     = pts[1]; d.pelvis    = pts[2];
                d.lShoulder  = pts[3]; d.rShoulder = pts[4];
                d.lElbow     = pts[5]; d.rElbow    = pts[5]; // нет в дампе — зеркалим
                d.lHand      = pts[6]; d.rHand     = pts[6];
                d.lHip       = pts[7]; d.rHip      = pts[8];
                CGFloat bh   = (CGFloat)std::abs(d.pelvis.y - d.head.y);
                if (bh < 10.f || bh > 2000.f) goto fallback; // санити
                d.headR  = (float)(bh * 0.10f);
                CGFloat bw   = bh * 0.5f;
                d.box    = CGRectMake(d.head.x - bw * .5f,
                                      d.head.y - d.headR * 1.5f,
                                      bw, bh + d.headR * 2.f);
                d.hasBox = d.hasSkel = d.valid = true;
            }
        }

    fallback:
        if (!d.valid) {
            Vector3 wPos; memset(&wPos, 0, sizeof(wPos));
            if (!safeRead(netPtr + OFF_PN_POSITION, &wPos)) continue;
            Vector3 t3 = {wPos.x, wPos.y + 1.75f, wPos.z};
            Vector3 b3 = {wPos.x, wPos.y,           wPos.z};
            CGPoint top, bot;
            if (w2s(cam, t3, &top) && w2s(cam, b3, &bot)) {
                CGFloat bh = (CGFloat)std::abs(bot.y - top.y);
                if (bh < 5.f || bh > 2000.f) continue;
                CGFloat bw = bh * .5f;
                d.box    = CGRectMake(top.x - bw * .5f, top.y, bw, bh);
                d.head   = top; d.headR = (float)(bh * .10f);
                d.hasBox = d.valid = true;
            }
        }

        if (d.valid)
            [nd addObject:[NSValue value:&d withObjCType:@encode(PlayerESPData)]];
    }

    g_frontBuf = [nd copy]; // атомарная замена (ARC retain/release)
}

// ═══════════════════════════════════════════════════════════
// MARK: — Palette
// ═══════════════════════════════════════════════════════════

NS_INLINE UIColor *cA()   { return [UIColor colorWithRed:.28f green:.82f blue:1.f  alpha:1.f]; }
NS_INLINE UIColor *cBg()  { return [UIColor colorWithRed:.04f green:.04f blue:.07f alpha:.97f]; }
NS_INLINE UIColor *cRow() { return [UIColor colorWithRed:.07f green:.08f blue:.12f alpha:1.f]; }
NS_INLINE UIColor *cTx()  { return [UIColor colorWithWhite:.88f alpha:1.f]; }
NS_INLINE UIColor *cSub() { return [UIColor colorWithWhite:.36f alpha:1.f]; }
NS_INLINE UIColor *cDiv() { return [UIColor colorWithWhite:.11f alpha:1.f]; }

// ═══════════════════════════════════════════════════════════
// MARK: — ESPView
// ═══════════════════════════════════════════════════════════

@interface ESPView : UIView
@end
@implementation ESPView

- (instancetype)initWithFrame:(CGRect)f {
    self = [super initWithFrame:f];
    self.backgroundColor        = UIColor.clearColor;
    self.userInteractionEnabled = NO;
    self.layer.zPosition        = 99990;
    return self;
}

- (void)drawRect:(CGRect)__unused r {
    CGContextRef ctx = UIGraphicsGetCurrentContext();
    if (!ctx) return;
    NSArray *snap = g_frontBuf; // ARC — retain на время drawRect
    if (!snap) return;

    for (NSValue *v in snap) {
        PlayerESPData d; [v getValue:&d];
        if (!d.valid) continue;

        if (g_espBox && d.hasBox) {
            CGRect  rb = d.box;
            CGFloat cw = rb.size.width  * 0.25f;
            CGFloat ch = rb.size.height * 0.16f;
            CGFloat x  = rb.origin.x, y = rb.origin.y;
            CGFloat W  = rb.size.width, H = rb.size.height;

            CGContextSetLineWidth(ctx, 1.5f);
            CGContextSetShadowWithColor(ctx, CGSizeMake(0,0), 3.f,
                [UIColor.blackColor colorWithAlphaComponent:.95f].CGColor);
            CGContextSetStrokeColorWithColor(ctx,
                [UIColor colorWithRed:.3f green:.85f blue:1.f alpha:g_boxAlpha].CGColor);

#define C(x1,y1,x2,y2,x3,y3) \
    CGContextMoveToPoint(ctx,x1,y1); \
    CGContextAddLineToPoint(ctx,x2,y2); \
    CGContextAddLineToPoint(ctx,x3,y3);
            C(x,      y+ch,   x,   y,   x+cw, y);
            C(x+W-cw, y,      x+W, y,   x+W,  y+ch);
            C(x,      y+H-ch, x,   y+H, x+cw, y+H);
            C(x+W-cw, y+H,    x+W, y+H, x+W,  y+H-ch);
#undef C
            CGContextStrokePath(ctx);
            CGContextSetShadowWithColor(ctx, CGSizeZero, 0, NULL);
        }

        if (g_espSkel && d.hasSkel) {
            CGContextSetLineWidth(ctx, 1.0f);
            CGContextSetStrokeColorWithColor(ctx,
                [UIColor colorWithWhite:1.f alpha:.72f].CGColor);
            CGContextSetShadowWithColor(ctx, CGSizeMake(0,0), 2.5f,
                [UIColor.blackColor colorWithAlphaComponent:.85f].CGColor);

#define BL(a,b) \
    CGContextMoveToPoint(ctx,(a).x,(a).y); \
    CGContextAddLineToPoint(ctx,(b).x,(b).y);
            BL(d.head,      d.chest);
            BL(d.chest,     d.pelvis);
            BL(d.chest,     d.lShoulder);
            BL(d.lShoulder, d.lElbow);
            BL(d.lElbow,    d.lHand);
            BL(d.chest,     d.rShoulder);
            BL(d.rShoulder, d.rElbow);
            BL(d.rElbow,    d.rHand);
            BL(d.pelvis,    d.lHip);
            BL(d.pelvis,    d.rHip);
#undef BL
            CGContextStrokePath(ctx);
            CGContextSetShadowWithColor(ctx, CGSizeZero, 0, NULL);

            CGFloat hr = d.headR < 5.f ? 5.f : d.headR;
            CGRect  hc = CGRectMake(d.head.x - hr, d.head.y - hr, hr * 2.f, hr * 2.f);
            CGContextSetFillColorWithColor(ctx,
                [UIColor colorWithRed:.3f green:.85f blue:1.f alpha:.15f].CGColor);
            CGContextFillEllipseInRect(ctx, hc);
            CGContextSetLineWidth(ctx, 1.4f);
            CGContextSetStrokeColorWithColor(ctx,
                [UIColor colorWithRed:.3f green:.85f blue:1.f alpha:1.f].CGColor);
            CGContextSetShadowWithColor(ctx, CGSizeMake(0,0), 5.f,
                [UIColor colorWithRed:0.f green:.6f blue:1.f alpha:1.f].CGColor);
            CGContextStrokeEllipseInRect(ctx, hc);
            CGContextSetShadowWithColor(ctx, CGSizeZero, 0, NULL);
        }
    }
}
@end

// ═══════════════════════════════════════════════════════════
// MARK: — FABDragDelegate
// ═══════════════════════════════════════════════════════════

@interface FABDragDelegate : NSObject
@property (nonatomic, weak) UIView *target;
@end
@implementation FABDragDelegate {
    CGPoint _start;
}
- (void)pan:(UIPanGestureRecognizer *)gr {
    UIView *sv = self.target.superview; if (!sv) return;
    if (gr.state == UIGestureRecognizerStateBegan)
        _start = self.target.center;
    CGPoint t  = [gr translationInView:sv];
    CGFloat hw = self.target.bounds.size.width  * .5f;
    CGFloat hh = self.target.bounds.size.height * .5f;
    CGFloat nx = MAX(hw, MIN(sv.bounds.size.width  - hw, _start.x + t.x));
    CGFloat ny = MAX(hh, MIN(sv.bounds.size.height - hh, _start.y + t.y));
    self.target.center = CGPointMake(nx, ny);
}
@end

// ═══════════════════════════════════════════════════════════
// MARK: — MenuView
// ═══════════════════════════════════════════════════════════

@interface MenuView : UIView
@property (nonatomic, strong) UIButton *closeBtn;
- (void)syncToggles;
@end

@implementation MenuView {
    UISwitch *_swBox;
    UISwitch *_swSkel;
}

- (instancetype)init {
    const CGFloat W = 268.f, H = 150.f;
    CGFloat sx = UIScreen.mainScreen.bounds.size.width;
    CGFloat sy = UIScreen.mainScreen.bounds.size.height;
    self = [super initWithFrame:CGRectMake((sx - W) * .5f, sy - H - 100.f, W, H)];
    if (!self) return nil;
    self.backgroundColor     = cBg();
    self.layer.cornerRadius  = 3.f;
    self.layer.borderColor   = [UIColor colorWithWhite:.13f alpha:1.f].CGColor;
    self.layer.borderWidth   = .5f;
    self.layer.masksToBounds = YES;
    [self _build];
    UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc]
        initWithTarget:self action:@selector(_drag:)];
    [self addGestureRecognizer:pan];
    return self;
}

- (void)_build {
    const CGFloat W = self.bounds.size.width;

    UIView *hdr = [[UIView alloc] initWithFrame:CGRectMake(0, 0, W, 26.f)];
    hdr.backgroundColor = [UIColor colorWithRed:.05f green:.05f blue:.09f alpha:1.f];

    UILabel *lbl = [[UILabel alloc] initWithFrame:CGRectMake(10, 0, W - 40, 26)];
    lbl.text = @"COUNTERFLAME  ESP";
    lbl.textColor = cA();
    lbl.font = [UIFont monospacedSystemFontOfSize:9.f weight:UIFontWeightBold];

    self.closeBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    self.closeBtn.frame = CGRectMake(W - 28, 0, 28, 26);
    [self.closeBtn setTitle:@"✕" forState:UIControlStateNormal];
    [self.closeBtn setTitleColor:cSub() forState:UIControlStateNormal];
    [self.closeBtn setTitleColor:cTx()  forState:UIControlStateHighlighted];
    self.closeBtn.titleLabel.font =
        [UIFont systemFontOfSize:10.f weight:UIFontWeightLight];

    UIView *div = [[UIView alloc] initWithFrame:CGRectMake(0, 26, W, .5f)];
    div.backgroundColor = cDiv();

    [hdr addSubview:lbl];
    [hdr addSubview:self.closeBtn];
    [self addSubview:hdr];
    [self addSubview:div];

    CGFloat y = 34.f;
    _swBox  = [self _row:@"ESP Box"  sub:@"угловые линии"
                       y:y W:W val:g_espBox  sel:@selector(_tBox:)];  y += 44.f;
    _swSkel = [self _row:@"Skeleton" sub:@"кости + голова"
                       y:y W:W val:g_espSkel sel:@selector(_tSkel:)];
}

- (UISwitch *)_row:(NSString *)name sub:(NSString *)sub
                 y:(CGFloat)y W:(CGFloat)W val:(bool)val sel:(SEL)sel {
    UIView *row = [[UIView alloc] initWithFrame:CGRectMake(8, y, W - 16, 36)];
    row.backgroundColor    = cRow();
    row.layer.cornerRadius = 2.f;

    UILabel *lb = [[UILabel alloc] initWithFrame:CGRectMake(10, 3, W - 95, 15)];
    lb.text = name; lb.textColor = cTx();
    lb.font = [UIFont systemFontOfSize:11.5f weight:UIFontWeightMedium];

    UILabel *sb = [[UILabel alloc] initWithFrame:CGRectMake(10, 20, W - 95, 12)];
    sb.text = sub; sb.textColor = cSub();
    sb.font = [UIFont systemFontOfSize:9.f];

    UISwitch *sw = [[UISwitch alloc] init];
    [sw sizeToFit];
    sw.transform   = CGAffineTransformMakeScale(.72f, .72f);
    CGFloat swW = sw.frame.size.width;
    CGFloat swH = sw.frame.size.height;
    sw.frame = CGRectMake(W - 16 - swW - 4, (36.f - swH) * .5f, swW, swH);
    sw.on          = (BOOL)val;
    sw.onTintColor = cA();
    sw.tintColor   = [UIColor colorWithWhite:.15f alpha:1.f];
    [sw addTarget:self action:sel forControlEvents:UIControlEventValueChanged];

    [row addSubview:lb]; [row addSubview:sb]; [row addSubview:sw];
    [self addSubview:row];
    return sw;
}

- (void)_tBox:(UISwitch *)s  { g_espBox  = (bool)s.on; }
- (void)_tSkel:(UISwitch *)s { g_espSkel = (bool)s.on; }

- (void)syncToggles {
    _swBox.on  = (BOOL)g_espBox;
    _swSkel.on = (BOOL)g_espSkel;
}

- (void)_drag:(UIPanGestureRecognizer *)gr {
    UIView *sv = self.superview; if (!sv) return;
    CGPoint t = [gr translationInView:sv];
    self.center = CGPointMake(self.center.x + t.x, self.center.y + t.y);
    [gr setTranslation:CGPointZero inView:sv];
}
@end

// ═══════════════════════════════════════════════════════════
// MARK: — Ticker (CADisplayLink target)
// ═══════════════════════════════════════════════════════════

@interface CFTicker : NSObject
@property (nonatomic, weak) ESPView *espView;
@end
@implementation CFTicker
- (void)tick:(CADisplayLink *)__unused dl {
    resolveSymbols();
    collectFrame();
    [self.espView setNeedsDisplay];
}
@end

// ═══════════════════════════════════════════════════════════
// MARK: — Overlay
// ═══════════════════════════════════════════════════════════

static ESPView       *g_esp     = nil;
static MenuView      *g_menu    = nil;
static UIButton      *g_fab     = nil;
static CFTicker      *g_ticker  = nil;
static FABDragDelegate *g_fabDD = nil;
static bool           g_ready   = false;

static UIWindow *findWindow() {
    if ([UIApplication.sharedApplication
         respondsToSelector:@selector(connectedScenes)]) {
        for (UIScene *sc in UIApplication.sharedApplication.connectedScenes) {
            if (![sc isKindOfClass:UIWindowScene.class]) continue;
            UIWindowScene *ws = (UIWindowScene *)sc;
            for (UIWindow *w in ws.windows)
                if (!w.isHidden) return w;
        }
    }
    for (UIWindow *w in UIApplication.sharedApplication.windows)
        if (!w.isHidden) return w;
    return UIApplication.sharedApplication.keyWindow;
}

static void showMenu(bool show) {
    g_menu.hidden = !show;
    g_fab.hidden  =  show;
    if (show) [g_menu syncToggles];
}

static void injectOverlay() {
    if (g_ready) return;
    UIWindow *win = findWindow();
    if (!win) return;

    g_screen = UIScreen.mainScreen.bounds.size;

    // ESP
    g_esp = [[ESPView alloc] initWithFrame:win.bounds];
    g_esp.autoresizingMask =
        UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [win addSubview:g_esp];

    // Menu
    g_menu                 = [[MenuView alloc] init];
    g_menu.hidden          = YES;
    g_menu.layer.zPosition = 99995;
    [win addSubview:g_menu];

    __weak ESPView  *wESP  = g_esp;
    __weak MenuView *wMenu = g_menu;

    [g_menu.closeBtn addAction:
        [UIAction actionWithHandler:^(__kindof UIAction *__unused a) {
            showMenu(false);
            (void)wMenu; (void)wESP;
        }]
        forControlEvents:UIControlEventTouchUpInside];

    // FAB
    g_fab = [UIButton buttonWithType:UIButtonTypeCustom];
    g_fab.frame = CGRectMake(10.f, 130.f, 30.f, 30.f);
    g_fab.backgroundColor    = cBg();
    g_fab.layer.cornerRadius = 3.f;
    g_fab.layer.borderWidth  = .5f;
    g_fab.layer.borderColor  = [UIColor colorWithWhite:.16f alpha:1.f].CGColor;
    g_fab.layer.zPosition    = 99996;
    [g_fab setTitle:@"☰" forState:UIControlStateNormal];
    [g_fab setTitleColor:cA() forState:UIControlStateNormal];
    g_fab.titleLabel.font = [UIFont systemFontOfSize:13.f];
    g_fab.hidden = NO;

    [g_fab addAction:
        [UIAction actionWithHandler:^(__kindof UIAction *__unused a) {
            showMenu(true);
        }]
        forControlEvents:UIControlEventTouchUpInside];

    g_fabDD        = [[FABDragDelegate alloc] init];
    g_fabDD.target = g_fab;
    UIPanGestureRecognizer *fp = [[UIPanGestureRecognizer alloc]
        initWithTarget:g_fabDD action:@selector(pan:)];
    [g_fab addGestureRecognizer:fp];
    [win addSubview:g_fab];

    // Ticker @ 30 fps
    g_ticker         = [[CFTicker alloc] init];
    g_ticker.espView = g_esp;
    CADisplayLink *dl = [CADisplayLink displayLinkWithTarget:g_ticker
                                                    selector:@selector(tick:)];
    dl.preferredFramesPerSecond = 30;
    [dl addToRunLoop:NSRunLoop.mainRunLoop forMode:NSRunLoopCommonModes];

    g_ready = true;
}

// ═══════════════════════════════════════════════════════════
// MARK: — Entry
// ═══════════════════════════════════════════════════════════

@interface CFLoader : NSObject
@end
@implementation CFLoader
+ (void)load {
    dispatch_after(
        dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3.0 * NSEC_PER_SEC)),
        dispatch_get_main_queue(),
        ^{ injectOverlay(); });
}
@end

#pragma clang diagnostic pop
