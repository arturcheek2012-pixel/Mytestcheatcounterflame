// inject: DYLD_INSERT_LIBRARIES / Live Container
// dump: забрать через Live Container → Local App Data → <UUID игры> → Documents/il2cpp_dump.txt

#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <dlfcn.h>
#import <mach-o/dyld.h>

// ─── config ───────────────────────────────────────────────────────────────────
static const CGFloat kW   = 260.0f;
static const CGFloat kH   = 360.0f;
static const CGFloat kHdr = 42.0f;
static const CGFloat kR   = 12.0f;
static const NSTimeInterval kDur = 0.22;

static inline UIColor* C(CGFloat r, CGFloat g, CGFloat b, CGFloat a) {
    return [UIColor colorWithRed:r green:g blue:b alpha:a];
}

// ─── IL2CPP function pointers ─────────────────────────────────────────────────
static void*    (*fp_domain_get)(void);
static void**   (*fp_domain_assemblies)(void*, size_t*);
static void*    (*fp_assembly_image)(void*);
static char*    (*fp_image_name)(void*);
static size_t   (*fp_image_class_count)(void*);
static void*    (*fp_image_class)(void*, size_t);
static char*    (*fp_class_name)(void*);
static char*    (*fp_class_ns)(void*);
static void*    (*fp_class_parent)(void*);
static void*    (*fp_class_methods)(void*, void**);
static char*    (*fp_method_name)(void*);
static uint32_t (*fp_method_params)(void*);
static void*    (*fp_class_fields)(void*, void**);
static char*    (*fp_field_name)(void*);
static size_t   (*fp_field_offset)(void*);

static BOOL LoadAPI(void) {
#define R(p,s) p = (__typeof__(p))dlsym(RTLD_DEFAULT, s)
    R(fp_domain_get,        "il2cpp_domain_get");
    R(fp_domain_assemblies, "il2cpp_domain_get_assemblies");
    R(fp_assembly_image,    "il2cpp_assembly_get_image");
    R(fp_image_name,        "il2cpp_image_get_name");
    R(fp_image_class_count, "il2cpp_image_get_class_count");
    R(fp_image_class,       "il2cpp_image_get_class");
    R(fp_class_name,        "il2cpp_class_get_name");
    R(fp_class_ns,          "il2cpp_class_get_namespace");
    R(fp_class_parent,      "il2cpp_class_get_parent");
    R(fp_class_methods,     "il2cpp_class_get_methods");
    R(fp_method_name,       "il2cpp_method_get_name");
    R(fp_method_params,     "il2cpp_method_get_param_count");
    R(fp_class_fields,      "il2cpp_class_get_fields");
    R(fp_field_name,        "il2cpp_field_get_name");
    R(fp_field_offset,      "il2cpp_field_get_offset");
#undef R
    return fp_domain_get != NULL;
}

static uintptr_t GetUnityBase(void) {
    for (uint32_t i = 0, n = _dyld_image_count(); i < n; i++) {
        const char* nm = _dyld_get_image_name(i);
        if (nm && strstr(nm, "UnityFramework"))
            return (uintptr_t)_dyld_get_image_header(i);
    }
    return 0;
}

