#import <UIKit/UIKit.h>
#import <CoreGraphics/CoreGraphics.h>
#ifdef __cplusplus
extern "C" {
#endif
extern void MSHookFunction(void* symbol, void* replace, void** result) __attribute__((weak_import));
#ifdef __cplusplus
}
#endif
#include <dlfcn.h>
#include <vector>
#include <cmath>
#include <string>

// ═══════════════════════════════════════════════════════════════════
//  OFFSETS
// ═══════════════════════════════════════════════════════════════════
#define OFF_PC_FPSCAMERA      0x28
#define OFF_PC_MAINCAMERA     0x30
#define OFF_PC_MOVEMENT       0x40
#define OFF_PC_ARMSCTRL       0x60
#define OFF_PC_PLAYERLOCK     0x68
#define OFF_PC_NETWORK        0x88
#define OFF_PC_ANIMCTRL       0x98
#define OFF_PC_MATMANAGER     0xA0
#define OFF_PC_ISDEATH        0xA8

#define OFF_SKEL_RENDERERS    0x70
#define OFF_SKEL_HEAD         0xA8
#define OFF_SKEL_CHEST        0xB0
#define OFF_SKEL_PELVIS       0xB8
#define OFF_SKEL_LARM         0xC0
#define OFF_SKEL_RARM         0xC8
#define OFF_SKEL_LTHIGH       0xD0
#define OFF_SKEL_RTHIGH       0xD8
#define OFF_SKEL_HITBOXOPEN   0x169

#define OFF_NET_POSITION      0xBC
#define OFF_NET_ROTATION      0xC8
#define OFF_NET_VELOCITY      0xF8
#define OFF_NET_VIEWVERT      0x10C
#define OFF_NET_CAMPIVOT      0x110

#define OFF_CULL_CONTROLLER   0x18
#define OFF_CULL_NETWORK      0x20
#define OFF_CULL_OCCLUDED     0x48
#define OFF_CULL_INFRAUSTRUM  0x49

#define OFF_LOCK_PLAYERBODY   0x20
#define OFF_LOCK_ROTATIONX    0x38
#define OFF_LOCK_HIPFOV       0x40

#define OFF_ARMS_CANFIRE      0x13D
#define OFF_ARMS_ISRELOAD     0x13E
#define OFF_ARMS_MAINCAMTRANS 0xF8

#define OFF_TWH_RENDERERS     0x28
#define OFF_TWH_ISENABLED     0x30
#define OFF_WF_ENABLED        0x54

// ═══════════════════════════════════════════════════════════════════
//  TYPES
// ═══════════════════════════════════════════════════════════════════
struct Vec2  { float x, y; };
struct Vec3  { float x, y, z; };
struct Vec4  { float x, y, z, w; };
struct Quat  { float x, y, z, w; };
struct Color { float r, g, b, a; };

