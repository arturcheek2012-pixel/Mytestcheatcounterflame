#import <UIKit/UIKit.h>
#import <CoreGraphics/CoreGraphics.h>
#include <dlfcn.h>
#include <vector>
#include <cmath>
#include <string>
#include <stdint.h>
#include <mach-o/dyld.h>
#include <sys/mman.h>

// ═══════════════════════════════════════════════════════════════════
//  HOOK ENGINE (без substrate — через прямую запись B/BL инструкции)
// ═══════════════════════════════════════════════════════════════════
// arm64 trampoline: 4 инструкции, пишем напрямую в память
static bool cfHook(void* target, void* replace, void** orig) {
    if (!target || !replace) return false;

    // снимаем защиту
    uintptr_t page     = (uintptr_t)target & ~(uintptr_t)(4096 - 1);
    mprotect((void*)page, 4096 * 2, PROT_READ | PROT_WRITE | PROT_EXEC);

    uint32_t* dst = (uint32_t*)target;

    // сохраняем оригинал (первые 4 инструкции)
    if (orig) {
        // выделяем трамплин (5 инструкций + бранч назад)
        void* tramp = mmap(NULL, 64,
            PROT_READ|PROT_WRITE|PROT_EXEC,
            MAP_PRIVATE|MAP_ANONYMOUS, -1, 0);
        if (!tramp) return false;
        uint32_t* t = (uint32_t*)tramp;
        // копируем 4 инструкции оригинала
        t[0] = dst[0]; t[1] = dst[1]; t[2] = dst[2]; t[3] = dst[3];
        // бранч назад к target+16
        uintptr_t back = (uintptr_t)target + 16;
        (void)back;
        // LDR x16, #8 / BR x16 / <addr64>
        t[4] = 0x58000050; // ldr x16, #8
        t[5] = 0xD61F0200; // br x16
        *((uint64_t*)&t[6]) = (uintptr_t)target + 16;
        __builtin___clear_cache((char*)tramp, (char*)tramp + 64);
        *orig = tramp;
    }

    // пишем хук: LDR x16, #8 / BR x16 / <addr64>
    dst[0] = 0x58000050; // ldr x16, #8
    dst[1] = 0xD61F0200; // br x16
    *((uint64_t*)&dst[2]) = (uint64_t)replace;

    __builtin___clear_cache((char*)target, (char*)target + 16);
    return true;
}

#define HOOK(target, replace, orig) cfHook((void*)(target), (void*)(replace), (void**)(orig))

// ═══════════════════════════════════════════════════════════════════
//  OFFSETS
// ═══════════════════════════════════════════════════════════════════
#define OFF_PC_ARMSCTRL       0x60
#define OFF_PC_PLAYERLOCK     0x68
#define OFF_PC_NETWORK        0x88
#define OFF_PC_ANIMCTRL       0x98
#define OFF_PC_ISDEATH        0xA8

#define OFF_SKEL_HEAD         0xA8
#define OFF_SKEL_CHEST        0xB0
#define OFF_SKEL_PELVIS       0xB8

#define OFF_NET_POSITION      0xBC
#define OFF_NET_CAMPIVOT      0x110

#define OFF_CULL_CONTROLLER   0x18
#define OFF_CULL_OCCLUDED     0x48
#define OFF_CULL_INFRAUSTRUM  0x49

#define OFF_LOCK_PLAYERBODY   0x20
#define OFF_LOCK_ROTATIONX    0x38
#define OFF_LOCK_HIPFOV       0x40

// ═══════════════════════════════════════════════════════════════════
//  TYPES
// ═══════════════════════════════════════════════════════════════════
struct CFVec2  { float x, y; };
struct CFVec3  { float x, y, z; };
struct CFColor { float r, g, b, a; };

struct CFMatrix4x4 {
    float m[4][4];
    CFVec3 MultiplyPoint(CFVec3 v) const {
        CFVec3 r;
        r.x = m[0][0]*v.x + m[0][1]*v.y + m[0][2]*v.z + m[0][3];
        r.y = m[1][0]*v.x + m[1][1]*v.y + m[1][2]*v.z + m[1][3];
        r.z = m[2][0]*v.x + m[2][1]*v.y + m[2][2]*v.z + m[2][3];
        float w = m[3][0]*v.x + m[3][1]*v.y + m[3][2]*v.z + m[3][3];
        if (fabsf(w) > 1e-6f) { r.x/=w; r.y/=w; r.z/=w; }
        return r;
    }
};

