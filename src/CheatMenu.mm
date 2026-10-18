// ─────────────────────────────────────────────────────────────────────────────
// Counter Flame ESP — tweak
// inject: DYLD_INSERT_LIBRARIES / LiveContainer
// toggle: пилюля ☰ → тап → меню
// ─────────────────────────────────────────────────────────────────────────────

#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#include <mach-o/dyld.h>
#include <dlfcn.h>

// ═══════════════════════════════════════════════════════════════════════════════
//  IL2CPP — заглушки. Подставь свою il2cpp-библиотеку через dlsym.
// ═══════════════════════════════════════════════════════════════════════════════
typedef void* il2cpp_object_t;
typedef void* il2cpp_class_t;
typedef void* il2cpp_field_t;
typedef void* il2cpp_method_t;

static void* (*il2cpp_domain_get)(void)                                                = NULL;
static void* (*il2cpp_domain_get_assemblies)(void*, size_t*)                           = NULL;
static void* (*il2cpp_assembly_get_image)(void*)                                       = NULL;
static il2cpp_class_t (*il2cpp_class_from_name)(void*, const char*, const char*)       = NULL;
static il2cpp_field_t (*il2cpp_class_get_field_from_name)(il2cpp_class_t, const char*) = NULL;
static void (*il2cpp_field_get_value)(il2cpp_object_t, il2cpp_field_t, void*)          = NULL;
static void (*il2cpp_field_static_get_value)(il2cpp_field_t, void*)                    = NULL;
static il2cpp_method_t (*il2cpp_class_get_method_from_name)(il2cpp_class_t, const char*, int) = NULL;
static il2cpp_object_t (*il2cpp_runtime_invoke)(il2cpp_method_t, il2cpp_object_t, void**, void**) = NULL;

static BOOL il2cpp_ready = NO;

static il2cpp_class_t cls_PlayerHull = NULL;
static il2cpp_class_t cls_Camera     = NULL;
static il2cpp_class_t cls_Transform  = NULL;

static il2cpp_field_t fld_SKEL_head, fld_SKEL_chest, fld_SKEL_pelvis;
static il2cpp_field_t fld_SKEL_lArm, fld_SKEL_rArm, fld_SKEL_lThigh, fld_SKEL_rThigh;
static il2cpp_field_t fld_HULL_box, fld_HULL_ducked, fld_HULL_team;
static il2cpp_field_t fld_HULL_active;   // static List<PlayerHull> PlayerHull.Active (0x8)
static il2cpp_field_t fld_PC_isDeath;    // PlayerController._isDeath (0xA8)
static il2cpp_field_t fld_PC_net;        // PlayerController._network (0x88)
static il2cpp_field_t fld_NET_pos;       // PlayerNetwork.networkPosition (0xBC)
static il2cpp_field_t fld_HULL_skel;     // PlayerHull -> PlayerSkeleton (обычно в _controller)

// ─── Vector3 ──────────────────────────────────────────────────────────────────
typedef struct { float x, y, z; } Vector3;
static inline Vector3 V3Add(Vector3 a, Vector3 b) { return (Vector3){a.x+b.x,a.y+b.y,a.z+b.z}; }
static inline Vector3 V3Scale(Vector3 a, float s){ return (Vector3){a.x*s,a.y*s,a.z*s}; }

// TODO-IL2CPP: transform.get_position через il2cpp_runtime_invoke
static Vector3 TRANSFORM_POSITION(il2cpp_object_t transform) {
    if (!transform || !cls_Transform || !il2cpp_runtime_invoke) return (Vector3){0,0,0};
    il2cpp_method_t m = il2cpp_class_get_method_from_name(cls_Transform, "get_position", 0);
    if (!m) return (Vector3){0,0,0};
    void* exc = NULL;
    il2cpp_object_t boxed = il2cpp_runtime_invoke(m, transform, NULL, &exc);
    if (!boxed || exc) return (Vector3){0,0,0};
    return *(Vector3*)((char*)boxed + 0x10);   // boxed struct: header 0x10
}

static il2cpp_object_t CAMERA_MAIN(void) {
    if (!cls_Camera || !il2cpp_runtime_invoke) return NULL;
    il2cpp_method_t m = il2cpp_class_get_method_from_name(cls_Camera, "get_main", 0);
    if (!m) return NULL;
    void* exc = NULL;
    return il2cpp_runtime_invoke(m, NULL, NULL, &exc);
}

