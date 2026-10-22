// Tweak.mm — CounterFlame ESP
// Target: com.ScarletWork.CounterFlame.app
// Build: theos dylib, iOS 14+, arm64
// Offsets from Assembly-CSharp dump (IL2CPP)
// не проверял на живом бинаре — FILL: по своему дампу если что-то съехало

#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#include <mach-o/dyld.h>
#include <stdint.h>
#include <math.h>

// ─────────────────────────────────────────
// MARK: — Config
// ─────────────────────────────────────────

static bool  g_espBox      = true;
static bool  g_espSkeleton = true;
static float g_boxAlpha    = 0.85f;

// ─────────────────────────────────────────
// MARK: — IL2CPP types (opaque)
// ─────────────────────────────────────────

typedef void*    Il2CppObject;
typedef void*    Il2CppString;
typedef void*    Transform;
typedef void*    Camera;

struct Vector3 { float x, y, z; };
struct Vector2 { float x, y; };
struct Quaternion { float x, y, z, w; };

// ─────────────────────────────────────────
// MARK: — Offsets (from dump)
// ─────────────────────────────────────────

// PlayerController
#define OFF_PC_CAMERA           0x30   // Camera*
#define OFF_PC_NETWORK          0x88   // PlayerNetwork*
#define OFF_PC_ANIM_CTRL        0x98   // PlayerAnimatorController*
#define OFF_PC_IS_DEATH         0xA8   // bool

// PlayerNetwork
#define OFF_PN_NET_POSITION     0xBC   // Vector3
#define OFF_PN_NET_ROTATION     0xC8   // Quaternion

// PlayerAnimatorController
#define OFF_PAC_SKELETON        0x68   // PlayerSkeleton*

// PlayerSkeleton bones (Transform*)
#define OFF_SK_HEAD             0xA8
#define OFF_SK_CHEST            0xB0
#define OFF_SK_PELVIS           0xB8
#define OFF_SK_L_UPPER_ARM      0xC0
#define OFF_SK_R_UPPER_ARM      0xC8
#define OFF_SK_L_THIGH          0xD0
#define OFF_SK_R_THIGH          0xD8
#define OFF_SK_L_FOREARM        0x38
#define OFF_SK_R_FOREARM        0x38   // FILL: нет отдельного правого forearm в дампе — уточни
#define OFF_SK_L_HAND           0x40
#define OFF_SK_L_PALM           0x48

// _actorToView static — FILL: адрес из il2cpp_inspect / dumpcs для поля _actorToView
// Пока используем PhotonNetwork.PlayerList через API

// ─────────────────────────────────────────
// MARK: — IL2CPP helper resolvers
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

// FILL: адреса методов из il2cpp dump (RVA от UnityFramework base)
// grep "GetPlayerList\|WorldToScreenPoint\|get_position\|Transform_get_position" dump.cs для RVA

typedef Il2CppObject* (*t_GetPlayerList)(Il2CppObject* instance);
typedef Vector3       (*t_TransformGetPos)(Transform t, void* mth);
typedef Vector2       (*t_WorldToScreen)(Camera cam, Vector3 world, void* mth);
typedef bool          (*t_GetIsDeath)(Il2CppObject* pc, void* mth);
typedef Il2CppObject* (*t_GetPhotonNetworkInst)(void);

// Один раз резолвим через il2cpp_resolve_icall или GetMethodPointer
// FILL: вставь реальные RVA из dump.cs

#define RVA_PLAYERLIST          0x0  // FILL
#define RVA_TRANSFORM_GETPOS    0x0  // FILL
#define RVA_WORLD2SCREEN        0x0  // FILL

static t_TransformGetPos  fn_transformGetPos  = nullptr;
static t_WorldToScreen    fn_worldToScreen    = nullptr;

static void resolveSymbols() {
    uintptr_t b = getBase();
    if (!b) return;
    fn_transformGetPos = (t_TransformGetPos)(b + RVA_TRANSFORM_GETPOS);
    fn_worldToScreen   = (t_WorldToScreen)  (b + RVA_WORLD2SCREEN);
}

