#import <UIKit/UIKit.h>
#import <CoreGraphics/CoreGraphics.h>
#include <dlfcn.h>
#include <vector>
#include <cmath>
#include <cstring>
#include <string>
#include <stdint.h>
#include <mach-o/dyld.h>
#include <sys/mman.h>
#include <libkern/OSCacheControl.h>

// ═══════════════════════════════════════════════════════════════════
//  HOOK ENGINE
// ═══════════════════════════════════════════════════════════════════
static bool cfHook(void* target, void* replace, void** orig) {
    if (!target || !replace) return false;
    uintptr_t page = (uintptr_t)target & ~(uintptr_t)(4096 - 1);
    mprotect((void*)page, 4096 * 2, PROT_READ | PROT_WRITE | PROT_EXEC);

    uint32_t* dst = (uint32_t*)target;

    if (orig) {
        void* tramp = mmap(NULL, 64, PROT_READ|PROT_WRITE|PROT_EXEC,
                           MAP_PRIVATE|MAP_ANONYMOUS, -1, 0);
        if (!tramp) return false;
        uint32_t* t = (uint32_t*)tramp;
        t[0] = dst[0]; t[1] = dst[1]; t[2] = dst[2]; t[3] = dst[3];
        t[4] = 0x58000050; // ldr x16, #8
        t[5] = 0xD61F0200; // br  x16
        *((uint64_t*)&t[6]) = (uintptr_t)target + 16;
        sys_icache_invalidate(tramp, 64);
        *orig = tramp;
    }

    dst[0] = 0x58000050;
    dst[1] = 0xD61F0200;
    *((uint64_t*)&dst[2]) = (uint64_t)replace;
    sys_icache_invalidate(target, 16);
    return true;
}
#define HOOK(target, replace, orig) cfHook((void*)(target), (void*)(replace), (void**)(orig))

// ═══════════════════════════════════════════════════════════════════
//  OFFSETS
// ═══════════════════════════════════════════════════════════════════
#define OFF_PC_FPSCAM        0x28
#define OFF_PC_MAINCAM       0x30
#define OFF_PC_ARMSCTRL      0x60
#define OFF_PC_PLAYERLOCK    0x68
#define OFF_PC_NETWORK       0x88
#define OFF_PC_PLAYER        0x90
#define OFF_PC_ANIMCTRL      0x98
#define OFF_PC_ISDEATH       0xA8

#define OFF_SKEL_HEAD        0xA8
#define OFF_SKEL_CHEST       0xB0
#define OFF_SKEL_PELVIS      0xB8

#define OFF_NET_POSITION     0xBC
#define OFF_NET_CAMPIVOT     0x110

#define OFF_CULL_CONTROLLER  0x18
#define OFF_CULL_OCCLUDED    0x48
#define OFF_CULL_INFRAUSTRUM 0x49

#define OFF_LOCK_PLAYERBODY  0x20
#define OFF_LOCK_ROTATIONX   0x38
#define OFF_LOCK_CANMOVE     0x3C
#define OFF_LOCK_HIPFOV      0x40

// ═══════════════════════════════════════════════════════════════════
//  TYPES
// ═══════════════════════════════════════════════════════════════════
struct CFVec2  { float x, y; };
struct CFVec3  { float x, y, z; };
struct CFColor { float r, g, b, a; };

// ═══════════════════════════════════════════════════════════════════
//  MEMORY
// ═══════════════════════════════════════════════════════════════════
template<typename T>
static inline T cfRd(uintptr_t a) {
    if (a < 0x10000) { T z; memset(&z,0,sizeof(z)); return z; }
    return *reinterpret_cast<T*>(a);
}
template<typename T>
static inline void cfWr(uintptr_t a, T v) {
    if (a >= 0x10000) *reinterpret_cast<T*>(a) = v;
}
static inline uintptr_t cfPtr(uintptr_t a) {
    if (a < 0x10000) return 0;
    uintptr_t p = *reinterpret_cast<uintptr_t*>(a);
    return p >= 0x10000 ? p : 0;
}

static inline uintptr_t listGet(uintptr_t list, int i) {
    uintptr_t arr = cfPtr(list + 0x10);
    return arr ? cfPtr(arr + 0x20 + (uintptr_t)i * 0x8) : 0;
}
static inline int listCount(uintptr_t list) {
    if (list < 0x10000) return 0;
    return *reinterpret_cast<int*>(list + 0x18);
}
static inline float v3dist(CFVec3 a, CFVec3 b) {
    float dx=a.x-b.x, dy=a.y-b.y, dz=a.z-b.z;
    return sqrtf(dx*dx+dy*dy+dz*dz);
}
static inline float v2dist(CFVec2 a, CFVec2 b) {
    float dx=a.x-b.x, dy=a.y-b.y;
    return sqrtf(dx*dx+dy*dy);
}

