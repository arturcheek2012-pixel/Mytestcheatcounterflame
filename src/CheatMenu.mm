// ─────────────────────────────────────────────────────────────────────────────
// Counter Flame — Cheat Menu + ESP (боксы)
// inject: DYLD_INSERT_LIBRARIES / LiveContainer
// toggle: пилюля ☰ → тап → меню
// ─────────────────────────────────────────────────────────────────────────────

#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#include <mach-o/dyld.h>
#include <dlfcn.h>
#include <math.h>

// ═══════════════════════════════════════════════════════════════════════════════
//  IL2CPP runtime
// ═══════════════════════════════════════════════════════════════════════════════
typedef void* il2cpp_object_t;
typedef void* il2cpp_class_t;
typedef void* il2cpp_field_t;
typedef void* il2cpp_method_t;
typedef void* il2cpp_image_t;
typedef void* il2cpp_domain_t;

static il2cpp_domain_t (*il2cpp_domain_get)(void)                                          = NULL;
static void**          (*il2cpp_domain_get_assemblies)(il2cpp_domain_t, size_t*)           = NULL;
static il2cpp_image_t  (*il2cpp_assembly_get_image)(void*)                                 = NULL;
static il2cpp_class_t  (*il2cpp_class_from_name)(il2cpp_image_t, const char*, const char*) = NULL;
static il2cpp_field_t  (*il2cpp_class_get_field_from_name)(il2cpp_class_t, const char*)    = NULL;
static void            (*il2cpp_field_get_value)(il2cpp_object_t, il2cpp_field_t, void*)  = NULL;
static void            (*il2cpp_field_static_get_value)(il2cpp_field_t, void*)             = NULL;
static il2cpp_method_t (*il2cpp_class_get_method_from_name)(il2cpp_class_t, const char*, int) = NULL;
static il2cpp_object_t (*il2cpp_runtime_invoke)(il2cpp_method_t, il2cpp_object_t, void**, void**) = NULL;
static il2cpp_class_t  (*il2cpp_object_get_class)(il2cpp_object_t)                         = NULL;
static uint64_t        (*il2cpp_array_length)(il2cpp_object_t)                             = NULL;

static BOOL g_il2cpp = NO;

// ═══════════════════════════════════════════════════════════════════════════════
//  Классы / поля — точно по дампу
// ═══════════════════════════════════════════════════════════════════════════════
static il2cpp_class_t cls_PlayerHull     = NULL;
static il2cpp_class_t cls_Camera         = NULL;
static il2cpp_class_t cls_Transform      = NULL;

static il2cpp_field_t fld_HULL_active;   // static List<PlayerHull>  (0x8)
static il2cpp_field_t fld_HULL_hulls;    // static PlayerHull[]      (0x0)
static il2cpp_field_t fld_HULL_box;      // BoxCollider _box         (0x18)
static il2cpp_field_t fld_HULL_team;     // Team _team               (0x30)

static il2cpp_field_t fld_LIST_items;    // T[] _items
static il2cpp_field_t fld_LIST_size;     // int _size

// ═══════════════════════════════════════════════════════════════════════════════
//  Helpers
// ═══════════════════════════════════════════════════════════════════════════════
typedef struct { float x, y, z; } Vector3;

static inline il2cpp_object_t FIELD_OBJ(il2cpp_object_t o, il2cpp_field_t f) {
    if (!o || !f || !il2cpp_field_get_value) return NULL;
    il2cpp_object_t v = NULL; il2cpp_field_get_value(o, f, &v); return v;
}
static inline int FIELD_INT(il2cpp_object_t o, il2cpp_field_t f) {
    if (!o || !f || !il2cpp_field_get_value) return 0;
    int v = 0; il2cpp_field_get_value(o, f, &v); return v;
}

static il2cpp_object_t COMPONENT_TRANSFORM(il2cpp_object_t comp) {
    if (!comp || !il2cpp_object_get_class || !il2cpp_runtime_invoke) return NULL;
    il2cpp_class_t cls = il2cpp_object_get_class(comp);
    if (!cls) return NULL;
    il2cpp_method_t m = il2cpp_class_get_method_from_name(cls, "get_transform", 0);
    if (!m) return NULL;
    void* exc = NULL;
    return il2cpp_runtime_invoke(m, comp, NULL, &exc);
}