// ═══════════════════════════════════════════════════════════════════
//  MEMORY
// ═══════════════════════════════════════════════════════════════════
template<typename T>
static inline T cfRd(uintptr_t a) {
    if (!a) { T z; memset(&z,0,sizeof(z)); return z; }
    return *reinterpret_cast<T*>(a);
}
template<typename T>
static inline void cfWr(uintptr_t a, T v) {
    if (a) *reinterpret_cast<T*>(a) = v;
}
static inline uintptr_t cfPtr(uintptr_t a) { return cfRd<uintptr_t>(a); }

static inline uintptr_t listGet(uintptr_t list, int i) {
    uintptr_t arr = cfPtr(list + 0x10);
    return arr ? cfPtr(arr + 0x20 + (uintptr_t)i * 0x8) : 0;
}
static inline int listCount(uintptr_t list) {
    return list ? cfRd<int>(list + 0x18) : 0;
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
    bool    chamsWireframe;
    bool    aimEnabled;
    float   aimFov;
    int     aimBone;
    bool    aimVisOnly;
    float   aimSmooth;
};
static Config g_cfg;
static void ConfigInit(Config* c) {
    c->espEnabled     = false;
    c->espBox         = true;
    c->espSkeleton    = false;
    c->espVisCheck    = true;
    c->espColorVis    = (CFColor){0.f,1.f,0.f,1.f};
    c->espColorHid    = (CFColor){1.f,0.f,0.f,1.f};
    c->chamsEnabled   = false;
    c->chamsWireframe = false;
    c->aimEnabled     = false;
    c->aimFov         = 80.f;
    c->aimBone        = 0;
    c->aimVisOnly     = true;
    c->aimSmooth      = 6.f;
}

// ═══════════════════════════════════════════════════════════════════
//  IL2CPP
// ═══════════════════════════════════════════════════════════════════
typedef void*       (*t_DomainGet)();
typedef void*       (*t_DomainGetAssemblies)(void*, size_t*);
typedef void*       (*t_AssemblyGetImage)(void*);
typedef size_t      (*t_ImageGetClassCount)(void*);
typedef void*       (*t_ClassFromName)(void*, const char*, const char*);
typedef void*       (*t_ClassGetMethod)(void*, const char*, int);
typedef const void* (*t_MethodGetPtr)(void*);
typedef void*       (*t_ClassGetStaticFields)(void*);

static t_DomainGet            il2_DomainGet;
static t_DomainGetAssemblies  il2_DomainGetAssemblies;
static t_AssemblyGetImage     il2_AssemblyGetImage;
static t_ImageGetClassCount   il2_ImageGetClassCount;
static t_ClassFromName        il2_ClassFromName;
static t_ClassGetMethod       il2_ClassGetMethod;
static t_MethodGetPtr         il2_MethodGetPtr;
static t_ClassGetStaticFields il2_ClassGetStaticFields;

static void* g_mainImage = NULL;

static bool Il2CppInit() {
    void* h = dlopen(NULL, RTLD_NOW);
    if (!h) return false;
#define LD(fn) il2_##fn = (t_##fn)dlsym(h, "il2cpp_" #fn)
    LD(DomainGet); LD(DomainGetAssemblies); LD(AssemblyGetImage);
    LD(ImageGetClassCount); LD(ClassFromName);
    LD(ClassGetMethod); LD(MethodGetPtr); LD(ClassGetStaticFields);
#undef LD
    return il2_DomainGet != NULL;
}

static void* GetMainImage() {
    if (g_mainImage) return g_mainImage;
    size_t cnt = 0;
    void* domain = il2_DomainGet();
    void** asms = (void**)il2_DomainGetAssemblies(domain, &cnt);
    for (size_t i = 0; i < cnt; i++) {
        void* img = il2_AssemblyGetImage(asms[i]);
        if (img && il2_ImageGetClassCount(img) > 2000) {
            g_mainImage = img;
            break;
        }
    }
    return g_mainImage;
}

static uintptr_t FindMethod(void* img, const char* ns,
                             const char* cls, const char* method, int pc) {
    if (!img) return 0;
    void* klass = il2_ClassFromName(img, ns, cls);
    if (!klass) return 0;
    void* m = il2_ClassGetMethod(klass, method, pc);
    if (!m) return 0;
    return (uintptr_t)il2_MethodGetPtr(m);
}

