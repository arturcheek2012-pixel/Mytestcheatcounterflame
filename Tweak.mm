// Tweak.mm — CounterFlame ESP
// Target: com.ScarletWork.CounterFlame.app
// iOS 14+, arm64, theos dylib
// не проверял на живом бинаре — FILL: RVA и итерация игроков под твой дамп

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wc++11-extensions"
#pragma clang diagnostic ignored "-Wabsolute-value"

#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#include <objc/runtime.h>
#include <mach-o/dyld.h>
#include <stdint.h>
#include <cmath>

// ─────────────────────────────────────────
// MARK: — Config
// ─────────────────────────────────────────

static bool  g_espBox      = true;
static bool  g_espSkeleton = true;
static float g_boxAlpha    = 0.85f;

// ─────────────────────────────────────────
// MARK: — IL2CPP types
// ─────────────────────────────────────────

typedef void*    Il2CppObject;
typedef void*    Transform;
typedef void*    Camera_t;

struct Vector3  { float x, y, z; };
struct Vector2  { float x, y; };
struct Quaternion { float x, y, z, w; };

// ─────────────────────────────────────────
// MARK: — Offsets
// ─────────────────────────────────────────

#define OFF_PC_CAMERA           0x30
#define OFF_PC_NETWORK          0x88
#define OFF_PC_ANIM_CTRL        0x98
#define OFF_PC_IS_DEATH         0xA8

#define OFF_PN_NET_POSITION     0xBC
#define OFF_PN_NET_ROTATION     0xC8

#define OFF_PAC_SKELETON        0x68

#define OFF_SK_HEAD             0xA8
#define OFF_SK_CHEST            0xB0
#define OFF_SK_PELVIS           0xB8
#define OFF_SK_L_UPPER_ARM      0xC0
#define OFF_SK_R_UPPER_ARM      0xC8
#define OFF_SK_L_THIGH          0xD0
#define OFF_SK_R_THIGH          0xD8
#define OFF_SK_L_FOREARM        0x38
#define OFF_SK_R_FOREARM        0x60  // FILL: уточни по дампу PlayerSkeleton
#define OFF_SK_L_HAND           0x40
#define OFF_SK_R_HAND           0x68  // FILL

// ─────────────────────────────────────────
// MARK: — IL2CPP helpers
// ─────────────────────────────────────────

static uintptr_t il2cpp_base = 0;

static uintptr_t getBase() {
    if (il2cpp_base) return il2cpp_base;
    for (uint32_t i = 0; i < _dyld_image_count(); i++) {
        const char* name = _dyld_get_image_name(i);
        if (name && strstr(name, "UnityFramework")) {
            il2cpp_base = (uintptr_t)_dyld_get_image_vmaddr_slide(i);
            return il2cpp_base;
        }
    }
    return 0;
}

template<typename T>
static inline T rd(uintptr_t addr) {
    if (!addr) {
        T zero;
        memset(&zero, 0, sizeof(T));
        return zero;
    }
    return *(T*)addr;
}

// ─────────────────────────────────────────
// MARK: — Function pointers
// ─────────────────────────────────────────

typedef Vector3 (*fn_TransformGetPos_t)(Transform t, void* method);
typedef Vector2 (*fn_WorldToScreen_t)(Camera_t cam, Vector3 world, void* method);

static fn_TransformGetPos_t fn_transformGetPos = NULL;
static fn_WorldToScreen_t   fn_worldToScreen   = NULL;

// FILL: RVA от UnityFramework — grep "Transform::get_position" и "Camera::WorldToScreenPoint" в dump.cs
#define RVA_TRANSFORM_GETPOS  0x0
#define RVA_WORLD2SCREEN      0x0

static void resolveSymbols() {
    uintptr_t b = getBase();
    if (!b) return;
    if (RVA_TRANSFORM_GETPOS) fn_transformGetPos = (fn_TransformGetPos_t)(b + RVA_TRANSFORM_GETPOS);
    if (RVA_WORLD2SCREEN)     fn_worldToScreen   = (fn_WorldToScreen_t)(b + RVA_WORLD2SCREEN);
}

