// CounterFlame ESP
// caught-by: скриншот-детект через металлическую overlay, поведенческий анализ

#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>
#include <dlfcn.h>

// ─── оффсеты из дампа ─────────────────────────────────────────────────────
// PlayerController (от начала класса)
#define PC_NETWORK   0x88   // PlayerNetwork*
#define PC_IS_DEATH  0xA8   // bool

// PlayerNetwork
#define PN_POSITION  0xBC   // Vector3 — серверная позиция

// PlayerSkeleton
#define PS_HEAD      0xA8   // Transform* — голова
#define PS_CHEST     0xB0   // Transform* — грудь
#define PS_PELVIS    0xB8   // Transform* — таз (центр бокса)
#define PS_LSHOULDER 0xC0   // Transform* — левое плечо
#define PS_RSHOULDER 0xC8   // Transform* — правое плечо
#define PS_LTHIGH    0xD0   // Transform* — левое бедро
#define PS_RTHIGH    0xD8   // Transform* — правое бедро

// ─── il2cpp API ───────────────────────────────────────────────────────────
typedef void*  (*fn_domain_get_t)(void);
typedef void** (*fn_domain_get_assemblies_t)(void*, size_t*);
typedef void*  (*fn_assembly_get_image_t)(void*);
typedef void*  (*fn_class_from_name_t)(void*, const char*, const char*);
typedef void*  (*fn_class_get_method_t)(void*, const char*, int);
typedef void*  (*fn_runtime_invoke_t)(void*, void*, void**, void**);
typedef void*  (*fn_object_unbox_t)(void*);
typedef void*  (*fn_class_get_type_t)(void*);
typedef void*  (*fn_class_get_field_t)(void*, const char*);
typedef void   (*fn_field_get_value_t)(void*, void*, void*);
typedef void   (*fn_field_static_get_t)(void*, void*);

static fn_domain_get_t           _domain_get;
static fn_domain_get_assemblies_t _domain_assemblies;
static fn_assembly_get_image_t   _asm_get_image;
static fn_class_from_name_t      _class_from_name;
static fn_class_get_method_t     _class_get_method;
static fn_runtime_invoke_t       _runtime_invoke;
static fn_object_unbox_t         _object_unbox;
static fn_class_get_type_t       _class_get_type;

typedef struct { float x, y, z; }       Vec3;
typedef struct { float x, y, z, w; }    Vec4;

static inline void*   rptr(void *o, ptrdiff_t off)  { return o ? *(void**)((uint8_t*)o+off) : NULL; }
static inline float   rfloat(void *o, ptrdiff_t off){ return o ? *(float*)((uint8_t*)o+off) : 0.f; }
static inline uint8_t rbyte(void *o, ptrdiff_t off) { return o ? *((uint8_t*)o+off) : 0; }
static inline int32_t rint32(void *o, ptrdiff_t off){ return o ? *(int32_t*)((uint8_t*)o+off) : 0; }
static inline Vec3    rvec3(void *o, ptrdiff_t off) {
    if (!o) return (Vec3){0,0,0};
    return *(Vec3*)((uint8_t*)o+off);
}

// ─── cached ptrs ──────────────────────────────────────────────────────────
static void *gPCClass           = NULL; // PlayerController
static void *gPSClass           = NULL; // PlayerSkeleton
static void *gFindObjectsMethod = NULL; // Object.FindObjectsOfType(Type)
static void *gGetComponentMethod= NULL; // Component.GetComponent(Type)  
static void *gCameraMainMethod  = NULL; // Camera.get_main
static void *gW2SMethod         = NULL; // Camera.WorldToScreenPoint
static void *gTransformPosMethod= NULL; // Transform.get_position
static void *gPSType            = NULL; // typeof(PlayerSkeleton)
static BOOL  gReady             = NO;

// PlayerHull offsets
#define PH_TEAM  0x30   // Team (int): None=0, CT=1, TR=2

