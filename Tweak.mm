#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <dlfcn.h>
#import <mach-o/dyld.h>
#import <math.h>
#import <sys/mman.h>
#import <mach/mach.h>
#import <stdint.h>
#import <string.h>

// ═══════════════════════════════════════════════════════════════════════════════
// OFFSETS — проверено по дампу CounterFlame
// ═══════════════════════════════════════════════════════════════════════════════
//
// PlayerCulling (static data):
//   0x8  → Instances  (List<PlayerCulling>)
// PlayerCulling (instance, MonoBehaviour base 0x10):
//   0x18 → _controller          (PlayerController)
//   0x28 → _animatorController  (PlayerAnimatorController)
//   0x48 → _occluded            (bool)
// PlayerController:
//   0x80 → _view                (PhotonView)
//   0xA8 → _isDeath             (bool)
// PhotonView:
//   0x60 → <IsMine>k__BackingField (bool)
// PlayerAnimatorController:
//   0x68 → _skeleton            (PlayerSkeleton)
// PlayerSkeleton:
//   0xA8 → _headBone            (Transform)
//   0xB0 → _chestBone           (Transform)
//
// ArmsController (для silent aim):
//   0x100 → _cameraTransform    (Transform)
//
// ArmsController.Shoot  RVA 0x1277208
// base: 0x112a70000  (из дампа)

// ═══════════════════════════════════════════════════════════════════════════════
// IL2CPP API
// ═══════════════════════════════════════════════════════════════════════════════
static void*    (*fp_domain_get)(void);
static void**   (*fp_domain_assemblies)(void*,size_t*);
static void*    (*fp_assembly_image)(void*);
static char*    (*fp_image_name)(void*);
static void*    (*fp_class_from_name)(void*,const char*,const char*);
static void*    (*fp_class_static_data)(void*);
static void*    (*fp_class_method_from_name)(void*,const char*,int);
static void*    (*fp_runtime_invoke)(void*,void*,void**,void**);
static void*    (*fp_object_unbox)(void*);

static BOOL g_apiLoaded = NO;
static BOOL LoadAPI(void) {
    if (g_apiLoaded) return YES;
#define R(p,s) p=(__typeof__(p))dlsym(RTLD_DEFAULT,s)
    R(fp_domain_get,             "il2cpp_domain_get");
    R(fp_domain_assemblies,      "il2cpp_domain_get_assemblies");
    R(fp_assembly_image,         "il2cpp_assembly_get_image");
    R(fp_image_name,             "il2cpp_image_get_name");
    R(fp_class_from_name,        "il2cpp_class_from_name");
    R(fp_class_static_data,      "il2cpp_class_get_static_field_data");
    R(fp_class_method_from_name, "il2cpp_class_get_method_from_name");
    R(fp_runtime_invoke,         "il2cpp_runtime_invoke");
    R(fp_object_unbox,           "il2cpp_object_unbox");
#undef R
    g_apiLoaded = (fp_domain_get != NULL && fp_class_from_name != NULL);
    return g_apiLoaded;
}

// ═══════════════════════════════════════════════════════════════════════════════
// types
// ═══════════════════════════════════════════════════════════════════════════════
typedef struct { float x,y,z;   } Vec3;
typedef struct { float x,y,z,w; } Quat;

// ═══════════════════════════════════════════════════════════════════════════════
// memory helpers
// ═══════════════════════════════════════════════════════════════════════════════
static BOOL IsPtr(const void *p) {
    uintptr_t v = (uintptr_t)p;
    return v > 0x10000UL && v < 0x00FFFFFFFFFFFFFFULL;
}
static void* RdPtr(const void *b, size_t o) {
    if (!IsPtr(b)) return NULL;
    void **a = (void **)((const uint8_t *)b + o);
    if (!IsPtr(a)) return NULL;
    return *a;
}
static BOOL RdBool(const void *b, size_t o) {
    if (!IsPtr(b)) return NO;
    return *(bool *)((const uint8_t *)b + o);
}

// ═══════════════════════════════════════════════════════════════════════════════
// inline hook без Substrate — arm64 trampoline
// ═══════════════════════════════════════════════════════════════════════════════
// пишем абсолютный прыжок: LDR X16, #8 / BR X16 / <64-bit addr>  (16 байт)
#define HOOK_SIZE 16

typedef struct {
    uint8_t  orig[HOOK_SIZE];
    void    *target;        // адрес оригинальной функции
    void    *trampoline;    // выделенная страница с оригинальными байтами + прыжком обратно
} HookCtx;