static inline Vector3 bonePos(Transform bone) {
    if (!bone || !fn_transformGetPos) {
        Vector3 z; memset(&z, 0, sizeof(z)); return z;
    }
    return fn_transformGetPos(bone, NULL);
}

// ─────────────────────────────────────────
// MARK: — W2S
// ─────────────────────────────────────────

static CGSize screenSize;

static bool worldToScreen(Camera_t cam, Vector3 world, CGPoint *out) {
    if (!cam || !fn_worldToScreen) return false;
    Vector2 s = fn_worldToScreen(cam, world, NULL);
    out->x = (CGFloat)s.x;
    out->y = screenSize.height - (CGFloat)s.y;
    return (s.x > 0.0f && s.x < (float)screenSize.width && s.y > 0.0f);
}

// ─────────────────────────────────────────
// MARK: — ESP data
// ─────────────────────────────────────────

typedef struct {
    CGRect   box;
    bool     hasBox;
    CGPoint  head, chest, pelvis;
    CGPoint  lShoulder, rShoulder;
    CGPoint  lElbow, rElbow;
    CGPoint  lHand, rHand;
    CGPoint  lHip, rHip;
    float    headR;
    bool     valid;
} PlayerESPData;

static NSMutableArray *g_frameData;
static dispatch_semaphore_t g_dataSema;

// ─────────────────────────────────────────
// MARK: — ESP View
// ─────────────────────────────────────────

@interface ESPView : UIView
@end

@implementation ESPView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor        = [UIColor clearColor];
        self.userInteractionEnabled = NO;
        self.layer.zPosition        = 9999;
    }
    return self;
}

- (void)drawRect:(CGRect)rect {
    CGContextRef ctx = UIGraphicsGetCurrentContext();
    if (!ctx) return;

    dispatch_semaphore_wait(g_dataSema, DISPATCH_TIME_FOREVER);
    NSArray *snap = [g_frameData copy];
    dispatch_semaphore_signal(g_dataSema);

    for (NSValue *val in snap) {
        PlayerESPData d;
        [val getValue:&d];
        if (!d.valid) continue;

        // ── Box ──────────────────────────────────────
        if (g_espBox && d.hasBox) {
            CGRect r  = d.box;
            CGFloat cw = r.size.width  * 0.28f;
            CGFloat ch = r.size.height * 0.18f;

            CGContextSetLineWidth(ctx, 1.6f);
            CGContextSetShadowWithColor(ctx, CGSizeMake(0,0), 3.0f,
                [[UIColor blackColor] colorWithAlphaComponent:0.9f].CGColor);
            CGContextSetStrokeColorWithColor(ctx,
                [UIColor colorWithRed:0.35f green:0.85f blue:1.0f alpha:g_boxAlpha].CGColor);

            // top-left
            CGContextMoveToPoint(ctx, r.origin.x, r.origin.y + ch);
            CGContextAddLineToPoint(ctx, r.origin.x, r.origin.y);
            CGContextAddLineToPoint(ctx, r.origin.x + cw, r.origin.y);
            // top-right
            CGContextMoveToPoint(ctx, r.origin.x + r.size.width - cw, r.origin.y);
            CGContextAddLineToPoint(ctx, r.origin.x + r.size.width, r.origin.y);
            CGContextAddLineToPoint(ctx, r.origin.x + r.size.width, r.origin.y + ch);
            // bottom-left
            CGContextMoveToPoint(ctx, r.origin.x, r.origin.y + r.size.height - ch);
            CGContextAddLineToPoint(ctx, r.origin.x, r.origin.y + r.size.height);
            CGContextAddLineToPoint(ctx, r.origin.x + cw, r.origin.y + r.size.height);
            // bottom-right
            CGContextMoveToPoint(ctx, r.origin.x + r.size.width - cw, r.origin.y + r.size.height);
            CGContextAddLineToPoint(ctx, r.origin.x + r.size.width, r.origin.y + r.size.height);
            CGContextAddLineToPoint(ctx, r.origin.x + r.size.width, r.origin.y + r.size.height - ch);

            CGContextStrokePath(ctx);
            CGContextSetShadowWithColor(ctx, CGSizeZero, 0, NULL);
        }

        // ── Skeleton ─────────────────────────────────
        if (g_espSkeleton) {
            CGContextSetLineWidth(ctx, 1.1f);
            CGContextSetStrokeColorWithColor(ctx,
                [UIColor colorWithRed:1.0f green:1.0f blue:1.0f alpha:0.75f].CGColor);
            CGContextSetShadowWithColor(ctx, CGSizeMake(0,0), 2.5f,
                [[UIColor blackColor] colorWithAlphaComponent:0.8f].CGColor);

#define BL(a, b) \
    CGContextMoveToPoint(ctx, (a).x, (a).y); \
    CGContextAddLineToPoint(ctx, (b).x, (b).y);

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

            // Голова
            CGFloat hr = d.headR < 6.0f ? 6.0f : d.headR;
            CGRect hc  = CGRectMake(d.head.x - hr, d.head.y - hr, hr * 2.0f, hr * 2.0f);

            CGContextSetFillColorWithColor(ctx,
                [UIColor colorWithRed:0.35f green:0.85f blue:1.0f alpha:0.18f].CGColor);
            CGContextFillEllipseInRect(ctx, hc);

            CGContextSetLineWidth(ctx, 1.4f);
            CGContextSetStrokeColorWithColor(ctx,
                [UIColor colorWithRed:0.35f green:0.85f blue:1.0f alpha:0.95f].CGColor);
            CGContextSetShadowWithColor(ctx, CGSizeMake(0,0), 4.0f,
                [UIColor colorWithRed:0.0f green:0.6f blue:1.0f alpha:0.9f].CGColor);
            CGContextStrokeEllipseInRect(ctx, hc);
            CGContextSetShadowWithColor(ctx, CGSizeZero, 0, NULL);
        }
    }
}

