// CounterFlame ESP
// caught-by: скриншот-детект через металлическую overlay, поведенческий анализ
// FILL: верифицировать PC_MOVEMENT / PC_IS_DEATH по дампу после обновления игры

#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>
#include <dlfcn.h>

#define PC_MOVEMENT  0x40
#define PC_IS_DEATH  0xA8

typedef void*    (*il2cpp_domain_get_t)(void);
typedef void**   (*il2cpp_domain_get_assemblies_t)(void*, size_t*);
typedef void*    (*il2cpp_assembly_get_image_t)(void*);
typedef void*    (*il2cpp_class_from_name_t)(void*, const char*, const char*);
typedef void*    (*il2cpp_class_get_method_from_name_t)(void*, const char*, int);
typedef void*    (*il2cpp_runtime_invoke_t)(void*, void*, void**, void**);
typedef void*    (*il2cpp_object_unbox_t)(void*);
typedef void*    (*il2cpp_class_get_type_t)(void*);

static il2cpp_domain_get_t                 _domain_get;
static il2cpp_domain_get_assemblies_t      _domain_get_assemblies;
static il2cpp_assembly_get_image_t         _assembly_get_image;
static il2cpp_class_from_name_t            _class_from_name;
static il2cpp_class_get_method_from_name_t _class_get_method;
static il2cpp_runtime_invoke_t             _runtime_invoke;
static il2cpp_object_unbox_t               _object_unbox;
static il2cpp_class_get_type_t             _class_get_type;

typedef struct { float x, y, z; } Vec3;

static inline void*   rptr(void *o, ptrdiff_t off) { return o ? *(void**)((uint8_t*)o+off) : NULL; }
static inline uint8_t rbyte(void *o, ptrdiff_t off){ return o ? *((uint8_t*)o+off) : 0; }

static void *gPlayerControllerClass = NULL;
static void *gFindObjectsMethod     = NULL;
static void *gTransformPosMethod    = NULL;
static void *gCameraMainMethod      = NULL;
static void *gW2SMethod             = NULL;
static BOOL  gMethodsInited         = NO;
static BOOL  gESPEnabled            = NO;

// ─── ESP overlay ──────────────────────────────────────────────────────────
@interface ESPView : UIView
@property (nonatomic, strong) NSArray<NSValue*> *boxes;
@end
@implementation ESPView
- (instancetype)initWithFrame:(CGRect)f {
    self = [super initWithFrame:f];
    self.backgroundColor = [UIColor clearColor];
    self.userInteractionEnabled = NO;
    self.layer.zPosition = 900;
    _boxes = @[];
    return self;
}
- (void)drawRect:(CGRect)__unused r {
    CGContextRef ctx = UIGraphicsGetCurrentContext();
    CGContextSetStrokeColorWithColor(ctx, [UIColor colorWithRed:0 green:1 blue:0 alpha:0.9].CGColor);
    CGContextSetLineWidth(ctx, 2.0);
    for (NSValue *v in _boxes) CGContextStrokeRect(ctx, v.CGRectValue);
}
@end

// ─── Menu view (обычный UIView, не UIWindow) ───────────────────────────────
@interface ESPMenuView : UIView
@property (nonatomic, strong) UISwitch *espSwitch;
@end
@implementation ESPMenuView {
    ESPView *_espView; // слабая ссылка через ivar чтобы не cycle
}