// Team enum
typedef enum { TeamNone = 0, TeamCT = 1, TeamTR = 2 } Team;

static void *gPhotonViewClass   = NULL;
static void *gIsMineMethod      = NULL; // PhotonView.get_IsMine
static void *gHullClass         = NULL; // PlayerHull
static void *gHullType          = NULL; // typeof(PlayerHull)
static int   gLocalTeam         = TeamNone; // кэш нашей команды

// ─── ESP data ─────────────────────────────────────────────────────────────
typedef struct {
    CGPoint head, chest, pelvis, lshoulder, rshoulder, lthigh, rthigh;
    CGRect  box;
    BOOL    valid;
} PlayerESPData;

// ─── overlay view ─────────────────────────────────────────────────────────
@interface ESPView : UIView
@property (nonatomic, strong) NSArray *players; // PlayerESPData* в NSData
@end

@implementation ESPView
- (instancetype)initWithFrame:(CGRect)f {
    self = [super initWithFrame:f];
    self.backgroundColor = [UIColor clearColor];
    self.userInteractionEnabled = NO;
    self.layer.zPosition = 900;
    _players = @[];
    return self;
}
- (void)drawRect:(CGRect)__unused r {
    CGContextRef ctx = UIGraphicsGetCurrentContext();
    CGContextSetLineWidth(ctx, 1.5);

    for (NSData *d in _players) {
        if (d.length != sizeof(PlayerESPData)) continue;
        PlayerESPData p;
        [d getBytes:&p length:sizeof(p)];
        if (!p.valid) continue;

        // бокс — красный
        CGContextSetStrokeColorWithColor(ctx, [UIColor colorWithRed:1 green:0.1 blue:0.1 alpha:0.9].CGColor);
        CGContextStrokeRect(ctx, p.box);

        // скелет — зелёный
        CGContextSetStrokeColorWithColor(ctx, [UIColor colorWithRed:0 green:1 blue:0 alpha:0.85].CGColor);

        // голова → грудь
        if (!CGPointEqualToPoint(p.head, CGPointZero) &&
            !CGPointEqualToPoint(p.chest, CGPointZero)) {
            CGContextMoveToPoint(ctx, p.head.x, p.head.y);
            CGContextAddLineToPoint(ctx, p.chest.x, p.chest.y);
        }
        // грудь → таз
        if (!CGPointEqualToPoint(p.chest, CGPointZero) &&
            !CGPointEqualToPoint(p.pelvis, CGPointZero)) {
            CGContextMoveToPoint(ctx, p.chest.x, p.chest.y);
            CGContextAddLineToPoint(ctx, p.pelvis.x, p.pelvis.y);
        }
        // плечи
        if (!CGPointEqualToPoint(p.lshoulder, CGPointZero) &&
            !CGPointEqualToPoint(p.rshoulder, CGPointZero)) {
            CGContextMoveToPoint(ctx, p.lshoulder.x, p.lshoulder.y);
            CGContextAddLineToPoint(ctx, p.chest.x, p.chest.y);
            CGContextAddLineToPoint(ctx, p.rshoulder.x, p.rshoulder.y);
        }
        // бёдра
        if (!CGPointEqualToPoint(p.lthigh, CGPointZero) &&
            !CGPointEqualToPoint(p.rthigh, CGPointZero)) {
            CGContextMoveToPoint(ctx, p.lthigh.x, p.lthigh.y);
            CGContextAddLineToPoint(ctx, p.pelvis.x, p.pelvis.y);
            CGContextAddLineToPoint(ctx, p.rthigh.x, p.rthigh.y);
        }
        CGContextStrokePath(ctx);

        // кружок на голове
        if (!CGPointEqualToPoint(p.head, CGPointZero)) {
            CGFloat r2 = p.box.size.width * 0.15f;
            CGContextStrokeEllipseInRect(ctx,
                CGRectMake(p.head.x - r2, p.head.y - r2, r2*2, r2*2));
        }
    }
}
@end