@end

// ─────────────────────────────────────────
// MARK: — Menu
// ─────────────────────────────────────────

static UIColor *clrAccent()  { return [UIColor colorWithRed:0.35f green:0.85f blue:1.0f alpha:1.0f]; }
static UIColor *clrBg()      { return [UIColor colorWithRed:0.06f green:0.06f blue:0.09f alpha:0.94f]; }
static UIColor *clrPanel()   { return [UIColor colorWithRed:0.09f green:0.09f blue:0.13f alpha:1.0f]; }
static UIColor *clrPrimary() { return [UIColor colorWithWhite:0.92f alpha:1.0f]; }
static UIColor *clrSub()     { return [UIColor colorWithWhite:0.45f alpha:1.0f]; }

@interface MenuView : UIView
@end

@implementation MenuView

- (instancetype)init {
    CGFloat W  = 310.0f, H = 190.0f;
    CGFloat sx = [UIScreen mainScreen].bounds.size.width;
    CGFloat sy = [UIScreen mainScreen].bounds.size.height;
    self = [super initWithFrame:CGRectMake((sx - W) * 0.5f, sy - H - 90.0f, W, H)];
    if (!self) return nil;

    self.backgroundColor     = clrBg();
    self.layer.cornerRadius  = 6.0f;
    self.layer.masksToBounds = YES;
    self.layer.borderColor   = [UIColor colorWithWhite:0.18f alpha:1.0f].CGColor;
    self.layer.borderWidth   = 0.5f;

    [self buildUI];

    UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc]
        initWithTarget:self action:@selector(handlePan:)];
    [self addGestureRecognizer:pan];

    return self;
}

