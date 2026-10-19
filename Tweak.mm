// CounterFlame ESP — Counter Flame (com.ScarletWork.CounterFlame)
// base: 0x112a70000
// defeats: нет хуков на rendering pipeline, чистая overlay-view поверх окна
// caught-by: скриншот-детект через металлическую overlay (если есть), поведенческий анализ
//
// FILL: BASE пересчитать через ASLR slide при каждом запуске если нужен прямой доступ к памяти
//       но здесь используем il2cpp API — BASE не нужен напрямую

#import <UIKit/UIKit.h>
#import <CoreGraphics/CoreGraphics.h>
#import <objc/runtime.h>
#include <dlfcn.h>

// ─── PlayerController offsets ─────────────────────────────────────────────
// FILL: верифицировать по дампу после каждого обновления игры
#define PC_MOVEMENT     0x40   // PlayerController._movementController (PlayerMovement*)
#define PC_IS_DEATH     0xA8   // PlayerController._isDeath (bool)

// ─── il2cpp API ───────────────────────────────────────────────────────────
typedef void*    (*il2cpp_domain_get_t)(void);
typedef void**   (*il2cpp_domain_get_assemblies_t)(void*, size_t*);
typedef void*    (*il2cpp_assembly_get_image_t)(void*);
typedef void*    (*il2cpp_class_from_name_t)(void*, const char*, const char*);
typedef void*    (*il2cpp_class_get_field_from_name_t)(void*, const char*);
typedef void     (*il2cpp_field_static_get_value_t)(void*, void*);
typedef void*    (*il2cpp_class_get_method_from_name_t)(void*, const char*, int);
typedef void*    (*il2cpp_runtime_invoke_t)(void*, void*, void**, void**);
typedef void*    (*il2cpp_object_unbox_t)(void*);
typedef void*    (*il2cpp_class_get_type_t)(void*);

static il2cpp_domain_get_t                  _domain_get;
static il2cpp_domain_get_assemblies_t       _domain_get_assemblies;
static il2cpp_assembly_get_image_t          _assembly_get_image;
static il2cpp_class_from_name_t             _class_from_name;
static il2cpp_class_get_method_from_name_t  _class_get_method;
static il2cpp_runtime_invoke_t              _runtime_invoke;
static il2cpp_object_unbox_t                _object_unbox;
static il2cpp_class_get_type_t              _class_get_type;

// ─── Unity Vector3 ────────────────────────────────────────────────────────
typedef struct { float x, y, z; } Vec3;

// ─── helpers ──────────────────────────────────────────────────────────────
static inline void* rptr(void *obj, ptrdiff_t off) {
    if (!obj) return NULL;
    return *(void**)((uint8_t*)obj + off);
}
static inline uint8_t rbyte(void *obj, ptrdiff_t off) {
    if (!obj) return 0;
    return *((uint8_t*)obj + off);
}
static inline int32_t arr_len(void *arr) {
    // Il2CppArray: length @ 0x18
    if (!arr) return 0;
    return *(int32_t*)((uint8_t*)arr + 0x18);
}
static inline void** arr_data(void *arr) {
    // Il2CppArray: data @ 0x20
    if (!arr) return NULL;
    return (void**)((uint8_t*)arr + 0x20);
}

// ─── cached method ptrs ───────────────────────────────────────────────────
static void *gPlayerControllerClass = NULL;
static void *gFindObjectsMethod     = NULL;   // UnityEngine.Object.FindObjectsOfType(Type)
static void *gTransformPosMethod    = NULL;   // Transform.get_position
static void *gCameraMainMethod      = NULL;   // Camera.get_main
static void *gW2SMethod             = NULL;   // Camera.WorldToScreenPoint
static BOOL  gMethodsInited         = NO;

// ─── ESP overlay ──────────────────────────────────────────────────────────
@interface ESPView : UIView
@property (nonatomic, strong) NSArray<NSValue*> *boxes;
@end

@implementation ESPView
- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    self.backgroundColor = [UIColor clearColor];
    self.userInteractionEnabled = NO;
    self.layer.zPosition = 1000;
    _boxes = @[];
    return self;
}
- (void)drawRect:(CGRect)__unused rect {
    CGContextRef ctx = UIGraphicsGetCurrentContext();
    [[UIColor colorWithRed:0 green:1 blue:0 alpha:0.9] setStroke];
    CGContextSetLineWidth(ctx, 2.0);
    for (NSValue *v in _boxes) {
        CGContextStrokeRect(ctx, v.CGRectValue);
    }
}
@end