struct Matrix4x4 {
    float m[4][4];
    Vec3 MultiplyPoint(Vec3 v) const {
        Vec3 r;
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
template<typename T> static inline T Rd(uintptr_t a) {
    if (!a) return T{};
    return *reinterpret_cast<T*>(a);
}
template<typename T> static inline void Wr(uintptr_t a, T v) {
    if (!a) return;
    *reinterpret_cast<T*>(a) = v;
}
static inline uintptr_t Ptr(uintptr_t a) { return Rd<uintptr_t>(a); }

static inline uintptr_t ListGet(uintptr_t list, int i) {
    uintptr_t arr = Ptr(list + 0x10);
    return arr ? Ptr(arr + 0x20 + i * 0x8) : 0;
}
static inline int ListCount(uintptr_t list) {
    return list ? Rd<int>(list + 0x18) : 0;
}

static inline float Vec3Dist(Vec3 a, Vec3 b) {
    float dx=a.x-b.x, dy=a.y-b.y, dz=a.z-b.z;
    return sqrtf(dx*dx+dy*dy+dz*dz);
}
static inline float Vec2Dist(Vec2 a, Vec2 b) {
    float dx=a.x-b.x, dy=a.y-b.y;
    return sqrtf(dx*dx+dy*dy);
}

// ═══════════════════════════════════════════════════════════════════
//  CONFIG
// ═══════════════════════════════════════════════════════════════════
struct Config {
    bool  espEnabled    = false;
    bool  espBox        = true;
    bool  espSkeleton   = false;
    bool  espVisCheck   = true;
    Color espColorVis   = {0.f, 1.f, 0.f, 1.f};
    Color espColorHid   = {1.f, 0.f, 0.f, 1.f};

    bool  chamsEnabled  = false;
    bool  chamsWireframe= false;

    bool  aimEnabled    = false;
    float aimFov        = 80.f;
    int   aimBone       = 0;     // 0=голова 1=грудь 2=таз
    bool  aimVisOnly    = true;
    float aimSmooth     = 6.f;
} g_cfg;

// ═══════════════════════════════════════════════════════════════════
//  IL2CPP API
// ═══════════════════════════════════════════════════════════════════
typedef void*       (*t_DomainGet)();
typedef void*       (*t_DomainGetAssemblies)(void*, size_t*);
typedef void*       (*t_AssemblyGetImage)(void*);
typedef size_t      (*t_ImageGetClassCount)(void*);
typedef void*       (*t_ImageGetClass)(void*, size_t);
typedef const char* (*t_ClassGetName)(void*);
typedef void*       (*t_ClassFromName)(void*, const char*, const char*);
typedef void*       (*t_ClassGetMethod)(void*, const char*, int);
typedef const void* (*t_MethodGetPtr)(void*);
typedef void*       (*t_ClassGetStaticFields)(void*);

static t_DomainGet             il2_DomainGet;
static t_DomainGetAssemblies   il2_DomainGetAssemblies;
static t_AssemblyGetImage      il2_AssemblyGetImage;
static t_ImageGetClassCount    il2_ImageGetClassCount;
static t_ImageGetClass         il2_ImageGetClass;
static t_ClassGetName          il2_ClassGetName;
static t_ClassFromName         il2_ClassFromName;
static t_ClassGetMethod        il2_ClassGetMethod;
static t_MethodGetPtr          il2_MethodGetPtr;
static t_ClassGetStaticFields  il2_ClassGetStaticFields;

static void* g_mainImage = nullptr;

static bool Il2CppInit() {
    void* h = dlopen(NULL, RTLD_NOW);
    if (!h) return false;
#define LD(fn) il2_##fn = (decltype(il2_##fn))dlsym(h, "il2cpp_" #fn)
    LD(DomainGet); LD(DomainGetAssemblies); LD(AssemblyGetImage);
    LD(ImageGetClassCount); LD(ImageGetClass); LD(ClassGetName);
    LD(ClassFromName); LD(ClassGetMethod); LD(MethodGetPtr);
    LD(ClassGetStaticFields);
#undef LD
    return il2_DomainGet != nullptr;
}

static void* GetMainImage() {
    if (g_mainImage) return g_mainImage;
    size_t cnt = 0;
    void* domain = il2_DomainGet();
    void** asms = (void**)il2_DomainGetAssemblies(domain, &cnt);
    for (size_t i = 0; i < cnt; i++) {
        void* img = il2_AssemblyGetImage(asms[i]);
        if (img && il2_ImageGetClassCount(img) > 2000)
            { g_mainImage = img; break; }
    }
    return g_mainImage;
}

static uintptr_t FindMethod(void* img, const char* ns,
                             const char* cls, const char* method, int pc = -1) {
    if (!img) return 0;
    void* klass = il2_ClassFromName(img, ns, cls);
    if (!klass) return 0;
    void* m = il2_ClassGetMethod(klass, method, pc);
    if (!m) return 0;
    return (uintptr_t)il2_MethodGetPtr(m);
}

// статические поля класса
static uintptr_t GetStaticFields(void* img, const char* ns, const char* cls) {
    if (!img || !il2_ClassGetStaticFields) return 0;
    void* klass = il2_ClassFromName(img, ns, cls);
    if (!klass) return 0;
    return (uintptr_t)il2_ClassGetStaticFields(klass);
}

// ═══════════════════════════════════════════════════════════════════
//  UNITY CALLS
// ═══════════════════════════════════════════════════════════════════
typedef void (*t_GetPos)(uintptr_t, Vec3*);
typedef void (*t_SetEuler)(uintptr_t, Vec4*);  // Injected принимает Vec4
typedef void (*t_GetMatrix)(uintptr_t, Matrix4x4*);

static t_GetPos    Transform_get_position  = nullptr;
static t_SetEuler  Transform_set_eulerAngles = nullptr;
static t_GetMatrix Camera_get_proj         = nullptr;
static t_GetMatrix Camera_get_w2cam        = nullptr;

static Vec3 GetPos(uintptr_t transform) {
    Vec3 v{};
    if (transform && Transform_get_position)
        Transform_get_position(transform, &v);
    return v;
}

// ═══════════════════════════════════════════════════════════════════
//  CHAMS API
// ═══════════════════════════════════════════════════════════════════
typedef void (*t_TWH_SetOnOutline)(uintptr_t);
typedef void (*t_TWH_SetOff)(uintptr_t);
typedef void (*t_WF_SetEnabled)(uintptr_t, bool);
typedef void (*t_WF_CollectPlayers)(uintptr_t);
typedef void (*t_WF_Refresh)(uintptr_t);

static t_TWH_SetOnOutline  TWH_SetOnOutline  = nullptr;
static t_TWH_SetOff        TWH_SetOff        = nullptr;
static t_WF_SetEnabled     WF_SetEnabled     = nullptr;
static t_WF_CollectPlayers WF_CollectPlayers = nullptr;
static t_WF_Refresh        WF_Refresh        = nullptr;

// FILL: найти singleton через static field или хук Awake
static uintptr_t g_TWH_instance = 0;
static uintptr_t g_WF_instance  = 0;

static void ApplyChams(bool enable) {
    if (g_cfg.chamsWireframe) {
        if (!g_WF_instance) return;
        if (WF_SetEnabled)     WF_SetEnabled(g_WF_instance, enable);
        if (enable && WF_CollectPlayers) WF_CollectPlayers(g_WF_instance);
        if (enable && WF_Refresh)        WF_Refresh(g_WF_instance);
    } else {
        if (!g_TWH_instance) return;
        if (enable && TWH_SetOnOutline) TWH_SetOnOutline(g_TWH_instance);
        else if (!enable && TWH_SetOff) TWH_SetOff(g_TWH_instance);
    }
}

// ═══════════════════════════════════════════════════════════════════
//  CAMERA + W2S
// ═══════════════════════════════════════════════════════════════════
static Matrix4x4 g_viewProj{};
static float     g_sw = 0, g_sh = 0;
static Vec2      g_center{};

static void UpdateVP(uintptr_t cam) {
    if (!cam) return;
    Matrix4x4 proj{}, w2c{};
    if (Camera_get_proj)  Camera_get_proj(cam, &proj);
    if (Camera_get_w2cam) Camera_get_w2cam(cam, &w2c);
    Matrix4x4& vp = g_viewProj;
    for (int r = 0; r < 4; r++)
        for (int c = 0; c < 4; c++) {
            vp.m[r][c] = 0;
            for (int k = 0; k < 4; k++)
                vp.m[r][c] += proj.m[r][k] * w2c.m[k][c];
        }
}

static bool W2S(Vec3 world, Vec2& screen) {
    Vec3 clip = g_viewProj.MultiplyPoint(world);
    if (clip.z < 0.01f) return false;
    screen.x = (1.f + clip.x) * 0.5f * g_sw;
    screen.y = (1.f - clip.y) * 0.5f * g_sh;
    return true;
}

// ═══════════════════════════════════════════════════════════════════
//  PLAYER DATA
// ═══════════════════════════════════════════════════════════════════
struct Player {
    uintptr_t controller, network, culling, skeleton;
    Vec3  headPos, chestPos, pelvisPos, netPos;
    Vec2  headS, chestS, pelvisS, topS, botS;
    bool  headOnS, chestOnS, pelvisOnS;
    bool  isDead, occluded, inFrustum;
    float dist;
};

static std::vector<Player> g_players;
static uintptr_t g_localCtrl = 0;
static Vec3      g_localPos{};

// FILL: il2cpp_class_get_static_field_data(PlayerCulling) + 0x8 = List<PlayerCulling>
static uintptr_t g_cullingInstances = 0;

static void UpdatePlayers() {
    g_players.clear();
    if (!g_cullingInstances) return;

    uintptr_t list = Ptr(g_cullingInstances);
    int count = ListCount(list);
    if (count <= 0 || count > 64) return;

    for (int i = 0; i < count; i++) {
        uintptr_t culling = ListGet(list, i);
        if (!culling) continue;

        uintptr_t ctrl = Ptr(culling + OFF_CULL_CONTROLLER);
        if (!ctrl || ctrl == g_localCtrl) continue;

        bool dead = Rd<bool>(ctrl + OFF_PC_ISDEATH);
        bool occ  = Rd<bool>(culling + OFF_CULL_OCCLUDED);
        bool frus = Rd<bool>(culling + OFF_CULL_INFRAUSTRUM);

        uintptr_t net = Ptr(ctrl + OFF_PC_NETWORK);
        if (!net) continue;

        Vec3 netPos = Rd<Vec3>(net + OFF_NET_POSITION);

        // скелет: animCtrl → skeleton (оффсет 0x20 — FILL если не совпадёт)
        uintptr_t animCtrl = Ptr(ctrl + OFF_PC_ANIMCTRL);
        uintptr_t skel     = animCtrl ? Ptr(animCtrl + 0x20) : 0;

        Vec3 headPos{}, chestPos{}, pelvisPos{};
        if (skel) {
            headPos   = GetPos(Ptr(skel + OFF_SKEL_HEAD));
            chestPos  = GetPos(Ptr(skel + OFF_SKEL_CHEST));
            pelvisPos = GetPos(Ptr(skel + OFF_SKEL_PELVIS));
        } else {
            // fallback: networkPosition + камера-пивот
            Vec3 pivot = Rd<Vec3>(net + OFF_NET_CAMPIVOT);
            headPos = { netPos.x + pivot.x, netPos.y + pivot.y, netPos.z + pivot.z };
            chestPos = netPos; chestPos.y += 1.0f;
            pelvisPos = netPos; pelvisPos.y += 0.5f;
        }

        if (dead || !frus) continue;

        Player p{};
        p.controller = ctrl; p.network = net;
        p.culling = culling; p.skeleton = skel;
        p.isDead = dead; p.occluded = occ; p.inFrustum = frus;
        p.headPos = headPos; p.chestPos = chestPos;
        p.pelvisPos = pelvisPos; p.netPos = netPos;
        p.dist = Vec3Dist(g_localPos, netPos);

        p.headOnS   = W2S(headPos,   p.headS);
        p.chestOnS  = W2S(chestPos,  p.chestS);
        p.pelvisOnS = W2S(pelvisPos, p.pelvisS);

        Vec3 bot = netPos; bot.y -= 0.2f;
        W2S(headPos, p.topS);
        W2S(bot,     p.botS);

        g_players.push_back(p);
    }
}

// ═══════════════════════════════════════════════════════════════════
//  AIMBOT
// ═══════════════════════════════════════════════════════════════════
static void DoAimbot(uintptr_t localCtrl) {
    if (!g_cfg.aimEnabled || !localCtrl) return;
    if (g_players.empty()) return;

    float bestDist = g_cfg.aimFov;
    const Player* best = nullptr;

    for (auto& p : g_players) {
        if (g_cfg.aimVisOnly && p.occluded) continue;
        Vec2 tgt{};
        switch (g_cfg.aimBone) {
            case 0: tgt = p.headS;   break;
            case 1: tgt = p.chestS;  break;
            case 2: tgt = p.pelvisS; break;
            default: tgt = p.headS;
        }
        float d = Vec2Dist(tgt, g_center);
        if (d < bestDist) { bestDist = d; best = &p; }
    }
    if (!best) return;

    Vec2 tgt{};
    switch (g_cfg.aimBone) {
        case 0: tgt = best->headS;   break;
        case 1: tgt = best->chestS;  break;
        case 2: tgt = best->pelvisS; break;
        default: tgt = best->headS;
    }

    float dx = (tgt.x - g_center.x) / g_cfg.aimSmooth;
    float dy = (tgt.y - g_center.y) / g_cfg.aimSmooth;

    uintptr_t lock = Ptr(localCtrl + OFF_PC_PLAYERLOCK);
    if (!lock) return;

    float hipFov = Rd<float>(lock + OFF_LOCK_HIPFOV);
    if (hipFov < 1.f) hipFov = 60.f;

    float curX = Rd<float>(lock + OFF_LOCK_ROTATIONX);
    float dAngleX = -dy * (hipFov / g_sh);
    Wr<float>(lock + OFF_LOCK_ROTATIONX, curX + dAngleX);

    // горизонталь: playerBody transform eulerAngles.y
    uintptr_t body = Ptr(lock + OFF_LOCK_PLAYERBODY);
    if (body && Transform_set_eulerAngles) {
        // читаем текущий euler через GetEulerAngles_Injected
        // FILL: нужен адрес Transform_get_eulerAngles_Injected — добавить аналогично get_position
        // пока: прямая запись через Vec4 (w=ignored)
        // float dAngleY = dx * (hipFov / g_sw);
        // Vec4 euler = { 0, currentY + dAngleY, 0, 0 };
        // Transform_set_eulerAngles(body, &euler);
    }
}

// ═══════════════════════════════════════════════════════════════════
//  ESP OVERLAY
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
- (void)drawRect:(CGRect)rect {
    if (!g_cfg.espEnabled) return;
    CGContextRef ctx = UIGraphicsGetCurrentContext();
    if (!ctx) return;
    CGContextSetLineWidth(ctx, 1.5f);

    for (auto& p : g_players) {
        Color c = (p.occluded && g_cfg.espVisCheck) ? g_cfg.espColorHid : g_cfg.espColorVis;
        CGContextSetRGBStrokeColor(ctx, c.r, c.g, c.b, c.a);

        // box
        if (g_cfg.espBox && p.headOnS && p.pelvisOnS) {
            float h = p.botS.y - p.topS.y;
            float w = h * 0.45f;
            CGContextStrokeRect(ctx,
                CGRectMake(p.topS.x - w*0.5f, p.topS.y, w, h));
        }

        // skeleton
        if (g_cfg.espSkeleton) {
            auto ln = [&](Vec2 a, Vec2 b) {
                CGContextMoveToPoint(ctx, a.x, a.y);
                CGContextAddLineToPoint(ctx, b.x, b.y);
                CGContextStrokePath(ctx);
            };
            if (p.headOnS  && p.chestOnS)  ln(p.headS,  p.chestS);
            if (p.chestOnS && p.pelvisOnS) ln(p.chestS, p.pelvisS);
        }
    }

    // FOV circle
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
@property (nonatomic, assign) CGPoint panStart, originStart;
@end

@implementation CFMenu {
    CGFloat _y;
}

- (instancetype)init {
    self = [super initWithFrame:CGRectMake(10, 100, 44, 44)];
    self.backgroundColor = [UIColor clearColor];

    UIButton* btn = [UIButton buttonWithType:UIButtonTypeCustom];
    btn.frame = CGRectMake(0, 0, 44, 44);
    [btn setTitle:@"☰" forState:UIControlStateNormal];
    btn.titleLabel.font = [UIFont systemFontOfSize:22];
    [btn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    btn.backgroundColor = [UIColor colorWithRed:.05 green:.05 blue:.1 alpha:.9f];
    btn.layer.cornerRadius = 8;
    btn.layer.borderWidth = 1;
    btn.layer.borderColor = [UIColor colorWithWhite:.3 alpha:1].CGColor;
    [btn addTarget:self action:@selector(toggle) forControlEvents:UIControlEventTouchUpInside];
    [self addSubview:btn];

    _panel = [[UIScrollView alloc] initWithFrame:CGRectMake(50, 0, 270, 400)];
    _panel.backgroundColor = [UIColor colorWithRed:.06 green:.06 blue:.1 alpha:.93f];
    _panel.layer.cornerRadius = 10;
    _panel.layer.borderWidth = 1;
    _panel.layer.borderColor = [UIColor colorWithRed:.2 green:.4 blue:.8 alpha:.8f].CGColor;
    _panel.hidden = YES;
    [self addSubview:_panel];

    [self buildUI];

    UIPanGestureRecognizer* pan = [[UIPanGestureRecognizer alloc]
        initWithTarget:self action:@selector(drag:)];
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
        CGRect f  = self.frame;
        f.origin.x = _originStart.x + p.x - _panStart.x;
        f.origin.y = _originStart.y + p.y - _panStart.y;
        self.frame = f;
    }
}

// ── UI helpers ───────────────────────────────────────────────────
- (void)section:(NSString*)title {
    UILabel* l = [[UILabel alloc] initWithFrame:CGRectMake(10, _y, 250, 18)];
    l.text      = title;
    l.textColor = [UIColor colorWithRed:.3 green:.7 blue:1 alpha:1];
    l.font      = [UIFont boldSystemFontOfSize:11];
    [_panel addSubview:l];
    _y += 22;
}

- (UISwitch*)row:(NSString*)title val:(BOOL)v sel:(SEL)s {
    UILabel* l = [[UILabel alloc] initWithFrame:CGRectMake(10, _y+3, 190, 20)];
    l.text      = title;
    l.textColor = [UIColor whiteColor];
    l.font      = [UIFont systemFontOfSize:13];
    [_panel addSubview:l];

    UISwitch* sw = [[UISwitch alloc] initWithFrame:CGRectMake(200, _y, 51, 31)];
    sw.transform = CGAffineTransformMakeScale(0.78, 0.78);
    sw.on = v;
    [sw addTarget:self action:s forControlEvents:UIControlEventValueChanged];
    [_panel addSubview:sw];
    _y += 36;
    return sw;
}

- (UISlider*)slider:(NSString*)title min:(float)mn max:(float)mx
               val:(float)v sel:(SEL)s tag:(NSInteger)tag {
    UILabel* l = [[UILabel alloc] initWithFrame:CGRectMake(10, _y, 250, 16)];
    l.text      = [NSString stringWithFormat:@"%@ : %.0f", title, v];
    l.textColor = [UIColor lightGrayColor];
    l.font      = [UIFont systemFontOfSize:11];
    l.tag       = tag;
    [_panel addSubview:l];
    _y += 18;

    UISlider* sl = [[UISlider alloc] initWithFrame:CGRectMake(10, _y, 250, 26)];
    sl.minimumValue = mn; sl.maximumValue = mx; sl.value = v;
    sl.tintColor    = [UIColor colorWithRed:.2 green:.5 blue:1 alpha:1];
    sl.tag          = tag;
    [sl addTarget:self action:s forControlEvents:UIControlEventValueChanged];
    [_panel addSubview:sl];
    _y += 32;
    return sl;
}

- (void)buildUI {
    _y = 10;

    [self section:@"─── ESP ───────────────────"];
    [self row:@"ESP"             val:g_cfg.espEnabled  sel:@selector(onESP:)];
    [self row:@"Box"             val:g_cfg.espBox      sel:@selector(onBox:)];
    [self row:@"Skeleton"        val:g_cfg.espSkeleton sel:@selector(onSkel:)];
    [self row:@"Vis check"       val:g_cfg.espVisCheck sel:@selector(onVis:)];

    [self section:@"─── CHAMS ─────────────────"];
    [self row:@"Chams"           val:g_cfg.chamsEnabled   sel:@selector(onChams:)];
    [self row:@"Wireframe"       val:g_cfg.chamsWireframe sel:@selector(onWF:)];

    [self section:@"─── AIMBOT ────────────────"];
    [self row:@"Aimbot"          val:g_cfg.aimEnabled  sel:@selector(onAim:)];
    [self row:@"Только видимые"  val:g_cfg.aimVisOnly  sel:@selector(onAimVis:)];
    [self slider:@"FOV"  min:10 max:350 val:g_cfg.aimFov   sel:@selector(onFov:)  tag:100];
    [self slider:@"Smooth" min:1 max:25 val:g_cfg.aimSmooth sel:@selector(onSmooth:) tag:101];

    // кость
    UILabel* bl = [[UILabel alloc] initWithFrame:CGRectMake(10, _y, 250, 16)];
    bl.text      = @"Цель";
    bl.textColor = [UIColor lightGrayColor];
    bl.font      = [UIFont systemFontOfSize:11];
    [_panel addSubview:bl];
    _y += 18;

    UISegmentedControl* sc = [[UISegmentedControl alloc]
        initWithItems:@[@"Голова", @"Грудь", @"Таз"]];
    sc.frame = CGRectMake(10, _y, 250, 28);
    sc.selectedSegmentIndex = g_cfg.aimBone;
    [sc addTarget:self action:@selector(onBone:) forControlEvents:UIControlEventValueChanged];
    [_panel addSubview:sc];
    _y += 36;

    _panel.contentSize = CGSizeMake(270, _y + 16);
}

// ── Handlers ─────────────────────────────────────────────────────
- (void)onESP:(UISwitch*)s     { g_cfg.espEnabled    = s.on; }
- (void)onBox:(UISwitch*)s     { g_cfg.espBox        = s.on; }
- (void)onSkel:(UISwitch*)s    { g_cfg.espSkeleton   = s.on; }
- (void)onVis:(UISwitch*)s     { g_cfg.espVisCheck   = s.on; }
- (void)onChams:(UISwitch*)s   { g_cfg.chamsEnabled  = s.on; ApplyChams(s.on); }
- (void)onWF:(UISwitch*)s      { g_cfg.chamsWireframe= s.on; ApplyChams(g_cfg.chamsEnabled); }
- (void)onAim:(UISwitch*)s     { g_cfg.aimEnabled    = s.on; }
- (void)onAimVis:(UISwitch*)s  { g_cfg.aimVisOnly    = s.on; }
- (void)onBone:(UISegmentedControl*)sc { g_cfg.aimBone = (int)sc.selectedSegmentIndex; }

- (void)onFov:(UISlider*)sl {
    g_cfg.aimFov = sl.value;
    UILabel* l = (UILabel*)[_panel viewWithTag:100];
    l.text = [NSString stringWithFormat:@"FOV : %.0f", sl.value];
}
- (void)onSmooth:(UISlider*)sl {
    g_cfg.aimSmooth = sl.value;
    UILabel* l = (UILabel*)[_panel viewWithTag:101];
    l.text = [NSString stringWithFormat:@"Smooth : %.0f", sl.value];
}
@end

// ═══════════════════════════════════════════════════════════════════
//  HOOK: Camera.OnPreRender — главный тик
// ═══════════════════════════════════════════════════════════════════
static uintptr_t   g_mainCam   = 0;
static CFESPView*  g_espView   = nil;
static CFMenu*     g_menu      = nil;

typedef void (*t_OnPreRender)(uintptr_t);
static t_OnPreRender orig_OnPreRender = nullptr;

static void Hook_OnPreRender(uintptr_t thiz) {
    orig_OnPreRender(thiz);

    if (!g_mainCam) g_mainCam = thiz;
    if (thiz != g_mainCam) return;

    UpdateVP(thiz);

    if (g_localCtrl) {
        uintptr_t net = Ptr(g_localCtrl + OFF_PC_NETWORK);
        if (net) g_localPos = Rd<Vec3>(net + OFF_NET_POSITION);
    }

    UpdatePlayers();
    DoAimbot(g_localCtrl);

    dispatch_async(dispatch_get_main_queue(), ^{
        [g_espView setNeedsDisplay];
    });
}

// ═══════════════════════════════════════════════════════════════════
//  HOOK: TournamentWallHack.Awake — ловим singleton
// ═══════════════════════════════════════════════════════════════════
typedef void (*t_Awake)(uintptr_t);
static t_Awake orig_TWH_Awake = nullptr;
static t_Awake orig_WF_Awake  = nullptr;

static void Hook_TWH_Awake(uintptr_t thiz) {
    orig_TWH_Awake(thiz);
    g_TWH_instance = thiz;
}
static void Hook_WF_Awake(uintptr_t thiz) {
    orig_WF_Awake(thiz);
    g_WF_instance = thiz;
}

// ═══════════════════════════════════════════════════════════════════
//  HOOK: PlayerController.Awake — локальный игрок
// ═══════════════════════════════════════════════════════════════════
// FILL: это упрощение — правильнее фильтровать по PhotonView.IsMine
// но PlayerController.Awake вызывается один раз — первый экземпляр = local
typedef void (*t_PCAwake)(uintptr_t);
static t_PCAwake orig_PCAwake = nullptr;
static void Hook_PCAwake(uintptr_t thiz) {
    orig_PCAwake(thiz);
    if (!g_localCtrl) g_localCtrl = thiz;
}

// ═══════════════════════════════════════════════════════════════════
//  INIT
// ═══════════════════════════════════════════════════════════════════
static void Init() {
    if (!Il2CppInit()) return;
    void* img = GetMainImage();
    if (!img) return;

    // Unity calls
    uintptr_t a;
    a = FindMethod(img, "UnityEngine", "Transform", "get_position_Injected", 1);
    Transform_get_position = (t_GetPos)a;

    a = FindMethod(img, "UnityEngine", "Transform", "set_eulerAngles_Injected", 1);
    Transform_set_eulerAngles = (t_SetEuler)a;

    a = FindMethod(img, "UnityEngine", "Camera", "get_projectionMatrix_Injected", 1);
    Camera_get_proj = (t_GetMatrix)a;

    a = FindMethod(img, "UnityEngine", "Camera", "get_worldToCameraMatrix_Injected", 1);
    Camera_get_w2cam = (t_GetMatrix)a;

    // Chams API
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

    // Hooks
    a = FindMethod(img, "UnityEngine", "Camera", "OnPreRender", 0);
    if (a) MSHookFunction((void*)a, (void*)Hook_OnPreRender, (void**)&orig_OnPreRender);

    a = FindMethod(img, "", "TournamentWallHack", "Awake", 0);
    if (a) MSHookFunction((void*)a, (void*)Hook_TWH_Awake, (void**)&orig_TWH_Awake);

    a = FindMethod(img, "", "WireframeWallhack", "Awake", 0);
    if (a) MSHookFunction((void*)a, (void*)Hook_WF_Awake, (void**)&orig_WF_Awake);

    a = FindMethod(img, "", "PlayerController", "Awake", 0);
    if (a) MSHookFunction((void*)a, (void*)Hook_PCAwake, (void**)&orig_PCAwake);

    // PlayerCulling.Instances static field
    // FILL: раскомментить когда будет il2cpp_class_get_static_field_data в билде
    // uintptr_t sf = GetStaticFields(img, "", "PlayerCulling");
    // if (sf) g_cullingInstances = sf + 0x8; // Instances = первое стат. поле

    // UI
    dispatch_async(dispatch_get_main_queue(), ^{
        UIWindow* win = UIApplication.sharedApplication.keyWindow;
        if (!win) return;
        CGRect s = UIScreen.mainScreen.bounds;
        g_sw = s.size.width; g_sh = s.size.height;
        g_center = { g_sw * 0.5f, g_sh * 0.5f };

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