// ═══════════════════════════════════════════════════════════════════
//  CONFIG
// ═══════════════════════════════════════════════════════════════════
struct Config {
    bool    espEnabled;
    bool    espBox;
    bool    espSkeleton;
    bool    espVisCheck;
    CFColor espColorVis;
    CFColor espColorHid;
    bool    chamsEnabled;
    bool    aimEnabled;
    float   aimFov;
    int     aimBone;
    bool    aimVisOnly;
    float   aimSmooth;
};
static Config g_cfg;

static void ConfigInit(Config* c) {
    c->espEnabled   = false;
    c->espBox       = true;
    c->espSkeleton  = false;
    c->espVisCheck  = true;
    c->espColorVis  = (CFColor){0.f,1.f,0.f,1.f};
    c->espColorHid  = (CFColor){1.f,0.f,0.f,1.f};
    c->chamsEnabled = false;
    c->aimEnabled   = false;
    c->aimFov       = 80.f;
    c->aimBone      = 0;
    c->aimVisOnly   = true;
    c->aimSmooth    = 6.f;
}

// ═══════════════════════════════════════════════════════════════════
//  IL2CPP
// ═══════════════════════════════════════════════════════════════════
typedef void*       (*t_DomainGet)();
typedef void*       (*t_DomainGetAssemblies)(void*, size_t*);
typedef void*       (*t_AssemblyGetImage)(void*);
typedef const char* (*t_ImageGetName)(void*);
typedef size_t      (*t_ImageGetClassCount)(void*);
typedef void*       (*t_ClassFromName)(void*, const char*, const char*);
typedef void*       (*t_ClassGetMethod)(void*, const char*, int);
typedef const void* (*t_MethodGetPtr)(void*);
typedef void*       (*t_ClassGetStaticFieldData)(void*);

static t_DomainGet               il2_DomainGet;
static t_DomainGetAssemblies     il2_DomainGetAssemblies;
static t_AssemblyGetImage        il2_AssemblyGetImage;
static t_ImageGetName            il2_ImageGetName;
static t_ImageGetClassCount      il2_ImageGetClassCount;
static t_ClassFromName           il2_ClassFromName;
static t_ClassGetMethod          il2_ClassGetMethod;
static t_MethodGetPtr            il2_MethodGetPtr;
static t_ClassGetStaticFieldData il2_ClassGetStaticFieldData;

static bool Il2CppInit() {
    void* h = dlopen(NULL, RTLD_NOW);
    if (!h) return false;
#define LD(var, name) il2_##var = (t_##var)dlsym(h, "il2cpp_" name)
    LD(DomainGet,               "domain_get");
    LD(DomainGetAssemblies,     "domain_get_assemblies");
    LD(AssemblyGetImage,        "assembly_get_image");
    LD(ImageGetName,            "image_get_name");
    LD(ImageGetClassCount,      "image_get_class_count");
    LD(ClassFromName,           "class_from_name");
    LD(ClassGetMethod,          "class_get_method_from_name");
    LD(MethodGetPtr,            "method_get_pointer");
    LD(ClassGetStaticFieldData, "class_get_static_field_data");
#undef LD
    return il2_DomainGet && il2_ClassFromName && il2_ClassGetMethod;
}

static void* FindImageByName(const char* needle) {
    if (!il2_DomainGet || !il2_DomainGetAssemblies ||
        !il2_AssemblyGetImage || !il2_ImageGetName) return NULL;
    size_t cnt = 0;
    void* domain = il2_DomainGet();
    if (!domain) return NULL;
    void** asms = (void**)il2_DomainGetAssemblies(domain, &cnt);
    if (!asms) return NULL;
    for (size_t i = 0; i < cnt; i++) {
        void* img = il2_AssemblyGetImage(asms[i]);
        if (!img) continue;
        const char* n = il2_ImageGetName(img);
        if (n && strstr(n, needle)) return img;
    }
    return NULL;
}

static uintptr_t FindMethodInImage(void* img, const char* ns,
                                   const char* cls, const char* meth, int pc) {
    if (!img) return 0;
    void* klass = il2_ClassFromName(img, ns, cls);
    if (!klass) return 0;
    void* m = il2_ClassGetMethod(klass, meth, pc);
    if (!m) return 0;
    return (uintptr_t)il2_MethodGetPtr(m);
}