// read<T> с нулевой проверкой
template<typename T>
static inline T rd(uintptr_t addr) {
    if (!addr) return T{};
    return *(T*)addr;
}

static inline Vector3 bonePos(Transform bone) {
    if (!bone || !fn_transformGetPos) return {};
    return fn_transformGetPos(bone, nullptr);
}

// ─────────────────────────────────────────
// MARK: — W2S
// ─────────────────────────────────────────

static CGSize screenSize;

static bool worldToScreen(Camera cam, Vector3 world, CGPoint& out) {
    if (!cam || !fn_worldToScreen) return false;
    Vector2 s = fn_worldToScreen(cam, world, nullptr);
    // Unity screen Y = 0 снизу, UIKit Y = 0 сверху
    out.x = s.x;
    out.y = screenSize.height - s.y;
    return (s.x > 0 && s.x < screenSize.width && s.y > 0);
}

// ─────────────────────────────────────────
// MARK: — ESP Overlay (UIView)
// ─────────────────────────────────────────

// Хранилище per-frame данных — собираем в игровом потоке, рисуем в main
struct PlayerESPData {
    // box
    CGRect    box;
    bool      hasBox;
    // skeleton joints (screen)
    CGPoint   head, chest, pelvis;
    CGPoint   lShoulder, rShoulder;
    CGPoint   lElbow,    rElbow;
    CGPoint   lHand,     rHand;
    CGPoint   lHip,      rHip;
    // head circle radius
    float     headR;
    bool      valid;
};

static NSMutableArray<NSValue*>* g_frameData; // NSValue wrapping PlayerESPData*
static dispatch_semaphore_t      g_dataSema;

@interface ESPView : UIView
@end

@implementation ESPView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor        = UIColor.clearColor;
        self.userInteractionEnabled = NO;
        self.layer.zPosition        = 9999;
    }
    return self;
}