static BOOL CAMERA_WORLD_TO_SCREEN(il2cpp_object_t cam, Vector3 world, Vector3* out) {
    if (!cam || !out || !cls_Camera || !il2cpp_runtime_invoke) return NO;
    il2cpp_method_t m = il2cpp_class_get_method_from_name(cls_Camera, "WorldToScreenPoint", 1);
    if (!m) return NO;
    Vector3 arg = world;
    void* args[1] = { &arg };
    void* exc = NULL;
    il2cpp_object_t boxed = il2cpp_runtime_invoke(m, cam, args, &exc);
    if (!boxed || exc) return NO;
    *out = *(Vector3*)((char*)boxed + 0x10);
    return out->z > 0.0f;
}

static inline il2cpp_object_t FIELD_OBJ(il2cpp_object_t o, il2cpp_field_t f) {
    if (!o || !f || !il2cpp_field_get_value) return NULL;
    il2cpp_object_t v = NULL; il2cpp_field_get_value(o, f, &v); return v;
}
static inline BOOL FIELD_BOOL(il2cpp_object_t o, il2cpp_field_t f) {
    if (!o || !f || !il2cpp_field_get_value) return NO;
    BOOL v = NO; il2cpp_field_get_value(o, f, &v); return v;
}
static inline int FIELD_INT(il2cpp_object_t o, il2cpp_field_t f) {
    if (!o || !f || !il2cpp_field_get_value) return 0;
    int v = 0; il2cpp_field_get_value(o, f, &v); return v;
}
static inline Vector3 FIELD_VEC3(il2cpp_object_t o, il2cpp_field_t f) {
    Vector3 v = {0,0,0}; if (!o || !f || !il2cpp_field_get_value) return v;
    il2cpp_field_get_value(o, f, &v); return v;
}

// TODO-IL2CPP: подгрузи символы (dlopen/dlsym) и инициализируй классы
static void ESP_IL2CPP_Init(void) {
    // void* h = dlopen(NULL, RTLD_LAZY);
    // il2cpp_domain_get = dlsym(h, "il2cpp_domain_get");
    // ... (см. предыдущий ответ)
    il2cpp_ready = NO; // поставь YES когда API реально подключён
}

// ═══════════════════════════════════════════════════════════════════════════════
//  Consts / helpers
// ═══════════════════════════════════════════════════════════════════════════════
static const CGFloat kW   = 260.0f;
static const CGFloat kH   = 360.0f;
static const CGFloat kHdr = 42.0f;
static const CGFloat kR   = 12.0f;
static const NSTimeInterval kDur = 0.20;

static inline UIColor* C(CGFloat r, CGFloat g, CGFloat b, CGFloat a) {
    return [UIColor colorWithRed:r green:g blue:b alpha:a];
}

// Безопасная ориентация под iOS 14+
static UIWindowScene* ActiveWindowScene(void) {
    for (UIScene* s in [UIApplication sharedApplication].connectedScenes) {
        if ([s isKindOfClass:[UIWindowScene class]] &&
            s.activationState == UISceneActivationStateForegroundActive) {
            return (UIWindowScene*)s;
        }
    }
    for (UIScene* s in [UIApplication sharedApplication].connectedScenes) {
        if ([s isKindOfClass:[UIWindowScene class]]) return (UIWindowScene*)s;
    }
    return nil;
}

static CGRect SafeScreenBounds(void) {
    UIWindowScene* scene = ActiveWindowScene();
    UIWindow* key = scene ? scene.windows.firstObject : UIApplication.sharedApplication.keyWindow;
    CGRect b = key ? key.bounds : UIScreen.mainScreen.bounds;
    UIEdgeInsets ins = key ? key.safeAreaInsets : UIEdgeInsetsZero;
    // меню не должно уезжать под notch/Dynamic Island
    b.origin.y      += MAX(ins.top, 12);
    b.size.height   -= MAX(ins.top, 12) + MAX(ins.bottom, 12);
    return b;
}