- (void)buildUI {
    CGFloat W = self.bounds.size.width;

    // Tab bar
    UIView *tab = [[UIView alloc] initWithFrame:CGRectMake(0, 0, W, 34.0f)];
    tab.backgroundColor = clrPanel();

    UILabel *title = [[UILabel alloc] initWithFrame:CGRectMake(10, 0, 80, 34)];
    title.text      = @"FLAME";
    title.textColor = clrAccent();
    title.font      = [UIFont systemFontOfSize:11.0f weight:UIFontWeightHeavy];

    // Tab: ESP
    UIButton *tESP = [[UIButton alloc] initWithFrame:CGRectMake(88, 0, 60, 34)];
    [tESP setTitle:@"ESP" forState:UIControlStateNormal];
    [tESP setTitleColor:clrAccent() forState:UIControlStateNormal];
    tESP.titleLabel.font = [UIFont systemFontOfSize:11.0f weight:UIFontWeightSemibold];
    UIView *line = [[UIView alloc] initWithFrame:CGRectMake(0, 31.0f, 60, 2.0f)];
    line.backgroundColor     = clrAccent();
    line.layer.cornerRadius  = 1.0f;
    [tESP addSubview:line];

    UILabel *handle = [[UILabel alloc] initWithFrame:CGRectMake(W - 34, 0, 34, 34)];
    handle.text          = @"⠿";
    handle.textColor     = clrSub();
    handle.font          = [UIFont systemFontOfSize:14.0f];
    handle.textAlignment = NSTextAlignmentCenter;

    [tab addSubview:title];
    [tab addSubview:tESP];
    [tab addSubview:handle];
    [self addSubview:tab];

    UIView *sep = [[UIView alloc] initWithFrame:CGRectMake(0, 34, W, 0.5f)];
    sep.backgroundColor = [UIColor colorWithWhite:0.2f alpha:1.0f];
    [self addSubview:sep];

    // Rows
    CGFloat py = 34.5f + 10.0f;
    py = [self row:@"ESP Box"   sub:@"Угловой box вокруг игрока" on:g_espBox   y:py W:W
         toggle:^(BOOL v){ g_espBox = (bool)v; }];
    py = [self row:@"Skeleton"  sub:@"Тонкий скелет + голова"    on:g_espSkeleton y:py W:W
         toggle:^(BOOL v){ g_espSkeleton = (bool)v; }];
}

- (CGFloat)row:(NSString*)name sub:(NSString*)sub on:(bool)on
             y:(CGFloat)y W:(CGFloat)W
        toggle:(void(^)(BOOL))blk {
    UIView *row = [[UIView alloc] initWithFrame:CGRectMake(8, y, W - 16, 44)];
    row.backgroundColor    = clrPanel();
    row.layer.cornerRadius = 5.0f;

    UILabel *lb = [[UILabel alloc] initWithFrame:CGRectMake(12, 5, W - 100, 18)];
    lb.text      = name;
    lb.textColor = clrPrimary();
    lb.font      = [UIFont systemFontOfSize:12.0f weight:UIFontWeightMedium];

    UILabel *sb = [[UILabel alloc] initWithFrame:CGRectMake(12, 23, W - 100, 13)];
    sb.text      = sub;
    sb.textColor = clrSub();
    sb.font      = [UIFont systemFontOfSize:10.0f];

    UISwitch *sw = [[UISwitch alloc] init];
    sw.frame       = CGRectMake(W - 70, 10, 51, 31);
    sw.transform   = CGAffineTransformMakeScale(0.75f, 0.75f);
    sw.on          = on;
    sw.onTintColor = clrAccent();

    void(^captured)(BOOL) = blk;
    [sw addAction:[UIAction actionWithHandler:^(UIAction *a){
        captured(((UISwitch *)a.sender).on);
    }] forControlEvents:UIControlEventValueChanged];

    [row addSubview:lb];
    [row addSubview:sb];
    [row addSubview:sw];
    [self addSubview:row];
    return y + 50.0f;
}

- (void)handlePan:(UIPanGestureRecognizer *)gr {
    UIView *sv = self.superview;
    if (!sv) return;
    CGPoint t = [gr translationInView:sv];
    self.center = CGPointMake(self.center.x + t.x, self.center.y + t.y);
    [gr setTranslation:CGPointZero inView:sv];
}

@end

// ─────────────────────────────────────────
// MARK: — Globals
// ─────────────────────────────────────────

static ESPView  *g_esp       = nil;
static MenuView *g_menu      = nil;
static bool      g_menuVis   = false;

// FILL: заполни из хука PhotonView / _actorToView
Il2CppObject   **g_playerControllers = NULL;
int              g_playerCount       = 0;

// ─────────────────────────────────────────
// MARK: — ESP frame collection
// ─────────────────────────────────────────