- (void)drawRect:(CGRect)rect {
    CGContextRef ctx = UIGraphicsGetCurrentContext();
    if (!ctx) return;

    dispatch_semaphore_wait(g_dataSema, DISPATCH_TIME_FOREVER);
    NSArray* snapshot = [g_frameData copy];
    dispatch_semaphore_signal(g_dataSema);

    for (NSValue* val in snapshot) {
        PlayerESPData* d = nil;
        [val getValue:&d];
        if (!d || !d->valid) continue;

        // ── Box ──────────────────────────────────────
        if (g_espBox && d->hasBox) {
            // Угловой ESP box — рисуем только 4 угла, не полный прямоугольник
            CGRect r = d->box;
            float cw = r.size.width  * 0.28f; // длина уголка
            float ch = r.size.height * 0.18f;
            CGContextSetLineWidth(ctx, 1.6f);

            // Тень для читаемости на любом фоне
            CGContextSetShadowWithColor(ctx,
                CGSizeMake(0, 0), 3.0,
                [UIColor.blackColor colorWithAlphaComponent:0.9f].CGColor);

            // Цвет — холодный голубой
            CGContextSetStrokeColorWithColor(ctx,
                [UIColor colorWithRed:0.35 green:0.85 blue:1.0 alpha:g_boxAlpha].CGColor);

            // Top-left
            CGContextMoveToPoint(ctx, r.origin.x, r.origin.y + ch);
            CGContextAddLineToPoint(ctx, r.origin.x, r.origin.y);
            CGContextAddLineToPoint(ctx, r.origin.x + cw, r.origin.y);

            // Top-right
            CGContextMoveToPoint(ctx, r.origin.x + r.size.width - cw, r.origin.y);
            CGContextAddLineToPoint(ctx, r.origin.x + r.size.width, r.origin.y);
            CGContextAddLineToPoint(ctx, r.origin.x + r.size.width, r.origin.y + ch);

            // Bottom-left
            CGContextMoveToPoint(ctx, r.origin.x, r.origin.y + r.size.height - ch);
            CGContextAddLineToPoint(ctx, r.origin.x, r.origin.y + r.size.height);
            CGContextAddLineToPoint(ctx, r.origin.x + cw, r.origin.y + r.size.height);

            // Bottom-right
            CGContextMoveToPoint(ctx, r.origin.x + r.size.width - cw, r.origin.y + r.size.height);
            CGContextAddLineToPoint(ctx, r.origin.x + r.size.width, r.origin.y + r.size.height);
            CGContextAddLineToPoint(ctx, r.origin.x + r.size.width, r.origin.y + r.size.height - ch);

            CGContextStrokePath(ctx);
            CGContextSetShadowWithColor(ctx, CGSizeZero, 0, nil);
        }

        // ── Skeleton ─────────────────────────────────
        if (g_espSkeleton) {
            CGContextSetLineWidth(ctx, 1.1f);
            CGContextSetStrokeColorWithColor(ctx,
                [UIColor colorWithRed:1.0 green:1.0 blue:1.0 alpha:0.75f].CGColor);
            CGContextSetShadowWithColor(ctx,
                CGSizeMake(0, 0), 2.5,
                [UIColor.blackColor colorWithAlphaComponent:0.8f].CGColor);

            // Helper lambda-style inline macro
#define BONE_LINE(a, b) \
            CGContextMoveToPoint(ctx, (a).x, (a).y); \
            CGContextAddLineToPoint(ctx, (b).x, (b).y);

            // Позвоночник
            BONE_LINE(d->head,  d->chest);
            BONE_LINE(d->chest, d->pelvis);

            // Руки
            BONE_LINE(d->chest,    d->lShoulder);
            BONE_LINE(d->lShoulder, d->lElbow);
            BONE_LINE(d->lElbow,   d->lHand);

            BONE_LINE(d->chest,    d->rShoulder);
            BONE_LINE(d->rShoulder, d->rElbow);
            BONE_LINE(d->rElbow,   d->rHand);

            // Ноги
            BONE_LINE(d->pelvis, d->lHip);
            BONE_LINE(d->pelvis, d->rHip);

            CGContextStrokePath(ctx);
            CGContextSetShadowWithColor(ctx, CGSizeZero, 0, nil);

            // ── Голова — выделенный круг ──────────────
            float r = MAX(d->headR, 6.0f);
            CGRect headCircle = CGRectMake(
                d->head.x - r, d->head.y - r, r * 2, r * 2);

            // Заливка полупрозрачная
            CGContextSetFillColorWithColor(ctx,
                [UIColor colorWithRed:0.35 green:0.85 blue:1.0 alpha:0.18f].CGColor);
            CGContextFillEllipseInRect(ctx, headCircle);

            // Обводка яркая
            CGContextSetLineWidth(ctx, 1.4f);
            CGContextSetStrokeColorWithColor(ctx,
                [UIColor colorWithRed:0.35 green:0.85 blue:1.0 alpha:0.95f].CGColor);
            CGContextSetShadowWithColor(ctx,
                CGSizeMake(0, 0), 4.0,
                [UIColor colorWithRed:0.0 green:0.6 blue:1.0 alpha:0.9f].CGColor);
            CGContextStrokeEllipseInRect(ctx, headCircle);
            CGContextSetShadowWithColor(ctx, CGSizeZero, 0, nil);

#undef BONE_LINE
        }
    }
}

@end

// ─────────────────────────────────────────
// MARK: — Menu overlay
// ─────────────────────────────────────────

@interface MenuView : UIView
@property (nonatomic, assign) CGPoint  dragOffset;
@property (nonatomic, assign) BOOL     isDragging;
@property (nonatomic, strong) UIButton *tabESP;
@property (nonatomic, strong) UIView   *pageESP;
@end

@implementation MenuView