// ─── menu view ────────────────────────────────────────────────────────────
@interface ESPMenuView : UIView
@property (nonatomic, strong) UISwitch *espSwitch;
- (void)show;
@end

static ESPView     *gESPView  = nil;
static ESPMenuView *gMenuView = nil;
static BOOL         gESPOn    = NO;

// ─── World → Screen ───────────────────────────────────────────────────────
static CGPoint w2s(Vec3 world) {
    if (!gCameraMainMethod || !gW2SMethod) return CGPointZero;
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

// Transform.get_position через invoke
static Vec3 getTransformPos(void *tr) {
    if (!tr || !gTransformPosMethod) return (Vec3){0,0,0};
    void *exc = NULL;
    void *res = _runtime_invoke(gTransformPosMethod, tr, NULL, &exc);
    if (!res || exc) return (Vec3){0,0,0};
    Vec3 *p = (Vec3*)_object_unbox(res);
    return p ? *p : (Vec3){0,0,0};
}

// ─── ticker ───────────────────────────────────────────────────────────────
@interface ESPTicker : NSObject
- (void)tick;
@end

@implementation ESPMenuView {
    ESPView *_ev;
}
- (instancetype)initWithESPView:(ESPView*)ev {
    self = [super initWithFrame:CGRectMake(0,0,165,95)];
    _ev = ev;
    self.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.75];
    self.layer.cornerRadius = 10;
    self.layer.zPosition = 1000;
    self.userInteractionEnabled = YES;

    UILabel *t = [[UILabel alloc] initWithFrame:CGRectMake(0,4,165,22)];
    t.text = @"CF ESP"; t.textColor = [UIColor colorWithRed:0 green:1 blue:0 alpha:1];
    t.font = [UIFont boldSystemFontOfSize:13]; t.textAlignment = NSTextAlignmentCenter;
    [self addSubview:t];

    UILabel *l = [[UILabel alloc] initWithFrame:CGRectMake(10,31,50,22)];
    l.text = @"ESP"; l.textColor = [UIColor whiteColor];
    l.font = [UIFont systemFontOfSize:12]; [self addSubview:l];

    _espSwitch = [UISwitch new];
    _espSwitch.transform = CGAffineTransformMakeScale(0.75, 0.75);
    _espSwitch.frame = CGRectMake(62,29,51,31);
    [_espSwitch addTarget:self action:@selector(toggled:) forControlEvents:UIControlEventValueChanged];
    [self addSubview:_espSwitch];

    UIButton *hide = [UIButton buttonWithType:UIButtonTypeSystem];
    hide.frame = CGRectMake(8,65,66,22);
    [hide setTitle:@"Скрыть" forState:UIControlStateNormal];
    [hide setTitleColor:[UIColor lightGrayColor] forState:UIControlStateNormal];
    hide.titleLabel.font = [UIFont systemFontOfSize:11];
    [hide addTarget:self action:@selector(hideMenu) forControlEvents:UIControlEventTouchUpInside];
    [self addSubview:hide];

    UIButton *close = [UIButton buttonWithType:UIButtonTypeSystem];
    close.frame = CGRectMake(88,65,66,22);
    [close setTitle:@"Закрыть" forState:UIControlStateNormal];
    [close setTitleColor:[UIColor redColor] forState:UIControlStateNormal];
    close.titleLabel.font = [UIFont systemFontOfSize:11];
    [close addTarget:self action:@selector(closeMenu) forControlEvents:UIControlEventTouchUpInside];
    [self addSubview:close];

    UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc]
        initWithTarget:self action:@selector(pan:)];
    [self addGestureRecognizer:pan];
    return self;
}
- (void)pan:(UIPanGestureRecognizer*)gr {
    CGPoint t = [gr translationInView:self.superview];
    self.center = CGPointMake(self.center.x+t.x, self.center.y+t.y);
    [gr setTranslation:CGPointZero inView:self.superview];
}
- (void)toggled:(UISwitch*)s { gESPOn = s.isOn; _ev.hidden = !gESPOn; }
- (void)hideMenu  { self.hidden = YES; }
- (void)closeMenu { gESPOn = NO; _ev.hidden = YES; _espSwitch.on = NO; self.hidden = YES; }
- (void)show      { self.hidden = NO; }
@end