static uintptr_t FindMethodAnywhere(const char* ns,
                                    const char* cls, const char* meth, int pc) {
    if (!il2_DomainGet || !il2_DomainGetAssemblies || !il2_AssemblyGetImage)
        return 0;
    size_t cnt = 0;
    void* domain = il2_DomainGet();
    if (!domain) return 0;
    void** asms = (void**)il2_DomainGetAssemblies(domain, &cnt);
    if (!asms) return 0;
    for (size_t i = 0; i < cnt; i++) {
        void* img = il2_AssemblyGetImage(asms[i]);
        if (!img) continue;
        uintptr_t r = FindMethodInImage(img, ns, cls, meth, pc);
        if (r) return r;
    }
    return 0;
}

static uintptr_t GetStaticFieldsOf(void* img, const char* ns, const char* cls) {
    if (!img || !il2_ClassGetStaticFieldData) return 0;
    void* klass = il2_ClassFromName(img, ns, cls);
    return klass ? (uintptr_t)il2_ClassGetStaticFieldData(klass) : 0;
}

// ═══════════════════════════════════════════════════════════════════
//  UNITY CALLS
// ═══════════════════════════════════════════════════════════════════
typedef void      (*t_GetPos)(uintptr_t, CFVec3*);
typedef void      (*t_W2SInjected)(uintptr_t, CFVec3*, CFVec3*);
typedef uintptr_t (*t_GetMain)();

static t_GetPos      Transform_get_position = NULL;
static t_W2SInjected Camera_W2S             = NULL;
static t_GetMain     Camera_GetMain         = NULL;

static CFVec3 GetPos(uintptr_t transform) {
    CFVec3 v; memset(&v,0,sizeof(v));
    if (transform >= 0x10000 && Transform_get_position)
        Transform_get_position(transform, &v);
    return v;
}

// ═══════════════════════════════════════════════════════════════════
//  CHAMS
// ═══════════════════════════════════════════════════════════════════
typedef void (*t_TWH_SetOnOutline)(uintptr_t);
typedef void (*t_TWH_SetOff)(uintptr_t);

static t_TWH_SetOnOutline TWH_SetOnOutline = NULL;
static t_TWH_SetOff       TWH_SetOff       = NULL;
static uintptr_t          g_TWH_instance   = 0;

static void ApplyChams(bool enable) {
    if (g_TWH_instance < 0x10000) return;
    if (enable  && TWH_SetOnOutline) TWH_SetOnOutline(g_TWH_instance);
    if (!enable && TWH_SetOff)       TWH_SetOff(g_TWH_instance);
}

// ═══════════════════════════════════════════════════════════════════
//  SCREEN / W2S
// ═══════════════════════════════════════════════════════════════════
static float g_sw = 0.f, g_sh = 0.f;
static CFVec2 g_center;
static uintptr_t g_mainCam = 0;

static bool W2S(CFVec3 world, CFVec2* out) {
    if (!Camera_W2S || g_mainCam < 0x10000) return false;
    CFVec3 r; memset(&r,0,sizeof(r));
    Camera_W2S(g_mainCam, &world, &r);
    if (r.z < 0.01f) return false;
    out->x = r.x;
    out->y = g_sh - r.y;
    return true;
}

// ═══════════════════════════════════════════════════════════════════
//  PLAYERS
// ═══════════════════════════════════════════════════════════════════
struct Player {
    uintptr_t controller, network, culling, skeleton;
    CFVec3 headPos, chestPos, pelvisPos, netPos;
    CFVec2 headS, chestS, pelvisS, topS, botS;
    bool   headOnS, chestOnS, pelvisOnS;
    bool   isDead, occluded, inFrustum;
    float  dist;
};

static std::vector<Player> g_players;
static uintptr_t g_localCtrl        = 0;
static uintptr_t g_localArms        = 0;
static CFVec3    g_localPos;
static uintptr_t g_cullingInstances = 0;