static UIColor* accent()  { return [UIColor colorWithRed:0.35 green:0.85 blue:1.0 alpha:1.0]; }
static UIColor* bg()      { return [UIColor colorWithRed:0.06 green:0.06 blue:0.09 alpha:0.94]; }
static UIColor* bgPanel() { return [UIColor colorWithRed:0.09 green:0.09 blue:0.13 alpha:1.0]; }
static UIColor* textPrimary()   { return [UIColor colorWithWhite:0.92 alpha:1.0]; }
static UIColor* textSecondary() { return [UIColor colorWithWhite:0.45 alpha:1.0]; }

- (instancetype)init {
    // Горизонтальное меню: компактная полоска с табами сверху, контент снизу
    CGFloat W = 320, H = 200;
    CGFloat sx = [UIScreen mainScreen].bounds.size.width;
    CGFloat sy = [UIScreen mainScreen].bounds.size.height;
    self = [super initWithFrame:CGRectMake((sx - W) / 2, sy - H - 80, W, H)];
    if (!self) return nil;

    // Основной фон
    self.backgroundColor             = bg();
    self.layer.cornerRadius          = 6;       // заострённые углы — минимум
    self.layer.masksToBounds         = YES;
    self.layer.borderColor           = [UIColor colorWithWhite:0.18 alpha:1.0].CGColor;
    self.layer.borderWidth           = 0.5f;

    // Тень снаружи (не clipsToBounds — нужен второй контейнер, но оставим просто shadow)
    // shadow требует masksToBounds = NO — делаем два слоя через shadowView
    [self buildUI];

    // Drag
    UIPanGestureRecognizer* pan = [[UIPanGestureRecognizer alloc]
        initWithTarget:self action:@selector(handlePan:)];
    [self addGestureRecognizer:pan];

    return self;
}

- (void)buildUI {
    CGFloat W = self.bounds.size.width;

    // ── Tab bar (горизонтальная полоска вверху) ──
    UIView* tabBar = [[UIView alloc] initWithFrame:CGRectMake(0, 0, W, 36)];
    tabBar.backgroundColor = bgPanel();

    // Логотип/заголовок слева
    UILabel* title = [[UILabel alloc] initWithFrame:CGRectMake(10, 0, 90, 36)];
    title.text          = @"FLAME";
    title.textColor     = accent();
    title.font          = [UIFont systemFontOfSize:11 weight:UIFontWeightHeavy];
    title.alpha         = 0.9f;
    [tabBar addSubview:title];

    // Таб ESP
    self.tabESP = [self makeTab:@"ESP" x:90 width:70 active:YES];
    [self.tabESP addTarget:self action:@selector(onTabESP) forControlEvents:UIControlEventTouchUpInside];
    [tabBar addSubview:self.tabESP];

    // Drag handle справа
    UILabel* handle = [[UILabel alloc] initWithFrame:CGRectMake(W - 36, 0, 36, 36)];
    handle.text      = @"⠿";
    handle.textColor = textSecondary();
    handle.font      = [UIFont systemFontOfSize:14];
    handle.textAlignment = NSTextAlignmentCenter;
    [tabBar addSubview:handle];

    [self addSubview:tabBar];

    // Разделитель
    UIView* sep = [[UIView alloc] initWithFrame:CGRectMake(0, 36, W, 0.5f)];
    sep.backgroundColor = [UIColor colorWithWhite:0.2 alpha:1.0];
    [self addSubview:sep];

    // ── Page ESP ────────────────────────────────
    self.pageESP = [[UIView alloc] initWithFrame:CGRectMake(0, 36.5f, W, self.bounds.size.height - 36.5f)];
    self.pageESP.backgroundColor = UIColor.clearColor;
    [self buildESPPage:self.pageESP];
    [self addSubview:self.pageESP];
}

- (UIButton*)makeTab:(NSString*)text x:(CGFloat)x width:(CGFloat)w active:(BOOL)active {
    UIButton* btn = [[UIButton alloc] initWithFrame:CGRectMake(x, 0, w, 36)];
    [btn setTitle:text forState:UIControlStateNormal];
    [btn setTitleColor:active ? accent() : textSecondary() forState:UIControlStateNormal];
    btn.titleLabel.font = [UIFont systemFontOfSize:11 weight:UIFontWeightSemibold];

    if (active) {
        UIView* line = [[UIView alloc] initWithFrame:CGRectMake(0, 33, w, 2)];
        line.backgroundColor  = accent();
        line.layer.cornerRadius = 1;
        line.tag = 99;
        [btn addSubview:line];
    }
    return btn;
}