- (instancetype)initWithESPView:(ESPView*)espView {
    self = [super initWithFrame:CGRectMake(0, 0, 160, 90)];
    _espView = espView;
    self.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.75];
    self.layer.cornerRadius = 10;
    self.layer.zPosition = 1000;
    self.userInteractionEnabled = YES;

    UILabel *title = [[UILabel alloc] initWithFrame:CGRectMake(0, 4, 160, 22)];
    title.text = @"CF ESP";
    title.textColor = [UIColor colorWithRed:0 green:1 blue:0 alpha:1];
    title.font = [UIFont boldSystemFontOfSize:13];
    title.textAlignment = NSTextAlignmentCenter;
    [self addSubview:title];

    UILabel *lbl = [[UILabel alloc] initWithFrame:CGRectMake(10, 30, 50, 24)];
    lbl.text = @"ESP";
    lbl.textColor = [UIColor whiteColor];
    lbl.font = [UIFont systemFontOfSize:12];
    [self addSubview:lbl];

    _espSwitch = [[UISwitch alloc] init];
    _espSwitch.transform = CGAffineTransformMakeScale(0.75, 0.75);
    _espSwitch.frame = CGRectMake(62, 28, 51, 31);
    [_espSwitch addTarget:self action:@selector(toggled:) forControlEvents:UIControlEventValueChanged];
    [self addSubview:_espSwitch];

    UIButton *hide = [UIButton buttonWithType:UIButtonTypeSystem];
    hide.frame = CGRectMake(8, 62, 66, 22);
    [hide setTitle:@"Скрыть" forState:UIControlStateNormal];
    [hide setTitleColor:[UIColor lightGrayColor] forState:UIControlStateNormal];
    hide.titleLabel.font = [UIFont systemFontOfSize:11];
    [hide addTarget:self action:@selector(hideMenu) forControlEvents:UIControlEventTouchUpInside];
    [self addSubview:hide];

    UIButton *close = [UIButton buttonWithType:UIButtonTypeSystem];
    close.frame = CGRectMake(86, 62, 66, 22);
    [close setTitle:@"Закрыть" forState:UIControlStateNormal];
    [close setTitleColor:[UIColor redColor] forState:UIControlStateNormal];
    close.titleLabel.font = [UIFont systemFontOfSize:11];
    [close addTarget:self action:@selector(closeMenu) forControlEvents:UIControlEventTouchUpInside];
    [self addSubview:close];

    UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc]
        initWithTarget:self action:@selector(handlePan:)];
    [self addGestureRecognizer:pan];

    return self;
}
- (void)handlePan:(UIPanGestureRecognizer*)gr {
    CGPoint t = [gr translationInView:self.superview];
    self.center = CGPointMake(self.center.x + t.x, self.center.y + t.y);
    [gr setTranslation:CGPointZero inView:self.superview];
}
- (void)toggled:(UISwitch*)s {
    gESPEnabled = s.isOn;
    _espView.hidden = !gESPEnabled;
}
- (void)hideMenu  { self.hidden = YES; }
- (void)closeMenu {
    gESPEnabled = NO;
    _espView.hidden = YES;
    _espSwitch.on = NO;
    self.hidden = YES;
}
- (void)show { self.hidden = NO; }
@end

// ─── Ticker ───────────────────────────────────────────────────────────────
@interface ESPTicker : NSObject
- (void)tick;
@end

static ESPView     *gESPView    = nil;
static ESPMenuView *gMenuView   = nil;

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
    return CGPointMake(sp->x / scale, sh - sp->y / scale);
}

@implementation ESPTicker
- (void)tick {
    if (!gESPEnabled || !gMethodsInited || !gFindObjectsMethod || !gPlayerControllerClass) return;
    void *pcType = _class_get_type(gPlayerControllerClass);
    if (!pcType) return;
    void *exc = NULL, *args[1] = { pcType };
    void *arr = _runtime_invoke(gFindObjectsMethod, NULL, args, &exc);
    if (!arr || exc) return;
    int32_t count = *(int32_t*)((uint8_t*)arr + 0x18);
    void  **data  = (void**)((uint8_t*)arr + 0x20);
    if (!data || count <= 0) return;
    CGFloat sh = [UIScreen mainScreen].bounds.size.height;
    NSMutableArray<NSValue*> *boxes = [NSMutableArray arrayWithCapacity:count];
    for (int i = 0; i < count && i < 32; i++) {
        void *pc = data[i];
        if (!pc || rbyte(pc, PC_IS_DEATH)) continue;
        void *pm = rptr(pc, PC_MOVEMENT);
        if (!pm) continue;
        void *tr = rptr(pm, 0x10);
        if (!tr) continue;
        void *posRes = _runtime_invoke(gTransformPosMethod, tr, NULL, &exc);
        if (!posRes || exc) continue;
        Vec3 *pos = (Vec3*)_object_unbox(posRes);
        if (!pos) continue;
        Vec3 head = { pos->x, pos->y + 1.8f, pos->z };
        CGPoint feet = worldToScreen(*pos);
        CGPoint hdpt = worldToScreen(head);
        if (CGPointEqualToPoint(feet, CGPointZero)) continue;
        if (CGPointEqualToPoint(hdpt, CGPointZero)) continue;
        if (feet.y < 0 || feet.y > sh) continue;
        CGFloat h = fabs(feet.y - hdpt.y);
        if (h < 5.f) continue;
        CGFloat w = h * 0.4f;
        [boxes addObject:[NSValue valueWithCGRect:CGRectMake(feet.x - w*.5f, hdpt.y, w, h)]];
    }
    NSArray *snap = [boxes copy];
    dispatch_async(dispatch_get_main_queue(), ^{
        gESPView.boxes = snap;
        [gESPView setNeedsDisplay];
    });
}
@end