static BOOL WriteHook(void *dst, void *replacement, HookCtx *ctx) {
    // сохраняем оригинал
    memcpy(ctx->orig, dst, HOOK_SIZE);
    ctx->target = dst;

    // trampoline: скопируем первые HOOK_SIZE байт оригинала, потом прыжок на dst+HOOK_SIZE
    // выделяем RWX страницу
    void *tram = mmap(NULL, 4096, PROT_READ|PROT_WRITE|PROT_EXEC,
                      MAP_PRIVATE|MAP_ANONYMOUS, -1, 0);
    if (tram == MAP_FAILED) return NO;

    uint8_t *t = (uint8_t *)tram;
    memcpy(t, ctx->orig, HOOK_SIZE);
    // LDR X16, #8
    uint32_t ldr = 0x58000050; // LDR X16, pc+8
    memcpy(t + HOOK_SIZE, &ldr, 4);
    // BR X16
    uint32_t br  = 0xD61F0200;
    memcpy(t + HOOK_SIZE + 4, &br, 4);
    // абсолютный адрес возврата
    uintptr_t retAddr = (uintptr_t)dst + HOOK_SIZE;
    memcpy(t + HOOK_SIZE + 8, &retAddr, 8);
    ctx->trampoline = tram;

    // патчим оригинал: снимаем защиту через mprotect
    uintptr_t page   = (uintptr_t)dst & ~(uintptr_t)(4096-1);
    mprotect((void *)page, 4096, PROT_READ|PROT_WRITE|PROT_EXEC);

    uint8_t patch[HOOK_SIZE];
    // LDR X16, #8
    memcpy(patch, &ldr, 4);
    // BR X16
    memcpy(patch + 4, &br, 4);
    // адрес replacement
    uintptr_t repAddr = (uintptr_t)replacement;
    memcpy(patch + 8, &repAddr, 8);
    memcpy(dst, patch, HOOK_SIZE);

    // сбрасываем i-cache
    __builtin___clear_cache((char *)dst, (char *)dst + HOOK_SIZE);
    mprotect((void *)page, 4096, PROT_READ|PROT_EXEC);
    return YES;
}

// ═══════════════════════════════════════════════════════════════════════════════
// Unity / IL2CPP инит
// ═══════════════════════════════════════════════════════════════════════════════
static void* g_imgCSharp  = NULL;
static void* g_imgUnity   = NULL;
static void* g_pcullClass = NULL;
static void* g_getTransM  = NULL;
static void* g_getPosM    = NULL;
static void* g_getForwM   = NULL;
static void* g_setForwM   = NULL;
static void* g_getMainM   = NULL;
static void* g_w2sM       = NULL;
static BOOL  g_initDone   = NO;

static void InitClasses(void) {
    if (g_initDone) return;
    if (!LoadAPI()) return;

    void *domain = fp_domain_get();
    size_t n = 0;
    void **asms = fp_domain_assemblies(domain, &n);
    for (size_t i = 0; i < n; i++) {
        void *img = fp_assembly_image(asms[i]); if (!img) continue;
        const char *nm = fp_image_name(img);    if (!nm)  continue;
        if (!g_imgCSharp && strcmp(nm, "Assembly-CSharp.dll") == 0) g_imgCSharp = img;
        if (!g_imgUnity  && (strcmp(nm, "UnityEngine.CoreModule.dll") == 0 ||
                              strcmp(nm, "UnityEngine.dll") == 0))    g_imgUnity  = img;
    }

    if (g_imgCSharp)
        g_pcullClass = fp_class_from_name(g_imgCSharp, "", "PlayerCulling");

    if (g_imgUnity) {
        void *camC  = fp_class_from_name(g_imgUnity, "UnityEngine", "Camera");
        void *compC = fp_class_from_name(g_imgUnity, "UnityEngine", "Component");
        void *trnC  = fp_class_from_name(g_imgUnity, "UnityEngine", "Transform");

        if (camC) {
            g_getMainM = fp_class_method_from_name(camC, "get_main",           0);
            g_w2sM     = fp_class_method_from_name(camC, "WorldToScreenPoint", 1);
        }
        if (compC)
            g_getTransM = fp_class_method_from_name(compC, "get_transform", 0);
        if (trnC) {
            g_getPosM  = fp_class_method_from_name(trnC, "get_position", 0);
            g_getForwM = fp_class_method_from_name(trnC, "get_forward",  0);
            g_setForwM = fp_class_method_from_name(trnC, "set_forward",  1);
        }
    }
    g_initDone = (g_pcullClass != NULL && g_getTransM != NULL && g_getPosM != NULL);
}

// ═══════════════════════════════════════════════════════════════════════════════
// GetPosFromTransform / W2S
// ═══════════════════════════════════════════════════════════════════════════════
static Vec3 GetPosFromTransform(void *tr) {
    Vec3 z = {0,0,0};
    if (!IsPtr(tr) || !fp_runtime_invoke || !g_getPosM || !fp_object_unbox) return z;
    void *exc = NULL;
    void *bp = fp_runtime_invoke(g_getPosM, tr, NULL, &exc);
    if (!IsPtr(bp) || exc) return z;
    Vec3 *p = (Vec3 *)fp_object_unbox(bp);
    if (!p) return z;
    return *p;
}

static CGPoint W2S(Vec3 wp) {
    const CGPoint bad = {-1, -1};
    if (!fp_runtime_invoke || !g_getMainM || !g_w2sM || !fp_object_unbox) return bad;
    void *exc = NULL;
    void *cam = fp_runtime_invoke(g_getMainM, NULL, NULL, &exc);
    if (!IsPtr(cam) || exc) return bad;
    void *params[1] = {&wp};
    exc = NULL;
    void *br = fp_runtime_invoke(g_w2sM, cam, params, &exc);
    if (!IsPtr(br) || exc) return bad;
    Vec3 *sv = (Vec3 *)fp_object_unbox(br);
    if (!sv || sv->z <= 0.0f) return bad;
    Vec3 svCopy = *sv;
    CGFloat sc = [UIScreen mainScreen].scale;
    CGFloat uH = [UIScreen mainScreen].bounds.size.height;
    return CGPointMake(svCopy.x / sc, uH - svCopy.y / sc);
}

