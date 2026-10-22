// Tweak.mm — CounterFlame ESP
// Target : com.ScarletWork.CounterFlame.app
// Runtime: LiveContainer, iOS 16-26, arm64
// не проверял на живом бинаре — FILL: RVA под твой дамп

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wc++11-extensions"
#pragma clang diagnostic ignored "-Wabsolute-value"
#pragma clang diagnostic ignored "-Wdeprecated-declarations"

#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <QuartzCore/QuartzCore.h>
#include <objc/runtime.h>
#include <mach-o/dyld.h>
#include <stdint.h>
#include <cmath>

// ═══════════════════════════════════════════════
// MARK: — Config
// ═══════════════════════════════════════════════

static bool  g_espBox      = true;
static bool  g_espSkeleton = true;
static float g_boxAlpha    = 0.85f;

// ═══════════════════════════════════════════════
// MARK: — IL2CPP types
// ═══════════════════════════════════════════════

typedef void* Il2CppObject;
typedef void* Transform;
typedef void* Camera_t;

struct Vector3    { float x, y, z; };
struct Vector2    { float x, y; };
struct Quaternion { float x, y, z, w; };

// ═══════════════════════════════════════════════
// MARK: — Offsets
// ═══════════════════════════════════════════════

#define OFF_PC_NETWORK      0x88
#define OFF_PC_ANIM_CTRL    0x98
#define OFF_PC_IS_DEATH     0xA8
#define OFF_PC_CAMERA       0x30

#define OFF_PN_NET_POSITION 0xBC

#define OFF_PAC_SKELETON    0x68

#define OFF_SK_HEAD         0xA8
#define OFF_SK_CHEST        0xB0
#define OFF_SK_PELVIS       0xB8
#define OFF_SK_L_UPPER_ARM  0xC0
#define OFF_SK_R_UPPER_ARM  0xC8
#define OFF_SK_L_THIGH      0xD0
#define OFF_SK_R_THIGH      0xD8
#define OFF_SK_L_FOREARM    0x38
#define OFF_SK_R_FOREARM    0x60   // FILL: уточни по дампу
#define OFF_SK_L_HAND       0x40
#define OFF_SK_R_HAND       0x68   // FILL

// FILL: RVA от базы UnityFramework
// grep "Transform::get_position" и "Camera::WorldToScreenPoint" в dump.cs
#define RVA_TRANSFORM_GETPOS  0x0
#define RVA_WORLD2SCREEN      0x0

// ═══════════════════════════════════════════════
// MARK: — IL2CPP helpers
// ═══════════════════════════════════════════════

static uintptr_t s_base = 0;

static uintptr_t getBase() {
    if (s_base) return s_base;
    for (uint32_t i = 0, n = _dyld_image_count(); i < n; i++) {
        const char *nm = _dyld_get_image_name(i);
        if (nm && strstr(nm, "UnityFramework")) {
            s_base = (uintptr_t)_dyld_get_image_vmaddr_slide(i);
            return s_base;
        }
    }
    return 0;
}

template<typename T>
static inline T rd(uintptr_t a) {
    if (!a) { T z; memset(&z,0,sizeof(z)); return z; }
    return *(T*)a;
}

typedef Vector3 (*PFN_GetPos)(Transform, void*);
typedef Vector2 (*PFN_W2S)(Camera_t, Vector3, void*);

static PFN_GetPos s_getPos = NULL;
static PFN_W2S    s_w2s    = NULL;

static void resolveSymbols() {
    uintptr_t b = getBase();
    if (!b) return;
    if (RVA_TRANSFORM_GETPOS) s_getPos = (PFN_GetPos)(b + RVA_TRANSFORM_GETPOS);
    if (RVA_WORLD2SCREEN)     s_w2s    = (PFN_W2S)  (b + RVA_WORLD2SCREEN);
}

static inline Vector3 bonePos(Transform bone) {
    if (!bone || !s_getPos) { Vector3 z; memset(&z,0,sizeof(z)); return z; }
    return s_getPos(bone, NULL);
}

// ═══════════════════════════════════════════════
// MARK: — W2S
// ═══════════════════════════════════════════════

static CGSize g_screen;