- (void)buildESPPage:(UIView*)page {
    CGFloat W  = page.bounds.size.width;
    CGFloat py = 12;

    // Row helper — toggle + label
    py = [self addRow:@"ESP Box"      desc:@"Угловой box вокруг игрока"
                value:g_espBox      page:page y:py w:W
                onToggle:^(BOOL v){ g_espBox = v; }];

    py = [self addRow:@"Skeleton"     desc:@"Тонкий скелет + голова"
                value:g_espSkeleton page:page y:py w:W
                onToggle:^(BOOL v){ g_espSkeleton = v; }];
}

- (CGFloat)addRow:(NSString*)name desc:(NSString*)desc value:(bool)val
             page:(UIView*)page y:(CGFloat)y w:(CGFloat)W
        onToggle:(void(^)(BOOL))block {

    UIView* row = [[UIView alloc] initWithFrame:CGRectMake(8, y, W - 16, 44)];
    row.backgroundColor    = bgPanel();
    row.layer.cornerRadius = 5;

    UILabel* lbl = [[UILabel alloc] initWithFrame:CGRectMake(12, 6, W - 100, 18)];
    lbl.text      = name;
    lbl.textColor = textPrimary();
    lbl.font      = [UIFont systemFontOfSize:12 weight:UIFontWeightMedium];

    UILabel* sub = [[UILabel alloc] initWithFrame:CGRectMake(12, 24, W - 100, 13)];
    sub.text      = desc;
    sub.textColor = textSecondary();
    sub.font      = [UIFont systemFontOfSize:10 weight:UIFontWeightRegular];

    UISwitch* sw = [[UISwitch alloc] init];
    sw.frame     = CGRectMake(W - 75, 10, 51, 31);
    sw.transform = CGAffineTransformMakeScale(0.75f, 0.75f);
    sw.on        = val;
    sw.onTintColor = accent();
    sw.tintColor   = [UIColor colorWithWhite:0.2 alpha:1.0];

    // capture block
    void(^cb)(BOOL) = block;
    [sw addAction:[UIAction actionWithHandler:^(UIAction* a) {
        cb([(UISwitch*)a.sender isOn]);
    }] forControlEvents:UIControlEventValueChanged];

    [row addSubview:lbl];
    [row addSubview:sub];
    [row addSubview:sw];
    [page addSubview:row];

    return y + 50;
}

- (void)onTabESP { /* единственный таб, ничего */ }

- (void)handlePan:(UIPanGestureRecognizer*)gr {
    UIView* sv = self.superview;
    if (!sv) return;
    CGPoint t = [gr translationInView:sv];
    self.center = CGPointMake(self.center.x + t.x, self.center.y + t.y);
    [gr setTranslation:CGPointZero inView:sv];
}

@end

// ─────────────────────────────────────────
// MARK: — Toggle button (floating)
// ─────────────────────────────────────────

static MenuView* g_menu  = nil;
static ESPView*  g_esp   = nil;
static bool      g_menuVisible = false;

static void toggleMenu() {
    dispatch_async(dispatch_get_main_queue(), ^{
        g_menu.hidden    = g_menuVisible;
        g_menuVisible    = !g_menuVisible;
    });
}

// ─────────────────────────────────────────
// MARK: — ESP frame collection (game thread)
// ─────────────────────────────────────────

// FILL: адрес PhotonNetwork._players или итерация через _actorToView
// Это вызывается из хука Update — раз в кадр