// ═══════════════════════════════════════════════════════════════════════════════
// Vec3 math
// ═══════════════════════════════════════════════════════════════════════════════
static inline Vec3  v3sub(Vec3 a, Vec3 b)  { return (Vec3){a.x-b.x, a.y-b.y, a.z-b.z}; }
static inline float v3dot(Vec3 a, Vec3 b)  { return a.x*b.x + a.y*b.y + a.z*b.z; }
static inline float v3len(Vec3 v)          { return sqrtf(v3dot(v, v)); }
static inline Vec3  v3norm(Vec3 v) {
    float l = v3len(v);
    return l > 1e-6f ? (Vec3){v.x/l, v.y/l, v.z/l} : (Vec3){0, 0, 1};
}

// ═══════════════════════════════════════════════════════════════════════════════
// SILENT AIM
// ═══════════════════════════════════════════════════════════════════════════════
static BOOL  g_aimOn   = NO;
static int   g_aimBone = 0;
static float g_aimFov  = 60.f;

static BOOL FindBestTarget(Vec3 *outWorld) {
    if (!IsPtr(g_pcullClass) || !fp_class_static_data) return NO;

    void *sd   = fp_class_static_data(g_pcullClass); if (!IsPtr(sd))   return NO;
    void *list = RdPtr(sd, 0x8);                      if (!IsPtr(list)) return NO;
    void *arr  = RdPtr(list, 0x10);
    int32_t sz = *(int32_t *)((uint8_t *)list + 0x18);
    if (!IsPtr(arr) || sz <= 0 || sz > 200) return NO;

    CGSize  scr   = [UIScreen mainScreen].bounds.size;
    CGFloat cx    = scr.width  * 0.5f;
    CGFloat cy    = scr.height * 0.5f;
    CGFloat fovPx = (g_aimFov / 90.f) * (scr.height * 0.5f);

    Vec3    bestWorld = {0,0,0};
    CGFloat bestDist  = 1e9f;
    BOOL    found     = NO;

    for (int i = 0; i < sz && i < 200; i++) {
        void *culling = RdPtr(arr, 0x20 + (size_t)i * 8); if (!IsPtr(culling)) continue;
        void *ctrl    = RdPtr(culling, 0x18);              if (!IsPtr(ctrl))    continue;
        if (RdBool(ctrl, 0xA8)) continue;
        void *view = RdPtr(ctrl, 0x80);
        if (IsPtr(view) && RdBool(view, 0x60)) continue;
        void *animCtrl = RdPtr(culling, 0x28); if (!IsPtr(animCtrl)) continue;
        void *skel     = RdPtr(animCtrl, 0x68); if (!IsPtr(skel))    continue;
        void *bone     = RdPtr(skel, g_aimBone == 0 ? 0xA8 : 0xB0);
        if (!IsPtr(bone)) continue;

        Vec3 bonePos = GetPosFromTransform(bone);
        if (bonePos.x == 0 && bonePos.y == 0 && bonePos.z == 0) continue;

        CGPoint sp = W2S(bonePos);
        if (sp.x < 0) continue;

        CGFloat dx = sp.x - cx, dy = sp.y - cy;
        CGFloat d  = sqrtf(dx*dx + dy*dy);
        if (d > fovPx || d >= bestDist) continue;

        bestDist = d; bestWorld = bonePos; found = YES;
    }
    if (found) *outWorld = bestWorld;
    return found;
}

// ═══════════════════════════════════════════════════════════════════════════════
// hook Shoot
// ═══════════════════════════════════════════════════════════════════════════════
typedef void (*Shoot_t)(void *self, void *methodInfo);
static Shoot_t  g_origShoot   = NULL;
static HookCtx  g_shootCtx;
static BOOL     g_hookInstalled = NO;

static void hook_Shoot(void *self, void *methodInfo) {
    if (!g_aimOn || !g_initDone || !IsPtr(self)) {
        g_origShoot(self, methodInfo);
        return;
    }
    void *camTr = RdPtr(self, 0x100);
    if (!IsPtr(camTr) || !g_getForwM || !g_setForwM) {
        g_origShoot(self, methodInfo);
        return;
    }

    void *exc = NULL;
    void *forwBox = fp_runtime_invoke(g_getForwM, camTr, NULL, &exc);
    Vec3 origForw = {0, 0, 1};
    if (IsPtr(forwBox) && !exc) {
        Vec3 *fp_ = (Vec3 *)fp_object_unbox(forwBox);
        if (fp_) origForw = *fp_;
    }

    Vec3 camPos = GetPosFromTransform(camTr);
    Vec3 target;
    if (FindBestTarget(&target) && (camPos.x || camPos.y || camPos.z)) {
        Vec3 dir = v3norm(v3sub(target, camPos));
        exc = NULL;
        void *sp[1] = {&dir};
        fp_runtime_invoke(g_setForwM, camTr, sp, &exc);
    }

    g_origShoot(self, methodInfo);

    exc = NULL;
    void *rp[1] = {&origForw};
    fp_runtime_invoke(g_setForwM, camTr, rp, &exc);
}