// ─── ticker (CADisplayLink target) ────────────────────────────────────────
@interface ESPTicker : NSObject
@end

// ─── menu window ──────────────────────────────────────────────────────────
@interface ESPMenuWindow : UIWindow
@property (nonatomic, strong) UISwitch *espSwitch;
- (void)showMenu;
@end

static ESPView       *gESPView      = nil;
static ESPMenuWindow *gMenuWindow   = nil;
static BOOL           gESPEnabled   = NO;

// ─── WorldToScreen ────────────────────────────────────────────────────────
static CGPoint worldToScreen(Vec3 world) {
    void *exc = NULL;
    void *cam = _runtime_invoke(gCameraMainMethod, NULL, NULL, &exc);
    if (!cam || exc) return CGPointZero;

    void *args[1] = { &world };
    void *res = _runtime_invoke(gW2SMethod, cam, args, &exc);
    if (!res || exc) return CGPointZero;

    Vec3 *sp = (Vec3*)_object_unbox(res);
    if (!sp || sp->z < 0.f) return CGPointZero;

    CGFloat scale = [UIScreen mainScreen].scale;
    CGFloat sh    = [UIScreen mainScreen].bounds.size.height;
    // Unity: (0,0)=bottom-left; UIKit: (0,0)=top-left
    return CGPointMake(sp->x / scale, sh - sp->y / scale);
}

// ─── esp tick ─────────────────────────────────────────────────────────────
static void espTick(void) {
    if (!gESPEnabled || !gMethodsInited) return;
    if (!gFindObjectsMethod || !gPlayerControllerClass) return;

    void *pcType = _class_get_type(gPlayerControllerClass);
    if (!pcType) return;

    void *exc  = NULL;
    void *args[1] = { pcType };
    void *arr  = _runtime_invoke(gFindObjectsMethod, NULL, args, &exc);
    if (!arr || exc) return;

    int32_t count = arr_len(arr);
    void  **data  = arr_data(arr);
    if (!data || count <= 0) return;

    CGFloat sh = [UIScreen mainScreen].bounds.size.height;
    NSMutableArray<NSValue*> *boxes = [NSMutableArray arrayWithCapacity:count];

    for (int i = 0; i < count && i < 32; i++) {
        void *pc = data[i];
        if (!pc) continue;
        if (rbyte(pc, PC_IS_DEATH)) continue;

        // PlayerMovement (Component → m_Transform @ 0x10)
        void *pm = rptr(pc, PC_MOVEMENT);
        if (!pm) continue;

        void *tr = rptr(pm, 0x10);
        if (!tr) continue;

        void *posRes = _runtime_invoke(gTransformPosMethod, tr, NULL, &exc);
        if (!posRes || exc) continue;

        Vec3 *pos = (Vec3*)_object_unbox(posRes);
        if (!pos) continue;

        Vec3 head = { pos->x, pos->y + 1.8f, pos->z };

        CGPoint screenFeet = worldToScreen(*pos);
        CGPoint screenHead = worldToScreen(head);
        if (CGPointEqualToPoint(screenFeet, CGPointZero)) continue;
        if (CGPointEqualToPoint(screenHead, CGPointZero)) continue;
        if (screenFeet.y < 0 || screenFeet.y > sh)       continue;

        CGFloat height = fabs(screenFeet.y - screenHead.y);
        if (height < 5.f) continue;

        CGFloat width = height * 0.4f;
        CGRect box = CGRectMake(screenFeet.x - width * 0.5f,
                                screenHead.y, width, height);
        [boxes addObject:[NSValue valueWithCGRect:box]];
    }

    NSArray *snap = [boxes copy];
    dispatch_async(dispatch_get_main_queue(), ^{
        gESPView.boxes = snap;
        [gESPView setNeedsDisplay];
    });
}

@implementation ESPTicker
- (void)tick { espTick(); }
@end

// ─── ESPMenuWindow impl ───────────────────────────────────────────────────
@implementation ESPMenuWindow