static void collectESPFrame(Camera_t cam) {
    if (!cam || !g_playerControllers || g_playerCount <= 0) return;

    NSMutableArray *newData = [NSMutableArray arrayWithCapacity:(NSUInteger)g_playerCount];

    for (int i = 0; i < g_playerCount; i++) {
        Il2CppObject *pc = g_playerControllers[i];
        if (!pc) continue;

        bool dead = rd<bool>((uintptr_t)pc + OFF_PC_IS_DEATH);
        if (dead) continue;

        Il2CppObject *net = rd<Il2CppObject *>((uintptr_t)pc + OFF_PC_NETWORK);
        if (!net) continue;

        Vector3 wPos = rd<Vector3>((uintptr_t)net + OFF_PN_NET_POSITION);

        Il2CppObject *animCtrl = rd<Il2CppObject *>((uintptr_t)pc + OFF_PC_ANIM_CTRL);
        Il2CppObject *skeleton = animCtrl
            ? rd<Il2CppObject *>((uintptr_t)animCtrl + OFF_PAC_SKELETON)
            : NULL;

        PlayerESPData d;
        memset(&d, 0, sizeof(d));

        if (skeleton) {
            Transform head   = rd<Transform>((uintptr_t)skeleton + OFF_SK_HEAD);
            Transform chest  = rd<Transform>((uintptr_t)skeleton + OFF_SK_CHEST);
            Transform pelvis = rd<Transform>((uintptr_t)skeleton + OFF_SK_PELVIS);
            Transform lArm   = rd<Transform>((uintptr_t)skeleton + OFF_SK_L_UPPER_ARM);
            Transform rArm   = rd<Transform>((uintptr_t)skeleton + OFF_SK_R_UPPER_ARM);
            Transform lFore  = rd<Transform>((uintptr_t)skeleton + OFF_SK_L_FOREARM);
            Transform rFore  = rd<Transform>((uintptr_t)skeleton + OFF_SK_R_FOREARM);
            Transform lHand  = rd<Transform>((uintptr_t)skeleton + OFF_SK_L_HAND);
            Transform rHand  = rd<Transform>((uintptr_t)skeleton + OFF_SK_R_HAND);
            Transform lThigh = rd<Transform>((uintptr_t)skeleton + OFF_SK_L_THIGH);
            Transform rThigh = rd<Transform>((uintptr_t)skeleton + OFF_SK_R_THIGH);

            bool ok = true;
            CGPoint p;

#define W2S(bone, dst) ok &= worldToScreen(cam, bonePos(bone), &p); (dst) = p;

            W2S(head,   d.head);
            W2S(chest,  d.chest);
            W2S(pelvis, d.pelvis);
            W2S(lArm,   d.lShoulder);
            W2S(rArm,   d.rShoulder);
            W2S(lFore,  d.lElbow);
            W2S(rFore,  d.rElbow);
            W2S(lHand,  d.lHand);
            W2S(rHand,  d.rHand);
            W2S(lThigh, d.lHip);
            W2S(rThigh, d.rHip);
#undef W2S

            if (ok) {
                CGFloat boxH  = d.pelvis.y - d.head.y;
                CGFloat absH  = std::abs(boxH);
                d.headR       = (float)(absH * 0.09f);
                CGFloat bw    = absH * 0.45f;
                d.box         = CGRectMake(d.head.x - bw * 0.5f,
                                           d.head.y - d.headR * 1.5f,
                                           bw,
                                           absH + d.headR * 2.0f);
                d.hasBox = true;
                d.valid  = true;
            }
        }

        // fallback box по networkPosition
        if (!d.valid) {
            Vector3 top3 = { wPos.x, wPos.y + 1.75f, wPos.z };
            Vector3 bot3 = { wPos.x, wPos.y,          wPos.z };
            CGPoint top, bot;
            if (worldToScreen(cam, top3, &top) && worldToScreen(cam, bot3, &bot)) {
                CGFloat bh = std::abs(bot.y - top.y);
                CGFloat bw = bh * 0.45f;
                d.box   = CGRectMake(top.x - bw * 0.5f, top.y, bw, bh);
                d.hasBox = true;
                d.valid  = true;
                // head fallback
                d.head  = top;
                d.headR = (float)(bh * 0.09f);
            }
        }

        [newData addObject:[NSValue value:&d withObjCType:@encode(PlayerESPData)]];
    }

    dispatch_semaphore_wait(g_dataSema, DISPATCH_TIME_FOREVER);
    g_frameData = newData;
    dispatch_semaphore_signal(g_dataSema);

    dispatch_async(dispatch_get_main_queue(), ^{
        [g_esp setNeedsDisplay];
    });
}