static void UpdatePlayers() {
    g_players.clear();
    if (g_cullingInstances < 0x10000) return;

    uintptr_t list = cfPtr(g_cullingInstances);
    int count = listCount(list);
    if (count <= 0 || count > 64) return;

    for (int i = 0; i < count; i++) {
        uintptr_t culling = listGet(list, i);
        if (culling < 0x10000) continue;

        uintptr_t ctrl = cfPtr(culling + OFF_CULL_CONTROLLER);
        if (ctrl < 0x10000 || ctrl == g_localCtrl) continue;

        bool dead = cfRd<bool>(ctrl + OFF_PC_ISDEATH);
        if (dead) continue;

        bool occ  = cfRd<bool>(culling + OFF_CULL_OCCLUDED);
        bool frus = cfRd<bool>(culling + OFF_CULL_INFRAUSTRUM);

        uintptr_t net = cfPtr(ctrl + OFF_PC_NETWORK);
        if (net < 0x10000) continue;

        CFVec3 netPos = cfRd<CFVec3>(net + OFF_NET_POSITION);

        uintptr_t animCtrl = cfPtr(ctrl + OFF_PC_ANIMCTRL);
        uintptr_t skel     = animCtrl ? cfPtr(animCtrl + 0x20) : 0;

        CFVec3 headPos, chestPos, pelvisPos;
        memset(&headPos,   0, sizeof(headPos));
        memset(&chestPos,  0, sizeof(chestPos));
        memset(&pelvisPos, 0, sizeof(pelvisPos));

        if (skel >= 0x10000) {
            headPos   = GetPos(cfPtr(skel + OFF_SKEL_HEAD));
            chestPos  = GetPos(cfPtr(skel + OFF_SKEL_CHEST));
            pelvisPos = GetPos(cfPtr(skel + OFF_SKEL_PELVIS));
        } else {
            CFVec3 pivot = cfRd<CFVec3>(net + OFF_NET_CAMPIVOT);
            headPos.x = netPos.x + pivot.x;
            headPos.y = netPos.y + pivot.y;
            headPos.z = netPos.z + pivot.z;
            chestPos  = netPos; chestPos.y  += 1.0f;
            pelvisPos = netPos; pelvisPos.y += 0.5f;
        }

        Player p;
        memset(&p, 0, sizeof(p));
        p.controller = ctrl; p.network = net;
        p.culling    = culling; p.skeleton = skel;
        p.isDead = dead; p.occluded = occ; p.inFrustum = frus;
        p.headPos = headPos; p.chestPos = chestPos;
        p.pelvisPos = pelvisPos; p.netPos = netPos;
        p.dist = v3dist(g_localPos, netPos);

        p.headOnS   = W2S(headPos,   &p.headS);
        p.chestOnS  = W2S(chestPos,  &p.chestS);
        p.pelvisOnS = W2S(pelvisPos, &p.pelvisS);

        CFVec3 bot = netPos; bot.y -= 0.2f;
        W2S(headPos, &p.topS);
        W2S(bot,     &p.botS);

        g_players.push_back(p);
    }
}

// ═══════════════════════════════════════════════════════════════════
//  AIMBOT
// ═══════════════════════════════════════════════════════════════════
static void DoAimbot(uintptr_t localCtrl) {
    if (!g_cfg.aimEnabled || localCtrl < 0x10000 || g_players.empty()) return;

    float bestDist = g_cfg.aimFov;
    const Player* best = NULL;

    for (size_t i = 0; i < g_players.size(); i++) {
        const Player& p = g_players[i];
        if (g_cfg.aimVisOnly && p.occluded) continue;
        if (!p.headOnS) continue;
        CFVec2 tgt;
        if      (g_cfg.aimBone == 1) tgt = p.chestS;
        else if (g_cfg.aimBone == 2) tgt = p.pelvisS;
        else                          tgt = p.headS;
        float d = v2dist(tgt, g_center);
        if (d < bestDist) { bestDist = d; best = &p; }
    }
    if (!best) return;

    CFVec2 tgt;
    if      (g_cfg.aimBone == 1) tgt = best->chestS;
    else if (g_cfg.aimBone == 2) tgt = best->pelvisS;
    else                          tgt = best->headS;

    float dy = (tgt.y - g_center.y) / g_cfg.aimSmooth;

    uintptr_t lock = cfPtr(localCtrl + OFF_PC_PLAYERLOCK);
    if (lock < 0x10000) return;

    cfWr<bool>(lock + OFF_LOCK_CANMOVE, true);

    float hipFov = cfRd<float>(lock + OFF_LOCK_HIPFOV);
    if (hipFov < 1.f) hipFov = 60.f;

    float curX = cfRd<float>(lock + OFF_LOCK_ROTATIONX);
    cfWr<float>(lock + OFF_LOCK_ROTATIONX, curX + (-dy * (hipFov / g_sh)));
}