- (instancetype)initWithWindowScene:(UIWindowScene*)scene {
    CGFloat sw = scene.screen.bounds.size.width;
    self = [super initWithWindowScene:scene];
    if (!self) return nil;

    self.frame = CGRectMake(sw - 170, 60, 160, 90);
    self.windowLevel = UIWindowLevelAlert + 100;
    self.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.75];
    self.layer.cornerRadius = 10;
    self.clipsToBounds = YES;
    self.rootViewController = [UIViewController new];

    // drag
    UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc]
        initWithTarget:self action:@selector(handlePan:)];
    [self addGestureRecognizer:pan];

    // title
    UILabel *title = [[UILabel alloc] initWithFrame:CGRectMake(0, 4, 160, 22)];
    title.text = @"CF ESP";
    title.textColor = [UIColor colorWithRed:0 green:1 blue:0 alpha:1];
    title.font = [UIFont boldSystemFontOfSize:13];
    title.textAlignment = NSTextAlignmentCenter;
    [self addSubview:title];

    // ESP label
    UILabel *espLabel = [[UILabel alloc] initWithFrame:CGRectMake(10, 30, 50, 22)];
    espLabel.text = @"ESP";
    espLabel.textColor = [UIColor whiteColor];
    espLabel.font = [UIFont systemFontOfSize:12];
    [self addSubview:espLabel];

    // switch
    _espSwitch = [[UISwitch alloc] init];
    _espSwitch.transform = CGAffineTransformMakeScale(0.75, 0.75);
    CGSize sz = _espSwitch.intrinsicContentSize;
    _espSwitch.frame = CGRectMake(65, 28, sz.width, sz.height);
    [_espSwitch addTarget:self action:@selector(espToggled:)
        forControlEvents:UIControlEventValueChanged];
    [self addSubview:_espSwitch];

    // hide button
    UIButton *hide = [UIButton buttonWithType:UIButtonTypeSystem];
    hide.frame = CGRectMake(8, 62, 66, 20);
    [hide setTitle:@"Скрыть" forState:UIControlStateNormal];
    [hide setTitleColor:[UIColor lightGrayColor] forState:UIControlStateNormal];
    hide.titleLabel.font = [UIFont systemFontOfSize:11];
    [hide addTarget:self action:@selector(hideMenu)
        forControlEvents:UIControlEventTouchUpInside];
    [self addSubview:hide];

    // close button
    UIButton *close = [UIButton buttonWithType:UIButtonTypeSystem];
    close.frame = CGRectMake(86, 62, 66, 20);
    [close setTitle:@"Закрыть" forState:UIControlStateNormal];
    [close setTitleColor:[UIColor redColor] forState:UIControlStateNormal];
    close.titleLabel.font = [UIFont systemFontOfSize:11];
    [close addTarget:self action:@selector(closeMenu)
        forControlEvents:UIControlEventTouchUpInside];
    [self addSubview:close];

    return self;
}

- (void)handlePan:(UIPanGestureRecognizer*)gr {
    CGPoint t = [gr translationInView:self.superview];
    self.center = CGPointMake(self.center.x + t.x, self.center.y + t.y);
    [gr setTranslation:CGPointZero inView:self.superview];
}
- (void)espToggled:(UISwitch*)s {
    gESPEnabled = s.isOn;
    gESPView.hidden = !gESPEnabled;
}
- (void)hideMenu  { self.hidden = YES; }
- (void)closeMenu {
    gESPEnabled = NO;
    gESPView.hidden = YES;
    _espSwitch.on = NO;
    self.hidden = YES;
}
- (void)showMenu  { self.hidden = NO; }

@end

// ─── il2cpp init ──────────────────────────────────────────────────────────
static void* findAssemblyImage(void **asms, size_t cnt,
                                const char *ns, const char *cls) {
    for (size_t i = 0; i < cnt; i++) {
        void *img = _assembly_get_image(asms[i]);
        if (img && _class_from_name(img, ns, cls)) return img;
    }
    return NULL;
}

static BOOL bindIl2cppSymbols(void) {
    // GameAssembly.dylib грузится как главный executable на jailbreak через substrate
    // dlopen(NULL) покрывает его через dyld; если нет — пробуем путь явно
    void *handle = dlopen(NULL, RTLD_LAZY);
    if (!handle) return NO;

#define BIND(var, name) \
    var = (__typeof__(var))dlsym(handle, name); \
    if (!var) { NSLog(@"[esp] missing: " name); return NO; }

    BIND(_domain_get,            "il2cpp_domain_get")
    BIND(_domain_get_assemblies, "il2cpp_domain_get_assemblies")
    BIND(_assembly_get_image,    "il2cpp_assembly_get_image")
    BIND(_class_from_name,       "il2cpp_class_from_name")
    BIND(_class_get_method,      "il2cpp_class_get_method_from_name")
    BIND(_runtime_invoke,        "il2cpp_runtime_invoke")
    BIND(_object_unbox,          "il2cpp_object_unbox")
    BIND(_class_get_type,        "il2cpp_class_get_type")
#undef BIND
    return YES;
}