static void InstallHook(void) {
    if (g_hookInstalled) return;
    // FILL: пересчитай RVA если игра обновилась — nm/otool на новом бинарнике
    uintptr_t base = 0;
    for (uint32_t i = 0; i < _dyld_image_count(); i++) {
        const char *nm = _dyld_get_image_name(i);
        if (nm && strstr(nm, "CounterFlame")) {
            base = (uintptr_t)_dyld_get_image_vmaddr_slide(i) + 0x100000000ULL;
            break;
        }
    }
    if (!base) return;

    void *shootAddr = (void *)(base + 0x1277208);

    // trampoline для orig_Shoot — вызывается из hook_Shoot
    void *tram = mmap(NULL, 4096, PROT_READ|PROT_WRITE|PROT_EXEC,
                      MAP_PRIVATE|MAP_ANONYMOUS, -1, 0);
    if (tram == MAP_FAILED) return;

    uint8_t *t = (uint8_t *)tram;
    memcpy(t, shootAddr, HOOK_SIZE);
    uint32_t ldr = 0x58000050, br = 0xD61F0200;
    memcpy(t + HOOK_SIZE,     &ldr, 4);
    memcpy(t + HOOK_SIZE + 4, &br,  4);
    uintptr_t retAddr = (uintptr_t)shootAddr + HOOK_SIZE;
    memcpy(t + HOOK_SIZE + 8, &retAddr, 8);
    __builtin___clear_cache((char *)tram, (char *)tram + HOOK_SIZE + 16);
    g_origShoot = (Shoot_t)tram;

    // патчим оригинал
    uintptr_t page = (uintptr_t)shootAddr & ~(uintptr_t)(4095);
    mprotect((void *)page, 4096, PROT_READ|PROT_WRITE|PROT_EXEC);

    uint8_t patch[HOOK_SIZE];
    uintptr_t repAddr = (uintptr_t)hook_Shoot;
    memcpy(patch,     &ldr, 4);
    memcpy(patch + 4, &br,  4);
    memcpy(patch + 8, &repAddr, 8);
    memcpy(shootAddr, patch, HOOK_SIZE);
    __builtin___clear_cache((char *)shootAddr, (char *)shootAddr + HOOK_SIZE);
    mprotect((void *)page, 4096, PROT_READ|PROT_EXEC);

    g_hookInstalled = YES;
}

// ═══════════════════════════════════════════════════════════════════════════════
// ESP
// ═══════════════════════════════════════════════════════════════════════════════
#define MAX_ESP 64
typedef struct { CGFloat fx, fy, hx, hy; BOOL valid; } ESPEntry;
static ESPEntry g_esp[MAX_ESP];
static int      g_espCount = 0;
static BOOL     g_espOn    = NO;