// ═══════════════════════════════════════════════════════════════════════════════
//  Passthrough (фикс перехвата тачей)
// ═══════════════════════════════════════════════════════════════════════════════
@interface PassthroughWindow : UIWindow @end
@implementation PassthroughWindow
- (UIView*)hitTest:(CGPoint)p withEvent:(UIEvent*)e {
    UIView* hit = [super hitTest:p withEvent:e];
    return (hit == self.rootViewController.view) ? nil : hit;
}
@end

@interface PassthroughView : UIView @end
@implementation PassthroughView
- (UIView*)hitTest:(CGPoint)p withEvent:(UIEvent*)e {
    UIView* hit = [super hitTest:p withEvent:e];
    return (hit == self) ? nil : hit;
}
@end

// ═══════════════════════════════════════════════════════════════════════════════
//  PillButton (fix: drag + tap через pan-end)
// ═══════════════════════════════════════════════════════════════════════════════
@interface PillButton : UIView
@property (copy) dispatch_block_t action;
@end
@implementation PillButton {
    CGPoint _start;
    CGPoint _origin;
    BOOL    _moved;
}
- (instancetype)init {
    self = [super initWithFrame:CGRectMake(20, 120, 44, 28)];
    self.backgroundColor    = C(0.10f, 0.10f, 0.13f, 0.92f);
    self.layer.cornerRadius = 14;
    self.layer.borderColor  = C(0.27f, 0.52f, 1.00f, 0.45f).CGColor;
    self.layer.borderWidth  = 1.0f;

    UILabel* lbl        = [[UILabel alloc] initWithFrame:self.bounds];
    lbl.text            = @"☰";
    lbl.textAlignment   = NSTextAlignmentCenter;
    lbl.font            = [UIFont systemFontOfSize:13];
    lbl.textColor       = C(0.75f, 0.75f, 0.80f, 1.0f);
    lbl.userInteractionEnabled = NO;
    [self addSubview:lbl];

    UIPanGestureRecognizer* pan = [[UIPanGestureRecognizer alloc]
        initWithTarget:self action:@selector(handlePan:)];
    pan.maximumNumberOfTouches = 1;
    [self addGestureRecognizer:pan];
    return self;
}
- (void)handlePan:(UIPanGestureRecognizer*)g {
    CGPoint loc = [g locationInView:self.superview];
    if (g.state == UIGestureRecognizerStateBegan) {
        _moved  = NO;
        _start  = loc;
        _origin = self.frame.origin;
    } else if (g.state == UIGestureRecognizerStateChanged) {
        CGFloat dx = loc.x - _start.x, dy = loc.y - _start.y;
        if (fabs(dx) > 4 || fabs(dy) > 4) _moved = YES;
        CGRect f = self.frame;
        f.origin = CGPointMake(_origin.x + dx, _origin.y + dy);
        self.frame = f;
    } else if (g.state == UIGestureRecognizerStateEnded ||
               g.state == UIGestureRecognizerStateCancelled) {
        if (!_moved && _action) _action();
    }
}
@end

// ═══════════════════════════════════════════════════════════════════════════════
//  MenuView
// ═══════════════════════════════════════════════════════════════════════════════
@interface MenuView : UIView
@property (strong) UIButton* hideBtn;
@property (strong) UIButton* closeBtn;
@property (strong) UIButton* espBtn;
@property (assign) BOOL espEnabled;
@end