@implementation ESPTicker
- (void)tick {
    if (!gESPOn || !gReady) return;
    if (!gFindObjectsMethod || !gPCClass) return;

    void *pcType = _class_get_type(gPCClass);
    if (!pcType) return;

    void *exc = NULL, *args[1] = { pcType };
    void *arr = _runtime_invoke(gFindObjectsMethod, NULL, args, &exc);
    if (!arr || exc) return;

    int32_t count = *(int32_t*)((uint8_t*)arr + 0x18);
    void  **data  = (void**)((uint8_t*)arr + 0x20);
    if (!data || count <= 0) return;

    CGFloat sh = [UIScreen mainScreen].bounds.size.height;
    NSMutableArray *results = [NSMutableArray arrayWithCapacity:count];

    for (int i = 0; i < count && i < 32; i++) {
        void *pc = data[i];
        if (!pc) continue;

        // фильтр мёртвых
        if (rbyte(pc, PC_IS_DEATH)) continue;

        // фильтр тимейтов через PlayerHull._team (0x30)
        if (gGetComponentMethod && gHullType) {
            void *hullArgs[1] = { gHullType };
            void *hull = _runtime_invoke(gGetComponentMethod, pc, hullArgs, &exc);
            if (hull && !exc) {
                int team = *(int*)((uint8_t*)hull + PH_TEAM);

                // кэшируем нашу команду через IsMine
                if (gLocalTeam == TeamNone && gPhotonViewClass && gIsMineMethod) {
                    void *pvType = _class_get_type(gPhotonViewClass);
                    void *pvArgs[1] = { pvType };
                    void *pv = _runtime_invoke(gGetComponentMethod, pc, pvArgs, &exc);
                    if (pv && !exc) {
                        void *res = _runtime_invoke(gIsMineMethod, pv, NULL, &exc);
                        if (res && !exc) {
                            uint8_t *b = (uint8_t*)_object_unbox(res);
                            if (b && *b) gLocalTeam = team; // наш PC — запомнили команду
                        }
                    }
                }

                if (team == TeamNone) continue;              // спектатор
                if (gLocalTeam != TeamNone && team == gLocalTeam) continue; // тимейт
            }
        }

        // PlayerNetwork → серверная позиция (стабильнее чем Transform)
        void *pn = rptr(pc, PC_NETWORK);
        if (!pn) continue;
        Vec3 netPos = rvec3(pn, PN_POSITION);
        if (netPos.x == 0 && netPos.y == 0 && netPos.z == 0) continue;

        // голова и таз для бокса
        Vec3 headPos  = { netPos.x, netPos.y + 1.7f, netPos.z };
        Vec3 feetPos  = { netPos.x, netPos.y,         netPos.z };

        // PlayerSkeleton через GetComponent если доступно
        Vec3 skHead     = headPos;
        Vec3 skChest    = { netPos.x, netPos.y + 1.3f, netPos.z };
        Vec3 skPelvis   = { netPos.x, netPos.y + 0.9f, netPos.z };
        Vec3 skLShoulder= { netPos.x - 0.3f, netPos.y + 1.3f, netPos.z };
        Vec3 skRShoulder= { netPos.x + 0.3f, netPos.y + 1.3f, netPos.z };
        Vec3 skLThigh   = { netPos.x - 0.15f, netPos.y + 0.5f, netPos.z };
        Vec3 skRThigh   = { netPos.x + 0.15f, netPos.y + 0.5f, netPos.z };

        if (gGetComponentMethod && gPSClass && gPSType) {
            void *psArgs[1] = { gPSType };
            void *ps = _runtime_invoke(gGetComponentMethod, pc, psArgs, &exc);
            if (ps && !exc) {
                void *trHead = rptr(ps, PS_HEAD);
                void *trChest= rptr(ps, PS_CHEST);
                void *trPelv = rptr(ps, PS_PELVIS);
                void *trLS   = rptr(ps, PS_LSHOULDER);
                void *trRS   = rptr(ps, PS_RSHOULDER);
                void *trLT   = rptr(ps, PS_LTHIGH);
                void *trRT   = rptr(ps, PS_RTHIGH);

                if (trHead)  skHead      = getTransformPos(trHead);
                if (trChest) skChest     = getTransformPos(trChest);
                if (trPelv)  skPelvis    = getTransformPos(trPelv);
                if (trLS)    skLShoulder = getTransformPos(trLS);
                if (trRS)    skRShoulder = getTransformPos(trRS);
                if (trLT)    skLThigh    = getTransformPos(trLT);
                if (trRT)    skRThigh    = getTransformPos(trRT);

                // если скелет дал голову — используем её для бокса
                headPos = skHead;
            }
        }

        CGPoint screenHead = w2s(headPos);
        CGPoint screenFeet = w2s(feetPos);
        if (CGPointEqualToPoint(screenHead, CGPointZero)) continue;
        if (CGPointEqualToPoint(screenFeet, CGPointZero)) continue;
        if (screenFeet.y < 0 || screenFeet.y > sh) continue;

        CGFloat height = fabs(screenFeet.y - screenHead.y);
        if (height < 8.f) continue;
        CGFloat width = height * 0.45f;

        PlayerESPData esp = {0};
        esp.valid      = YES;
        esp.head       = w2s(skHead);
        esp.chest      = w2s(skChest);
        esp.pelvis     = w2s(skPelvis);
        esp.lshoulder  = w2s(skLShoulder);
        esp.rshoulder  = w2s(skRShoulder);
        esp.lthigh     = w2s(skLThigh);
        esp.rthigh     = w2s(skRThigh);
        esp.box        = CGRectMake(screenHead.x - width*.5f, screenHead.y, width, height);

        [results addObject:[NSData dataWithBytes:&esp length:sizeof(esp)]];
    }

    NSArray *snap = [results copy];
    dispatch_async(dispatch_get_main_queue(), ^{
        gESPView.players = snap;
        [gESPView setNeedsDisplay];
    });
}
@end