static NSString* PerformDump(void) {
    if (!LoadAPI()) return @"ошибка: API не найден";

    void* domain = fp_domain_get();
    if (!domain) return @"ошибка: domain NULL";

    uintptr_t base    = GetUnityBase();
    size_t    asmCnt  = 0;
    void**    asms    = fp_domain_assemblies(domain, &asmCnt);
    if (!asms) return @"ошибка: assemblies NULL";

    NSMutableString* out = [NSMutableString string];
    [out appendFormat:@"// Counter Flame IL2CPP Dump\n// UnityFramework base: 0x%lx\n\n",
        (unsigned long)base];

    NSUInteger total = 0;

    for (size_t ai = 0; ai < asmCnt; ai++) {
        void* img = fp_assembly_image(asms[ai]);
        if (!img) continue;

        const char* imgNm = fp_image_name(img);
        size_t      cc    = fp_image_class_count(img);
        [out appendFormat:@"\n// === %s (%zu) ===\n", imgNm ?: "?", cc];

        for (size_t ci = 0; ci < cc; ci++) {
            void* klass = fp_image_class(img, ci);
            if (!klass) continue;

            const char* ns  = fp_class_ns(klass);
            const char* nm  = fp_class_name(klass);
            void*       par = fp_class_parent(klass);
            const char* pn  = par ? fp_class_name(par) : NULL;

            NSString* full = (ns && *ns)
                ? [NSString stringWithFormat:@"%s.%s", ns, nm ?: "?"]
                : [NSString stringWithUTF8String:nm ?: "?"];

            pn ? [out appendFormat:@"\npublic class %@ : %s {\n", full, pn]
               : [out appendFormat:@"\npublic class %@ {\n", full];

            // fields
            void* fi = NULL, *fld;
            while ((fld = fp_class_fields(klass, &fi))) {
                const char* fn  = fp_field_name(fld);
                size_t      off = fp_field_offset(fld);
                [out appendFormat:@"\t// 0x%zX  %s\n", off, fn ?: "?"];
            }

            // methods — methodPointer is first field of MethodInfo (offset 0, arm64)
            void* mi = NULL, *mth;
            while ((mth = fp_class_methods(klass, &mi))) {
                const char* mn  = fp_method_name(mth);
                uint32_t    np  = fp_method_params(mth);
                uintptr_t   ptr = *(uintptr_t*)mth;
                if (ptr > base)
                    [out appendFormat:@"\t// RVA: 0x%llX  p:%u  %s\n",
                        (unsigned long long)(ptr - base), np, mn ?: "?"];
                else
                    [out appendFormat:@"\t// RVA: N/A  p:%u  %s\n", np, mn ?: "?"];
            }

            [out appendString:@"}\n"];
            total++;
        }
    }

    [out appendFormat:@"\n// Total: %lu classes\n", (unsigned long)total];

    NSString* docs = NSSearchPathForDirectoriesInDomains(
        NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
    NSString* path = [docs stringByAppendingPathComponent:@"il2cpp_dump.txt"];

    NSError* err = nil;
    [out writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:&err];

    return err
        ? [NSString stringWithFormat:@"ошибка: %@", err.localizedDescription]
        : [NSString stringWithFormat:@"✓ %lu классов\nil2cpp_dump.txt", (unsigned long)total];
}

// ─── PassthroughWindow ────────────────────────────────────────────────────────
@interface PassthroughWindow : UIWindow @end
@implementation PassthroughWindow
- (UIView*)hitTest:(CGPoint)p withEvent:(UIEvent*)e {
    UIView* v = [super hitTest:p withEvent:e];
    return (v == self.rootViewController.view) ? nil : v;
}
@end

// ─── PassthroughView ──────────────────────────────────────────────────────────
@interface PassthroughView : UIView @end
@implementation PassthroughView
- (UIView*)hitTest:(CGPoint)p withEvent:(UIEvent*)e {
    UIView* v = [super hitTest:p withEvent:e];
    return (v == self) ? nil : v;
}
@end

// ─── PillButton ───────────────────────────────────────────────────────────────
@interface PillButton : UIView
@property (copy) dispatch_block_t action;
@end

@implementation PillButton { CGPoint _off; BOOL _moved; }

- (instancetype)init {
    self = [super initWithFrame:CGRectMake(20, 120, 44, 28)];
    self.backgroundColor    = C(0.10f, 0.10f, 0.13f, 0.92f);
    self.layer.cornerRadius = 14;
    self.layer.borderColor  = C(0.27f, 0.52f, 1.00f, 0.45f).CGColor;
    self.layer.borderWidth  = 1.0f;

    UILabel* l      = [[UILabel alloc] initWithFrame:self.bounds];
    l.text          = @"☰";
    l.textAlignment = NSTextAlignmentCenter;
    l.font          = [UIFont systemFontOfSize:13];
    l.textColor     = C(0.75f, 0.75f, 0.80f, 1.0f);
    [self addSubview:l];

    [self addGestureRecognizer:[[UIPanGestureRecognizer alloc]
        initWithTarget:self action:@selector(pan:)]];
    return self;
}

- (void)pan:(UIPanGestureRecognizer*)g {
    CGPoint loc = [g locationInView:self.superview];
    if (g.state == UIGestureRecognizerStateBegan) {
        _moved = NO;
        _off   = CGPointMake(loc.x - self.frame.origin.x, loc.y - self.frame.origin.y);
    } else if (g.state == UIGestureRecognizerStateChanged) {
        _moved = YES;
        CGRect f = self.frame;
        f.origin = CGPointMake(loc.x - _off.x, loc.y - _off.y);
        self.frame = f;
    }
}
- (void)touchesEnded:(NSSet*)t withEvent:(UIEvent*)e {
    if (!_moved && _action) _action();
}
@end

// ─── MenuView ─────────────────────────────────────────────────────────────────
@interface MenuView : UIView
@property (strong) UIButton* hideBtn;
@property (strong) UIButton* closeBtn;
@property (strong) UIButton* dumpBtn;
@property (strong) UILabel*  statusLabel;
@end

@implementation MenuView { CGPoint _drag; }

- (instancetype)initWithFrame:(CGRect)f {
    self = [super initWithFrame:f];
    self.backgroundColor     = C(0.07f, 0.07f, 0.09f, 0.93f);
    self.layer.cornerRadius  = kR;
    self.layer.masksToBounds = YES;

    // header
    UIView* hdr          = [[UIView alloc] initWithFrame:CGRectMake(0, 0, kW, kHdr)];
    hdr.backgroundColor  = C(0.10f, 0.10f, 0.13f, 1.0f);
    [self addSubview:hdr];

    UIView* accent       = [[UIView alloc] initWithFrame:CGRectMake(0, kHdr-1, kW, 1)];
    accent.backgroundColor = C(0.27f, 0.52f, 1.00f, 0.55f);
    [self addSubview:accent];

    UILabel* title       = [[UILabel alloc] initWithFrame:CGRectMake(0, (kHdr-17)*.5f, kW, 17)];
    title.text           = @"Cheat Menu";
    title.font           = [UIFont systemFontOfSize:13 weight:UIFontWeightSemibold];
    title.textColor      = C(0.92f, 0.92f, 0.95f, 1.0f);
    title.textAlignment  = NSTextAlignmentCenter;
    [self addSubview:title];

    // section card
    UIView* card         = [[UIView alloc] initWithFrame:CGRectMake(12, kHdr+14, kW-24, 100)];
    card.backgroundColor = C(0.10f, 0.10f, 0.13f, 1.0f);
    card.layer.cornerRadius = 8;
    [self addSubview:card];

    UILabel* sLabel      = [[UILabel alloc] initWithFrame:CGRectMake(10, 10, kW-44, 12)];
    sLabel.text          = @"TOOLS";
    sLabel.font          = [UIFont systemFontOfSize:9 weight:UIFontWeightSemibold];
    sLabel.textColor     = C(0.27f, 0.52f, 1.00f, 1.0f);
    [card addSubview:sLabel];

    self.dumpBtn         = [UIButton buttonWithType:UIButtonTypeCustom];
    self.dumpBtn.frame   = CGRectMake(10, 30, (kW-24)-20, 34);
    self.dumpBtn.backgroundColor     = C(0.14f, 0.14f, 0.18f, 1.0f);
    self.dumpBtn.layer.cornerRadius  = 6;
    self.dumpBtn.layer.borderColor   = C(0.27f, 0.52f, 1.00f, 0.30f).CGColor;
    self.dumpBtn.layer.borderWidth   = 1.0f;
    self.dumpBtn.titleLabel.font     = [UIFont systemFontOfSize:11 weight:UIFontWeightMedium];
    [self.dumpBtn setTitle:@"Dump IL2CPP" forState:UIControlStateNormal];
    [self.dumpBtn setTitleColor:C(0.80f, 0.80f, 0.90f, 1.0f) forState:UIControlStateNormal];
    [self.dumpBtn setTitleColor:C(0.27f, 0.52f, 1.00f, 1.0f) forState:UIControlStateHighlighted];
    [self.dumpBtn setTitleColor:C(0.40f, 0.40f, 0.45f, 1.0f) forState:UIControlStateDisabled];
    [self.dumpBtn addTarget:self action:@selector(btnDown:) forControlEvents:UIControlEventTouchDown];
    [self.dumpBtn addTarget:self action:@selector(btnUp:)
        forControlEvents:UIControlEventTouchUpInside|UIControlEventTouchUpOutside];
    [card addSubview:self.dumpBtn];

    self.statusLabel     = [[UILabel alloc] initWithFrame:CGRectMake(10, 70, (kW-24)-20, 24)];
    self.statusLabel.font          = [UIFont monospacedSystemFontOfSize:9 weight:UIFontWeightRegular];
    self.statusLabel.textColor     = C(0.35f, 0.70f, 0.40f, 1.0f);
    self.statusLabel.numberOfLines = 2;
    [card addSubview:self.statusLabel];

    // header buttons
    self.hideBtn  = [self makeHdrBtn:@"−" x:kW-58];
    self.closeBtn = [self makeHdrBtn:@"×" x:kW-30];

    // border
    CALayer* border      = [CALayer layer];
    border.frame         = CGRectMake(0, 0, kW, kH);
    border.borderColor   = C(0.22f, 0.22f, 0.28f, 0.65f).CGColor;
    border.borderWidth   = 1.0f;
    border.cornerRadius  = kR;
    [self.layer addSublayer:border];

    // drag
    [hdr addGestureRecognizer:[[UIPanGestureRecognizer alloc]
        initWithTarget:self action:@selector(pan:)]];
    return self;
}

- (UIButton*)makeHdrBtn:(NSString*)g x:(CGFloat)x {
    UIButton* b             = [UIButton buttonWithType:UIButtonTypeCustom];
    b.frame                 = CGRectMake(x, (kHdr-24)*.5f, 24, 24);
    b.layer.cornerRadius    = 12;
    b.layer.masksToBounds   = YES;
    b.backgroundColor       = C(0.17f, 0.17f, 0.21f, 1.0f);
    b.titleLabel.font       = [UIFont systemFontOfSize:11 weight:UIFontWeightMedium];
    [b setTitle:g forState:UIControlStateNormal];
    [b setTitleColor:C(0.55f, 0.55f, 0.60f, 1) forState:UIControlStateNormal];
    [b setTitleColor:[UIColor whiteColor]        forState:UIControlStateHighlighted];
    [b addTarget:self action:@selector(btnDown:) forControlEvents:UIControlEventTouchDown];
    [b addTarget:self action:@selector(btnUp:)
        forControlEvents:UIControlEventTouchUpInside|UIControlEventTouchUpOutside];
    [self addSubview:b];
    return b;
}

- (void)btnDown:(UIButton*)b {
    [UIView animateWithDuration:0.08 animations:^{ b.backgroundColor = C(0.28f,0.28f,0.36f,1); }];
}
- (void)btnUp:(UIButton*)b {
    [UIView animateWithDuration:0.12 animations:^{ b.backgroundColor = C(0.17f,0.17f,0.21f,1); }];
}

- (void)pan:(UIPanGestureRecognizer*)g {
    CGPoint loc = [g locationInView:self.superview];
    if (g.state == UIGestureRecognizerStateBegan)
        _drag = CGPointMake(loc.x - self.frame.origin.x, loc.y - self.frame.origin.y);
    else if (g.state == UIGestureRecognizerStateChanged) {
        CGRect r = self.frame;
        r.origin = CGPointMake(loc.x - _drag.x, loc.y - _drag.y);
        self.frame = r;
    }
}
@end

// ─── Controller ───────────────────────────────────────────────────────────────
@interface CheatController : NSObject
+ (instancetype)shared;
- (void)toggle;
@end

@implementation CheatController {
    UIWindow*   _win;
    MenuView*   _menu;
    PillButton* _pill;
    BOOL        _visible;
}

+ (instancetype)shared {
    static CheatController* inst;
    static dispatch_once_t  once;
    dispatch_once(&once, ^{ inst = [CheatController new]; });
    return inst;
}

- (instancetype)init {
    self = [super init];
    [self build];
    return self;
}

- (void)build {
    UIWindowScene* scene = nil;
    for (UIScene* s in [UIApplication sharedApplication].connectedScenes)
        if ([s isKindOfClass:[UIWindowScene class]]) { scene = (UIWindowScene*)s; break; }

    _win = scene
        ? [[PassthroughWindow alloc] initWithWindowScene:scene]
        : [[PassthroughWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
    _win.windowLevel     = UIWindowLevelAlert + 200;
    _win.backgroundColor = [UIColor clearColor];

    PassthroughView* pv  = [[PassthroughView alloc]
        initWithFrame:[UIScreen mainScreen].bounds];
    pv.backgroundColor   = [UIColor clearColor];

    UIViewController* vc = [UIViewController new];
    vc.view              = pv;
    _win.rootViewController = vc;
    [_win makeKeyAndVisible];

    CGSize sz = [UIScreen mainScreen].bounds.size;
    _menu = [[MenuView alloc] initWithFrame:
        CGRectMake((sz.width-kW)*.5f, (sz.height-kH)*.5f, kW, kH)];
    [pv addSubview:_menu];

    [_menu.hideBtn  addTarget:self action:@selector(doHide)
        forControlEvents:UIControlEventTouchUpInside];
    [_menu.closeBtn addTarget:self action:@selector(doClose)
        forControlEvents:UIControlEventTouchUpInside];
    [_menu.dumpBtn  addTarget:self action:@selector(doDump)
        forControlEvents:UIControlEventTouchUpInside];

    __weak CheatController* ws = self;
    _pill        = [PillButton new];
    _pill.action = ^{ [ws doShow]; };
    _pill.hidden = YES;
    [pv addSubview:_pill];
}

- (void)doDump {
    _menu.dumpBtn.enabled      = NO;
    _menu.statusLabel.text     = @"dumping...";
    _menu.statusLabel.textColor = C(0.70f, 0.70f, 0.35f, 1.0f);

    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSString* result = PerformDump();
        dispatch_async(dispatch_get_main_queue(), ^{
            self->_menu.dumpBtn.enabled      = YES;
            self->_menu.statusLabel.text      = result;
            self->_menu.statusLabel.textColor =
                [result hasPrefix:@"ошибка"]
                    ? C(0.80f, 0.30f, 0.30f, 1.0f)
                    : C(0.35f, 0.70f, 0.40f, 1.0f);
        });
    });
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
    } completion:^(BOOL _) {
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
    } completion:^(BOOL _) {
        self->_menu.hidden    = YES;
        self->_menu.transform = CGAffineTransformIdentity;
        self->_pill.hidden    = NO;
        self->_visible        = NO;
    }];
}

- (void)toggle {
    _visible ? [self doHide] : [self doShow];
}
@end

// ─── entry ────────────────────────────────────────────────────────────────────
__attribute__((constructor))
static void Init(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            [[CheatController shared] toggle];
        });
    });
}