@implementation MenuView {
    CGPoint _dragOffset;
    BOOL    _dragging;
}

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    self.backgroundColor     = C(0.07f, 0.07f, 0.09f, 0.93f);
    self.layer.cornerRadius  = kR;
    self.layer.masksToBounds = YES;

    UIView* hdr         = [[UIView alloc] initWithFrame:CGRectMake(0, 0, kW, kHdr)];
    hdr.backgroundColor = C(0.10f, 0.10f, 0.13f, 1.0f);
    [self addSubview:hdr];

    UIView* line         = [[UIView alloc] initWithFrame:CGRectMake(0, kHdr - 1, kW, 1)];
    line.backgroundColor = C(0.27f, 0.52f, 1.00f, 0.55f);
    [self addSubview:line];

    UILabel* title      = [[UILabel alloc] initWithFrame:CGRectMake(0, (kHdr-17)*.5f, kW, 17)];
    title.text          = @"Cheat Menu";
    title.font          = [UIFont systemFontOfSize:13 weight:UIFontWeightSemibold];
    title.textColor     = C(0.92f, 0.92f, 0.95f, 1.0f);
    title.textAlignment = NSTextAlignmentCenter;
    [self addSubview:title];

    CALayer* border      = [CALayer layer];
    border.frame         = CGRectMake(0, 0, kW, kH);
    border.borderColor   = C(0.22f, 0.22f, 0.28f, 0.65f).CGColor;
    border.borderWidth   = 1.0f;
    border.cornerRadius  = kR;
    [self.layer addSublayer:border];

    self.hideBtn  = [self makeHdrBtn:@"−" x:kW-58];
    self.closeBtn = [self makeHdrBtn:@"×" x:kW-30];

    // ESP-toggle
    self.espBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    self.espBtn.frame = CGRectMake(14, kHdr + 12, kW - 28, 40);
    self.espBtn.backgroundColor = C(0.14f, 0.14f, 0.17f, 1.0f);
    self.espBtn.layer.cornerRadius = 8;
    self.espBtn.layer.masksToBounds = YES;
    self.espBtn.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeft;
    self.espBtn.contentEdgeInsets = UIEdgeInsetsMake(0, 12, 0, 0);
    self.espBtn.titleLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightMedium];
    [self.espBtn setTitle:@"ESP: OFF" forState:UIControlStateNormal];
    [self.espBtn setTitleColor:C(0.55f,0.55f,0.60f,1) forState:UIControlStateNormal];
    [self addSubview:self.espBtn];

    // drag за header
    UIPanGestureRecognizer* pan = [[UIPanGestureRecognizer alloc]
        initWithTarget:self action:@selector(handlePan:)];
    pan.delegate = (id<UIGestureRecognizerDelegate>)self;
    [hdr addGestureRecognizer:pan];

    return self;
}

// не мешаем нажатиям на кнопки хедера
- (BOOL)gestureRecognizer:(UIGestureRecognizer*)g
       shouldReceiveTouch:(UITouch*)t {
    return ![t.view isKindOfClass:[UIButton class]];
}

- (UIButton*)makeHdrBtn:(NSString*)g x:(CGFloat)x {
    UIButton* btn               = [UIButton buttonWithType:UIButtonTypeCustom];
    btn.frame                   = CGRectMake(x, (kHdr-24)*.5f, 24, 24);
    btn.layer.cornerRadius      = 12;
    btn.layer.masksToBounds     = YES;
    btn.backgroundColor         = C(0.17f, 0.17f, 0.21f, 1.0f);
    btn.titleLabel.font         = [UIFont systemFontOfSize:11 weight:UIFontWeightMedium];
    [btn setTitle:g forState:UIControlStateNormal];
    [btn setTitleColor:C(0.55f,0.55f,0.60f,1) forState:UIControlStateNormal];
    [btn setTitleColor:[UIColor whiteColor]    forState:UIControlStateHighlighted];
    [btn addTarget:self action:@selector(btnDown:)
        forControlEvents:UIControlEventTouchDown];
    [btn addTarget:self action:@selector(btnUp:)
        forControlEvents:UIControlEventTouchUpInside|UIControlEventTouchUpOutside];
    [self addSubview:btn];
    return btn;
}
- (void)btnDown:(UIButton*)b {
    [UIView animateWithDuration:0.08 animations:^{
        b.backgroundColor = C(0.28f, 0.28f, 0.36f, 1.0f);
    }];
}
- (void)btnUp:(UIButton*)b {
    [UIView animateWithDuration:0.12 animations:^{
        b.backgroundColor = C(0.17f, 0.17f, 0.21f, 1.0f);
    }];
}

