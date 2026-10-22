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
#include <stdint.h>
#include <cmath>

// ═══════════════════════════════════════════════════════════
// MARK: — IL2CPP types
// ═══════════════════════════════════════════════════════════

typedef void*  Il2CppObject;
typedef void*  Transform;
typedef void*  Camera_t;
typedef void*  Il2CppArray;

struct Vector3    { float x, y, z; };
struct Vector2    { float x, y; };

// ═══════════════════════════════════════════════════════════
// MARK: — Offsets (from dump_cs.txt)
// ═══════════════════════════════════════════════════════════

// PlayerController fields
#define OFF_PC_NETWORK      0x88   // PlayerNetwork*
#define OFF_PC_ANIM_CTRL    0x98   // PlayerAnimatorController*
#define OFF_PC_IS_DEATH     0xA8   // bool

// PlayerNetwork fields
#define OFF_PN_POSITION     0xBC   // Vector3 networkPosition

// PlayerAnimatorController fields
#define OFF_PAC_SKELETON    0x68   // PlayerSkeleton* (_skeleton — default/active one)

// PlayerSkeleton bone Transform* fields
#define OFF_SK_HEAD         0xA8
#define OFF_SK_CHEST        0xB0
#define OFF_SK_PELVIS       0xB8
#define OFF_SK_L_UPPER_ARM  0xC0
#define OFF_SK_R_UPPER_ARM  0xC8
#define OFF_SK_L_THIGH      0xD0
#define OFF_SK_R_THIGH      0xD8
#define OFF_SK_L_FOREARM    0x38
#define OFF_SK_L_HAND       0x40

// Photon.Realtime.Player
#define OFF_PLAYER_TAG      0x48   // TagObject — это PlayerController*

// Il2CppArray
#define OFF_ARRAY_LEN       0x18   // int32 m_uBounds[0]
#define OFF_ARRAY_DATA      0x20   // void* items[0]

// ═══════════════════════════════════════════════════════════
// MARK: — RVAs (dump base 0x112a70000, slide вычитаем динамически)
// ═══════════════════════════════════════════════════════════

// Dump base, нужна для вычисления слайда
#define DUMP_BASE           0x112a70000ULL

// Transform::get_position_Injected(out Vector3) — p:1
#define RVA_TRANSFORM_GETPOS_INJ  0x2BB48F4

// Camera::WorldToScreenPoint_Injected(Vector3, Eye, out Vector3) — p:3
// используем p:2 перегрузку без Eye: 0x2B73E5C
#define RVA_WORLD2SCREEN    0x2B73E5C

// Camera::get_main — p:0
#define RVA_CAMERA_MAIN     0x2B741F0

// PhotonNetwork::get_PlayerList — p:0 → Photon.Realtime.Player[]
#define RVA_GET_PLAYERLIST  0x24BC978

// ═══════════════════════════════════════════════════════════
// MARK: — Config
// ═══════════════════════════════════════════════════════════

static bool  g_espBox      = true;
static bool  g_espSkel     = true;
static float g_boxAlpha    = 0.9f;

// ═══════════════════════════════════════════════════════════
// MARK: — Base resolution
// ═══════════════════════════════════════════════════════════

static uintptr_t s_slide = 0;
static bool      s_slideFound = false;

static uintptr_t getSlide() {
    if (s_slideFound) return s_slide;
    for (uint32_t i = 0, n = _dyld_image_count(); i < n; i++) {
        const char *nm = _dyld_get_image_name(i);
        if (nm && strstr(nm, "UnityFramework")) {
            s_slide = (uintptr_t)_dyld_get_image_vmaddr_slide(i);
            s_slideFound = true;
            return s_slide;
        }
    }
    return 0;
}

static inline uintptr_t rva(uint64_t offset) {
    // RVA из дампа уже абсолютные адреса с базой DUMP_BASE
    // реальный адрес = адрес_из_дампа - DUMP_BASE + slide
    uintptr_t slide = getSlide();
    if (!slide) return 0;
    return (uintptr_t)(offset - DUMP_BASE + slide);
}

// ═══════════════════════════════════════════════════════════
// MARK: — Function pointers
// ═══════════════════════════════════════════════════════════