static bool w2s(Camera_t cam, Vector3 w, CGPoint *out) {
    if (!cam || !s_w2s) return false;
    Vector2 s = s_w2s(cam, w, NULL);
    out->x = (CGFloat)s.x;
    out->y = g_screen.height - (CGFloat)s.y;
    return s.x > 0.f && s.x < (float)g_screen.width && s.y > 0.f;
}

// ═══════════════════════════════════════════════
// MARK: — ESP data
// ═══════════════════════════════════════════════

typedef struct {
    CGRect  box;
    bool    hasBox;
    CGPoint head, chest, pelvis;
    CGPoint lShoulder, rShoulder;
    CGPoint lElbow, rElbow;
    CGPoint lHand, rHand;
    CGPoint lHip, rHip;
    float   headR;
    bool    valid;
} PlayerESPData;

static NSMutableArray       *g_frameData = nil;
static dispatch_semaphore_t  g_sema;

// ═══════════════════════════════════════════════
// MARK: — Player list (FILL)
// ═══════════════════════════════════════════════

// Заполни из хука PhotonView / _actorToView
Il2CppObject **g_players = NULL;
int            g_playerCount = 0;

// ═══════════════════════════════════════════════
// MARK: — ESPView
// ═══════════════════════════════════════════════

@interface ESPView : UIView
@end
@implementation ESPView

- (instancetype)initWithFrame:(CGRect)f {
    self = [super initWithFrame:f];
    self.backgroundColor        = UIColor.clearColor;
    self.userInteractionEnabled = NO;
    self.layer.zPosition        = 99998;
    return self;
}

- (void)drawRect:(CGRect)r {
    CGContextRef ctx = UIGraphicsGetCurrentContext();
    if (!ctx) return;

    dispatch_semaphore_wait(g_sema, DISPATCH_TIME_FOREVER);
    NSArray *snap = [g_frameData copy];
    dispatch_semaphore_signal(g_sema);

    for (NSValue *v in snap) {
        PlayerESPData d; [v getValue:&d];
        if (!d.valid) continue;

        // — Box —
        if (g_espBox && d.hasBox) {
            CGRect  rb = d.box;
            CGFloat cw = rb.size.width  * 0.28f;
            CGFloat ch = rb.size.height * 0.18f;
            CGContextSetLineWidth(ctx, 1.6f);
            CGContextSetShadowWithColor(ctx, CGSizeMake(0,0), 3.f,
                [UIColor.blackColor colorWithAlphaComponent:0.9f].CGColor);
            CGContextSetStrokeColorWithColor(ctx,
                [UIColor colorWithRed:.35f green:.85f blue:1.f alpha:g_boxAlpha].CGColor);
#define CORNER(x1,y1,x2,y2,x3,y3) \
    CGContextMoveToPoint(ctx,x1,y1); \
    CGContextAddLineToPoint(ctx,x2,y2); \
    CGContextAddLineToPoint(ctx,x3,y3);
            CGFloat x=rb.origin.x, y=rb.origin.y, W=rb.size.width, H=rb.size.height;
            CORNER(x, y+ch,       x,    y,    x+cw, y);
            CORNER(x+W-cw, y,     x+W,  y,    x+W,  y+ch);
            CORNER(x, y+H-ch,     x,    y+H,  x+cw, y+H);
            CORNER(x+W-cw, y+H,   x+W,  y+H,  x+W,  y+H-ch);
#undef CORNER
            CGContextStrokePath(ctx);
            CGContextSetShadowWithColor(ctx, CGSizeZero, 0, NULL);
        }

        // — Skeleton —
        if (g_espSkeleton) {
            CGContextSetLineWidth(ctx, 1.1f);
            CGContextSetStrokeColorWithColor(ctx,
                [UIColor colorWithWhite:1.f alpha:.75f].CGColor);
            CGContextSetShadowWithColor(ctx, CGSizeMake(0,0), 2.5f,
                [UIColor.blackColor colorWithAlphaComponent:.8f].CGColor);
#define BL(a,b) CGContextMoveToPoint(ctx,(a).x,(a).y); CGContextAddLineToPoint(ctx,(b).x,(b).y);
            BL(d.head,      d.chest);
            BL(d.chest,     d.pelvis);
            BL(d.chest,     d.lShoulder); BL(d.lShoulder, d.lElbow); BL(d.lElbow, d.lHand);
            BL(d.chest,     d.rShoulder); BL(d.rShoulder, d.rElbow); BL(d.rElbow, d.rHand);
            BL(d.pelvis,    d.lHip);
            BL(d.pelvis,    d.rHip);
#undef BL
            CGContextStrokePath(ctx);
            CGContextSetShadowWithColor(ctx, CGSizeZero, 0, NULL);

            // Голова — выделенный круг
            CGFloat hr = d.headR < 6.f ? 6.f : d.headR;
            CGRect  hc = CGRectMake(d.head.x-hr, d.head.y-hr, hr*2.f, hr*2.f);
            CGContextSetFillColorWithColor(ctx,
                [UIColor colorWithRed:.35f green:.85f blue:1.f alpha:.18f].CGColor);
            CGContextFillEllipseInRect(ctx, hc);
            CGContextSetLineWidth(ctx, 1.4f);
            CGContextSetStrokeColorWithColor(ctx,
                [UIColor colorWithRed:.35f green:.85f blue:1.f alpha:.95f].CGColor);
            CGContextSetShadowWithColor(ctx, CGSizeMake(0,0), 4.f,
                [UIColor colorWithRed:0 green:.6f blue:1.f alpha:.9f].CGColor);
            CGContextStrokeEllipseInRect(ctx, hc);
            CGContextSetShadowWithColor(ctx, CGSizeZero, 0, NULL);
        }
    }
}
@end