static uintptr_t GetStaticFields(void* img, const char* ns, const char* cls) {
    if (!img || !il2_ClassGetStaticFields) return 0;
    void* klass = il2_ClassFromName(img, ns, cls);
    return klass ? (uintptr_t)il2_ClassGetStaticFields(klass) : 0;
}

// ═══════════════════════════════════════════════════════════════════
//  UNITY CALLS
// ═══════════════════════════════════════════════════════════════════
typedef void (*t_GetPos)(uintptr_t, CFVec3*);
typedef void (*t_GetMatrix)(uintptr_t, CFMatrix4x4*);

static t_GetPos    Transform_get_position = NULL;
static t_GetMatrix Camera_get_proj        = NULL;
static t_GetMatrix Camera_get_w2cam       = NULL;

static CFVec3 GetPos(uintptr_t transform) {
    CFVec3 v;
    memset(&v, 0, sizeof(v));
    if (transform && Transform_get_position)
        Transform_get_position(transform, &v);
    return v;
}

// ═══════════════════════════════════════════════════════════════════
//  CHAMS
// ═══════════════════════════════════════════════════════════════════
typedef void (*t_TWH_SetOnOutline)(uintptr_t);
typedef void (*t_TWH_SetOff)(uintptr_t);
typedef void (*t_WF_SetEnabled)(uintptr_t, bool);
typedef void (*t_WF_CollectPlayers)(uintptr_t);
typedef void (*t_WF_Refresh)(uintptr_t);

static t_TWH_SetOnOutline  TWH_SetOnOutline  = NULL;
static t_TWH_SetOff        TWH_SetOff        = NULL;
static t_WF_SetEnabled     WF_SetEnabled     = NULL;
static t_WF_CollectPlayers WF_CollectPlayers = NULL;
static t_WF_Refresh        WF_Refresh        = NULL;

static uintptr_t g_TWH_instance = 0;
static uintptr_t g_WF_instance  = 0;

static void ApplyChams(bool enable) {
    if (g_cfg.chamsWireframe) {
        if (!g_WF_instance) return;
        if (WF_SetEnabled)               WF_SetEnabled(g_WF_instance, enable);
        if (enable && WF_CollectPlayers) WF_CollectPlayers(g_WF_instance);
        if (enable && WF_Refresh)        WF_Refresh(g_WF_instance);
    } else {
        if (!g_TWH_instance) return;
        if (enable  && TWH_SetOnOutline) TWH_SetOnOutline(g_TWH_instance);
        if (!enable && TWH_SetOff)       TWH_SetOff(g_TWH_instance);
    }
}

// ═══════════════════════════════════════════════════════════════════
//  CAMERA / W2S
// ═══════════════════════════════════════════════════════════════════
static CFMatrix4x4 g_viewProj;
static float       g_sw = 0.f, g_sh = 0.f;
static CFVec2      g_center;

static void UpdateVP(uintptr_t cam) {
    if (!cam) return;
    CFMatrix4x4 proj, w2c;
    memset(&proj, 0, sizeof(proj));
    memset(&w2c,  0, sizeof(w2c));
    if (Camera_get_proj)  Camera_get_proj(cam,  &proj);
    if (Camera_get_w2cam) Camera_get_w2cam(cam, &w2c);
    for (int r = 0; r < 4; r++)
        for (int c = 0; c < 4; c++) {
            g_viewProj.m[r][c] = 0;
            for (int k = 0; k < 4; k++)
                g_viewProj.m[r][c] += proj.m[r][k] * w2c.m[k][c];
        }
}