// Transform::get_position_Injected(out Vector3 ret)
typedef void     (*PFN_GetPosInj)(Transform self, Vector3 *out, void *method);
// Camera::WorldToScreenPoint(Vector3 position, Eye eye) → Vector3
// p:2 перегрузка без Eye принимает (self, Vector3, void*)
typedef Vector3  (*PFN_W2S)(Camera_t self, Vector3 pos, void *method);
// Camera::get_main → Camera*
typedef Camera_t (*PFN_CamMain)(void *method);
// PhotonNetwork::get_PlayerList → Photon.Realtime.Player[]
typedef Il2CppArray* (*PFN_PlayerList)(void *method);

static PFN_GetPosInj  s_getPosInj  = NULL;
static PFN_W2S        s_w2s        = NULL;
static PFN_CamMain    s_camMain    = NULL;
static PFN_PlayerList s_playerList = NULL;

static void resolveSymbols() {
    uintptr_t slide = getSlide();
    if (!slide) return;
#define BIND(fn, rva_const) \
    fn = ((__typeof__(fn))(uintptr_t)(rva_const - DUMP_BASE + slide))
    BIND(s_getPosInj,  RVA_TRANSFORM_GETPOS_INJ);
    BIND(s_w2s,        RVA_WORLD2SCREEN);
    BIND(s_camMain,    RVA_CAMERA_MAIN);
    BIND(s_playerList, RVA_GET_PLAYERLIST);
#undef BIND
}

// ═══════════════════════════════════════════════════════════
// MARK: — Helpers
// ═══════════════════════════════════════════════════════════

template<typename T>
static inline T rd(uintptr_t a) {
    if (!a) { T z; memset(&z,0,sizeof(z)); return z; }
    return *(T*)a;
}

static inline Vector3 boneWorldPos(Transform bone) {
    Vector3 out; memset(&out,0,sizeof(out));
    if (!bone || !s_getPosInj) return out;
    s_getPosInj(bone, &out, NULL);
    return out;
}

static CGSize g_screen;

// W2S: Unity screen Y=0 bottom → flip для UIKit
// WorldToScreenPoint p:2 возвращает Vector3 (z = depth)
static bool w2s(Camera_t cam, Vector3 world, CGPoint *out) {
    if (!cam || !s_w2s) return false;
    Vector3 s = s_w2s(cam, world, NULL);
    if (s.z <= 0.0f) return false; // за камерой
    out->x = (CGFloat)s.x;
    out->y = g_screen.height - (CGFloat)s.y;
    return (s.x > 0.f && s.x < (float)g_screen.width &&
            s.y > 0.f && s.y < (float)g_screen.height);
}

// ═══════════════════════════════════════════════════════════
// MARK: — ESP data
// ═══════════════════════════════════════════════════════════

typedef struct {
    // box
    CGRect  box;
    bool    hasBox;
    // skeleton
    CGPoint head, chest, pelvis;
    CGPoint lShoulder, rShoulder;
    CGPoint lElbow, rElbow;
    CGPoint lHand, rHand;
    CGPoint lHip, rHip;
    bool    hasSkel;
    float   headR;
    bool    valid;
} PlayerESPData;

static NSMutableArray       *g_frameData = nil;
static dispatch_semaphore_t  g_sema;

// ═══════════════════════════════════════════════════════════
// MARK: — ESP collection (called from display link)
// ═══════════════════════════════════════════════════════════