// ═══════════════════════════════════════════════
// MARK: — Colors
// ═══════════════════════════════════════════════

static UIColor *cAccent()  { return [UIColor colorWithRed:.35f green:.85f blue:1.f alpha:1.f]; }
static UIColor *cBg()      { return [UIColor colorWithRed:.06f green:.06f blue:.09f alpha:.95f]; }
static UIColor *cPanel()   { return [UIColor colorWithRed:.09f green:.09f blue:.13f alpha:1.f]; }
static UIColor *cPrim()    { return [UIColor colorWithWhite:.92f alpha:1.f]; }
static UIColor *cSub()     { return [UIColor colorWithWhite:.45f alpha:1.f]; }

// ═══════════════════════════════════════════════
// MARK: — MenuView
// ═══════════════════════════════════════════════

@interface MenuView : UIView
@end
@implementation MenuView

- (instancetype)init {
    CGFloat W = 310.f, H = 195.f;
    CGFloat sx = UIScreen.mainScreen.bounds.size.width;
    CGFloat sy = UIScreen.mainScreen.bounds.size.height;
    self = [super initWithFrame:CGRectMake((sx-W)*.5f, sy-H-100.f, W, H)];
    self.backgroundColor     = cBg();
    self.layer.cornerRadius  = 6.f;
    self.layer.masksToBounds = YES;
    self.layer.borderColor   = [UIColor colorWithWhite:.18f alpha:1.f].CGColor;
    self.layer.borderWidth   = .5f;
    [self buildUI];
    UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc]
        initWithTarget:self action:@selector(onPan:)];
    [self addGestureRecognizer:pan];
    return self;
}

- (void)buildUI {
    CGFloat W = self.bounds.size.width;

    // Tab bar
    UIView *tb = [[UIView alloc] initWithFrame:CGRectMake(0,0,W,34)];
    tb.backgroundColor = cPanel();

    UILabel *logo = [[UILabel alloc] initWithFrame:CGRectMake(10,0,80,34)];
    logo.text = @"FLAME"; logo.textColor = cAccent();
    logo.font = [UIFont systemFontOfSize:11 weight:UIFontWeightHeavy];
    [tb addSubview:logo];

    UIButton *tESP = [[UIButton alloc] initWithFrame:CGRectMake(88,0,60,34)];
    [tESP setTitle:@"ESP" forState:UIControlStateNormal];
    [tESP setTitleColor:cAccent() forState:UIControlStateNormal];
    tESP.titleLabel.font = [UIFont systemFontOfSize:11 weight:UIFontWeightSemibold];
    UIView *ln = [[UIView alloc] initWithFrame:CGRectMake(0,31,60,2)];
    ln.backgroundColor = cAccent(); ln.layer.cornerRadius = 1;
    [tESP addSubview:ln];
    [tb addSubview:tESP];

    UILabel *drag = [[UILabel alloc] initWithFrame:CGRectMake(W-34,0,34,34)];
    drag.text = @"⠿"; drag.textColor = cSub();
    drag.font = [UIFont systemFontOfSize:14]; drag.textAlignment = NSTextAlignmentCenter;
    [tb addSubview:drag];
    [self addSubview:tb];

    UIView *sep = [[UIView alloc] initWithFrame:CGRectMake(0,34,W,.5f)];
    sep.backgroundColor = [UIColor colorWithWhite:.2f alpha:1];
    [self addSubview:sep];

    CGFloat py = 44.f;
    py = [self addRow:@"ESP Box"  sub:@"Угловой box вокруг игрока" val:g_espBox   y:py W:W
              toggle:^(BOOL v){ g_espBox = (bool)v; }];
    py = [self addRow:@"Skeleton" sub:@"Тонкий скелет + голова"    val:g_espSkeleton y:py W:W
              toggle:^(BOOL v){ g_espSkeleton = (bool)v; }];
}