static void initMethods(void) {
    void *domain = _domain_get();
    if (!domain) { NSLog(@"[esp] domain null"); return; }

    size_t cnt  = 0;
    void **asms = _domain_get_assemblies(domain, &cnt);
    if (!asms || cnt == 0) { NSLog(@"[esp] no assemblies"); return; }

    void *mainImg = findAssemblyImage(asms, cnt, "",              "PlayerController");
    void *ueImg   = findAssemblyImage(asms, cnt, "UnityEngine",   "Camera");

    if (!mainImg) { NSLog(@"[esp] Assembly-CSharp не найден"); return; }
    if (!ueImg)   { NSLog(@"[esp] UnityEngine не найден");     return; }

    // PlayerController
    gPlayerControllerClass = _class_from_name(mainImg, "", "PlayerController");

    // UnityEngine.Object.FindObjectsOfType(Type)
    void *objClass = _class_from_name(ueImg, "UnityEngine", "Object");
    if (objClass)
        gFindObjectsMethod = _class_get_method(objClass, "FindObjectsOfType", 1);

    // Transform.get_position
    void *trClass = _class_from_name(ueImg, "UnityEngine", "Transform");
    if (trClass)
        gTransformPosMethod = _class_get_method(trClass, "get_position", 0);

    // Camera.get_main + Camera.WorldToScreenPoint
    void *camClass = _class_from_name(ueImg, "UnityEngine", "Camera");
    if (camClass) {
        gCameraMainMethod = _class_get_method(camClass, "get_main", 0);
        gW2SMethod        = _class_get_method(camClass, "WorldToScreenPoint", 1);
    }

    if (!gFindObjectsMethod) NSLog(@"[esp] FindObjectsOfType не найден");
    if (!gTransformPosMethod) NSLog(@"[esp] get_position не найден");
    if (!gCameraMainMethod || !gW2SMethod) NSLog(@"[esp] Camera методы не найдены");

    gMethodsInited = (gFindObjectsMethod && gTransformPosMethod &&
                      gCameraMainMethod  && gW2SMethod &&
                      gPlayerControllerClass);
    NSLog(@"[esp] методы: %@", gMethodsInited ? @"OK" : @"FAIL");
}

// ─── setup (main thread) ──────────────────────────────────────────────────
static void setupUI(UIWindowScene *scene) {
    CGRect screen = scene.screen.bounds;

    // overlay поверх keyWindow
    UIWindow *keyWindow = scene.windows.firstObject;
    gESPView = [[ESPView alloc] initWithFrame:screen];
    gESPView.hidden = YES;
    [keyWindow addSubview:gESPView];

    // меню-окно
    gMenuWindow = [[ESPMenuWindow alloc] initWithWindowScene:scene];
    gMenuWindow.hidden = NO;
    [gMenuWindow makeKeyAndVisible];
    // вернуть фокус основному окну чтобы игра не теряла ввод
    [keyWindow makeKeyWindow];

    // 3-пальцевый тап показывает меню
    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc]
        initWithTarget:gMenuWindow action:@selector(showMenu)];
    tap.numberOfTouchesRequired = 3;
    [keyWindow addGestureRecognizer:tap];

    // display link
    ESPTicker *ticker = [[ESPTicker alloc] init];
    // retain через associated object чтобы не умер
    objc_setAssociatedObject(gMenuWindow, "ticker", ticker, OBJC_ASSOCIATION_RETAIN);
    CADisplayLink *dl = [CADisplayLink displayLinkWithTarget:ticker
                                                    selector:@selector(tick)];
    dl.preferredFramesPerSecond = 30; // не грузим CPU зря
    [dl addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
}

static void setupESP(void) {
    if (!bindIl2cppSymbols()) {
        NSLog(@"[esp] bind failed");
        return;
    }
    initMethods();

    dispatch_async(dispatch_get_main_queue(), ^{
        UIWindowScene *scene = nil;
        for (UIScene *s in UIApplication.sharedApplication.connectedScenes) {
            if ([s isKindOfClass:[UIWindowScene class]] &&
                s.activationState == UISceneActivationStateForegroundActive) {
                scene = (UIWindowScene*)s;
                break;
            }
        }
        if (!scene) {
            NSLog(@"[esp] нет активной UIWindowScene");
            return;
        }
        setupUI(scene);
    });
}

// ─── entry point ─────────────────────────────────────────────────────────
__attribute__((constructor))
static void cfEspInit(void) {
    // ждём il2cpp runtime: 3.5с обычно хватает, при слабом девайсе поднять до 5
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3.5 * NSEC_PER_SEC)),
                   dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        setupESP();
    });
}