- (void)handlePan:(UIPanGestureRecognizer*)g {
    CGPoint loc = [g locationInView:self.superview];
    if (g.state == UIGestureRecognizerStateBegan) {
        _dragging   = YES;
        _dragOffset = CGPointMake(loc.x - self.frame.origin.x,
                                  loc.y - self.frame.origin.y);
    } else if (g.state == UIGestureRecognizerStateChanged) {
        CGRect f   = self.frame;
        f.origin   = CGPointMake(loc.x - _dragOffset.x,
                                 loc.y - _dragOffset.y);
        self.frame = f;
    } else if (g.state == UIGestureRecognizerStateEnded ||
               g.state == UIGestureRecognizerStateCancelled) {
        _dragging = NO;
        // клампим в safe area, чтобы меню не уехало за экран
        CGRect safe = SafeScreenBounds();
        CGRect f = self.frame;
        f.origin.x = MAX(safe.origin.x, MIN(f.origin.x, CGRectGetMaxX(safe) - f.size.width));
        f.origin.y = MAX(safe.origin.y, MIN(f.origin.y, CGRectGetMaxY(safe) - f.size.height));
        [UIView animateWithDuration:0.15 animations:^{ self.frame = f; }];
    }
}

- (void)setEspEnabled:(BOOL)on {
    _espEnabled = on;
    [self.espBtn setTitle:(on ? @"ESP: ON" : @"ESP: OFF") forState:UIControlStateNormal];
    UIColor* c = on ? C(0.27f,0.52f,1.00f,1) : C(0.55f,0.55f,0.60f,1);
    [self.espBtn setTitleColor:c forState:UIControlStateNormal];
}
@end

// ═══════════════════════════════════════════════════════════════════════════════
//  ESP overlay
// ═══════════════════════════════════════════════════════════════════════════════
@interface ESPOverlayView : UIView
@property (assign) BOOL enabled;
@end