// ─────────────────────────────────────────
// MARK: — Overlay setup
// ─────────────────────────────────────────

static void setupOverlay() {
    UIWindow *win = nil;
    for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {
        if ([scene isKindOfClass:[UIWindowScene class]]) {
            UIWindowScene *ws = (UIWindowScene *)scene;
            win = ws.windows.firstObject;
            if (win) break;
        }
    }
    if (!win) win = [UIApplication sharedApplication].windows.firstObject;
    if (!win) return;

    screenSize = [UIScreen mainScreen].bounds.size;

    g_esp = [[ESPView alloc] initWithFrame:win.bounds];
    g_esp.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [win addSubview:g_esp];

    g_menu = [[MenuView alloc] init];
    g_menu.hidden = YES;
    [win addSubview:g_menu];

    // Floating toggle
    UIButton *tog = [UIButton buttonWithType:UIButtonTypeCustom];
    tog.frame               = CGRectMake(10, 100, 38, 38);
    tog.backgroundColor     = [UIColor colorWithRed:0.06f green:0.06f blue:0.09f alpha:0.88f];
    tog.layer.cornerRadius  = 5.0f;
    tog.layer.borderWidth   = 0.5f;
    tog.layer.borderColor   = [UIColor colorWithWhite:0.22f alpha:1.0f].CGColor;
    [tog setTitle:@"▤" forState:UIControlStateNormal];
    [tog setTitleColor:clrAccent() forState:UIControlStateNormal];
    tog.titleLabel.font = [UIFont systemFontOfSize:18.0f];

    [tog addAction:[UIAction actionWithHandler:^(UIAction *a){
        g_menuVis    = !g_menuVis;
        g_menu.hidden = !g_menuVis;
    }] forControlEvents:UIControlEventTouchUpInside];

    [win addSubview:tog];
}

// ─────────────────────────────────────────
// MARK: — Hooks
// ─────────────────────────────────────────

// applicationDidFinishLaunching — оригинальный ObjC класс UnityAppController
static IMP orig_didFinishLaunching;
static BOOL hooked_didFinishLaunching(id self, SEL _cmd, UIApplication *app, NSDictionary *opts) {
    BOOL r = ((BOOL(*)(id,SEL,UIApplication*,NSDictionary*))orig_didFinishLaunching)(self, _cmd, app, opts);
    resolveSymbols();
    g_dataSema  = dispatch_semaphore_create(1);
    g_frameData = [NSMutableArray new];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.5 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{ setupOverlay(); });
    return r;
}

// FILL: хук Update — вставь имя класса и селектор из dump.cs
// Пример — UnityEngine.Camera.LateUpdate или PlayerController.Update
// static IMP orig_gameUpdate;
// static void hooked_gameUpdate(id self, SEL _cmd) {
//     orig_gameUpdate(self, _cmd);
//     // FILL: достать mainCamera из self или Camera.main
//     Camera_t cam = /* rd<Camera_t>((uintptr_t)(__bridge void*)self + OFF_PC_CAMERA) */;
//     collectESPFrame(cam);
// }

// ─────────────────────────────────────────
// MARK: — Ctor
// ─────────────────────────────────────────

__attribute__((constructor))
static void tweak_init() {
    NSString *bid = [[NSBundle mainBundle] bundleIdentifier];
    if (![bid isEqualToString:@"com.ScarletWork.CounterFlame"]) return;

    // hook UnityAppController
    Class cls = NSClassFromString(@"UnityAppController");
    if (cls) {
        SEL sel = @selector(application:didFinishLaunchingWithOptions:);
        Method m = class_getInstanceMethod(cls, sel);
        if (m) {
            orig_didFinishLaunching = method_getImplementation(m);
            method_setImplementation(m, (IMP)hooked_didFinishLaunching);
        }
    }
}