- (CGFloat)addRow:(NSString*)name sub:(NSString*)sub val:(bool)val
                y:(CGFloat)y W:(CGFloat)W toggle:(void(^)(BOOL))blk {
    UIView *row = [[UIView alloc] initWithFrame:CGRectMake(8,y,W-16,44)];
    row.backgroundColor = cPanel(); row.layer.cornerRadius = 5;

    UILabel *lb = [[UILabel alloc] initWithFrame:CGRectMake(12,5,W-100,18)];
    lb.text = name; lb.textColor = cPrim();
    lb.font = [UIFont systemFontOfSize:12 weight:UIFontWeightMedium];

    UILabel *sb = [[UILabel alloc] initWithFrame:CGRectMake(12,23,W-100,13)];
    sb.text = sub; sb.textColor = cSub();
    sb.font = [UIFont systemFontOfSize:10];

    UISwitch *sw = [[UISwitch alloc] init];
    sw.frame = CGRectMake(W-70,10,51,31);
    sw.transform = CGAffineTransformMakeScale(.75f,.75f);
    sw.on = val; sw.onTintColor = cAccent();

    void(^cap)(BOOL) = blk;
    [sw addAction:[UIAction actionWithHandler:^(UIAction *a){
        cap(((UISwitch*)a.sender).on);
    }] forControlEvents:UIControlEventValueChanged];

    [row addSubview:lb]; [row addSubview:sb]; [row addSubview:sw];
    [self addSubview:row];
    return y + 50.f;
}

- (void)onPan:(UIPanGestureRecognizer*)gr {
    UIView *sv = self.superview; if (!sv) return;
    CGPoint t = [gr translationInView:sv];
    self.center = CGPointMake(self.center.x+t.x, self.center.y+t.y);
    [gr setTranslation:CGPointZero inView:sv];
}
@end

// ═══════════════════════════════════════════════
// MARK: — Overlay globals + inject
// ═══════════════════════════════════════════════

static ESPView  *g_esp     = nil;
static MenuView *g_menu    = nil;
static bool      g_menuVis = false;
static bool      g_overlayReady = false;

// Ищем окно через все доступные API — работает на iOS 13-26 и в LiveContainer
static UIWindow *findWindow() {
    // iOS 15+ / LiveContainer: connectedScenes
    if ([UIApplication.sharedApplication respondsToSelector:@selector(connectedScenes)]) {
        for (UIScene *sc in UIApplication.sharedApplication.connectedScenes) {
            if (![sc isKindOfClass:UIWindowScene.class]) continue;
            UIWindowScene *ws = (UIWindowScene*)sc;
            for (UIWindow *w in ws.windows) {
                if (!w.isHidden && w.windowLevel == UIWindowLevelNormal) return w;
            }
            if (ws.windows.firstObject) return ws.windows.firstObject;
        }
    }
    // fallback legacy
    for (UIWindow *w in UIApplication.sharedApplication.windows) {
        if (!w.isHidden) return w;
    }
    return UIApplication.sharedApplication.keyWindow;
}