static Vector3 TRANSFORM_POSITION(il2cpp_object_t t) {
    if (!t || !cls_Transform || !il2cpp_runtime_invoke) return (Vector3){0,0,0};
    il2cpp_method_t m = il2cpp_class_get_method_from_name(cls_Transform, "get_position", 0);
    if (!m) return (Vector3){0,0,0};
    void* exc = NULL;
    il2cpp_object_t boxed = il2cpp_runtime_invoke(m, t, NULL, &exc);
    if (!boxed || exc) return (Vector3){0,0,0};
    return *(Vector3*)((char*)boxed + 0x10);
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

// ═══════════════════════════════════════════════════════════════════════════════
//  Список PlayerHull
// ═══════════════════════════════════════════════════════════════════════════════
static NSArray<NSValue*>* ESP_PlayerHulls(void) {
    if (!g_il2cpp || !cls_PlayerHull) return @[];
    NSMutableArray<NSValue*>* out = [NSMutableArray array];

    if (fld_HULL_hulls && il2cpp_field_static_get_value && il2cpp_array_length) {
        il2cpp_object_t arr = NULL;
        il2cpp_field_static_get_value(fld_HULL_hulls, &arr);
        if (arr) {
            uint64_t len = il2cpp_array_length(arr);
            for (uint64_t i = 0; i < len; i++) {
                il2cpp_object_t el = *(il2cpp_object_t*)((char*)arr + 0x20 + i * sizeof(void*));
                if (el) [out addObject:[NSValue valueWithPointer:el]];
            }
        }
    }

    if (out.count == 0 && fld_HULL_active && il2cpp_field_static_get_value) {
        il2cpp_object_t list = NULL;
        il2cpp_field_static_get_value(fld_HULL_active, &list);
        if (list) {
            if (!fld_LIST_items && il2cpp_object_get_class) {
                il2cpp_class_t lc = il2cpp_object_get_class(list);
                if (lc) {
                    fld_LIST_items = il2cpp_class_get_field_from_name(lc, "_items");
                    fld_LIST_size  = il2cpp_class_get_field_from_name(lc, "_size");
                }
            }
            if (fld_LIST_items && fld_LIST_size) {
                il2cpp_object_t items = NULL;
                int size = 0;
                il2cpp_field_get_value(list, fld_LIST_items, &items);
                il2cpp_field_get_value(list, fld_LIST_size,  &size);
                if (items && size > 0) {
                    for (int i = 0; i < size; i++) {
                        il2cpp_object_t el = *(il2cpp_object_t*)((char*)items + 0x20 + i * sizeof(void*));
                        if (el) [out addObject:[NSValue valueWithPointer:el]];
                    }
                }
            }
        }
    }
    return out;
}

// ═══════════════════════════════════════════════════════════════════════════════
//  ESP_IL2CPP_Init
// ═══════════════════════════════════════════════════════════════════════════════
static void ESP_IL2CPP_Init(void) {
    void* h = dlopen(NULL, RTLD_LAZY);

#define RESOLVE(dst, name) \
    do { dst = (__typeof__(dst))dlsym(h, name); } while (0)

    RESOLVE(il2cpp_domain_get,                 "il2cpp_domain_get");
    RESOLVE(il2cpp_domain_get_assemblies,      "il2cpp_domain_get_assemblies");
    RESOLVE(il2cpp_assembly_get_image,         "il2cpp_assembly_get_image");
    RESOLVE(il2cpp_class_from_name,            "il2cpp_class_from_name");
    RESOLVE(il2cpp_class_get_field_from_name,  "il2cpp_class_get_field_from_name");
    RESOLVE(il2cpp_field_get_value,            "il2cpp_field_get_value");
    RESOLVE(il2cpp_field_static_get_value,     "il2cpp_field_static_get_value");
    RESOLVE(il2cpp_class_get_method_from_name, "il2cpp_class_get_method_from_name");
    RESOLVE(il2cpp_runtime_invoke,             "il2cpp_runtime_invoke");
    RESOLVE(il2cpp_object_get_class,           "il2cpp_object_get_class");
    RESOLVE(il2cpp_array_length,               "il2cpp_array_length");

#undef RESOLVE

    if (!il2cpp_domain_get || !il2cpp_domain_get_assemblies ||
        !il2cpp_assembly_get_image || !il2cpp_class_from_name ||
        !il2cpp_class_get_field_from_name || !il2cpp_field_get_value ||
        !il2cpp_field_static_get_value || !il2cpp_class_get_method_from_name ||
        !il2cpp_runtime_invoke || !il2cpp_object_get_class) {
        g_il2cpp = NO;
        NSLog(@"[ESP] il2cpp symbols not found — ESP disabled");
        return;
    }

    size_t n = 0;
    void** asms = il2cpp_domain_get_assemblies(il2cpp_domain_get(), &n);
    if (!asms || !n) { g_il2cpp = NO; NSLog(@"[ESP] no assemblies"); return; }

    il2cpp_image_t img = NULL;
    for (size_t i = 0; i < n; i++) {
        il2cpp_image_t image = il2cpp_assembly_get_image(asms[i]);
        if (!image) continue;
        il2cpp_class_t probe = il2cpp_class_from_name(image, "", "PlayerHull");
        if (probe) { img = image; break; }
    }
    if (!img) { g_il2cpp = NO; NSLog(@"[ESP] PlayerHull class not found"); return; }

    cls_PlayerHull = il2cpp_class_from_name(img, "", "PlayerHull");
    cls_Camera     = il2cpp_class_from_name(img, "UnityEngine", "Camera");
    cls_Transform  = il2cpp_class_from_name(img, "UnityEngine", "Transform");

    if (!cls_PlayerHull || !cls_Camera || !cls_Transform) {
        g_il2cpp = NO; NSLog(@"[ESP] required classes missing"); return;
    }

    fld_HULL_active = il2cpp_class_get_field_from_name(cls_PlayerHull, "Active");
    fld_HULL_hulls  = il2cpp_class_get_field_from_name(cls_PlayerHull, "Hulls");
    fld_HULL_box    = il2cpp_class_get_field_from_name(cls_PlayerHull, "_box");
    fld_HULL_team   = il2cpp_class_get_field_from_name(cls_PlayerHull, "_team");

    g_il2cpp = YES;
    NSLog(@"[ESP] il2cpp ready (PlayerHull=%p hulls_fld=%p active_fld=%p)",
          cls_PlayerHull, fld_HULL_hulls, fld_HULL_active);
}

// ═══════════════════════════════════════════════════════════════════════════════
//  UI utilities
// ═══════════════════════════════════════════════════════════════════════════════
static const CGFloat kW   = 260.0f;
static const CGFloat kH   = 360.0f;
static const CGFloat kHdr = 42.0f;
static const CGFloat kR   = 12.0f;
static const NSTimeInterval kDur = 0.20;

static inline UIColor* C(CGFloat r, CGFloat g, CGFloat b, CGFloat a) {
    return [UIColor colorWithRed:r green:g blue:b alpha:a];
}

static UIWindowScene* ActiveWindowScene(void) {
    for (UIScene* s in [UIApplication sharedApplication].connectedScenes) {
        if ([s isKindOfClass:[UIWindowScene class]] &&
            s.activationState == UISceneActivationStateForegroundActive)
            return (UIWindowScene*)s;
    }
    for (UIScene* s in [UIApplication sharedApplication].connectedScenes) {
        if ([s isKindOfClass:[UIWindowScene class]]) return (UIWindowScene*)s;
    }
    return nil;
}
static UIWindow* KeyWindowForScene(UIWindowScene* scene) {
    if (scene) {
        for (UIWindow* w in scene.windows) if (w.isKeyWindow) return w;
        return scene.windows.firstObject;
    }
    for (UIWindow* w in UIApplication.sharedApplication.windows)
        if (w.isKeyWindow) return w;
    return UIApplication.sharedApplication.windows.firstObject;
}
static CGRect SafeScreenBounds(void) {
    UIWindow* key = KeyWindowForScene(ActiveWindowScene());
    CGRect b         = key ? key.bounds : UIScreen.mainScreen.bounds;
    UIEdgeInsets ins = key ? key.safeAreaInsets : UIEdgeInsetsZero;
    b.origin.y    += MAX(ins.top, 12);
    b.size.height -= MAX(ins.top, 12) + MAX(ins.bottom, 12);
    return b;
}

// ═══════════════════════════════════════════════════════════════════════════════
//  Passthrough window / view
// ═══════════════════════════════════════════════════════════════════════════════
@interface PassthroughWindow : UIWindow @end
@implementation PassthroughWindow
- (UIView*)hitTest:(CGPoint)p withEvent:(UIEvent*)e {
    UIView* hit = [super hitTest:p withEvent:e];
    return (hit == nil || hit == self.rootViewController.view) ? nil : hit;
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
//  PillButton
// ═══════════════════════════════════════════════════════════════════════════════
@interface PillButton : UIView
@property (copy) dispatch_block_t action;
@end
@implementation PillButton {
    CGPoint _start, _origin;
    BOOL    _moved;
}
- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor     = C(0.10f, 0.10f, 0.13f, 0.92f);
        self.layer.cornerRadius  = frame.size.height * 0.5f;
        self.layer.borderColor   = C(0.27f, 0.52f, 1.00f, 0.45f).CGColor;
        self.layer.borderWidth   = 1.0f;
        self.userInteractionEnabled = YES;
        UILabel* lbl        = [[UILabel alloc] initWithFrame:self.bounds];
        lbl.text            = @"☰";
        lbl.textAlignment   = NSTextAlignmentCenter;
        lbl.font            = [UIFont systemFontOfSize:13];
        lbl.textColor       = C(0.75f, 0.75f, 0.80f, 1.0f);
        lbl.userInteractionEnabled = NO;
        lbl.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        [self addSubview:lbl];
        UIPanGestureRecognizer* pan = [[UIPanGestureRecognizer alloc]
            initWithTarget:self action:@selector(handlePan:)];
        pan.maximumNumberOfTouches = 1;
        [self addGestureRecognizer:pan];
    }
    return self;
}
- (UIView*)hitTest:(CGPoint)point withEvent:(UIEvent*)event {
    if (self.hidden || self.alpha < 0.01f || !self.userInteractionEnabled) return nil;
    CGPoint p = [self convertPoint:point fromView:self.superview];
    return [self pointInside:p withEvent:event] ? self : nil;
}
- (void)handlePan:(UIPanGestureRecognizer*)g {
    CGPoint loc = [g locationInView:self.superview];
    if (g.state == UIGestureRecognizerStateBegan) {
        _moved = NO; _start = loc; _origin = self.frame.origin;
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
@interface MenuView : UIView <UIGestureRecognizerDelegate>
@property (strong) UIButton* hideBtn;
@property (strong) UIButton* closeBtn;
@property (strong) UIButton* espBtn;
@property (assign, nonatomic) BOOL espEnabled;
@end
@implementation MenuView {
    CGPoint _dragOffset;
}
- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    self.backgroundColor     = C(0.07f, 0.07f, 0.09f, 0.93f);
    self.layer.cornerRadius  = kR;
    self.layer.masksToBounds = YES;
    self.userInteractionEnabled = YES;

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

    UIPanGestureRecognizer* pan = [[UIPanGestureRecognizer alloc]
        initWithTarget:self action:@selector(handlePan:)];
    pan.delegate = self;
    [hdr addGestureRecognizer:pan];
    return self;
}
- (BOOL)gestureRecognizer:(UIGestureRecognizer*)g shouldReceiveTouch:(UITouch*)t {
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
    [btn addTarget:self action:@selector(btnDown:) forControlEvents:UIControlEventTouchDown];
    [btn addTarget:self action:@selector(btnUp:)
        forControlEvents:UIControlEventTouchUpInside|UIControlEventTouchUpOutside];
    [self addSubview:btn];
    return btn;
}
- (void)btnDown:(UIButton*)b {
    [UIView animateWithDuration:0.08 animations:^{ b.backgroundColor = C(0.28f,0.28f,0.36f,1.0f); }];
}
- (void)btnUp:(UIButton*)b {
    [UIView animateWithDuration:0.12 animations:^{ b.backgroundColor = C(0.17f,0.17f,0.21f,1.0f); }];
}
- (void)handlePan:(UIPanGestureRecognizer*)g {
    CGPoint loc = [g locationInView:self.superview];
    if (g.state == UIGestureRecognizerStateBegan) {
        _dragOffset = CGPointMake(loc.x - self.frame.origin.x, loc.y - self.frame.origin.y);
    } else if (g.state == UIGestureRecognizerStateChanged) {
        CGRect f = self.frame;
        f.origin = CGPointMake(loc.x - _dragOffset.x, loc.y - _dragOffset.y);
        self.frame = f;
    } else if (g.state == UIGestureRecognizerStateEnded ||
               g.state == UIGestureRecognizerStateCancelled) {
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
    self.userInteractionEnabled = NO;
    _link = [CADisplayLink displayLinkWithTarget:self selector:@selector(tick)];
    [_link addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
    return self;
}
- (void)dealloc { [_link invalidate]; }
- (void)tick { if (self.enabled) [self setNeedsDisplay]; }

- (void)drawRect:(CGRect)rect {
    if (!self.enabled || !g_il2cpp) return;
    CGContextRef ctx = UIGraphicsGetCurrentContext();
    if (!ctx) return;

    il2cpp_object_t cam = CAMERA_MAIN();
    if (!cam) return;

    NSArray<NSValue*>* hulls = ESP_PlayerHulls();
    CGFloat H = self.bounds.size.height;

    for (NSValue* v in hulls) {
        il2cpp_object_t hull = v.pointerValue;
        if (!hull) continue;

        int team = FIELD_INT(hull, fld_HULL_team);
        UIColor* col = (team == 1)
            ? [UIColor colorWithRed:0.27 green:0.52 blue:1.0 alpha:1]
            : [UIColor colorWithRed:1.0 green:0.36 blue:0.36 alpha:1];

        il2cpp_object_t box = FIELD_OBJ(hull, fld_HULL_box);
        if (!box) continue;
        il2cpp_object_t t = COMPONENT_TRANSFORM(box);
        if (!t) continue;
        Vector3 feetW = TRANSFORM_POSITION(t);
        if (feetW.x == 0 && feetW.y == 0 && feetW.z == 0) continue;
        Vector3 headW = (Vector3){feetW.x, feetW.y + 1.8f, feetW.z};

        Vector3 sf3, sh3;
        if (!CAMERA_WORLD_TO_SCREEN(cam, feetW, &sf3)) continue;
        if (!CAMERA_WORLD_TO_SCREEN(cam, headW, &sh3)) continue;
        CGPoint feet = CGPointMake(sf3.x, H - sf3.y);
        CGPoint head = CGPointMake(sh3.x, H - sh3.y);

        CGFloat h = feet.y - head.y;
        if (h < 6) continue;
        CGFloat w = h * 0.45f;
        CGContextSetStrokeColorWithColor(ctx, col.CGColor);
        CGContextSetLineWidth(ctx, 1.5f);
        CGContextStrokeRect(ctx, CGRectMake(feet.x - w*0.5f, head.y, w, h));
    }
}
@end

// ═══════════════════════════════════════════════════════════════════════════════
//  CheatController
// ═══════════════════════════════════════════════════════════════════════════════
@interface CheatController : NSObject
+ (instancetype)shared;
- (void)toggle;
- (void)layoutUI;
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
    NSNotificationCenter* nc = [NSNotificationCenter defaultCenter];
    [nc addObserver:self selector:@selector(onSceneChange:) name:UISceneDidActivateNotification object:nil];
    [nc addObserver:self selector:@selector(onSceneChange:) name:UISceneWillDeactivateNotification object:nil];
    [nc addObserver:self selector:@selector(onSceneChange:) name:UIApplicationDidBecomeActiveNotification object:nil];
    [nc addObserver:self selector:@selector(onSceneChange:) name:UIDeviceOrientationDidChangeNotification object:nil];
    [nc addObserver:self selector:@selector(onSceneChange:) name:UIWindowDidBecomeKeyNotification object:nil];
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    [nc addObserver:self selector:@selector(onSceneChange:)
              name:UIApplicationDidChangeStatusBarOrientationNotification object:nil];
#pragma clang diagnostic pop
    return self;
}
- (void)dealloc { [[NSNotificationCenter defaultCenter] removeObserver:self]; }
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
    UIWindowScene* scene = ActiveWindowScene();
    _win = scene ? [[PassthroughWindow alloc] initWithWindowScene:scene]
                 : [[PassthroughWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
    _win.windowLevel     = UIWindowLevelNormal + 1.0f;
    _win.backgroundColor = [UIColor clearColor];
    UIViewController* vc = [UIViewController new];
    _rootView = [[PassthroughView alloc] initWithFrame:[UIScreen mainScreen].bounds];
    _rootView.backgroundColor = [UIColor clearColor];
    vc.view = _rootView;
    _win.rootViewController = vc;
    _win.hidden = NO;

    _esp = [[ESPOverlayView alloc] initWithFrame:_rootView.bounds];
    [_rootView addSubview:_esp];

    _menu = [[MenuView alloc] initWithFrame:CGRectMake(0, 0, kW, kH)];
    _menu.hidden = YES;
    [_rootView addSubview:_menu];

    __weak typeof(self) ws = self;
    _pill = [[PillButton alloc] initWithFrame:CGRectMake(20, 120, 44, 28)];
    _pill.action = ^{ [ws doShow]; };
    _pill.hidden = NO;
    [_rootView addSubview:_pill];

    [_menu.hideBtn  addTarget:self action:@selector(doHide)  forControlEvents:UIControlEventTouchUpInside];
    [_menu.closeBtn addTarget:self action:@selector(doClose) forControlEvents:UIControlEventTouchUpInside];
    [_menu.espBtn   addTarget:self action:@selector(toggleESP) forControlEvents:UIControlEventTouchUpInside];

    [self layoutUI];
    [_rootView bringSubviewToFront:_esp];
    [_rootView bringSubviewToFront:_menu];
    [_rootView bringSubviewToFront:_pill];
}
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
    if (on && !g_il2cpp) {
        NSLog(@"[ESP] cannot enable: il2cpp not resolved");
    }
}
- (void)doShow {
    _pill.hidden = YES; _menu.hidden = NO;
    _menu.alpha = 0; _menu.transform = CGAffineTransformMakeScale(0.88f, 0.88f);
    [_rootView bringSubviewToFront:_menu];
    [UIView animateWithDuration:kDur delay:0 options:UIViewAnimationOptionCurveEaseOut animations:^{
        self->_menu.alpha = 1.0f; self->_menu.transform = CGAffineTransformIdentity;
    } completion:nil];
    _visible = YES;
}
- (void)doHide {
    [UIView animateWithDuration:kDur delay:0 options:UIViewAnimationOptionCurveEaseIn animations:^{
        self->_menu.alpha = 0.0f;
        self->_menu.transform = CGAffineTransformMakeScale(0.88f, 0.88f);
    } completion:^(BOOL finished) {
        self->_menu.hidden = YES;
        self->_pill.hidden = NO;
        [self->_rootView bringSubviewToFront:self->_pill];
    }];
    _visible = NO;
}
- (void)doClose {
    // Сохраняем состояние ESP, просто закрываем меню
    _esp.enabled = _menu.espEnabled;
    [self doHide];
}
- (void)toggle {
    if (_menu.hidden) {
        [self doShow];
    } else {
        [self doHide];
    }
}
@end

// ═══════════════════════════════════════════════════════════════════════════════
//  Entry point (constructor)
// ═══════════════════════════════════════════════════════════════════════════════
__attribute__((constructor))
static void CounterFlame_Init(void) {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        NSLog(@"[CF] Initializing Counter Flame cheat...");
        ESP_IL2CPP_Init();
        [CheatController shared];
        NSLog(@"[CF] Ready. g_il2cpp=%d", g_il2cpp);
    });
}