// ═══════════════════════════════════════════════════════════════════
//  ESP VIEW
// ═══════════════════════════════════════════════════════════════════
@interface CFESPView : UIView @end
@implementation CFESPView
- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = [UIColor clearColor];
        self.userInteractionEnabled = NO;
        self.opaque = NO;
    }
    return self;
}
- (void)drawRect:(CGRect)__unused rect {
    CGContextRef ctx = UIGraphicsGetCurrentContext();
    if (!ctx) return;

    if (g_cfg.espEnabled) {
        CGContextSetLineWidth(ctx, 1.5f);
        for (size_t i = 0; i < g_players.size(); i++) {
            const Player& p = g_players[i];
            CFColor c = (p.occluded && g_cfg.espVisCheck)
                        ? g_cfg.espColorHid : g_cfg.espColorVis;
            CGContextSetRGBStrokeColor(ctx, c.r, c.g, c.b, c.a);
            if (g_cfg.espBox && p.headOnS && p.pelvisOnS) {
                float h = p.botS.y - p.topS.y;
                if (h < 8.f) h = 8.f;
                float w = h * 0.45f;
                CGContextStrokeRect(ctx,
                    CGRectMake(p.topS.x - w*0.5f, p.topS.y, w, h));
            }
            if (g_cfg.espSkeleton) {
                if (p.headOnS && p.chestOnS) {
                    CGContextMoveToPoint(ctx, p.headS.x, p.headS.y);
                    CGContextAddLineToPoint(ctx, p.chestS.x, p.chestS.y);
                    CGContextStrokePath(ctx);
                }
                if (p.chestOnS && p.pelvisOnS) {
                    CGContextMoveToPoint(ctx, p.chestS.x, p.chestS.y);
                    CGContextAddLineToPoint(ctx, p.pelvisS.x, p.pelvisS.y);
                    CGContextStrokePath(ctx);
                }
            }
        }
    }
    if (g_cfg.aimEnabled) {
        CGContextSetRGBStrokeColor(ctx, 0.12f, 0.95f, 0.32f, 0.4f);
        CGContextSetLineWidth(ctx, 1.f);
        CGContextStrokeEllipseInRect(ctx,
            CGRectMake(g_center.x - g_cfg.aimFov,
                       g_center.y - g_cfg.aimFov,
                       g_cfg.aimFov * 2, g_cfg.aimFov * 2));
        CGContextSetLineWidth(ctx, 0.8f);
        CGContextMoveToPoint(ctx, g_center.x-6, g_center.y);
        CGContextAddLineToPoint(ctx, g_center.x+6, g_center.y);
        CGContextMoveToPoint(ctx, g_center.x, g_center.y-6);
        CGContextAddLineToPoint(ctx, g_center.x, g_center.y+6);
        CGContextStrokePath(ctx);
    }
}
@end

// ═══════════════════════════════════════════════════════════════════
//  MENU
// ═══════════════════════════════════════════════════════════════════
@interface CFMenu : UIView
@property (nonatomic, strong) UIScrollView* panel;
@end

@implementation CFMenu {
    CGFloat _y;
    CGPoint _drag;
}

- (instancetype)initWithScreen:(CGRect)sz {
    CGFloat h = MIN(480.f, sz.size.height - 80.f);
    CGFloat x = (sz.size.width  - 270.f) * 0.5f;
    CGFloat y = (sz.size.height - h)      * 0.5f;

    self = [super initWithFrame:CGRectMake(x, y, 270, h)];
    if (!self) return nil;

    self.backgroundColor = [UIColor colorWithRed:.07f green:.07f blue:.09f alpha:.93f];
    self.layer.cornerRadius = 12;
    self.layer.masksToBounds = YES;
    self.layer.borderWidth = 1;
    self.layer.borderColor =
        [UIColor colorWithRed:.22f green:.22f blue:.28f alpha:.65f].CGColor;

    UIView* hdr = [[UIView alloc] initWithFrame:CGRectMake(0,0,270,42)];
    hdr.backgroundColor = [UIColor colorWithRed:.10f green:.10f blue:.13f alpha:1];
    hdr.userInteractionEnabled = YES;
    [self addSubview:hdr];

    UIView* acc = [[UIView alloc] initWithFrame:CGRectMake(0,41,270,1)];
    acc.backgroundColor = [UIColor colorWithRed:.27f green:.52f blue:1 alpha:.55f];
    [self addSubview:acc];

    UILabel* ttl = [[UILabel alloc] initWithFrame:CGRectMake(0,12,270,18)];
    ttl.text = @"CF ESP";
    ttl.textAlignment = NSTextAlignmentCenter;
    ttl.font = [UIFont systemFontOfSize:13 weight:UIFontWeightSemibold];
    ttl.textColor = [UIColor colorWithWhite:.92f alpha:1];
    [self addSubview:ttl];

    UIPanGestureRecognizer* pan =
        [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(drag:)];
    [hdr addGestureRecognizer:pan];

    _panel = [[UIScrollView alloc] initWithFrame:CGRectMake(0,43,270,h-43)];
    _panel.backgroundColor = [UIColor clearColor];
    _panel.alwaysBounceVertical = YES;
    [self addSubview:_panel];

    [self buildUI];
    return self;
}