static void collectFrame() {
    if (!s_playerList || !s_camMain) return;

    Camera_t cam = s_camMain(NULL);
    if (!cam) return;

    Il2CppArray *arr = s_playerList(NULL);
    if (!arr) return;

    int32_t count = rd<int32_t>((uintptr_t)arr + OFF_ARRAY_LEN);
    if (count <= 0 || count > 64) return;

    NSMutableArray *nd = [NSMutableArray arrayWithCapacity:(NSUInteger)count];

    for (int32_t i = 0; i < count; i++) {
        // Player[] items начинаются с OFF_ARRAY_DATA, каждый элемент — Il2CppObject* (8 байт)
        uintptr_t playerPtr = rd<uintptr_t>((uintptr_t)arr + OFF_ARRAY_DATA + (uintptr_t)(i * 8));
        if (!playerPtr) continue;

        // TagObject → PlayerController*
        Il2CppObject *pc = rd<Il2CppObject*>(playerPtr + OFF_PLAYER_TAG);
        if (!pc) continue;

        // Проверка смерти
        bool dead = rd<bool>((uintptr_t)pc + OFF_PC_IS_DEATH);
        if (dead) continue;

        Il2CppObject *net = rd<Il2CppObject*>((uintptr_t)pc + OFF_PC_NETWORK);
        if (!net) continue;

        Il2CppObject *ac  = rd<Il2CppObject*>((uintptr_t)pc + OFF_PC_ANIM_CTRL);
        Il2CppObject *sk  = ac ? rd<Il2CppObject*>((uintptr_t)ac + OFF_PAC_SKELETON) : NULL;

        PlayerESPData d; memset(&d, 0, sizeof(d));

        if (sk) {
            Transform bones[9] = {
                rd<Transform>((uintptr_t)sk + OFF_SK_HEAD),
                rd<Transform>((uintptr_t)sk + OFF_SK_CHEST),
                rd<Transform>((uintptr_t)sk + OFF_SK_PELVIS),
                rd<Transform>((uintptr_t)sk + OFF_SK_L_UPPER_ARM),
                rd<Transform>((uintptr_t)sk + OFF_SK_R_UPPER_ARM),
                rd<Transform>((uintptr_t)sk + OFF_SK_L_FOREARM),
                rd<Transform>((uintptr_t)sk + OFF_SK_L_HAND),
                rd<Transform>((uintptr_t)sk + OFF_SK_L_THIGH),
                rd<Transform>((uintptr_t)sk + OFF_SK_R_THIGH),
            };
            CGPoint pts[9];
            bool ok = true;
            for (int j = 0; j < 9; j++)
                ok &= w2s(cam, boneWorldPos(bones[j]), &pts[j]);

            if (ok) {
                d.head=pts[0]; d.chest=pts[1]; d.pelvis=pts[2];
                d.lShoulder=pts[3]; d.rShoulder=pts[4];
                d.lElbow=pts[5];    d.rElbow=pts[5]; // правый forearm нет в дампе — зеркалим
                d.lHand=pts[6];     d.rHand=pts[6];
                d.lHip=pts[7];      d.rHip=pts[8];
                CGFloat bh    = std::abs(d.pelvis.y - d.head.y);
                d.headR       = (float)(bh * 0.10f);
                CGFloat bw    = bh * 0.5f;
                d.box         = CGRectMake(d.head.x - bw*.5f,
                                           d.head.y - d.headR*1.5f,
                                           bw, bh + d.headR*2.f);
                d.hasBox = d.hasSkel = d.valid = true;
            }
        }

        // Fallback: позиция из network если скелет не проекцировался
        if (!d.valid) {
            Vector3 wPos = rd<Vector3>((uintptr_t)net + OFF_PN_POSITION);
            Vector3 t3 = {wPos.x, wPos.y+1.75f, wPos.z};
            Vector3 b3 = {wPos.x, wPos.y,        wPos.z};
            CGPoint top, bot;
            if (w2s(cam,t3,&top) && w2s(cam,b3,&bot)) {
                CGFloat bh = std::abs(bot.y-top.y), bw = bh*.5f;
                d.box   = CGRectMake(top.x-bw*.5f, top.y, bw, bh);
                d.head  = top; d.headR = (float)(bh*.10f);
                d.hasBox = d.valid = true;
            }
        }

        if (d.valid)
            [nd addObject:[NSValue value:&d withObjCType:@encode(PlayerESPData)]];
    }

    dispatch_semaphore_wait(g_sema, DISPATCH_TIME_FOREVER);
    g_frameData = nd;
    dispatch_semaphore_signal(g_sema);
}

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