static void collectESPFrame(Camera mainCam) {
    if (!mainCam) return;

    // FILL: получить массив PlayerController* из PhotonNetwork.PlayerList
    // Шаблон — подставь свой способ итерации:
    //
    //   Il2CppObject* pnInst = ...; // PhotonNetwork.Instance или статик
    //   Il2CppObject* list   = fn_getPlayerList(pnInst);
    //   int count            = il2cpp_array_length(list);
    //   for (int i = 0; i < count; i++) {
    //       Il2CppObject* pc = il2cpp_array_get(list, i);
    //       ...
    //   }
    //
    // Ниже — скелет цикла с заглушкой на входе

    extern Il2CppObject** g_playerControllers;
    extern int            g_playerCount;

    NSMutableArray* newData = [NSMutableArray new];

    for (int i = 0; i < g_playerCount; i++) {
        Il2CppObject* pc = g_playerControllers[i];
        if (!pc) continue;

        bool isDead = rd<bool>((uintptr_t)pc + OFF_PC_IS_DEATH);
        if (isDead) continue;

        Il2CppObject* net = rd<Il2CppObject*>((uintptr_t)pc + OFF_PC_NETWORK);
        if (!net) continue;

        Vector3 wPos = rd<Vector3>((uintptr_t)net + OFF_PN_NET_POSITION);

        Il2CppObject* animCtrl = rd<Il2CppObject*>((uintptr_t)pc + OFF_PC_ANIM_CTRL);
        Il2CppObject* skeleton = animCtrl
            ? rd<Il2CppObject*>((uintptr_t)animCtrl + OFF_PAC_SKELETON)
            : nullptr;

        PlayerESPData* d = (PlayerESPData*)calloc(1, sizeof(PlayerESPData));
        d->valid = false;

        // Кости
        if (skeleton) {
            Transform head     = rd<Transform>((uintptr_t)skeleton + OFF_SK_HEAD);
            Transform chest    = rd<Transform>((uintptr_t)skeleton + OFF_SK_CHEST);
            Transform pelvis   = rd<Transform>((uintptr_t)skeleton + OFF_SK_PELVIS);
            Transform lArm     = rd<Transform>((uintptr_t)skeleton + OFF_SK_L_UPPER_ARM);
            Transform rArm     = rd<Transform>((uintptr_t)skeleton + OFF_SK_R_UPPER_ARM);
            Transform lFore    = rd<Transform>((uintptr_t)skeleton + OFF_SK_L_FOREARM);
            Transform lHand    = rd<Transform>((uintptr_t)skeleton + OFF_SK_L_HAND);
            Transform lThigh   = rd<Transform>((uintptr_t)skeleton + OFF_SK_L_THIGH);
            Transform rThigh   = rd<Transform>((uintptr_t)skeleton + OFF_SK_R_THIGH);

            CGPoint p;
            bool ok = true;

            #define W2S(bone, dst) \
                ok &= worldToScreen(mainCam, bonePos(bone), p); \
                (dst) = p;

            W2S(head,   d->head);
            W2S(chest,  d->chest);
            W2S(pelvis, d->pelvis);
            W2S(lArm,   d->lShoulder);
            W2S(rArm,   d->rShoulder);
            W2S(lFore,  d->lElbow);
            // rElbow = lFore оффсет одинаковый — FILL
            d->rElbow = d->lElbow;
            W2S(lHand,  d->lHand);
            d->rHand = d->lHand; // FILL
            W2S(lThigh, d->lHip);
            W2S(rThigh, d->rHip);

            #undef W2S

            if (ok) {
                // Радиус головы — 1/8 высоты box
                float boxH = d->pelvis.y - d->head.y;
                d->headR = fabsf(boxH) * 0.09f;

                // Box из head/pelvis
                float bw = fabsf(boxH) * 0.45f;
                d->box = CGRectMake(
                    d->head.x - bw / 2,
                    d->head.y - d->headR * 1.5f,
                    bw,
                    fabsf(boxH) + d->headR * 2);
                d->hasBox = YES;
                d->valid  = YES;
            }
        }

        // Если скелета нет, но позиция есть — только box
        if (!d->valid) {
            CGPoint root;
            Vector3 topW   = { wPos.x, wPos.y + 1.75f, wPos.z };
            Vector3 bottomW = { wPos.x, wPos.y, wPos.z };
            CGPoint top, bot;
            if (worldToScreen(mainCam, topW, top) &&
                worldToScreen(mainCam, bottomW, bot)) {
                float bh = fabsf(bot.y - top.y);
                float bw = bh * 0.45f;
                d->box     = CGRectMake(top.x - bw/2, top.y, bw, bh);
                d->hasBox  = YES;
                d->valid   = YES;
            }
        }

        NSValue* v = [NSValue value:&d withObjCType:@encode(PlayerESPData*)];
        [newData addObject:v];
    }

    dispatch_semaphore_wait(g_dataSema, DISPATCH_TIME_FOREVER);

    // Освобождаем старые
    for (NSValue* v in g_frameData) {
        PlayerESPData* d = nil;
        [v getValue:&d];
        free(d);
    }
    g_frameData = newData;

    dispatch_semaphore_signal(g_dataSema);

    // Перерисовка в main thread
    dispatch_async(dispatch_get_main_queue(), ^{
        [g_esp setNeedsDisplay];
    });
}