// ─── il2cpp bind + init ───────────────────────────────────────────────────
static BOOL bindSymbols(void) {
    void *h = dlopen(NULL, RTLD_LAZY);
    if (!h) return NO;
#define BIND(v,n) v = (__typeof__(v))dlsym(h,n); if(!v){NSLog(@"[esp] missing %s",n);return NO;}
    BIND(_domain_get,         "il2cpp_domain_get")
    BIND(_domain_assemblies,  "il2cpp_domain_get_assemblies")
    BIND(_asm_get_image,      "il2cpp_assembly_get_image")
    BIND(_class_from_name,    "il2cpp_class_from_name")
    BIND(_class_get_method,   "il2cpp_class_get_method_from_name")
    BIND(_runtime_invoke,     "il2cpp_runtime_invoke")
    BIND(_object_unbox,       "il2cpp_object_unbox")
    BIND(_class_get_type,     "il2cpp_class_get_type")
#undef BIND
    return YES;
}

static void* findImg(void **asms, size_t cnt, const char *ns, const char *cls) {
    for (size_t i = 0; i < cnt; i++) {
        void *img = _asm_get_image(asms[i]);
        if (img && _class_from_name(img, ns, cls)) return img;
    }
    return NULL;
}

static void initMethods(void) {
    void *domain = _domain_get();
    size_t cnt = 0;
    void **asms = _domain_assemblies(domain, &cnt);
    if (!asms || !cnt) { NSLog(@"[esp] нет assemblies"); return; }

    void *mainImg = findImg(asms, cnt, "",            "PlayerController");
    void *ueImg   = findImg(asms, cnt, "UnityEngine", "Camera");
    void *punImg  = findImg(asms, cnt, "Photon.Pun",  "PhotonView");

    if (!mainImg) { NSLog(@"[esp] Assembly-CSharp не найден"); return; }
    if (!ueImg)   { NSLog(@"[esp] UnityEngine не найден"); return; }

    // PlayerController
    gPCClass = _class_from_name(mainImg, "", "PlayerController");

    // PlayerSkeleton
    gPSClass = _class_from_name(mainImg, "", "PlayerSkeleton");
    if (gPSClass) gPSType = _class_get_type(gPSClass);

    // PlayerHull
    gHullClass = _class_from_name(mainImg, "", "PlayerHull");
    if (gHullClass) gHullType = _class_get_type(gHullClass);

    // PhotonView (для IsMine + кэша локальной команды)
    if (punImg) {
        gPhotonViewClass = _class_from_name(punImg, "Photon.Pun", "PhotonView");
        if (gPhotonViewClass)
            gIsMineMethod = _class_get_method(gPhotonViewClass, "get_IsMine", 0);
    }

    // UnityEngine
    void *objCls = _class_from_name(ueImg, "UnityEngine", "Object");
    if (objCls)
        gFindObjectsMethod = _class_get_method(objCls, "FindObjectsOfType", 1);

    void *compCls = _class_from_name(ueImg, "UnityEngine", "Component");
    if (compCls)
        gGetComponentMethod = _class_get_method(compCls, "GetComponent", 1);

    void *trCls = _class_from_name(ueImg, "UnityEngine", "Transform");
    if (trCls)
        gTransformPosMethod = _class_get_method(trCls, "get_position", 0);

    void *camCls = _class_from_name(ueImg, "UnityEngine", "Camera");
    if (camCls) {
        gCameraMainMethod = _class_get_method(camCls, "get_main", 0);
        gW2SMethod        = _class_get_method(camCls, "WorldToScreenPoint", 1);
    }

    gReady = (gFindObjectsMethod && gCameraMainMethod && gW2SMethod && gPCClass);
    NSLog(@"[esp] ready=%@ ps=%@ hull=%@ pv=%@",
          gReady ? @"YES" : @"NO",
          gPSClass ? @"YES" : @"NO",
          gHullClass ? @"YES" : @"NO",
          gPhotonViewClass ? @"YES" : @"NO");
}