- (void)drawRect:(CGRect)r {
    CGContextRef ctx = UIGraphicsGetCurrentContext();
    if (!ctx) return;

    dispatch_semaphore_wait(g_sema, DISPATCH_TIME_FOREVER);
    NSArray *snap = [g_frameData copy];
    dispatch_semaphore_signal(g_sema);

    for (NSValue *v in snap) {
        PlayerESPData d; [v getValue:&d];
        if (!d.valid) continue;

        // ─ Box (угловой) ────────────────────────────
        if (g_espBox && d.hasBox) {
            CGRect  rb = d.box;
            CGFloat cw = rb.size.width  * 0.25f;
            CGFloat ch = rb.size.height * 0.16f;
            CGFloat x=rb.origin.x, y=rb.origin.y;
            CGFloat W=rb.size.width, H=rb.size.height;

            CGContextSetLineWidth(ctx, 1.5f);
            // тень для читаемости на любом фоне
            CGContextSetShadowWithColor(ctx, CGSizeMake(0,0), 3.f,
                [UIColor.blackColor colorWithAlphaComponent:0.95f].CGColor);
            CGContextSetStrokeColorWithColor(ctx,
                [UIColor colorWithRed:.3f green:.85f blue:1.f alpha:g_boxAlpha].CGColor);

#define C(x1,y1, x2,y2, x3,y3) \
    CGContextMoveToPoint(ctx,x1,y1); \
    CGContextAddLineToPoint(ctx,x2,y2); \
    CGContextAddLineToPoint(ctx,x3,y3);
            C(x,      y+ch,  x,    y,    x+cw, y);
            C(x+W-cw, y,     x+W,  y,    x+W,  y+ch);
            C(x,      y+H-ch,x,    y+H,  x+cw, y+H);
            C(x+W-cw, y+H,   x+W,  y+H,  x+W,  y+H-ch);
#undef C
            CGContextStrokePath(ctx);
            CGContextSetShadowWithColor(ctx, CGSizeZero, 0, NULL);
        }

        // ─ Skeleton ──────────────────────────────────
        if (g_espSkel && d.hasSkel) {
            CGContextSetLineWidth(ctx, 1.0f);
            CGContextSetStrokeColorWithColor(ctx,
                [UIColor colorWithWhite:1.f alpha:.72f].CGColor);
            CGContextSetShadowWithColor(ctx, CGSizeMake(0,0), 2.5f,
                [UIColor.blackColor colorWithAlphaComponent:.85f].CGColor);

#define BL(a,b) \
    CGContextMoveToPoint(ctx,(a).x,(a).y); \
    CGContextAddLineToPoint(ctx,(b).x,(b).y);
            // позвоночник
            BL(d.head,      d.chest);
            BL(d.chest,     d.pelvis);
            // руки
            BL(d.chest,     d.lShoulder);
            BL(d.lShoulder, d.lElbow);
            BL(d.lElbow,    d.lHand);
            BL(d.chest,     d.rShoulder);
            BL(d.rShoulder, d.rElbow);
            BL(d.rElbow,    d.rHand);
            // ноги
            BL(d.pelvis, d.lHip);
            BL(d.pelvis, d.rHip);
#undef BL
            CGContextStrokePath(ctx);
            CGContextSetShadowWithColor(ctx, CGSizeZero, 0, NULL);

            // Голова — чёткий круг
            CGFloat hr = d.headR < 5.f ? 5.f : d.headR;
            CGRect hc  = CGRectMake(d.head.x-hr, d.head.y-hr, hr*2.f, hr*2.f);

            CGContextSetFillColorWithColor(ctx,
                [UIColor colorWithRed:.3f green:.85f blue:1.f alpha:.15f].CGColor);
            CGContextFillEllipseInRect(ctx, hc);

            CGContextSetLineWidth(ctx, 1.4f);
            CGContextSetStrokeColorWithColor(ctx,
                [UIColor colorWithRed:.3f green:.85f blue:1.f alpha:1.f].CGColor);
            CGContextSetShadowWithColor(ctx, CGSizeMake(0,0), 5.f,
                [UIColor colorWithRed:.0f green:.6f blue:1.f alpha:1.f].CGColor);
            CGContextStrokeEllipseInRect(ctx, hc);
            CGContextSetShadowWithColor(ctx, CGSizeZero, 0, NULL);
        }
    }
}
@end

// ═══════════════════════════════════════════════════════════
// MARK: — Colors
// ═══════════════════════════════════════════════════════════

NS_INLINE UIColor *cA()  { return [UIColor colorWithRed:.28f green:.82f blue:1.f alpha:1.f]; }
NS_INLINE UIColor *cBg() { return [UIColor colorWithRed:.05f green:.05f blue:.08f alpha:.96f]; }
NS_INLINE UIColor *cP2() { return [UIColor colorWithRed:.08f green:.08f blue:.12f alpha:1.f]; }
NS_INLINE UIColor *cTx() { return [UIColor colorWithWhite:.90f alpha:1.f]; }
NS_INLINE UIColor *cS()  { return [UIColor colorWithWhite:.40f alpha:1.f]; }