@implementation ESPOverlayView {
    CADisplayLink* _link;
}
- (instancetype)initWithFrame:(CGRect)f {
    self = [super initWithFrame:f];
    self.backgroundColor = [UIColor clearColor];
    self.userInteractionEnabled = NO;         // никогда не ест тачи
    _link = [CADisplayLink displayLinkWithTarget:self selector:@selector(tick)];
    [_link addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
    return self;
}
- (void)dealloc { [_link invalidate]; }
- (void)tick { if (self.enabled) [self setNeedsDisplay]; }

- (void)drawRect:(CGRect)rect {
    if (!self.enabled || !il2cpp_ready) return;
    CGContextRef ctx = UIGraphicsGetCurrentContext();
    if (!ctx) return;

    il2cpp_object_t cam = CAMERA_MAIN();
    if (!cam) return;

    NSArray* hulls = [self activeHulls];
    CGFloat screenH = self.bounds.size.height;

    for (id obj in hulls) {
        il2cpp_object_t hull = (il2cpp_object_t)(void*)obj;
        if (!hull) continue;
        if (FIELD_BOOL(hull, fld_PC_isDeath)) continue;

        int team = FIELD_INT(hull, fld_HULL_team);
        UIColor* col = (team == 1)
            ? [UIColor colorWithRed:0.27 green:0.52 blue:1.0 alpha:1]
            : [UIColor colorWithRed:1.0 green:0.36 blue:0.36 alpha:1];

        Vector3 feetW = FIELD_VEC3(hull, fld_NET_pos);          // networkPosition
        Vector3 headW = V3Add(feetW, (Vector3){0,1.8f,0});

        Vector3 sf3, sh3;
        if (!CAMERA_WORLD_TO_SCREEN(cam, feetW, &sf3)) continue;
        if (!CAMERA_WORLD_TO_SCREEN(cam, headW, &sh3)) continue;

        CGPoint feet = CGPointMake(sf3.x, screenH - sf3.y);
        CGPoint head = CGPointMake(sh3.x, screenH - sh3.y);

        CGFloat h = feet.y - head.y;
        if (h < 6) continue;
        CGFloat w = h * 0.45f;

        CGContextSetStrokeColorWithColor(ctx, col.CGColor);
        CGContextSetLineWidth(ctx, 1.5f);
        CGContextStrokeRect(ctx, CGRectMake(feet.x - w*0.5f, head.y, w, h));

        // кости
        il2cpp_object_t skel = FIELD_OBJ(hull, fld_HULL_skel);
        if (skel) {
            [self line:ctx
                   a:TRANSFORM_POSITION(FIELD_OBJ(skel, fld_SKEL_head))
                   b:TRANSFORM_POSITION(FIELD_OBJ(skel, fld_SKEL_chest))
                 cam:cam color:col screenH:screenH];
            [self line:ctx
                   a:TRANSFORM_POSITION(FIELD_OBJ(skel, fld_SKEL_chest))
                   b:TRANSFORM_POSITION(FIELD_OBJ(skel, fld_SKEL_pelvis))
                 cam:cam color:col screenH:screenH];
            [self line:ctx
                   a:TRANSFORM_POSITION(FIELD_OBJ(skel, fld_SKEL_chest))
                   b:TRANSFORM_POSITION(FIELD_OBJ(skel, fld_SKEL_lArm))
                 cam:cam color:col screenH:screenH];
            [self line:ctx
                   a:TRANSFORM_POSITION(FIELD_OBJ(skel, fld_SKEL_chest))
                   b:TRANSFORM_POSITION(FIELD_OBJ(skel, fld_SKEL_rArm))
                 cam:cam color:col screenH:screenH];
            [self line:ctx
                   a:TRANSFORM_POSITION(FIELD_OBJ(skel, fld_SKEL_pelvis))
                   b:TRANSFORM_POSITION(FIELD_OBJ(skel, fld_SKEL_lThigh))
                 cam:cam color:col screenH:screenH];
            [self line:ctx
                   a:TRANSFORM_POSITION(FIELD_OBJ(skel, fld_SKEL_pelvis))
                   b:TRANSFORM_POSITION(FIELD_OBJ(skel, fld_SKEL_rThigh))
                 cam:cam color:col screenH:screenH];
        }
    }
}

- (void)line:(CGContextRef)ctx a:(Vector3)a b:(Vector3)b
         cam:(il2cpp_object_t)cam color:(UIColor*)col screenH:(CGFloat)H {
    Vector3 sa, sb;
    if (!CAMERA_WORLD_TO_SCREEN(cam, a, &sa)) return;
    if (!CAMERA_WORLD_TO_SCREEN(cam, b, &sb)) return;
    CGPoint p1 = CGPointMake(sa.x, H - sa.y);
    CGPoint p2 = CGPointMake(sb.x, H - sb.y);
    CGContextSetStrokeColorWithColor(ctx, col.CGColor);
    CGContextSetLineWidth(ctx, 1.2f);
    CGContextMoveToPoint(ctx, p1.x, p1.y);
    CGContextAddLineToPoint(ctx, p2.x, p2.y);
    CGContextStrokePath(ctx);
}

// TODO-IL2CPP: подставь PlayerHull.Active (static List<PlayerHull>)
- (NSArray*)activeHulls {
    if (!fld_HULL_active || !il2cpp_field_static_get_value) return @[];
    // void* list = NULL; il2cpp_field_static_get_value(fld_HULL_active, &list);
    // вернуть как NSArray* через мост (у тебя свой il2cpp-list-to-array)
    return @[];
}
@end

// ═══════════════════════════════════════════════════════════════════════════════
//  CheatController
// ═══════════════════════════════════════════════════════════════════════════════
@interface CheatController : NSObject
+ (instancetype)shared;
- (void)toggle;
@end

@implementation CheatController {
    PassthroughWindow* _win;
    PassthroughView*   _rootView;
    MenuView*          _menu;
    PillButton*        _pill;
    ESPOverlayView*    _esp;
    BOOL               _visible;
    CGRect             _lastBounds;
}

+ (instancetype)shared {
    static CheatController* inst; static dispatch_once_t once;
    dispatch_once(&once, ^{ inst = [CheatController new]; });
    return inst;
}

- (instancetype)init {
    self = [super init];
    [self build];
    [[NSNotificationCenter defaultCenter]
        addObserver:self selector:@selector(onSceneChange:)
        name:UIWindowSceneDidUpdateCoordinateSpaceInterfaceOrientationNotification
        object:nil];
    [[NSNotificationCenter defaultCenter]
        addObserver:self selector:@selector(onSceneChange:)
        name:UIWindowDidBecomeKeyNotification
        object:nil];
    return self;
}

- (void)onSceneChange:(NSNotification*)n {
    dispatch_async(dispatch_get_main_queue(), ^{
        CGRect b = SafeScreenBounds();
        if (!CGRectEqualToRect(b, self->_lastBounds)) {
            self->_lastBounds = b;
            [self layoutUI];
        }
    });
}

- (void)build {
    // ── PassthroughWindow / PassthroughView (фикс перехвата тачей) ──
    UIWindowScene* scene = ActiveWindowScene();
    _win = scene
        ? [[PassthroughWindow alloc] initWithWindowScene:scene]
        : [[PassthroughWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
    _win.windowLevel     = UIWindowLevelAlert + 200;
    _win.backgroundColor = [UIColor clearColor];

    UIViewController* vc = [UIViewController new];
    _rootView = [[PassthroughView alloc] initWithFrame:[UIScreen mainScreen].bounds];
    _rootView.backgroundColor = [UIColor clearColor];
    vc.view = _rootView;
    _win.rootViewController = vc;
    [_win makeKeyAndVisible];

    // ── ESP (под меню) ──
    _esp = [[ESPOverlayView alloc] initWithFrame:_rootView.bounds];
    [_rootView addSubview:_esp];

    // ── Меню ──
    _menu = [[MenuView alloc] initWithFrame:CGRectMake(0, 0, kW, kH)];
    [_rootView addSubview:_menu];

    // ── Пилюля ──
    __weak typeof(self) ws = self;
    _pill = [PillButton new];
    _pill.action = ^{ [ws doShow]; };
    _pill.hidden = YES;
    [_rootView addSubview:_pill];

    // ── Колбэки ──
    [_menu.hideBtn  addTarget:self action:@selector(doHide)
        forControlEvents:UIControlEventTouchUpInside];
    [_menu.closeBtn addTarget:self action:@selector(doClose)
        forControlEvents:UIControlEventTouchUpInside];
    [_menu.espBtn   addTarget:self action:@selector(toggleESP)
        forControlEvents:UIControlEventTouchUpInside];

    [self layoutUI];
}

// ── Позиционирование с учётом safe area и текущей ориентации ──
- (void)layoutUI {
    CGRect safe = SafeScreenBounds();
    _lastBounds = safe;

    _rootView.frame = _win.bounds;
    _esp.frame      = _win.bounds;

    CGRect f = _menu.frame;
    f.origin.x = safe.origin.x + (safe.size.width  - f.size.width ) * 0.5f;
    f.origin.y = safe.origin.y + (safe.size.height - f.size.height) * 0.5f;
    _menu.frame = f;

    if (_pill) {
        CGRect pf = _pill.frame;
        if (CGRectIsEmpty(pf) || pf.origin.x < safe.origin.x) {
            pf.origin = CGPointMake(safe.origin.x + 20, safe.origin.y + 80);
            _pill.frame = pf;
        }
    }
}

- (void)toggleESP {
    BOOL on = !_menu.espEnabled;
    _menu.espEnabled = on;
    _esp.enabled     = on;
}

- (void)doShow {
    _pill.hidden    = YES;
    _menu.alpha     = 0;
    _menu.transform = CGAffineTransformMakeScale(0.88f, 0.88f);
    _menu.hidden    = NO;
    [UIView animateWithDuration:kDur delay:0
                        options:UIViewAnimationOptionCurveEaseOut
                     animations:^{
        self->_menu.alpha     = 1.0f;
        self->_menu.transform = CGAffineTransformIdentity;
    } completion:nil];
    _visible = YES;
}

- (void)doHide {
    [UIView animateWithDuration:kDur delay:0
                        options:UIViewAnimationOptionCurveEaseIn
                     animations:^{
        self->_menu.alpha     = 0.0f;
        self->_menu.transform = CGAffineTransformMakeScale(0.94f, 0.94f);
    } completion:^(BOOL done) {
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
        self->_menu.alpha     = 0.0f;
        self->_menu.transform = CGAffineTransformMakeScale(0.88f, 0.88f);
    } completion:^(BOOL done) {
        self->_menu.hidden    = YES;
        self->_menu.transform = CGAffineTransformIdentity;
        self->_pill.hidden    = NO;
        self->_visible        = NO;
    }];
}

- (void)toggle { _visible ? [self doHide] : [self doShow]; }

@end

// ═══════════════════════════════════════════════════════════════════════════════
//  entry
// ═══════════════════════════════════════════════════════════════════════════════
__attribute__((constructor))
static void Init(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            ESP_IL2CPP_Init();
            [[CheatController shared] toggle];
        });
    });
}