// ─── UI setup ─────────────────────────────────────────────────────────────
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

    gESPView = [[ESPView alloc] initWithFrame:screen];
    gESPView.hidden = YES;
    [kw addSubview:gESPView];

    gMenuView = [[ESPMenuView alloc] initWithESPView:gESPView];
    gMenuView.center = CGPointMake(sw - 92, 110);
    [kw addSubview:gMenuView];

    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc]
        initWithTarget:gMenuView action:@selector(show)];
    tap.numberOfTouchesRequired = 3;
    [kw addGestureRecognizer:tap];

    ESPTicker *ticker = [[ESPTicker alloc] init];
    objc_setAssociatedObject(kw, "cfesp_t", ticker, OBJC_ASSOCIATION_RETAIN);
    CADisplayLink *dl = [CADisplayLink displayLinkWithTarget:ticker selector:@selector(tick)];
    dl.preferredFramesPerSecond = 30;
    [dl addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
}

// ─── entry ────────────────────────────────────────────────────────────────
__attribute__((constructor))
static void cfEspInit(void) {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(4 * NSEC_PER_SEC)),
                   dispatch_get_global_queue(0,0), ^{
        if (!bindSymbols()) return;
        initMethods();
        dispatch_async(dispatch_get_main_queue(), ^{ setupUI(); });
    });
}