- (void)drag:(UIPanGestureRecognizer*)g {
    CGPoint loc = [g locationInView:self.superview];
    if (g.state == UIGestureRecognizerStateBegan)
        _drag = CGPointMake(loc.x - self.frame.origin.x,
                            loc.y - self.frame.origin.y);
    else if (g.state == UIGestureRecognizerStateChanged) {
        CGRect f = self.frame;
        f.origin = CGPointMake(loc.x - _drag.x, loc.y - _drag.y);
        self.frame = f;
    }
}

- (void)section:(NSString*)title {
    UILabel* l = [[UILabel alloc] initWithFrame:CGRectMake(10, _y, 250, 16)];
    l.text = title;
    l.textColor = [UIColor colorWithRed:.27f green:.52f blue:1 alpha:1];
    l.font = [UIFont boldSystemFontOfSize:10];
    [_panel addSubview:l]; _y += 22;
}

- (void)row:(NSString*)title val:(BOOL)v sel:(SEL)s {
    UILabel* l = [[UILabel alloc] initWithFrame:CGRectMake(10, _y+4, 185, 20)];
    l.text = title;
    l.textColor = [UIColor whiteColor];
    l.font = [UIFont systemFontOfSize:13];
    [_panel addSubview:l];

    UISwitch* sw = [[UISwitch alloc] initWithFrame:CGRectMake(198, _y, 51, 31)];
    sw.transform = CGAffineTransformMakeScale(0.78f, 0.78f);
    sw.on = v;
    [sw addTarget:self action:s forControlEvents:UIControlEventValueChanged];
    [_panel addSubview:sw];
    _y += 38;
}

- (void)slider:(NSString*)title min:(float)mn max:(float)mx val:(float)v
           sel:(SEL)s tag:(NSInteger)tag {
    UILabel* l = [[UILabel alloc] initWithFrame:CGRectMake(10, _y, 250, 14)];
    l.text = [NSString stringWithFormat:@"%@ : %.0f", title, v];
    l.textColor = [UIColor lightGrayColor];
    l.font = [UIFont systemFontOfSize:10];
    l.tag = tag;
    [_panel addSubview:l]; _y += 16;

    UISlider* sl = [[UISlider alloc] initWithFrame:CGRectMake(10, _y, 250, 26)];
    sl.minimumValue = mn; sl.maximumValue = mx; sl.value = v;
    sl.minimumTrackTintColor =
        [UIColor colorWithRed:.12f green:.95f blue:.32f alpha:.85f];
    sl.tag = tag;
    [sl addTarget:self action:s forControlEvents:UIControlEventValueChanged];
    [_panel addSubview:sl]; _y += 34;
}

- (void)buildUI {
    _y = 10;
    [self section:@"── ESP ─────────────────"];
    [self row:@"ESP"       val:g_cfg.espEnabled  sel:@selector(onESP:)];
    [self row:@"Box"       val:g_cfg.espBox      sel:@selector(onBox:)];
    [self row:@"Skeleton"  val:g_cfg.espSkeleton sel:@selector(onSkel:)];
    [self row:@"Vis check" val:g_cfg.espVisCheck sel:@selector(onVis:)];

    [self section:@"── CHAMS ───────────────"];
    [self row:@"Chams (outline)" val:g_cfg.chamsEnabled sel:@selector(onChams:)];

    [self section:@"── AIMBOT ──────────────"];
    [self row:@"Aimbot"        val:g_cfg.aimEnabled sel:@selector(onAim:)];
    [self row:@"Только видимые" val:g_cfg.aimVisOnly sel:@selector(onAimVis:)];
    [self slider:@"FOV"    min:10 max:350 val:g_cfg.aimFov
              sel:@selector(onFov:)    tag:100];
    [self slider:@"Smooth" min:1  max:25  val:g_cfg.aimSmooth
              sel:@selector(onSmooth:) tag:101];

    UILabel* bl = [[UILabel alloc] initWithFrame:CGRectMake(10, _y, 250, 14)];
    bl.text = @"Цель";
    bl.textColor = [UIColor lightGrayColor];
    bl.font = [UIFont systemFontOfSize:10];
    [_panel addSubview:bl]; _y += 16;

    NSArray* items = @[@"Голова", @"Грудь", @"Таз"];
    UISegmentedControl* sc = [[UISegmentedControl alloc] initWithItems:items];
    sc.frame = CGRectMake(10, _y, 250, 28);
    sc.selectedSegmentIndex = g_cfg.aimBone;
    [sc addTarget:self action:@selector(onBone:)
       forControlEvents:UIControlEventValueChanged];
    [_panel addSubview:sc]; _y += 38;

    _panel.contentSize = CGSizeMake(270, _y + 16);
}