// ═══════════════════════════════════════════════════════════
// MARK: — MenuView  (горизонтальное меню, CS-стиль)
// ═══════════════════════════════════════════════════════════

@interface MenuView : UIView
@property (nonatomic, strong) UIButton *closeBtn;
@end

@implementation MenuView

- (instancetype)init {
    const CGFloat W = 290.f, H = 185.f;
    CGFloat sx = UIScreen.mainScreen.bounds.size.width;
    CGFloat sy = UIScreen.mainScreen.bounds.size.height;
    self = [super initWithFrame:CGRectMake((sx-W)*.5f, sy-H-110.f, W, H)];
    self.backgroundColor     = cBg();
    self.layer.cornerRadius  = 4.f;      // минимальный — как в читах для КС
    self.layer.masksToBounds = YES;
    self.layer.borderColor   = [UIColor colorWithWhite:.16f alpha:1.f].CGColor;
    self.layer.borderWidth   = .5f;
    [self build];
    UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc]
        initWithTarget:self action:@selector(onPan:)];
    [self addGestureRecognizer:pan];
    return self;
}

- (void)build {
    const CGFloat W = self.bounds.size.width;

    // ── шапка ────────────────────────────────────
    UIView *hdr = [[UIView alloc] initWithFrame:CGRectMake(0,0,W,30.f)];
    hdr.backgroundColor = cP2();

    UILabel *logo = [[UILabel alloc] initWithFrame:CGRectMake(10,0,120,30)];
    logo.text = @"COUNTERFLAME";
    logo.textColor = cA();
    logo.font = [UIFont monospacedSystemFontOfSize:10.f weight:UIFontWeightBold];
    [hdr addSubview:logo];

    // Таб ESP — единственный, просто декоративная подчёркнутость
    UILabel *tab = [[UILabel alloc] initWithFrame:CGRectMake(150,0,60,30)];
    tab.text = @"ESP"; tab.textColor = cA();
    tab.font = [UIFont systemFontOfSize:11.f weight:UIFontWeightSemibold];
    tab.textAlignment = NSTextAlignmentCenter;
    UIView *tabLine = [[UIView alloc] initWithFrame:CGRectMake(0,27,60,2)];
    tabLine.backgroundColor = cA(); tabLine.layer.cornerRadius = 1;
    [tab addSubview:tabLine];
    [hdr addSubview:tab];

    // Крестик закрытия — справа в шапке
    self.closeBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    self.closeBtn.frame = CGRectMake(W-30,0,30,30);
    [self.closeBtn setTitle:@"×" forState:UIControlStateNormal];
    [self.closeBtn setTitleColor:cS() forState:UIControlStateNormal];
    self.closeBtn.titleLabel.font = [UIFont systemFontOfSize:18.f weight:UIFontWeightThin];
    [hdr addSubview:self.closeBtn];

    // Разделитель
    UIView *sep = [[UIView alloc] initWithFrame:CGRectMake(0,30,W,.5f)];
    sep.backgroundColor = [UIColor colorWithWhite:.15f alpha:1.f];

    [self addSubview:hdr];
    [self addSubview:sep];

    // ── строки ────────────────────────────────────
    CGFloat y = 38.f;
    y = [self row:@"ESP Box" sub:@"Угловой box" val:g_espBox y:y W:W
          tog:^(BOOL v){ g_espBox = (bool)v; }];
    y = [self row:@"Skeleton" sub:@"Скелет + голова" val:g_espSkel y:y W:W
          tog:^(BOOL v){ g_espSkel = (bool)v; }];
}