static void UpdateESP(void) {
    g_espCount = 0;
    if (!g_espOn || !IsPtr(g_pcullClass) || !fp_class_static_data) return;

    void *sd   = fp_class_static_data(g_pcullClass); if (!IsPtr(sd))   return;
    void *list = RdPtr(sd, 0x8);                      if (!IsPtr(list)) return;
    void *arr  = RdPtr(list, 0x10);
    int32_t sz = *(int32_t *)((uint8_t *)list + 0x18);
    if (!IsPtr(arr) || sz <= 0 || sz > 200) return;

    int n = sz < MAX_ESP ? sz : MAX_ESP;
    for (int i = 0; i < n; i++) {
        void *culling = RdPtr(arr, 0x20 + (size_t)i * 8); if (!IsPtr(culling)) continue;
        void *ctrl    = RdPtr(culling, 0x18);              if (!IsPtr(ctrl))    continue;
        if (RdBool(ctrl, 0xA8)) continue;
        void *view = RdPtr(ctrl, 0x80);
        if (IsPtr(view) && RdBool(view, 0x60)) continue;
        if (!fp_runtime_invoke || !g_getTransM || !fp_object_unbox) continue;
        void *exc = NULL;
        void *tr = fp_runtime_invoke(g_getTransM, culling, NULL, &exc);
        if (!IsPtr(tr) || exc) continue;

        Vec3 foot = GetPosFromTransform(tr);
        if (foot.x == 0 && foot.y == 0 && foot.z == 0) continue;

        Vec3 head = {foot.x, foot.y + 1.8f, foot.z};
        CGPoint fs = W2S(foot); if (fs.x < 0) continue;
        CGPoint hs = W2S(head); if (hs.x < 0) continue;
        g_esp[g_espCount++] = (ESPEntry){fs.x, fs.y, hs.x, hs.y, YES};
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// UI helpers
// ═══════════════════════════════════════════════════════════════════════════════
static inline UIColor *C(CGFloat r, CGFloat g, CGFloat b, CGFloat a) {
    return [UIColor colorWithRed:r green:g blue:b alpha:a];
}
static const CGFloat kMenuW = 280.f;
static const CGFloat kMenuH = 340.f;
static const CGFloat kHdr   = 42.f;
static const CGFloat kR     = 12.f;
static const NSTimeInterval kDur = 0.22;

// ═══════════════════════════════════════════════════════════════════════════════
// FOVCircleView
// ═══════════════════════════════════════════════════════════════════════════════
@interface FOVCircleView : UIView @end
@implementation FOVCircleView
-(instancetype)init {
    self = [super initWithFrame:[UIScreen mainScreen].bounds];
    self.backgroundColor = [UIColor clearColor];
    self.userInteractionEnabled = NO;
    return self;
}
-(void)drawRect:(CGRect)r {
    if (!g_aimOn) return;
    CGContextRef ctx = UIGraphicsGetCurrentContext(); if (!ctx) return;
    CGSize  scr    = [UIScreen mainScreen].bounds.size;
    CGFloat cx     = scr.width * 0.5f, cy = scr.height * 0.5f;
    CGFloat radius = (g_aimFov / 90.f) * (scr.height * 0.5f);
    CGContextSetStrokeColorWithColor(ctx, [UIColor colorWithRed:1 green:1 blue:1 alpha:.25f].CGColor);
    CGContextSetLineWidth(ctx, 1.f);
    CGContextStrokeEllipseInRect(ctx, CGRectMake(cx-radius, cy-radius, radius*2, radius*2));
}
@end

// ═══════════════════════════════════════════════════════════════════════════════
// ESPView
// ═══════════════════════════════════════════════════════════════════════════════
@interface ESPView : UIView @end
@implementation ESPView
-(instancetype)init {
    self = [super initWithFrame:[UIScreen mainScreen].bounds];
    self.backgroundColor = [UIColor clearColor];
    self.userInteractionEnabled = NO;
    return self;
}
-(void)drawRect:(CGRect)r {
    if (!g_espOn || g_espCount == 0) return;
    CGContextRef ctx = UIGraphicsGetCurrentContext(); if (!ctx) return;
    for (int i = 0; i < g_espCount; i++) {
        ESPEntry *e = &g_esp[i]; if (!e->valid) continue;
        CGFloat bh = e->fy - e->hy; if (bh < 4.f) continue;
        CGFloat bw = bh * 0.45f;
        CGFloat bx = ((e->fx + e->hx) * 0.5f) - bw * 0.5f;
        CGContextSetLineWidth(ctx, 1.5f);
        CGContextSetStrokeColorWithColor(ctx, [UIColor colorWithRed:.2f green:.8f blue:.2f alpha:.9f].CGColor);
        CGContextStrokeRect(ctx, CGRectMake(bx, e->hy, bw, bh));
        CGContextSetStrokeColorWithColor(ctx, [UIColor colorWithRed:.9f green:.2f blue:.1f alpha:.9f].CGColor);
        CGContextMoveToPoint(ctx, bx, e->hy);
        CGContextAddLineToPoint(ctx, bx + bw, e->hy);
        CGContextStrokePath(ctx);
    }
}
@end

// ═══════════════════════════════════════════════════════════════════════════════
// PillButton
// ═══════════════════════════════════════════════════════════════════════════════
@interface PillButton : UIView
@property (copy) dispatch_block_t action;
@end
@implementation PillButton { CGPoint _off; BOOL _moved; }
-(instancetype)init {
    self = [super initWithFrame:CGRectMake(20, 120, 44, 28)];
    self.backgroundColor = C(0.10f, 0.10f, 0.13f, 0.92f);
    self.layer.cornerRadius = 14;
    self.layer.borderColor  = C(0.27f, 0.52f, 1.00f, 0.45f).CGColor;
    self.layer.borderWidth  = 1;
    UILabel *l = [[UILabel alloc] initWithFrame:self.bounds];
    l.text = @"☰"; l.textAlignment = NSTextAlignmentCenter;
    l.font = [UIFont systemFontOfSize:13]; l.textColor = C(0.75f, 0.75f, 0.80f, 1);
    [self addSubview:l];
    [self addGestureRecognizer:[[UIPanGestureRecognizer alloc]
        initWithTarget:self action:@selector(pan:)]];
    return self;
}
-(void)pan:(UIPanGestureRecognizer *)g {
    CGPoint loc = [g locationInView:self.superview];
    if (g.state == UIGestureRecognizerStateBegan) {
        _moved = NO;
        _off = CGPointMake(loc.x - self.frame.origin.x, loc.y - self.frame.origin.y);
    } else if (g.state == UIGestureRecognizerStateChanged) {
        _moved = YES;
        CGRect f = self.frame;
        f.origin = CGPointMake(loc.x - _off.x, loc.y - _off.y);
        self.frame = f;
    }
}
-(void)touchesEnded:(NSSet *)t withEvent:(UIEvent *)e {
    if (!_moved && _action) _action();
}
@end

// ═══════════════════════════════════════════════════════════════════════════════
// MenuView
// ═══════════════════════════════════════════════════════════════════════════════
@interface MenuView : UIView
@property (strong) UIButton           *hideBtn;
@property (strong) UISwitch           *espSwitch;
@property (strong) UILabel            *espStatus;
@property (strong) UISwitch           *aimSwitch;
@property (strong) UILabel            *aimStatus;
@property (strong) UISlider           *fovSlider;
@property (strong) UILabel            *fovLabel;
@property (strong) UISegmentedControl *boneSegment;
@end

@implementation MenuView { CGPoint _drag; }
-(instancetype)initWithFrame:(CGRect)f {
    self = [super initWithFrame:f];
    self.backgroundColor = C(0.07f, 0.07f, 0.09f, 0.93f);
    self.layer.cornerRadius = kR;
    self.layer.masksToBounds = YES;

    UIView *hdr = [[UIView alloc] initWithFrame:CGRectMake(0, 0, kMenuW, kHdr)];
    hdr.backgroundColor = C(0.10f, 0.10f, 0.13f, 1);
    [self addSubview:hdr];

    UIView *acc = [[UIView alloc] initWithFrame:CGRectMake(0, kHdr-1, kMenuW, 1)];
    acc.backgroundColor = C(0.27f, 0.52f, 1.00f, 0.55f);
    [self addSubview:acc];

    UILabel *ttl = [[UILabel alloc] initWithFrame:CGRectMake(0, (kHdr-17)*.5f, kMenuW, 17)];
    ttl.text = @"☰  Cheat Menu"; ttl.textAlignment = NSTextAlignmentCenter;
    ttl.font = [UIFont systemFontOfSize:13 weight:UIFontWeightSemibold];
    ttl.textColor = C(0.92f, 0.92f, 0.95f, 1);
    [self addSubview:ttl];

    [hdr addGestureRecognizer:[[UIPanGestureRecognizer alloc]
        initWithTarget:self action:@selector(pan:)]];

    self.hideBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    self.hideBtn.frame = CGRectMake(kMenuW-30, (kHdr-24)*.5f, 24, 24);
    self.hideBtn.layer.cornerRadius = 12;
    self.hideBtn.layer.masksToBounds = YES;
    self.hideBtn.backgroundColor = C(0.17f, 0.17f, 0.21f, 1);
    self.hideBtn.titleLabel.font = [UIFont systemFontOfSize:11 weight:UIFontWeightMedium];
    [self.hideBtn setTitle:@"−" forState:UIControlStateNormal];
    [self.hideBtn setTitleColor:C(0.55f, 0.55f, 0.60f, 1) forState:UIControlStateNormal];
    [self addSubview:self.hideBtn];

    CGFloat cw = kMenuW - 24;

    UIView *card1 = [[UIView alloc] initWithFrame:CGRectMake(12, kHdr+14, cw, 80)];
    card1.backgroundColor = C(0.10f, 0.10f, 0.13f, 1);
    card1.layer.cornerRadius = 8;
    [self addSubview:card1];

    UILabel *sl1 = [[UILabel alloc] initWithFrame:CGRectMake(10, 10, cw-20, 12)];
    sl1.text = @"VISUALS"; sl1.font = [UIFont systemFontOfSize:9 weight:UIFontWeightSemibold];
    sl1.textColor = C(0.27f, 0.52f, 1.00f, 1); [card1 addSubview:sl1];

    UILabel *espLbl = [[UILabel alloc] initWithFrame:CGRectMake(10, 28, 100, 24)];
    espLbl.text = @"ESP"; espLbl.font = [UIFont systemFontOfSize:13 weight:UIFontWeightMedium];
    espLbl.textColor = C(0.80f, 0.80f, 0.90f, 1); [card1 addSubview:espLbl];

    self.espSwitch = [[UISwitch alloc] init];
    self.espSwitch.onTintColor = C(0.27f, 0.52f, 1.00f, 1);
    CGSize ssz = self.espSwitch.frame.size;
    self.espSwitch.frame = CGRectMake(cw-10-ssz.width, (80-ssz.height)*.5f, ssz.width, ssz.height);
    [card1 addSubview:self.espSwitch];

    self.espStatus = [[UILabel alloc] initWithFrame:CGRectMake(10, 56, cw-20, 14)];
    self.espStatus.text = @"выключен";
    self.espStatus.font = [UIFont monospacedSystemFontOfSize:9 weight:UIFontWeightRegular];
    self.espStatus.textColor = C(0.35f, 0.35f, 0.40f, 1);
    [card1 addSubview:self.espStatus];

    CGFloat aimY = kHdr + 14 + 80 + 10;
    UIView *card2 = [[UIView alloc] initWithFrame:CGRectMake(12, aimY, cw, 172)];
    card2.backgroundColor = C(0.10f, 0.10f, 0.13f, 1);
    card2.layer.cornerRadius = 8;
    [self addSubview:card2];

    UILabel *sl2 = [[UILabel alloc] initWithFrame:CGRectMake(10, 10, cw-20, 12)];
    sl2.text = @"SILENT AIM"; sl2.font = [UIFont systemFontOfSize:9 weight:UIFontWeightSemibold];
    sl2.textColor = C(1.00f, 0.45f, 0.20f, 1); [card2 addSubview:sl2];

    UILabel *aimLbl = [[UILabel alloc] initWithFrame:CGRectMake(10, 28, 120, 24)];
    aimLbl.text = @"Silent Aim"; aimLbl.font = [UIFont systemFontOfSize:13 weight:UIFontWeightMedium];
    aimLbl.textColor = C(0.80f, 0.80f, 0.90f, 1); [card2 addSubview:aimLbl];

    self.aimSwitch = [[UISwitch alloc] init];
    self.aimSwitch.onTintColor = C(1.00f, 0.45f, 0.20f, 1);
    self.aimSwitch.frame = CGRectMake(cw-10-ssz.width, 22, ssz.width, ssz.height);
    [card2 addSubview:self.aimSwitch];

    self.aimStatus = [[UILabel alloc] initWithFrame:CGRectMake(10, 58, cw-20, 14)];
    self.aimStatus.text = @"выключен";
    self.aimStatus.font = [UIFont monospacedSystemFontOfSize:9 weight:UIFontWeightRegular];
    self.aimStatus.textColor = C(0.35f, 0.35f, 0.40f, 1);
    [card2 addSubview:self.aimStatus];

    UILabel *boneLbl = [[UILabel alloc] initWithFrame:CGRectMake(10, 80, 60, 14)];
    boneLbl.text = @"Цель"; boneLbl.font = [UIFont systemFontOfSize:10 weight:UIFontWeightRegular];
    boneLbl.textColor = C(0.60f, 0.60f, 0.65f, 1); [card2 addSubview:boneLbl];

    self.boneSegment = [[UISegmentedControl alloc] initWithItems:@[@"Голова", @"Грудь"]];
    self.boneSegment.frame = CGRectMake(10, 98, cw-20, 28);
    self.boneSegment.selectedSegmentIndex = 0;
    self.boneSegment.tintColor = C(1.00f, 0.45f, 0.20f, 1);
    if (@available(iOS 13.0, *)) {
        [self.boneSegment setTitleTextAttributes:
            @{NSForegroundColorAttributeName: C(0.75f, 0.75f, 0.80f, 1)}
            forState:UIControlStateNormal];
        [self.boneSegment setTitleTextAttributes:
            @{NSForegroundColorAttributeName: [UIColor whiteColor]}
            forState:UIControlStateSelected];
    }
    [card2 addSubview:self.boneSegment];

    UILabel *fovTitleLbl = [[UILabel alloc] initWithFrame:CGRectMake(10, 134, 40, 14)];
    fovTitleLbl.text = @"FOV"; fovTitleLbl.font = [UIFont systemFontOfSize:10 weight:UIFontWeightRegular];
    fovTitleLbl.textColor = C(0.60f, 0.60f, 0.65f, 1); [card2 addSubview:fovTitleLbl];

    self.fovLabel = [[UILabel alloc] initWithFrame:CGRectMake(cw-50, 134, 40, 14)];
    self.fovLabel.text = @"60°"; self.fovLabel.textAlignment = NSTextAlignmentRight;
    self.fovLabel.font = [UIFont monospacedSystemFontOfSize:10 weight:UIFontWeightRegular];
    self.fovLabel.textColor = C(1.00f, 0.45f, 0.20f, 1); [card2 addSubview:self.fovLabel];

    self.fovSlider = [[UISlider alloc] initWithFrame:CGRectMake(10, 152, cw-20, 22)];
    self.fovSlider.minimumValue = 5.f; self.fovSlider.maximumValue = 180.f; self.fovSlider.value = 60.f;
    self.fovSlider.minimumTrackTintColor = C(1.00f, 0.45f, 0.20f, 1);
    self.fovSlider.maximumTrackTintColor = C(0.25f, 0.25f, 0.30f, 1);
    [card2 addSubview:self.fovSlider];

    CALayer *bdr = [CALayer layer];
    bdr.frame = CGRectMake(0, 0, kMenuW, kMenuH);
    bdr.borderColor = C(0.22f, 0.22f, 0.28f, 0.65f).CGColor;
    bdr.borderWidth = 1; bdr.cornerRadius = kR;
    [self.layer addSublayer:bdr];

    return self;
}
-(void)pan:(UIPanGestureRecognizer *)g {
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

// ═══════════════════════════════════════════════════════════════════════════════
// PassthroughWindow / PassthroughView
// ═══════════════════════════════════════════════════════════════════════════════
@interface PassthroughWindow : UIWindow @end
@implementation PassthroughWindow
-(UIView *)hitTest:(CGPoint)p withEvent:(UIEvent *)e {
    UIView *v = [super hitTest:p withEvent:e];
    if (!v || v == self || v == self.rootViewController.view) return nil;
    if (!v.userInteractionEnabled) return nil;
    return v;
}
@end

@interface PassthroughView : UIView @end
@implementation PassthroughView
-(UIView *)hitTest:(CGPoint)p withEvent:(UIEvent *)e {
    for (UIView *sub in [[self subviews] reverseObjectEnumerator]) {
        if (sub.hidden || !sub.userInteractionEnabled || sub.alpha < 0.01f) continue;
        CGPoint cv = [self convertPoint:p toView:sub];
        UIView *hit = [sub hitTest:cv withEvent:e];
        if (hit) return hit;
    }
    return nil;
}
@end

// ═══════════════════════════════════════════════════════════════════════════════
// CheatController
// ═══════════════════════════════════════════════════════════════════════════════
@interface CheatController : NSObject
+(instancetype)shared;
-(void)show;
@end

@implementation CheatController {
    PassthroughWindow *_win;
    MenuView          *_menu;
    ESPView           *_espView;
    FOVCircleView     *_fovView;
    PillButton        *_pill;
    CADisplayLink     *_dl;
}

+(instancetype)shared {
    static CheatController *inst;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ inst = [CheatController new]; });
    return inst;
}
-(instancetype)init { self = [super init]; [self build]; return self; }

-(void)build {
    UIWindowScene *scene = nil;
    for (UIScene *s in [UIApplication sharedApplication].connectedScenes)
        if ([s isKindOfClass:[UIWindowScene class]]) { scene = (UIWindowScene *)s; break; }

    _win = scene
        ? [[PassthroughWindow alloc] initWithWindowScene:scene]
        : [[PassthroughWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
    _win.windowLevel = UIWindowLevelAlert + 200;
    _win.backgroundColor = [UIColor clearColor];

    PassthroughView *pv = [[PassthroughView alloc] initWithFrame:[UIScreen mainScreen].bounds];
    pv.backgroundColor = [UIColor clearColor];
    UIViewController *vc = [UIViewController new]; vc.view = pv;
    _win.rootViewController = vc;
    _win.hidden = NO;

    _espView = [ESPView new]; [pv addSubview:_espView];
    _fovView = [FOVCircleView new]; [pv addSubview:_fovView];

    CGSize sz = [UIScreen mainScreen].bounds.size;
    _menu = [[MenuView alloc] initWithFrame:
        CGRectMake((sz.width-kMenuW)*.5f, (sz.height-kMenuH)*.5f, kMenuW, kMenuH)];
    [pv addSubview:_menu];

    __weak CheatController *ws = self;
    _pill = [PillButton new];
    _pill.action = ^{ [ws doShow]; };
    _pill.hidden = YES;
    [pv addSubview:_pill];

    [_menu.hideBtn     addTarget:self action:@selector(doHide)       forControlEvents:UIControlEventTouchUpInside];
    [_menu.espSwitch   addTarget:self action:@selector(espChanged:)  forControlEvents:UIControlEventValueChanged];
    [_menu.aimSwitch   addTarget:self action:@selector(aimChanged:)  forControlEvents:UIControlEventValueChanged];
    [_menu.fovSlider   addTarget:self action:@selector(fovChanged:)  forControlEvents:UIControlEventValueChanged];
    [_menu.boneSegment addTarget:self action:@selector(boneChanged:) forControlEvents:UIControlEventValueChanged];

    _dl = [CADisplayLink displayLinkWithTarget:self selector:@selector(tick)];
    _dl.preferredFramesPerSecond = 30;
    [_dl addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
}

-(void)espChanged:(UISwitch *)sw {
    g_espOn = sw.isOn;
    if (g_espOn && !g_initDone) InitClasses();
    _menu.espStatus.text      = g_espOn ? @"активен"  : @"выключен";
    _menu.espStatus.textColor = g_espOn ? C(0.35f,0.70f,0.40f,1) : C(0.35f,0.35f,0.40f,1);
    if (!g_espOn) { g_espCount = 0; [_espView setNeedsDisplay]; }
}
-(void)aimChanged:(UISwitch *)sw {
    g_aimOn = sw.isOn;
    if (g_aimOn) {
        if (!g_initDone)    InitClasses();
        if (!g_hookInstalled) InstallHook();
    }
    _menu.aimStatus.text      = g_aimOn ? @"активен"  : @"выключен";
    _menu.aimStatus.textColor = g_aimOn ? C(0.70f,0.40f,0.20f,1) : C(0.35f,0.35f,0.40f,1);
    [_fovView setNeedsDisplay];
}
-(void)fovChanged:(UISlider *)sl {
    g_aimFov = sl.value;
    _menu.fovLabel.text = [NSString stringWithFormat:@"%.0f°", g_aimFov];
    if (g_aimOn) [_fovView setNeedsDisplay];
}
-(void)boneChanged:(UISegmentedControl *)seg {
    g_aimBone = (int)seg.selectedSegmentIndex;
}
-(void)tick {
    if (!g_initDone && (g_espOn || g_aimOn)) InitClasses();
    if (g_espOn) { UpdateESP(); [_espView setNeedsDisplay]; }
}
-(void)doShow {
    _pill.hidden = YES; _menu.hidden = NO; _menu.alpha = 0;
    _menu.transform = CGAffineTransformMakeScale(0.88f, 0.88f);
    [UIView animateWithDuration:kDur delay:0
        options:UIViewAnimationOptionCurveEaseOut
        animations:^{
            self->_menu.alpha = 1;
            self->_menu.transform = CGAffineTransformIdentity;
        } completion:nil];
}
-(void)doHide {
    [UIView animateWithDuration:kDur delay:0
        options:UIViewAnimationOptionCurveEaseIn
        animations:^{
            self->_menu.alpha = 0;
            self->_menu.transform = CGAffineTransformMakeScale(0.94f, 0.94f);
        } completion:^(BOOL _) {
            self->_menu.hidden = YES;
            self->_menu.transform = CGAffineTransformIdentity;
            self->_pill.hidden = NO;
        }];
}
-(void)show { [self doShow]; }
@end

// ═══════════════════════════════════════════════════════════════════════════════
// Init
// ═══════════════════════════════════════════════════════════════════════════════
__attribute__((constructor))
static void Init(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5*NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            [[CheatController shared] show];
        });
    });
}