- (void)onESP:(UISwitch*)s    { g_cfg.espEnabled   = s.on; }
- (void)onBox:(UISwitch*)s    { g_cfg.espBox       = s.on; }
- (void)onSkel:(UISwitch*)s   { g_cfg.espSkeleton  = s.on; }
- (void)onVis:(UISwitch*)s    { g_cfg.espVisCheck  = s.on; }
- (void)onChams:(UISwitch*)s  { g_cfg.chamsEnabled = s.on; ApplyChams(s.on); }
- (void)onAim:(UISwitch*)s    { g_cfg.aimEnabled   = s.on; }
- (void)onAimVis:(UISwitch*)s { g_cfg.aimVisOnly   = s.on; }
- (void)onBone:(UISegmentedControl*)sc { g_cfg.aimBone = (int)sc.selectedSegmentIndex; }

- (void)onFov:(UISlider*)sl {
    g_cfg.aimFov = sl.value;
    UILabel* l = (UILabel*)[_panel viewWithTag:100];
    if (l) l.text = [NSString stringWithFormat:@"FOV : %.0f", sl.value];
}
- (void)onSmooth:(UISlider*)sl {
    g_cfg.aimSmooth = sl.value;
    UILabel* l = (UILabel*)[_panel viewWithTag:101];
    if (l) l.text = [NSString stringWithFormat:@"Smooth : %.0f", sl.value];
}
@end

// ═══════════════════════════════════════════════════════════════════
//  UI GLOBALS
// ═══════════════════════════════════════════════════════════════════
static CFESPView* g_espView = nil;
static CFMenu*    g_menu    = nil;
static bool       g_uiReady = false;

// ═══════════════════════════════════════════════════════════════════
//  HOOKS
// ═══════════════════════════════════════════════════════════════════
typedef void (*t_ArmsLateUpdate)(uintptr_t);
static t_ArmsLateUpdate orig_ArmsLateUpdate = NULL;

static void Hook_ArmsLateUpdate(uintptr_t thiz) {
    // обязательно вызываем оригинал первым
    if (orig_ArmsLateUpdate) orig_ArmsLateUpdate(thiz);

    // guards
    if (!g_uiReady)          return;
    if (g_localCtrl == 0)    return;
    if (g_localArms == 0)    return;
    if (thiz != g_localArms) return;
    if (!Camera_W2S || !Camera_GetMain) return;

    // обновляем главную камеру (один раз)
    if (g_mainCam == 0) {
        uintptr_t mc = Camera_GetMain();
        if (mc >= 0x10000) g_mainCam = mc;
    }

    // локальная позиция
    uintptr_t net = cfPtr(g_localCtrl + OFF_PC_NETWORK);
    if (net >= 0x10000) {
        g_localPos = cfRd<CFVec3>(net + OFF_NET_POSITION);
    }

    UpdatePlayers();
    DoAimbot(g_localCtrl);

    if (g_espView) {
        CFESPView* view = g_espView;
        dispatch_async(dispatch_get_main_queue(), ^{ [view setNeedsDisplay]; });
    }
}

typedef void (*t_Awake)(uintptr_t);
static t_Awake orig_TWH_Awake = NULL;
static t_Awake orig_PCAwake   = NULL;

static void Hook_TWH_Awake(uintptr_t thiz) {
    if (orig_TWH_Awake) orig_TWH_Awake(thiz);
    if (g_TWH_instance == 0 && thiz >= 0x10000)
        g_TWH_instance = thiz;
}

static void Hook_PCAwake(uintptr_t thiz) {
    if (orig_PCAwake) orig_PCAwake(thiz);
    if (g_localCtrl != 0) return;
    if (thiz < 0x10000) return;

    uintptr_t fps = cfPtr(thiz + OFF_PC_FPSCAM);
    uintptr_t net = cfPtr(thiz + OFF_PC_NETWORK);
    if (fps < 0x10000 || net < 0x10000) return;

    g_localCtrl = thiz;
    g_localArms = cfPtr(thiz + OFF_PC_ARMSCTRL);
}