static void injectOverlay() {
    if (g_overlayReady) return;

    UIWindow *win = findWindow();
    if (!win) return;

    g_screen = UIScreen.mainScreen.bounds.size;

    g_esp = [[ESPView alloc] initWithFrame:win.bounds];
    g_esp.autoresizingMask = UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight;
    [win addSubview:g_esp];

    g_menu = [[MenuView alloc] init];
    g_menu.hidden = YES;
    [win addSubview:g_menu];

    UIButton *tog = [UIButton buttonWithType:UIButtonTypeCustom];
    tog.frame              = CGRectMake(10, 120, 40, 40);
    tog.backgroundColor    = [UIColor colorWithRed:.06f green:.06f blue:.09f alpha:.9f];
    tog.layer.cornerRadius = 6.f;
    tog.layer.borderWidth  = .5f;
    tog.layer.borderColor  = [UIColor colorWithWhite:.22f alpha:1].CGColor;
    tog.layer.zPosition    = 99999;
    [tog setTitle:@"▤" forState:UIControlStateNormal];
    [tog setTitleColor:cAccent() forState:UIControlStateNormal];
    tog.titleLabel.font = [UIFont systemFontOfSize:18];
    [tog addAction:[UIAction actionWithHandler:^(UIAction *a){
        g_menuVis = !g_menuVis;
        g_menu.hidden = !g_menuVis;
    }] forControlEvents:UIControlEventTouchUpInside];
    [win addSubview:tog];

    g_overlayReady = true;
}

// ═══════════════════════════════════════════════
// MARK: — Polling CADisplayLink
// Крутится пока не найдёт окно, потом останавливается
// ═══════════════════════════════════════════════

@interface CFPoller : NSObject
+ (void)start;
@end
@implementation CFPoller {
    CADisplayLink *_dl;
    int _ticks;
}
+ (void)start {
    static CFPoller *p; // retain
    p = [[CFPoller alloc] init];
    [p begin];
}
- (void)begin {
    _dl = [CADisplayLink displayLinkWithTarget:self selector:@selector(tick)];
    _dl.preferredFramesPerSecond = 10;
    [_dl addToRunLoop:NSRunLoop.mainRunLoop forMode:NSRunLoopCommonModes];
}
- (void)tick {
    _ticks++;
    if (!g_overlayReady) {
        injectOverlay();
    }
    // Останавливаемся через 30 сек или когда готово + ещё 5 тиков
    if (g_overlayReady || _ticks > 300) {
        [_dl invalidate];
    }
}
@end

// ═══════════════════════════════════════════════
// MARK: — ESP frame collection
// ═══════════════════════════════════════════════