// ─── il2cpp init ──────────────────────────────────────────────────────────
static BOOL bindSymbols(void) {
    void *h = dlopen(NULL, RTLD_LAZY);
    if (!h) return NO;
#define BIND(v,n) v = (__typeof__(v))dlsym(h,n); if(!v){NSLog(@"[esp] missing %s",n);return NO;}
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

static void* findImg(void **asms, size_t cnt, const char *ns, const char *cls) {
    for (size_t i = 0; i < cnt; i++) {
        void *img = _assembly_get_image(asms[i]);
        if (img && _class_from_name(img, ns, cls)) return img;
    }
    return NULL;
}

static void initMethods(void) {
    void *domain = _domain_get();
    size_t cnt = 0;
    void **asms = _domain_get_assemblies(domain, &cnt);
    if (!asms || !cnt) return;
    void *mainImg = findImg(asms, cnt, "",            "PlayerController");
    void *ueImg   = findImg(asms, cnt, "UnityEngine", "Camera");
    if (!mainImg || !ueImg) { NSLog(@"[esp] образы не найдены"); return; }
    gPlayerControllerClass = _class_from_name(mainImg, "", "PlayerController");
    void *objCls = _class_from_name(ueImg, "UnityEngine", "Object");
    if (objCls) gFindObjectsMethod = _class_get_method(objCls, "FindObjectsOfType", 1);
    void *trCls  = _class_from_name(ueImg, "UnityEngine", "Transform");
    if (trCls)  gTransformPosMethod = _class_get_method(trCls, "get_position", 0);
    void *camCls = _class_from_name(ueImg, "UnityEngine", "Camera");
    if (camCls) {
        gCameraMainMethod = _class_get_method(camCls, "get_main", 0);
        gW2SMethod        = _class_get_method(camCls, "WorldToScreenPoint", 1);
    }
    gMethodsInited = (gFindObjectsMethod && gTransformPosMethod &&
                      gCameraMainMethod  && gW2SMethod && gPlayerControllerClass);
    NSLog(@"[esp] init: %@", gMethodsInited ? @"OK" : @"FAIL");
}

// ─── UI setup (main thread) ───────────────────────────────────────────────
static void setupUI(void) {
    UIWindow *kw = nil;
    for (UIScene *s in UIApplication.sharedApplication.connectedScenes) {
        if ([s isKindOfClass:[UIWindowScene class]] &&
            s.activationState == UISceneActivationStateForegroundActive) {
            kw = ((UIWindowScene*)s).windows.firstObject;
            break;
        }
    }
    if (!kw) { NSLog(@"[esp] нет keyWindow"); return; }

    CGRect screen = [UIScreen mainScreen].bounds;
    CGFloat sw = screen.size.width;

    // ESP overlay
    gESPView = [[ESPView alloc] initWithFrame:screen];
    gESPView.hidden = YES;
    [kw addSubview:gESPView];

    // меню как обычный view
    gMenuView = [[ESPMenuView alloc] initWithESPView:gESPView];
    gMenuView.center = CGPointMake(sw - 90, 105);
    [kw addSubview:gMenuView];

    // 3-пальцевый тап — показать меню
    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc]
        initWithTarget:gMenuView action:@selector(show)];
    tap.numberOfTouchesRequired = 3;
    [kw addGestureRecognizer:tap];

    // display link
    ESPTicker *ticker = [[ESPTicker alloc] init];
    objc_setAssociatedObject(kw, "cfesp_ticker", ticker, OBJC_ASSOCIATION_RETAIN);
    CADisplayLink *dl = [CADisplayLink displayLinkWithTarget:ticker selector:@selector(tick)];
    dl.preferredFramesPerSecond = 30;
    [dl addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
}

// ─── entry ────────────────────────────────────────────────────────────────
__attribute__((constructor))
static void cfEspInit(void) {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3.5 * NSEC_PER_SEC)),
                   dispatch_get_global_queue(0, 0), ^{
        if (!bindSymbols()) return;
        initMethods();
        dispatch_async(dispatch_get_main_queue(), ^{ setupUI(); });
    });
}