// ═══════════════════════════════════════════════════════════════════
//  UI helper
// ═══════════════════════════════════════════════════════════════════
static UIWindowScene* GetActiveScene(void) {
    if (@available(iOS 13.0, *)) {
        for (UIScene* sc in [UIApplication sharedApplication].connectedScenes) {
            if ([sc isKindOfClass:[UIWindowScene class]] &&
                sc.activationState == UISceneActivationStateForegroundActive) {
                return (UIWindowScene*)sc;
            }
        }
    }
    return nil;
}

static UIWindow* GetGameWindow(UIWindowScene* scene) {
    if (!scene) return nil;
    for (UIWindow* w in scene.windows) {
        if (w.rootViewController) return w;
    }
    return nil;
}

// ═══════════════════════════════════════════════════════════════════
//  BuildUI — ретраит пока не появится активная сцена и game-окно
// ═══════════════════════════════════════════════════════════════════
static void BuildUI(void) {
    UIWindowScene* scene = GetActiveScene();
    if (!scene) {
        dispatch_after(
            dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)),
            dispatch_get_main_queue(), ^{ BuildUI(); });
        return;
    }

    UIWindow* gameWin = GetGameWindow(scene);
    if (!gameWin) {
        dispatch_after(
            dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)),
            dispatch_get_main_queue(), ^{ BuildUI(); });
        return;
    }

    if (g_uiReady) return;  // уже собрано

    CGRect scr = [UIScreen mainScreen].bounds;
    g_sw = scr.size.width;
    g_sh = scr.size.height;
    g_center.x = g_sw * 0.5f;
    g_center.y = g_sh * 0.5f;

    // ESP-слой (не перехватывает touch)
    g_espView = [[CFESPView alloc] initWithFrame:scr];
    g_espView.userInteractionEnabled = NO;
    [gameWin addSubview:g_espView];

    // Меню (перехватывает touch только в своей области)
    g_menu = [[CFMenu alloc] initWithScreen:scr];
    [gameWin addSubview:g_menu];

    g_uiReady = true;
}

// ═══════════════════════════════════════════════════════════════════
//  INIT
// ═══════════════════════════════════════════════════════════════════
static void Init(void) {
    ConfigInit(&g_cfg);
    memset(&g_localPos, 0, sizeof(g_localPos));

    if (!Il2CppInit()) return;

    // Unity
    Transform_get_position = (t_GetPos)
        FindMethodAnywhere("UnityEngine", "Transform", "get_position_Injected", 1);
    if (!Transform_get_position) {
        Transform_get_position = (t_GetPos)
            FindMethodAnywhere("UnityEngine", "Transform", "get_position", 0);
    }

    Camera_W2S = (t_W2SInjected)
        FindMethodAnywhere("UnityEngine", "Camera",
                           "WorldToScreenPoint_Injected", 1);
    Camera_GetMain = (t_GetMain)
        FindMethodAnywhere("UnityEngine", "Camera", "get_main", 0);

    // Chams
    TWH_SetOnOutline = (t_TWH_SetOnOutline)
        FindMethodAnywhere("", "TournamentWallHack", "SetOnOutline", 0);
    TWH_SetOff = (t_TWH_SetOff)
        FindMethodAnywhere("", "TournamentWallHack", "SetOff", 0);

    // PlayerCulling.Instances (статик-поле)
    void* asmImg = FindImageByName("Assembly-CSharp");
    if (asmImg) {
        uintptr_t sf = GetStaticFieldsOf(asmImg, "", "PlayerCulling");
        if (sf >= 0x10000) g_cullingInstances = sf + 0x8;
    }

    // Hooks
    uintptr_t a = FindMethodAnywhere("", "ArmsController", "LateUpdate", 0);
    if (a) HOOK(a, Hook_ArmsLateUpdate, &orig_ArmsLateUpdate);

    a = FindMethodAnywhere("", "TournamentWallHack", "Awake", 0);
    if (a) HOOK(a, Hook_TWH_Awake, &orig_TWH_Awake);

    a = FindMethodAnywhere("", "PlayerController", "Awake", 0);
    if (a) HOOK(a, Hook_PCAwake, &orig_PCAwake);

    // UI — на main thread с ретраем
    dispatch_after(
        dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)),
        dispatch_get_main_queue(), ^{ BuildUI(); });
}

__attribute__((constructor))
static void Entry(void) {
    dispatch_after(
        dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3.0 * NSEC_PER_SEC)),
        dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0),
        ^{ Init(); });
}