// ─────────────────────────────────────────
// MARK: — Hooks
// ─────────────────────────────────────────

// Hook UnityAppController applicationDidBecomeActive — создаём overlay
// или hook первого Update на основной камере

%hook UnityAppController

- (void)applicationDidFinishLaunching:(UIApplication*)app {
    %orig;
    resolveSymbols();

    g_dataSema = dispatch_semaphore_create(1);
    g_frameData = [NSMutableArray new];
    screenSize  = [UIScreen mainScreen].bounds.size;

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        UIWindow* win = [UIApplication sharedApplication].windows.firstObject;
        if (!win) return;

        // ESP overlay
        g_esp = [[ESPView alloc] initWithFrame:win.bounds];
        g_esp.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        [win addSubview:g_esp];

        // Menu
        g_menu   = [[MenuView alloc] init];
        g_menu.hidden = YES;
        [win addSubview:g_menu];

        // Floating toggle button
        UIButton* tog = [UIButton buttonWithType:UIButtonTypeCustom];
        tog.frame     = CGRectMake(10, 80, 38, 38);
        tog.backgroundColor            = [UIColor colorWithRed:0.06 green:0.06 blue:0.09 alpha:0.88];
        tog.layer.cornerRadius         = 5;
        tog.layer.borderWidth          = 0.5f;
        tog.layer.borderColor          = [UIColor colorWithWhite:0.22 alpha:1.0].CGColor;
        [tog setTitle:@"▤" forState:UIControlStateNormal];
        [tog setTitleColor:[UIColor colorWithRed:0.35 green:0.85 blue:1.0 alpha:1.0]
                 forState:UIControlStateNormal];
        tog.titleLabel.font = [UIFont systemFontOfSize:18];
        [tog addTarget:[NSBlockOperation blockOperationWithBlock:^{}]
                action:@selector(main)
      forControlEvents:UIControlEventTouchUpInside];
        // UIAction вместо target/action для блока
        [tog addAction:[UIAction actionWithHandler:^(UIAction* a){
            toggleMenu();
        }] forControlEvents:UIControlEventTouchUpInside];
        [win addSubview:tog];
    });
}

%end

// FILL: хук на Update игрового цикла для сбора данных
// Пример — хук на PlayerController.Update или Camera LateUpdate
// grep "Update\b" dump.cs по PlayerController или CameraController
//
// %hook SomeGameUpdateClass
// - (void)Update {
//     %orig;
//     Il2CppObject* cam = /* get main camera */;
//     collectESPFrame(cam);
// }
// %end

// ─────────────────────────────────────────
// MARK: — Ctor
// ─────────────────────────────────────────

%ctor {
    NSString* bundle = [[NSBundle mainBundle] bundleIdentifier];
    if (![bundle isEqualToString:@"com.ScarletWork.CounterFlame"]) return;
    %init;
}