- (CGFloat)row:(NSString*)nm sub:(NSString*)sub val:(bool)val
             y:(CGFloat)y W:(CGFloat)W tog:(void(^)(BOOL))blk {
    UIView *row = [[UIView alloc] initWithFrame:CGRectMake(6,y,W-12,42)];
    row.backgroundColor    = cP2();
    row.layer.cornerRadius = 3.f;

    UILabel *lb = [[UILabel alloc] initWithFrame:CGRectMake(10,5,W-90,16)];
    lb.text = nm; lb.textColor = cTx();
    lb.font = [UIFont systemFontOfSize:12.f weight:UIFontWeightMedium];

    UILabel *sb = [[UILabel alloc] initWithFrame:CGRectMake(10,22,W-90,13)];
    sb.text = sub; sb.textColor = cS();
    sb.font = [UIFont systemFontOfSize:10.f];

    UISwitch *sw = [[UISwitch alloc] init];
    sw.frame = CGRectMake(W-64,8,0,0); // sizeToFit ниже
    [sw sizeToFit];
    sw.frame = CGRectMake(W-64, (42.f-sw.frame.size.height)*.5f,
                          sw.frame.size.width, sw.frame.size.height);
    sw.transform   = CGAffineTransformMakeScale(.72f,.72f);
    sw.on          = val;
    sw.onTintColor = cA();
    sw.tintColor   = [UIColor colorWithWhite:.18f alpha:1.f];

    void(^cb)(BOOL) = blk;
    [sw addAction:[UIAction actionWithHandler:^(UIAction *a){
        cb(((UISwitch *)a.sender).on);
    }] forControlEvents:UIControlEventValueChanged];

    [row addSubview:lb]; [row addSubview:sb]; [row addSubview:sw];
    [self addSubview:row];
    return y + 48.f;
}

- (void)onPan:(UIPanGestureRecognizer *)gr {
    UIView *sv = self.superview; if (!sv) return;
    CGPoint t = [gr translationInView:sv];
    self.center = CGPointMake(self.center.x+t.x, self.center.y+t.y);
    [gr setTranslation:CGPointZero inView:sv];
}
@end

// ═══════════════════════════════════════════════════════════
// MARK: — Overlay globals
// ═══════════════════════════════════════════════════════════

static ESPView  *g_esp    = nil;
static MenuView *g_menu   = nil;
static UIButton *g_tog    = nil;    // иконка-кнопка после скрытия меню
static bool      g_menuVis = false;
static bool      g_ready   = false;

static UIWindow *findWindow() {
    if ([UIApplication.sharedApplication respondsToSelector:@selector(connectedScenes)]) {
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
    g_menuVis     = show;
    g_menu.hidden = !show;
    // иконку показываем только когда меню скрыто
    g_tog.hidden  = show;
}

static void injectOverlay() {
    if (g_ready) return;
    UIWindow *win = findWindow();
    if (!win) return;

    g_screen = UIScreen.mainScreen.bounds.size;

    // ESP layer
    g_esp = [[ESPView alloc] initWithFrame:win.bounds];
    g_esp.autoresizingMask = UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight;
    [win addSubview:g_esp];

    // Menu (изначально скрыто)
    g_menu = [[MenuView alloc] init];
    g_menu.hidden = YES;
    g_menu.layer.zPosition = 99995;
    [win addSubview:g_menu];

    // Крестик меню → закрыть, показать иконку
    [g_menu.closeBtn addAction:[UIAction actionWithHandler:^(UIAction *a){
        showMenu(false);
    }] forControlEvents:UIControlEventTouchUpInside];

    // Floating иконка — показывается когда меню закрыто, тап открывает
    g_tog = [UIButton buttonWithType:UIButtonTypeCustom];
    g_tog.frame = CGRectMake(8.f, 120.f, 36.f, 36.f);
    g_tog.backgroundColor    = [UIColor colorWithRed:.05f green:.05f blue:.08f alpha:.92f];
    g_tog.layer.cornerRadius = 4.f;
    g_tog.layer.borderWidth  = .5f;
    g_tog.layer.borderColor  = [UIColor colorWithWhite:.2f alpha:1.f].CGColor;
    g_tog.layer.zPosition    = 99996;
    [g_tog setTitle:@"⊞" forState:UIControlStateNormal];
    [g_tog setTitleColor:cA() forState:UIControlStateNormal];
    g_tog.titleLabel.font = [UIFont systemFontOfSize:16.f];
    g_tog.hidden = NO;

    [g_tog addAction:[UIAction actionWithHandler:^(UIAction *a){
        showMenu(true);
    }] forControlEvents:UIControlEventTouchUpInside];

    // Drag для иконки