static void collectESPFrame(Camera_t cam) {
    if (!cam || !g_players || g_playerCount <= 0 || !g_overlayReady) return;

    NSMutableArray *nd = [NSMutableArray arrayWithCapacity:(NSUInteger)g_playerCount];

    for (int i = 0; i < g_playerCount; i++) {
        Il2CppObject *pc = g_players[i];
        if (!pc) continue;
        if (rd<bool>((uintptr_t)pc + OFF_PC_IS_DEATH)) continue;

        Il2CppObject *net = rd<Il2CppObject*>((uintptr_t)pc + OFF_PC_NETWORK);
        if (!net) continue;

        Vector3 wPos = rd<Vector3>((uintptr_t)net + OFF_PN_NET_POSITION);

        Il2CppObject *ac  = rd<Il2CppObject*>((uintptr_t)pc + OFF_PC_ANIM_CTRL);
        Il2CppObject *sk  = ac ? rd<Il2CppObject*>((uintptr_t)ac + OFF_PAC_SKELETON) : NULL;

        PlayerESPData d; memset(&d,0,sizeof(d));

        if (sk) {
            Transform bones[] = {
                rd<Transform>((uintptr_t)sk + OFF_SK_HEAD),
                rd<Transform>((uintptr_t)sk + OFF_SK_CHEST),
                rd<Transform>((uintptr_t)sk + OFF_SK_PELVIS),
                rd<Transform>((uintptr_t)sk + OFF_SK_L_UPPER_ARM),
                rd<Transform>((uintptr_t)sk + OFF_SK_R_UPPER_ARM),
                rd<Transform>((uintptr_t)sk + OFF_SK_L_FOREARM),
                rd<Transform>((uintptr_t)sk + OFF_SK_R_FOREARM),
                rd<Transform>((uintptr_t)sk + OFF_SK_L_HAND),
                rd<Transform>((uintptr_t)sk + OFF_SK_R_HAND),
                rd<Transform>((uintptr_t)sk + OFF_SK_L_THIGH),
                rd<Transform>((uintptr_t)sk + OFF_SK_R_THIGH),
            };
            CGPoint pts[11];
            bool ok = true;
            for (int j = 0; j < 11; j++)
                ok &= w2s(cam, bonePos(bones[j]), &pts[j]);

            if (ok) {
                d.head=pts[0]; d.chest=pts[1]; d.pelvis=pts[2];
                d.lShoulder=pts[3]; d.rShoulder=pts[4];
                d.lElbow=pts[5];    d.rElbow=pts[6];
                d.lHand=pts[7];     d.rHand=pts[8];
                d.lHip=pts[9];      d.rHip=pts[10];
                CGFloat bh = std::abs(d.pelvis.y - d.head.y);
                d.headR = (float)(bh * 0.09f);
                CGFloat bw = bh * 0.45f;
                d.box = CGRectMake(d.head.x - bw*.5f, d.head.y - d.headR*1.5f, bw, bh + d.headR*2.f);
                d.hasBox = d.valid = true;
            }
        }

        if (!d.valid) {
            CGPoint top, bot;
            Vector3 t3 = {wPos.x, wPos.y+1.75f, wPos.z};
            Vector3 b3 = {wPos.x, wPos.y,        wPos.z};
            if (w2s(cam,t3,&top) && w2s(cam,b3,&bot)) {
                CGFloat bh = std::abs(bot.y-top.y), bw = bh*.45f;
                d.box = CGRectMake(top.x-bw*.5f, top.y, bw, bh);
                d.head = top; d.headR = (float)(bh*.09f);
                d.hasBox = d.valid = true;
            }
        }

        [nd addObject:[NSValue value:&d withObjCType:@encode(PlayerESPData)]];
    }

    dispatch_semaphore_wait(g_sema, DISPATCH_TIME_FOREVER);
    g_frameData = nd;
    dispatch_semaphore_signal(g_sema);

    dispatch_async(dispatch_get_main_queue(), ^{ [g_esp setNeedsDisplay]; });
}

// ═══════════════════════════════════════════════
// MARK: — FILL: хук Update для collectESPFrame
// ═══════════════════════════════════════════════
//
// static IMP orig_update;
// static void hooked_update(id self, SEL _cmd) {
//     orig_update(self, _cmd);
//     Camera_t cam = rd<Camera_t>((uintptr_t)(__bridge void*)self + OFF_PC_CAMERA);
//     collectESPFrame(cam);
// }
//
// Подключи в tweak_init():
//   Class uc = NSClassFromString(@"ИмяКласса");
//   Method m  = class_getInstanceMethod(uc, @selector(Update));
//   if (m) { orig_update = method_getImplementation(m);
//             method_setImplementation(m,(IMP)hooked_update); }

// ═══════════════════════════════════════════════
// MARK: — Constructor
// Грузимся через __attribute__((constructor)) —
// работает и в Substrate, и в LiveContainer
// ═══════════════════════════════════════════════

__attribute__((constructor))
static void tweak_init() {
    NSString *bid = NSBundle.mainBundle.bundleIdentifier;
    if (![bid isEqualToString:@"com.ScarletWork.CounterFlame"]) return;

    g_sema      = dispatch_semaphore_create(1);
    g_frameData = [NSMutableArray new];

    resolveSymbols();

    // Запускаем поллер сразу — не ждём AppDelegate
    dispatch_async(dispatch_get_main_queue(), ^{
        [CFPoller start];
    });

    // Дополнительный триггер через сцену
    [[NSNotificationCenter defaultCenter]
        addObserverForName:UIWindowDidBecomeKeyNotification
                    object:nil queue:NSOperationQueue.mainQueue
                usingBlock:^(NSNotification *n){
        if (!g_overlayReady) injectOverlay();
    }];

    // И через UIScene если iOS 13+
    if (@available(iOS 13, *)) {
        [[NSNotificationCenter defaultCenter]
            addObserverForName:UISceneDidActivateNotification
                        object:nil queue:NSOperationQueue.mainQueue
                    usingBlock:^(NSNotification *n){
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(.5*NSEC_PER_SEC)),
                           dispatch_get_main_queue(), ^{
                if (!g_overlayReady) injectOverlay();
            });
        }];
    }
}

#pragma clang diagnostic pop