static bool W2S(CFVec3 world, CFVec2* screen) {
    CFVec3 clip = g_viewProj.MultiplyPoint(world);
    if (clip.z < 0.01f) return false;
    screen->x = (1.f + clip.x) * 0.5f * g_sw;
    screen->y = (1.f - clip.y) * 0.5f * g_sh;
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
static uintptr_t g_localCtrl      = 0;
static CFVec3    g_localPos;
// FILL: GetStaticFields(img,"","PlayerCulling") + 0x8
static uintptr_t g_cullingInstances = 0;

static void UpdatePlayers() {
    g_players.clear();
    if (!g_cullingInstances) return;

    uintptr_t list = cfPtr(g_cullingInstances);
    int count = listCount(list);
    if (count <= 0 || count > 64) return;

    for (int i = 0; i < count; i++) {
        uintptr_t culling = listGet(list, i);
        if (!culling) continue;

        uintptr_t ctrl = cfPtr(culling + OFF_CULL_CONTROLLER);
        if (!ctrl || ctrl == g_localCtrl) continue;

        bool dead = cfRd<bool>(ctrl + OFF_PC_ISDEATH);
        bool occ  = cfRd<bool>(culling + OFF_CULL_OCCLUDED);
        bool frus = cfRd<bool>(culling + OFF_CULL_INFRAUSTRUM);
        if (dead || !frus) continue;

        uintptr_t net = cfPtr(ctrl + OFF_PC_NETWORK);
        if (!net) continue;

        CFVec3 netPos = cfRd<CFVec3>(net + OFF_NET_POSITION);

        uintptr_t animCtrl = cfPtr(ctrl + OFF_PC_ANIMCTRL);
        uintptr_t skel     = animCtrl ? cfPtr(animCtrl + 0x20) : 0;

        CFVec3 headPos, chestPos, pelvisPos;
        memset(&headPos,   0, sizeof(headPos));
        memset(&chestPos,  0, sizeof(chestPos));
        memset(&pelvisPos, 0, sizeof(pelvisPos));

        if (skel) {
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
        p.controller = ctrl; p.network  = net;
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
    if (!g_cfg.aimEnabled || !localCtrl || g_players.empty()) return;

    float bestDist = g_cfg.aimFov;
    const Player* best = NULL;

    for (size_t i = 0; i < g_players.size(); i++) {
        const Player& p = g_players[i];
        if (g_cfg.aimVisOnly && p.occluded) continue;
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
    if (!lock) return;

    float hipFov = cfRd<float>(lock + OFF_LOCK_HIPFOV);
    if (hipFov < 1.f) hipFov = 60.f;

    float curX = cfRd<float>(lock + OFF_LOCK_ROTATIONX);
    cfWr<float>(lock + OFF_LOCK_ROTATIONX, curX + (-dy * (hipFov / g_sh)));
    // горизонталь: FILL eulerAngles на _playerBody
}

// ═══════════════════════════════════════════════════════════════════
//  ESP VIEW
// ═══════════════════════════════════════════════════════════════════
@interface CFESPView : UIView
@end
@implementation CFESPView
- (instancetype)initWithFrame:(CGRect)f {
    self = [super initWithFrame:f];
    self.backgroundColor = [UIColor clearColor];
    self.userInteractionEnabled = NO;
    return self;
}
- (void)drawRect:(CGRect)__unused rect {
    if (!g_cfg.espEnabled) return;
    CGContextRef ctx = UIGraphicsGetCurrentContext();
    if (!ctx) return;
    CGContextSetLineWidth(ctx, 1.5f);

    for (size_t i = 0; i < g_players.size(); i++) {
        const Player& p = g_players[i];
        CFColor c = (p.occluded && g_cfg.espVisCheck)
                    ? g_cfg.espColorHid : g_cfg.espColorVis;
        CGContextSetRGBStrokeColor(ctx, c.r, c.g, c.b, c.a);

        if (g_cfg.espBox && p.headOnS && p.pelvisOnS) {
            float h = p.botS.y - p.topS.y;
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
    if (g_cfg.aimEnabled) {
        CGContextSetRGBStrokeColor(ctx, 1, 1, 0, 0.5f);
        CGContextSetLineWidth(ctx, 1.f);
        CGContextStrokeEllipseInRect(ctx,
            CGRectMake(g_center.x - g_cfg.aimFov,
                       g_center.y - g_cfg.aimFov,
                       g_cfg.aimFov * 2, g_cfg.aimFov * 2));
    }
}
@end

// ═══════════════════════════════════════════════════════════════════
//  MENU
// ═══════════════════════════════════════════════════════════════════
@interface CFMenu : UIView
@property (nonatomic, strong) UIScrollView* panel;
@property (nonatomic, assign) CGPoint panStart;
@property (nonatomic, assign) CGPoint originStart;
@end

@implementation CFMenu {
    CGFloat _y;
}
- (instancetype)init {
    self = [super initWithFrame:CGRectMake(10, 100, 44, 44)];
    self.backgroundColor = [UIColor clearColor];

    UIButton* btn = [UIButton buttonWithType:UIButtonTypeCustom];
    btn.frame = CGRectMake(0, 0, 44, 44);
    [btn setTitle:@"\u2630" forState:UIControlStateNormal];
    btn.titleLabel.font = [UIFont systemFontOfSize:22];
    [btn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    btn.backgroundColor = [UIColor colorWithRed:.05f green:.05f blue:.1f alpha:.9f];
    btn.layer.cornerRadius = 8;
    btn.layer.borderWidth  = 1;
    btn.layer.borderColor  = [UIColor colorWithWhite:.3f alpha:1].CGColor;
    [btn addTarget:self action:@selector(toggle)
  forControlEvents:UIControlEventTouchUpInside];
    [self addSubview:btn];

    _panel = [[UIScrollView alloc] initWithFrame:CGRectMake(50, 0, 270, 420)];
    _panel.backgroundColor    = [UIColor colorWithRed:.06f green:.06f blue:.1f alpha:.93f];
    _panel.layer.cornerRadius = 10;
    _panel.layer.borderWidth  = 1;
    _panel.layer.borderColor  =
        [UIColor colorWithRed:.2f green:.4f blue:.8f alpha:.8f].CGColor;
    _panel.hidden = YES;
    [self addSubview:_panel];

    [self buildUI];

    UIPanGestureRecognizer* pan =
        [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(drag:)];
    [btn addGestureRecognizer:pan];
    return self;
}
- (void)toggle { _panel.hidden = !_panel.hidden; }
- (void)drag:(UIPanGestureRecognizer*)gr {
    if (gr.state == UIGestureRecognizerStateBegan) {
        _panStart    = [gr locationInView:self.superview];
        _originStart = self.frame.origin;
    } else if (gr.state == UIGestureRecognizerStateChanged) {
        CGPoint p = [gr locationInView:self.superview];
        CGRect  f = self.frame;
        f.origin.x = _originStart.x + p.x - _panStart.x;
        f.origin.y = _originStart.y + p.y - _panStart.y;
        self.frame = f;
    }
}
- (void)section:(NSString*)title {
    UILabel* l = [[UILabel alloc] initWithFrame:CGRectMake(10, _y, 250, 18)];
    l.text = title;
    l.textColor = [UIColor colorWithRed:.3f green:.7f blue:1 alpha:1];
    l.font = [UIFont boldSystemFontOfSize:11];
    [_panel addSubview:l];
    _y += 22;
}
- (void)row:(NSString*)title val:(BOOL)v sel:(SEL)s {
    UILabel* l = [[UILabel alloc] initWithFrame:CGRectMake(10, _y+3, 190, 20)];
    l.text = title; l.textColor = [UIColor whiteColor];
    l.font = [UIFont systemFontOfSize:13];
    [_panel addSubview:l];
    UISwitch* sw = [[UISwitch alloc] initWithFrame:CGRectMake(200, _y, 51, 31)];
    sw.transform = CGAffineTransformMakeScale(0.78f, 0.78f);
    sw.on = v;
    [sw addTarget:self action:s forControlEvents:UIControlEventValueChanged];
    [_panel addSubview:sw];
    _y += 36;
}
- (void)slider:(NSString*)title min:(float)mn max:(float)mx
           val:(float)v sel:(SEL)s tag:(NSInteger)tag {
    UILabel* l = [[UILabel alloc] initWithFrame:CGRectMake(10, _y, 250, 16)];
    l.text = [NSString stringWithFormat:@"%@ : %.0f", title, v];
    l.textColor = [UIColor lightGrayColor];
    l.font = [UIFont systemFontOfSize:11];
    l.tag = tag;
    [_panel addSubview:l];
    _y += 18;
    UISlider* sl = [[UISlider alloc] initWithFrame:CGRectMake(10, _y, 250, 26)];
    sl.minimumValue = mn; sl.maximumValue = mx; sl.value = v;
    sl.tintColor = [UIColor colorWithRed:.2f green:.5f blue:1 alpha:1];
    sl.tag = tag;
    [sl addTarget:self action:s forControlEvents:UIControlEventValueChanged];
    [_panel addSubview:sl];
    _y += 32;
}
- (void)buildUI {
    _y = 10;
    [self section:@"\u2500\u2500\u2500 ESP \u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500"];
    [self row:@"ESP"       val:(BOOL)g_cfg.espEnabled  sel:@selector(onESP:)];
    [self row:@"Box"       val:(BOOL)g_cfg.espBox      sel:@selector(onBox:)];
    [self row:@"Skeleton"  val:(BOOL)g_cfg.espSkeleton sel:@selector(onSkel:)];
    [self row:@"Vis check" val:(BOOL)g_cfg.espVisCheck sel:@selector(onVis:)];
    [self section:@"\u2500\u2500\u2500 CHAMS \u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500"];
    [self row:@"Chams"     val:(BOOL)g_cfg.chamsEnabled    sel:@selector(onChams:)];
    [self row:@"Wireframe" val:(BOOL)g_cfg.chamsWireframe  sel:@selector(onWF:)];
    [self section:@"\u2500\u2500\u2500 AIMBOT \u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500"];
    [self row:@"Aimbot"    val:(BOOL)g_cfg.aimEnabled  sel:@selector(onAim:)];
    [self row:@"\u0422\u043e\u043b\u044c\u043a\u043e \u0432\u0438\u0434\u0438\u043c\u044b\u0435"
              val:(BOOL)g_cfg.aimVisOnly sel:@selector(onAimVis:)];
    [self slider:@"FOV"    min:10 max:350 val:g_cfg.aimFov    sel:@selector(onFov:)    tag:100];
    [self slider:@"Smooth" min:1  max:25  val:g_cfg.aimSmooth sel:@selector(onSmooth:) tag:101];

    UILabel* bl = [[UILabel alloc] initWithFrame:CGRectMake(10, _y, 250, 16)];
    bl.text = @"\u0426\u0435\u043b\u044c";
    bl.textColor = [UIColor lightGrayColor];
    bl.font = [UIFont systemFontOfSize:11];
    [_panel addSubview:bl];
    _y += 18;

    NSArray* items = @[@"\u0413\u043e\u043b\u043e\u0432\u0430",
                       @"\u0413\u0440\u0443\u0434\u044c",
                       @"\u0422\u0430\u0437"];
    UISegmentedControl* sc = [[UISegmentedControl alloc] initWithItems:items];
    sc.frame = CGRectMake(10, _y, 250, 28);
    sc.selectedSegmentIndex = g_cfg.aimBone;
    [sc addTarget:self action:@selector(onBone:)
 forControlEvents:UIControlEventValueChanged];
    [_panel addSubview:sc];
    _y += 36;

    _panel.contentSize = CGSizeMake(270, _y + 16);
}
- (void)onESP:(UISwitch*)s    { g_cfg.espEnabled    = s.on; }
- (void)onBox:(UISwitch*)s    { g_cfg.espBox        = s.on; }
- (void)onSkel:(UISwitch*)s   { g_cfg.espSkeleton   = s.on; }
- (void)onVis:(UISwitch*)s    { g_cfg.espVisCheck   = s.on; }
- (void)onChams:(UISwitch*)s  { g_cfg.chamsEnabled  = s.on; ApplyChams(s.on); }
- (void)onWF:(UISwitch*)s     { g_cfg.chamsWireframe= s.on; ApplyChams(g_cfg.chamsEnabled); }
- (void)onAim:(UISwitch*)s    { g_cfg.aimEnabled    = s.on; }
- (void)onAimVis:(UISwitch*)s { g_cfg.aimVisOnly    = s.on; }
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
//  HOOKS
// ═══════════════════════════════════════════════════════════════════
static CFESPView* g_espView = nil;
static CFMenu*    g_menu    = nil;
static uintptr_t  g_mainCam = 0;

typedef void (*t_OnPreRender)(uintptr_t);
static t_OnPreRender orig_OnPreRender = NULL;
static void Hook_OnPreRender(uintptr_t thiz) {
    orig_OnPreRender(thiz);
    if (!g_mainCam) g_mainCam = thiz;
    if (thiz != g_mainCam) return;
    UpdateVP(thiz);
    if (g_localCtrl) {
        uintptr_t net = cfPtr(g_localCtrl + OFF_PC_NETWORK);
        if (net) g_localPos = cfRd<CFVec3>(net + OFF_NET_POSITION);
    }
    UpdatePlayers();
    DoAimbot(g_localCtrl);
    dispatch_async(dispatch_get_main_queue(), ^{ [g_espView setNeedsDisplay]; });
}

typedef void (*t_Awake)(uintptr_t);
static t_Awake orig_TWH_Awake = NULL;
static t_Awake orig_WF_Awake  = NULL;
static t_Awake orig_PCAwake   = NULL;

static void Hook_TWH_Awake(uintptr_t thiz) { orig_TWH_Awake(thiz); g_TWH_instance = thiz; }
static void Hook_WF_Awake(uintptr_t  thiz) { orig_WF_Awake(thiz);  g_WF_instance  = thiz; }
static void Hook_PCAwake(uintptr_t   thiz) {
    orig_PCAwake(thiz);
    // FILL: фильтр PhotonView.IsMine
    if (!g_localCtrl) g_localCtrl = thiz;
}

// ═══════════════════════════════════════════════════════════════════
//  UIWindow helper — iOS 13+ совместимо
// ═══════════════════════════════════════════════════════════════════
static UIWindow* GetKeyWindow() {
    if (@available(iOS 13.0, *)) {
        for (UIWindowScene* scene in [UIApplication sharedApplication].connectedScenes) {
            if (scene.activationState == UISceneActivationStateForegroundActive) {
                for (UIWindow* w in scene.windows) {
                    if (w.isKeyWindow) return w;
                }
            }
        }
    }
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    return [UIApplication sharedApplication].keyWindow;
#pragma clang diagnostic pop
}

// ═══════════════════════════════════════════════════════════════════
//  INIT
// ═══════════════════════════════════════════════════════════════════
static void Init() {
    ConfigInit(&g_cfg);
    memset(&g_localPos, 0, sizeof(g_localPos));
    memset(&g_viewProj, 0, sizeof(g_viewProj));
    memset(&g_center,   0, sizeof(g_center));

    if (!Il2CppInit()) return;
    void* img = GetMainImage();
    if (!img) return;

    uintptr_t a;

    a = FindMethod(img, "UnityEngine", "Transform", "get_position_Injected", 1);
    Transform_get_position = (t_GetPos)a;

    a = FindMethod(img, "UnityEngine", "Camera", "get_projectionMatrix_Injected", 1);
    Camera_get_proj = (t_GetMatrix)a;

    a = FindMethod(img, "UnityEngine", "Camera", "get_worldToCameraMatrix_Injected", 1);
    Camera_get_w2cam = (t_GetMatrix)a;

    a = FindMethod(img, "", "TournamentWallHack", "SetOnOutline", 0);
    TWH_SetOnOutline = (t_TWH_SetOnOutline)a;

    a = FindMethod(img, "", "TournamentWallHack", "SetOff", 0);
    TWH_SetOff = (t_TWH_SetOff)a;

    a = FindMethod(img, "", "WireframeWallhack", "SetEnabled", 1);
    WF_SetEnabled = (t_WF_SetEnabled)a;

    a = FindMethod(img, "", "WireframeWallhack", "CollectPlayers", 0);
    WF_CollectPlayers = (t_WF_CollectPlayers)a;

    a = FindMethod(img, "", "WireframeWallhack", "Refresh", 0);
    WF_Refresh = (t_WF_Refresh)a;

    a = FindMethod(img, "UnityEngine", "Camera", "OnPreRender", 0);
    if (a) HOOK(a, Hook_OnPreRender, &orig_OnPreRender);

    a = FindMethod(img, "", "TournamentWallHack", "Awake", 0);
    if (a) HOOK(a, Hook_TWH_Awake, &orig_TWH_Awake);

    a = FindMethod(img, "", "WireframeWallhack", "Awake", 0);
    if (a) HOOK(a, Hook_WF_Awake, &orig_WF_Awake);

    a = FindMethod(img, "", "PlayerController", "Awake", 0);
    if (a) HOOK(a, Hook_PCAwake, &orig_PCAwake);

    // PlayerCulling.Instances — раскомментить после проверки оффсета:
    // uintptr_t sf = GetStaticFields(img, "", "PlayerCulling");
    // if (sf) g_cullingInstances = sf + 0x8;

    dispatch_async(dispatch_get_main_queue(), ^{
        UIWindow* win = GetKeyWindow(); // ← фикс: было .keyWindow напрямую
        if (!win) return;
        CGRect s = [UIScreen mainScreen].bounds;
        g_sw = (float)s.size.width;
        g_sh = (float)s.size.height;
        g_center.x = g_sw * 0.5f;
        g_center.y = g_sh * 0.5f;

        g_espView = [[CFESPView alloc] initWithFrame:s];
        [win addSubview:g_espView];
        g_menu = [[CFMenu alloc] init];
        [win addSubview:g_menu];
    });
}

__attribute__((constructor))
static void Entry() {
    dispatch_after(
        dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3.0 * NSEC_PER_SEC)),
        dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0),
        ^{ Init(); }
    );
}
