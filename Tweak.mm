#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <dlfcn.h>
#import <mach-o/dyld.h>
#import <math.h>
#import <sys/mman.h>
#import <mach/mach.h>
#import <stdint.h>
#import <string.h>
#import <libkern/OSCacheControl.h>

// ═══════════════════════════════════════════════════════════════════════════════
// OFFSETS — выверено по dump_cs.txt, base 0x112a70000
// ═══════════════════════════════════════════════════════════════════════════════
//
// PlayerCulling (static):
//   0x8  → Instances (List<PlayerCulling>)
// PlayerCulling (instance):
//   0x18 → _controller         (PlayerController)
//   0x28 → _animatorController (ScarletWork.Photon.TPS.PlayerAnimatorController)
//   0x48 → _occluded           (bool)
//
// PlayerController:
//   0x60 → _armsController     (ArmsController)
//   0x80 → _view               (PhotonView)
//   0x88 → _network            (PlayerNetwork)
//   0xA0 → _movementController (PlayerMovement)  — фактически через _movementController
//   0xA8 → _isDeath            (bool)
//
// PhotonView:
//   0x60 → <IsMine>k__BackingField (bool)
//
// PlayerAnimatorController (ScarletWork.Photon.TPS):
//   0x68 → _skeleton           (ScarletWork.Game.PlayerSkeleton)
//
// PlayerSkeleton:
//   0xA8 → _headBone           (Transform)
//   0xB0 → _chestBone          (Transform)
//   0xB8 → _pelvisBone         (Transform)
//
// ArmsController:
//   0x100 → _cameraTransform   (Transform)  ← silent aim луч
//   0x13D → CanFire            (bool)
//   0x1D0 → _infiniteShots     (bool)
//   0x140 → MagazineCapacity   (int16)
//   0x142 → Capacity           (int16)      ← текущий патрон в магазине
//
// PlayerMovement:
//   0x18  → _speed             (float)
//
// ArmsController.Shoot  RVA 0x1277208
// ArmsController.set_IsGod RVA 0x126FFD4
// PlayerMovement.EnableNoclip RVA 0x148B268

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
static BOOL  RdBool(const void *b, size_t o)    { if (!IsPtr(b)) return NO;  return *(bool    *)((const uint8_t *)b + o); }
static float RdFloat(const void *b, size_t o)   { if (!IsPtr(b)) return 0.f; return *(float   *)((const uint8_t *)b + o); }
static int16_t RdI16(const void *b, size_t o)   { if (!IsPtr(b)) return 0;   return *(int16_t *)((const uint8_t *)b + o); }
static void  WrBool(void *b, size_t o, BOOL v)  { if (!IsPtr(b)) return; *(bool    *)((uint8_t *)b + o) = (bool)v; }
static void  WrFloat(void *b, size_t o, float v){ if (!IsPtr(b)) return; *(float   *)((uint8_t *)b + o) = v; }
static void  WrI16(void *b, size_t o, int16_t v){ if (!IsPtr(b)) return; *(int16_t *)((uint8_t *)b + o) = v; }

// ═══════════════════════════════════════════════════════════════════════════════
// arm64 inline hook (без Substrate)
// ═══════════════════════════════════════════════════════════════════════════════
#define HOOK_SIZE 16

static BOOL InstallInlineHook(void *dst, void *replacement, void **ppOrig) {
    // trampoline
    void *tram = mmap(NULL, 4096, PROT_READ|PROT_WRITE|PROT_EXEC,
                      MAP_PRIVATE|MAP_ANONYMOUS, -1, 0);
    if (tram == MAP_FAILED) return NO;

    uint32_t ldr_x16 = 0x58000050; // LDR X16, #8
    uint32_t br_x16  = 0xD61F0200; // BR  X16
    uint8_t *t = (uint8_t *)tram;
    memcpy(t, dst, HOOK_SIZE);
    memcpy(t+HOOK_SIZE,   &ldr_x16, 4);
    memcpy(t+HOOK_SIZE+4, &br_x16,  4);
    uintptr_t ret = (uintptr_t)dst + HOOK_SIZE;
    memcpy(t+HOOK_SIZE+8, &ret, 8);
    sys_icache_invalidate(tram, HOOK_SIZE+16);
    if (ppOrig) *ppOrig = tram;

    // patch dst
    uintptr_t page = (uintptr_t)dst & ~(uintptr_t)4095;
    mprotect((void *)page, 4096, PROT_READ|PROT_WRITE|PROT_EXEC);
    uint8_t patch[HOOK_SIZE];
    uintptr_t rep = (uintptr_t)replacement;
    memcpy(patch,   &ldr_x16, 4);
    memcpy(patch+4, &br_x16,  4);
    memcpy(patch+8, &rep, 8);
    memcpy(dst, patch, HOOK_SIZE);
    sys_icache_invalidate(dst, HOOK_SIZE);
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
        if (compC) g_getTransM = fp_class_method_from_name(compC, "get_transform", 0);
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
    return p ? *p : z;
}

static CGPoint W2S(Vec3 wp) {
    const CGPoint bad = {-1,-1};
    if (!fp_runtime_invoke || !g_getMainM || !g_w2sM || !fp_object_unbox) return bad;
    void *exc = NULL;
    void *cam = fp_runtime_invoke(g_getMainM, NULL, NULL, &exc);
    if (!IsPtr(cam) || exc) return bad;
    void *params[1] = {&wp};
    exc = NULL;
    void *br = fp_runtime_invoke(g_w2sM, cam, params, &exc);
    if (!IsPtr(br) || exc) return bad;
    Vec3 *sv = (Vec3 *)fp_object_unbox(br);
    if (!sv || sv->z <= 0.f) return bad;
    Vec3 s = *sv;
    CGFloat sc = [UIScreen mainScreen].scale;
    CGFloat uH = [UIScreen mainScreen].bounds.size.height;
    return CGPointMake(s.x / sc, uH - s.y / sc);
}

// ═══════════════════════════════════════════════════════════════════════════════
// Vec3 math
// ═══════════════════════════════════════════════════════════════════════════════
static inline Vec3  v3sub(Vec3 a,Vec3 b)  { return (Vec3){a.x-b.x,a.y-b.y,a.z-b.z}; }
static inline float v3dot(Vec3 a,Vec3 b)  { return a.x*b.x+a.y*b.y+a.z*b.z; }
static inline Vec3  v3norm(Vec3 v) {
    float l = sqrtf(v3dot(v,v));
    return l>1e-6f?(Vec3){v.x/l,v.y/l,v.z/l}:(Vec3){0,0,1};
}

// ═══════════════════════════════════════════════════════════════════════════════
// base игры
// ═══════════════════════════════════════════════════════════════════════════════
static uintptr_t g_gameBase = 0;

static uintptr_t GetGameBase(void) {
    if (g_gameBase) return g_gameBase;
    for (uint32_t i = 0; i < _dyld_image_count(); i++) {
        const char *nm = _dyld_get_image_name(i);
        if (nm && strstr(nm, "CounterFlame")) {
            g_gameBase = (uintptr_t)_dyld_get_image_vmaddr_slide(i) + 0x100000000ULL;
            break;
        }
    }
    return g_gameBase;
}

// ═══════════════════════════════════════════════════════════════════════════════
// FEATURE STATE
// ═══════════════════════════════════════════════════════════════════════════════
static BOOL  g_espOn        = NO;
static BOOL  g_aimOn        = NO;
static BOOL  g_godOn        = NO;   // god mode (ArmsController.set_IsGod)
static BOOL  g_infAmmoOn    = NO;   // _infiniteShots = YES
static BOOL  g_noclipOn     = NO;   // PlayerMovement.EnableNoclip
static BOOL  g_speedOn      = NO;   // _speed *= 1.8
static BOOL  g_noRecoilOn   = NO;   // нулевой recoil (патч _recoilMult)
static BOOL  g_wallhackOn   = NO;   // SetOccluded(false) каждый фрейм
static BOOL  g_rapidFireOn  = NO;   // CanFire = YES / timeFired сброс
static BOOL  g_oneHpOn      = NO;   // показывает HP врагов текстом
static int   g_aimBone      = 0;    // 0=голова 1=грудь 2=таз
static float g_aimFov       = 60.f;
static float g_speedMult    = 1.8f;

// ═══════════════════════════════════════════════════════════════════════════════
// итерация PlayerCulling
// ═══════════════════════════════════════════════════════════════════════════════
typedef void (^CullingIterBlock)(void *culling, void *ctrl, void *animCtrl);

static void IterateCulling(CullingIterBlock blk) {
    if (!IsPtr(g_pcullClass) || !fp_class_static_data) return;
    void *sd   = fp_class_static_data(g_pcullClass); if (!IsPtr(sd))   return;
    void *list = RdPtr(sd, 0x8);                      if (!IsPtr(list)) return;
    void *arr  = RdPtr(list, 0x10);
    int32_t sz = *(int32_t *)((uint8_t *)list + 0x18);
    if (!IsPtr(arr) || sz <= 0 || sz > 256) return;
    for (int i = 0; i < sz && i < 256; i++) {
        void *culling = RdPtr(arr, 0x20 + (size_t)i * 8); if (!IsPtr(culling)) continue;
        void *ctrl    = RdPtr(culling, 0x18);              if (!IsPtr(ctrl))    continue;
        void *animCtrl= RdPtr(culling, 0x28);              // may be NULL for self
        blk(culling, ctrl, animCtrl);
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// SILENT AIM — FindBestTarget
// ═══════════════════════════════════════════════════════════════════════════════
static BOOL FindBestTarget(Vec3 *outWorld) {
    CGSize  scr   = [UIScreen mainScreen].bounds.size;
    CGFloat cx    = scr.width  * 0.5f;
    CGFloat cy    = scr.height * 0.5f;
    CGFloat fovPx = (g_aimFov / 90.f) * (scr.height * 0.5f);

    __block Vec3    bestWorld = {0,0,0};
    __block CGFloat bestDist  = 1e9f;
    __block BOOL    found     = NO;

    IterateCulling(^(void *culling, void *ctrl, void *animCtrl) {
        if (RdBool(ctrl, 0xA8)) return;   // _isDeath
        void *view = RdPtr(ctrl, 0x80);
        if (IsPtr(view) && RdBool(view, 0x60)) return; // IsMine
        if (!IsPtr(animCtrl)) return;

        void *skel = RdPtr(animCtrl, 0x68); if (!IsPtr(skel)) return;
        size_t boneOff = (g_aimBone==0)?0xA8:(g_aimBone==1)?0xB0:0xB8;
        void *bone = RdPtr(skel, boneOff);  if (!IsPtr(bone)) return;

        Vec3 bonePos = GetPosFromTransform(bone);
        if (bonePos.x==0&&bonePos.y==0&&bonePos.z==0) return;

        CGPoint sp = W2S(bonePos);
        if (sp.x < 0) return;

        CGFloat dx=sp.x-cx, dy=sp.y-cy;
        CGFloat d = sqrtf(dx*dx+dy*dy);
        if (d>fovPx || d>=bestDist) return;
        bestDist=d; bestWorld=bonePos; found=YES;
    });

    if (found) *outWorld = bestWorld;
    return found;
}

// ═══════════════════════════════════════════════════════════════════════════════
// SILENT AIM hook — ArmsController.Shoot  RVA 0x1277208
// ═══════════════════════════════════════════════════════════════════════════════
typedef void (*Shoot_t)(void *self, void *methodInfo);
static Shoot_t g_origShoot    = NULL;
static BOOL    g_hookShoot    = NO;

static void hook_Shoot(void *self, void *methodInfo) {
    if (!g_aimOn || !g_initDone || !IsPtr(self)) {
        g_origShoot(self, methodInfo); return;
    }
    // self = ArmsController; _cameraTransform @ 0x100
    void *camTr = RdPtr(self, 0x100);
    if (!IsPtr(camTr) || !g_getForwM || !g_setForwM) {
        g_origShoot(self, methodInfo); return;
    }
    // сохраняем оригинальный forward
    void *exc=NULL;
    void *forwBox = fp_runtime_invoke(g_getForwM, camTr, NULL, &exc);
    Vec3 origForw = {0,0,1};
    if (IsPtr(forwBox)&&!exc) { Vec3 *fp_=(Vec3*)fp_object_unbox(forwBox); if(fp_) origForw=*fp_; }

    Vec3 camPos = GetPosFromTransform(camTr);
    Vec3 target;
    if (FindBestTarget(&target) && (camPos.x||camPos.y||camPos.z)) {
        Vec3 dir = v3norm(v3sub(target, camPos));
        exc=NULL; void *sp[1]={&dir};
        fp_runtime_invoke(g_setForwM, camTr, sp, &exc);
    }
    g_origShoot(self, methodInfo);
    // восстанавливаем forward
    exc=NULL; void *rp[1]={&origForw};
    fp_runtime_invoke(g_setForwM, camTr, rp, &exc);
}

// ═══════════════════════════════════════════════════════════════════════════════
// InstallHooks
// ═══════════════════════════════════════════════════════════════════════════════
static void InstallHooks(void) {
    uintptr_t base = GetGameBase(); if (!base) return;
    if (!g_hookShoot) {
        void *shootAddr = (void *)(base + 0x1277208);
        if (InstallInlineHook(shootAddr, (void*)hook_Shoot, (void**)&g_origShoot))
            g_hookShoot = YES;
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// FEATURES tick (вызывается каждый кадр)
// ═══════════════════════════════════════════════════════════════════════════════

// --- God mode: ставим IsGod=true на нашем ArmsController ---
static void TickGodMode(void) {
    if (!g_godOn || !IsPtr(g_pcullClass) || !fp_class_static_data) return;
    void *sd = fp_class_static_data(g_pcullClass); if (!IsPtr(sd)) return;
    void *list = RdPtr(sd, 0x8); if (!IsPtr(list)) return;
    void *arr = RdPtr(list, 0x10);
    int32_t sz = *(int32_t*)((uint8_t*)list+0x18);
    if (!IsPtr(arr)||sz<=0) return;
    for (int i=0;i<sz&&i<256;i++) {
        void *culling=RdPtr(arr,0x20+(size_t)i*8); if(!IsPtr(culling)) continue;
        void *ctrl=RdPtr(culling,0x18); if(!IsPtr(ctrl)) continue;
        void *view=RdPtr(ctrl,0x80);
        if (!IsPtr(view)||!RdBool(view,0x60)) continue; // только наш
        void *arms=RdPtr(ctrl,0x60); if(!IsPtr(arms)) continue;
        // set_IsGod(true) — патчим флаг напрямую через метод
        // IsGod bool в ArmsController — нет прямого офсета в дампе,
        // вызываем через set_IsGod RVA 0x126FFD4
        typedef void (*SetGod_t)(void *self, bool val, void *mi);
        static SetGod_t fp_setGod = NULL;
        if (!fp_setGod) {
            uintptr_t base = GetGameBase(); if (!base) return;
            fp_setGod = (SetGod_t)(base + (0x126FFD4 - 0x112a70000));
        }
        if (fp_setGod) fp_setGod(arms, true, NULL);
        break;
    }
}

// --- Infinite Ammo: _infiniteShots = YES ---
static void TickInfAmmo(void) {
    if (!g_infAmmoOn || !IsPtr(g_pcullClass) || !fp_class_static_data) return;
    void *sd=fp_class_static_data(g_pcullClass); if(!IsPtr(sd)) return;
    void *list=RdPtr(sd,0x8); if(!IsPtr(list)) return;
    void *arr=RdPtr(list,0x10);
    int32_t sz=*(int32_t*)((uint8_t*)list+0x18);
    if (!IsPtr(arr)||sz<=0) return;
    for (int i=0;i<sz&&i<256;i++) {
        void *culling=RdPtr(arr,0x20+(size_t)i*8); if(!IsPtr(culling)) continue;
        void *ctrl=RdPtr(culling,0x18); if(!IsPtr(ctrl)) continue;
        void *view=RdPtr(ctrl,0x80);
        if (!IsPtr(view)||!RdBool(view,0x60)) continue;
        void *arms=RdPtr(ctrl,0x60); if(!IsPtr(arms)) continue;
        WrBool(arms, 0x1D0, YES);           // _infiniteShots
        WrI16(arms, 0x142, RdI16(arms, 0x140)); // Capacity = MagazineCapacity
        break;
    }
}

// --- Speed hack: _speed на PlayerMovement ---
static void TickSpeed(void) {
    if (!g_speedOn || !IsPtr(g_pcullClass) || !fp_class_static_data) return;
    void *sd=fp_class_static_data(g_pcullClass); if(!IsPtr(sd)) return;
    void *list=RdPtr(sd,0x8); if(!IsPtr(list)) return;
    void *arr=RdPtr(list,0x10);
    int32_t sz=*(int32_t*)((uint8_t*)list+0x18);
    if (!IsPtr(arr)||sz<=0) return;
    for (int i=0;i<sz&&i<256;i++) {
        void *culling=RdPtr(arr,0x20+(size_t)i*8); if(!IsPtr(culling)) continue;
        void *ctrl=RdPtr(culling,0x18); if(!IsPtr(ctrl)) continue;
        void *view=RdPtr(ctrl,0x80);
        if (!IsPtr(view)||!RdBool(view,0x60)) continue;
        // PlayerController._movementController @ 0x40
        void *mv=RdPtr(ctrl,0x40); if(!IsPtr(mv)) continue;
        float cur = RdFloat(mv, 0x18);
        // не даём уйти за разумный предел
        if (cur > 0.f && cur < 4.f)
            WrFloat(mv, 0x18, cur * g_speedMult);
        break;
    }
}

// --- No Recoil: _recoilMult @ 0xA0, _accuracyMult @ 0xA4 ---
static void TickNoRecoil(void) {
    if (!g_noRecoilOn || !IsPtr(g_pcullClass) || !fp_class_static_data) return;
    void *sd=fp_class_static_data(g_pcullClass); if(!IsPtr(sd)) return;
    void *list=RdPtr(sd,0x8); if(!IsPtr(list)) return;
    void *arr=RdPtr(list,0x10);
    int32_t sz=*(int32_t*)((uint8_t*)list+0x18);
    if (!IsPtr(arr)||sz<=0) return;
    for (int i=0;i<sz&&i<256;i++) {
        void *culling=RdPtr(arr,0x20+(size_t)i*8); if(!IsPtr(culling)) continue;
        void *ctrl=RdPtr(culling,0x18); if(!IsPtr(ctrl)) continue;
        void *view=RdPtr(ctrl,0x80);
        if (!IsPtr(view)||!RdBool(view,0x60)) continue;
        void *arms=RdPtr(ctrl,0x60); if(!IsPtr(arms)) continue;
        WrFloat(arms, 0xA0, 0.f);  // _recoilMult
        WrFloat(arms, 0xA4, 0.f);  // _accuracyMult → нет разброса
        // сбрасываем накопившийся кик
        WrFloat(arms, 0x154, 0.f); // _camRecoilV
        WrFloat(arms, 0x158, 0.f); // _camRecoilH
        break;
    }
}

// --- Wallhack: SetOccluded(false) на всех врагах ---
static void TickWallhack(void) {
    if (!g_wallhackOn || !IsPtr(g_pcullClass) || !fp_class_static_data) return;
    void *sd=fp_class_static_data(g_pcullClass); if(!IsPtr(sd)) return;
    void *list=RdPtr(sd,0x8); if(!IsPtr(list)) return;
    void *arr=RdPtr(list,0x10);
    int32_t sz=*(int32_t*)((uint8_t*)list+0x18);
    if (!IsPtr(arr)||sz<=0) return;
    for (int i=0;i<sz&&i<256;i++) {
        void *culling=RdPtr(arr,0x20+(size_t)i*8); if(!IsPtr(culling)) continue;
        void *ctrl=RdPtr(culling,0x18); if(!IsPtr(ctrl)) continue;
        if (RdBool(ctrl,0xA8)) continue;
        void *view=RdPtr(ctrl,0x80);
        if (IsPtr(view)&&RdBool(view,0x60)) continue; // пропускаем себя
        WrBool(culling, 0x48, NO); // _occluded = false → враг всегда виден
    }
}

// --- Rapid Fire: CanFire=YES, обнуляем _timeFired ---
static void TickRapidFire(void) {
    if (!g_rapidFireOn || !IsPtr(g_pcullClass) || !fp_class_static_data) return;
    void *sd=fp_class_static_data(g_pcullClass); if(!IsPtr(sd)) return;
    void *list=RdPtr(sd,0x8); if(!IsPtr(list)) return;
    void *arr=RdPtr(list,0x10);
    int32_t sz=*(int32_t*)((uint8_t*)list+0x18);
    if (!IsPtr(arr)||sz<=0) return;
    for (int i=0;i<sz&&i<256;i++) {
        void *culling=RdPtr(arr,0x20+(size_t)i*8); if(!IsPtr(culling)) continue;
        void *ctrl=RdPtr(culling,0x18); if(!IsPtr(ctrl)) continue;
        void *view=RdPtr(ctrl,0x80);
        if (!IsPtr(view)||!RdBool(view,0x60)) continue;
        void *arms=RdPtr(ctrl,0x60); if(!IsPtr(arms)) continue;
        WrBool(arms, 0x13D, YES);   // CanFire
        WrFloat(arms, 0x144, 0.f);  // _timeFired сброс → нет кулдауна
        break;
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// ESP + HP labels
// ═══════════════════════════════════════════════════════════════════════════════
#define MAX_ESP 64
typedef struct {
    CGFloat fx,fy,hx,hy;
    BOOL valid;
} ESPEntry;
static ESPEntry g_esp[MAX_ESP];
static int      g_espCount = 0;

static void UpdateESP(void) {
    g_espCount = 0;
    if (!g_espOn || !IsPtr(g_pcullClass) || !fp_class_static_data) return;

    void *sd=fp_class_static_data(g_pcullClass); if(!IsPtr(sd)) return;
    void *list=RdPtr(sd,0x8); if(!IsPtr(list)) return;
    void *arr=RdPtr(list,0x10);
    int32_t sz=*(int32_t*)((uint8_t*)list+0x18);
    if (!IsPtr(arr)||sz<=0) return;

    int n=sz<MAX_ESP?sz:MAX_ESP;
    for (int i=0;i<n;i++) {
        void *culling=RdPtr(arr,0x20+(size_t)i*8); if(!IsPtr(culling)) continue;
        void *ctrl=RdPtr(culling,0x18); if(!IsPtr(ctrl)) continue;
        if (RdBool(ctrl,0xA8)) continue;
        void *view=RdPtr(ctrl,0x80);
        if (IsPtr(view)&&RdBool(view,0x60)) continue;
        if (!fp_runtime_invoke||!g_getTransM||!fp_object_unbox) continue;
        void *exc=NULL;
        void *tr=fp_runtime_invoke(g_getTransM,culling,NULL,&exc);
        if (!IsPtr(tr)||exc) continue;
        Vec3 foot=GetPosFromTransform(tr);
        if (foot.x==0&&foot.y==0&&foot.z==0) continue;
        Vec3 head={foot.x,foot.y+1.8f,foot.z};
        CGPoint fs=W2S(foot); if(fs.x<0) continue;
        CGPoint hs=W2S(head); if(hs.x<0) continue;
        g_esp[g_espCount++]=(ESPEntry){fs.x,fs.y,hs.x,hs.y,YES};
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// UI helpers
// ═══════════════════════════════════════════════════════════════════════════════
static inline UIColor *C(CGFloat r,CGFloat g,CGFloat b,CGFloat a) {
    return [UIColor colorWithRed:r green:g blue:b alpha:a];
}
static const CGFloat kMenuW=310.f, kMenuH=540.f, kHdr=42.f, kR=12.f;
static const NSTimeInterval kDur=0.22;

// ═══════════════════════════════════════════════════════════════════════════════
// FOVCircleView
// ═══════════════════════════════════════════════════════════════════════════════
@interface FOVCircleView : UIView @end
@implementation FOVCircleView
-(instancetype)init {
    self=[super initWithFrame:[UIScreen mainScreen].bounds];
    self.backgroundColor=[UIColor clearColor]; self.userInteractionEnabled=NO; return self;
}
-(void)drawRect:(CGRect)r {
    if (!g_aimOn) return;
    CGContextRef ctx=UIGraphicsGetCurrentContext(); if(!ctx) return;
    CGSize scr=[UIScreen mainScreen].bounds.size;
    CGFloat cx=scr.width*.5f,cy=scr.height*.5f;
    CGFloat radius=(g_aimFov/90.f)*(scr.height*.5f);
    CGContextSetStrokeColorWithColor(ctx,[UIColor colorWithRed:1 green:1 blue:1 alpha:.3f].CGColor);
    CGContextSetLineWidth(ctx,1.f);
    CGContextStrokeEllipseInRect(ctx,CGRectMake(cx-radius,cy-radius,radius*2,radius*2));
}
@end

// ═══════════════════════════════════════════════════════════════════════════════
// ESPView
// ═══════════════════════════════════════════════════════════════════════════════
@interface ESPView : UIView @end
@implementation ESPView
-(instancetype)init {
    self=[super initWithFrame:[UIScreen mainScreen].bounds];
    self.backgroundColor=[UIColor clearColor]; self.userInteractionEnabled=NO; return self;
}
-(void)drawRect:(CGRect)r {
    if (!g_espOn||g_espCount==0) return;
    CGContextRef ctx=UIGraphicsGetCurrentContext(); if(!ctx) return;
    for (int i=0;i<g_espCount;i++) {
        ESPEntry *e=&g_esp[i]; if(!e->valid) continue;
        CGFloat bh=e->fy-e->hy; if(bh<4.f) continue;
        CGFloat bw=bh*.45f;
        CGFloat bx=((e->fx+e->hx)*.5f)-bw*.5f;
        CGContextSetLineWidth(ctx,1.5f);
        CGContextSetStrokeColorWithColor(ctx,[UIColor colorWithRed:.2f green:.8f blue:.2f alpha:.9f].CGColor);
        CGContextStrokeRect(ctx,CGRectMake(bx,e->hy,bw,bh));
        CGContextSetStrokeColorWithColor(ctx,[UIColor colorWithRed:.9f green:.2f blue:.1f alpha:.9f].CGColor);
        CGContextMoveToPoint(ctx,bx,e->hy);
        CGContextAddLineToPoint(ctx,bx+bw,e->hy);
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
    self=[super initWithFrame:CGRectMake(20,120,44,28)];
    self.backgroundColor=C(.10f,.10f,.13f,.92f);
    self.layer.cornerRadius=14;
    self.layer.borderColor=C(.27f,.52f,1.f,.45f).CGColor;
    self.layer.borderWidth=1;
    UILabel *l=[[UILabel alloc]initWithFrame:self.bounds];
    l.text=@"☰";l.textAlignment=NSTextAlignmentCenter;
    l.font=[UIFont systemFontOfSize:13];l.textColor=C(.75f,.75f,.80f,1);
    [self addSubview:l];
    [self addGestureRecognizer:[[UIPanGestureRecognizer alloc]initWithTarget:self action:@selector(pan:)]];
    return self;
}
-(void)pan:(UIPanGestureRecognizer*)g {
    CGPoint loc=[g locationInView:self.superview];
    if(g.state==UIGestureRecognizerStateBegan){_moved=NO;_off=CGPointMake(loc.x-self.frame.origin.x,loc.y-self.frame.origin.y);}
    else if(g.state==UIGestureRecognizerStateChanged){_moved=YES;CGRect f=self.frame;f.origin=CGPointMake(loc.x-_off.x,loc.y-_off.y);self.frame=f;}
}
-(void)touchesEnded:(NSSet*)t withEvent:(UIEvent*)e{if(!_moved&&_action)_action();}
@end

// ═══════════════════════════════════════════════════════════════════════════════
// ToggleRow helper
// ═══════════════════════════════════════════════════════════════════════════════
@interface ToggleRow : UIView
@property (strong) UISwitch *sw;
@property (strong) UILabel  *statusLbl;
-(instancetype)initWithTitle:(NSString*)title color:(UIColor*)col width:(CGFloat)w;
@end
@implementation ToggleRow
-(instancetype)initWithTitle:(NSString*)title color:(UIColor*)col width:(CGFloat)w {
    self=[super initWithFrame:CGRectMake(0,0,w,44)];
    UILabel *lbl=[[UILabel alloc]initWithFrame:CGRectMake(10,0,w*.5f,44)];
    lbl.text=title; lbl.font=[UIFont systemFontOfSize:13 weight:UIFontWeightMedium];
    lbl.textColor=C(.80f,.80f,.90f,1); [self addSubview:lbl];
    self.sw=[[UISwitch alloc]init]; self.sw.onTintColor=col;
    CGSize sz=self.sw.frame.size;
    self.sw.frame=CGRectMake(w-10-sz.width,(44-sz.height)*.5f,sz.width,sz.height);
    [self addSubview:self.sw];
    self.statusLbl=[[UILabel alloc]initWithFrame:CGRectMake(10,28,w-20,12)];
    self.statusLbl.font=[UIFont monospacedSystemFontOfSize:9 weight:UIFontWeightRegular];
    self.statusLbl.textColor=C(.35f,.35f,.40f,1); [self addSubview:self.statusLbl];
    return self;
}
-(void)setOn:(BOOL)on {
    self.sw.on=on;
    self.statusLbl.text=on?@"активен":@"выключен";
    self.statusLbl.textColor=on?C(.35f,.70f,.40f,1):C(.35f,.35f,.40f,1);
}
@end

// ═══════════════════════════════════════════════════════════════════════════════
// MenuView
// ═══════════════════════════════════════════════════════════════════════════════
@interface MenuView : UIView
@property (strong) UIButton           *hideBtn;
// combat
@property (strong) ToggleRow *rowAim;
@property (strong) UISlider  *fovSlider;
@property (strong) UILabel   *fovLabel;
@property (strong) UISegmentedControl *boneSegment;
@property (strong) ToggleRow *rowRapidFire;
@property (strong) ToggleRow *rowNoRecoil;
// visuals
@property (strong) ToggleRow *rowEsp;
@property (strong) ToggleRow *rowWallhack;
// player
@property (strong) ToggleRow *rowGod;
@property (strong) ToggleRow *rowInfAmmo;
@property (strong) ToggleRow *rowSpeed;
@property (strong) ToggleRow *rowNoclip;
@end

@implementation MenuView { CGPoint _drag; }
-(instancetype)initWithFrame:(CGRect)f {
    self=[super initWithFrame:f];
    self.backgroundColor=C(.07f,.07f,.09f,.94f);
    self.layer.cornerRadius=kR; self.layer.masksToBounds=YES;

    // header
    UIView *hdr=[[UIView alloc]initWithFrame:CGRectMake(0,0,kMenuW,kHdr)];
    hdr.backgroundColor=C(.10f,.10f,.13f,1); [self addSubview:hdr];
    UIView *acc=[[UIView alloc]initWithFrame:CGRectMake(0,kHdr-1,kMenuW,1)];
    acc.backgroundColor=C(.27f,.52f,1.f,.55f); [self addSubview:acc];
    UILabel *ttl=[[UILabel alloc]initWithFrame:CGRectMake(0,(kHdr-17)*.5f,kMenuW,17)];
    ttl.text=@"☰  CF Cheat"; ttl.textAlignment=NSTextAlignmentCenter;
    ttl.font=[UIFont systemFontOfSize:13 weight:UIFontWeightSemibold];
    ttl.textColor=C(.92f,.92f,.95f,1); [self addSubview:ttl];
    [hdr addGestureRecognizer:[[UIPanGestureRecognizer alloc]initWithTarget:self action:@selector(pan:)]];

    self.hideBtn=[UIButton buttonWithType:UIButtonTypeCustom];
    self.hideBtn.frame=CGRectMake(kMenuW-30,(kHdr-24)*.5f,24,24);
    self.hideBtn.layer.cornerRadius=12; self.hideBtn.layer.masksToBounds=YES;
    self.hideBtn.backgroundColor=C(.17f,.17f,.21f,1);
    self.hideBtn.titleLabel.font=[UIFont systemFontOfSize:11 weight:UIFontWeightMedium];
    [self.hideBtn setTitle:@"−" forState:UIControlStateNormal];
    [self.hideBtn setTitleColor:C(.55f,.55f,.60f,1) forState:UIControlStateNormal];
    [self addSubview:self.hideBtn];

    CGFloat cw=kMenuW-24;
    CGFloat y=kHdr+10;

    // ── COMBAT card
    UIView *cc=[self makeCard:CGRectMake(12,y,cw,290) title:@"COMBAT" titleColor:C(1.f,.45f,.20f,1)];
    [self addSubview:cc]; y+=290+8;

    CGFloat ry=26;
    self.rowAim=[[ToggleRow alloc]initWithTitle:@"Silent Aim" color:C(1.f,.45f,.20f,1) width:cw-20];
    self.rowAim.frame=CGRectMake(10,ry,cw-20,44); [cc addSubview:self.rowAim]; ry+=44;

    // bone
    UILabel *boneLbl=[[UILabel alloc]initWithFrame:CGRectMake(10,ry,50,14)];
    boneLbl.text=@"Цель"; boneLbl.font=[UIFont systemFontOfSize:10]; boneLbl.textColor=C(.6f,.6f,.65f,1); [cc addSubview:boneLbl];
    self.boneSegment=[[UISegmentedControl alloc]initWithItems:@[@"Голова",@"Грудь",@"Таз"]];
    self.boneSegment.frame=CGRectMake(10,ry+16,cw-20,26);
    self.boneSegment.selectedSegmentIndex=0; self.boneSegment.tintColor=C(1.f,.45f,.20f,1);
    if (@available(iOS 13,*)) {
        [self.boneSegment setTitleTextAttributes:@{NSForegroundColorAttributeName:C(.75f,.75f,.80f,1)} forState:UIControlStateNormal];
        [self.boneSegment setTitleTextAttributes:@{NSForegroundColorAttributeName:[UIColor whiteColor]} forState:UIControlStateSelected];
    }
    [cc addSubview:self.boneSegment]; ry+=46;

    // fov
    UILabel *fovT=[[UILabel alloc]initWithFrame:CGRectMake(10,ry,40,14)];
    fovT.text=@"FOV"; fovT.font=[UIFont systemFontOfSize:10]; fovT.textColor=C(.6f,.6f,.65f,1); [cc addSubview:fovT];
    self.fovLabel=[[UILabel alloc]initWithFrame:CGRectMake(cw-60,ry,50,14)];
    self.fovLabel.text=@"60°"; self.fovLabel.textAlignment=NSTextAlignmentRight;
    self.fovLabel.font=[UIFont monospacedSystemFontOfSize:10 weight:UIFontWeightRegular];
    self.fovLabel.textColor=C(1.f,.45f,.20f,1); [cc addSubview:self.fovLabel];
    self.fovSlider=[[UISlider alloc]initWithFrame:CGRectMake(10,ry+16,cw-20,22)];
    self.fovSlider.minimumValue=5.f; self.fovSlider.maximumValue=180.f; self.fovSlider.value=60.f;
    self.fovSlider.minimumTrackTintColor=C(1.f,.45f,.20f,1);
    self.fovSlider.maximumTrackTintColor=C(.25f,.25f,.30f,1); [cc addSubview:self.fovSlider]; ry+=44;

    self.rowRapidFire=[[ToggleRow alloc]initWithTitle:@"Rapid Fire" color:C(1.f,.45f,.20f,1) width:cw-20];
    self.rowRapidFire.frame=CGRectMake(10,ry,cw-20,38); [cc addSubview:self.rowRapidFire]; ry+=40;

    self.rowNoRecoil=[[ToggleRow alloc]initWithTitle:@"No Recoil" color:C(1.f,.45f,.20f,1) width:cw-20];
    self.rowNoRecoil.frame=CGRectMake(10,ry,cw-20,38); [cc addSubview:self.rowNoRecoil];

    // ── VISUALS card
    UIView *vc=[self makeCard:CGRectMake(12,y,cw,106) title:@"VISUALS" titleColor:C(.27f,.52f,1.f,1)];
    [self addSubview:vc]; y+=106+8;
    ry=26;
    self.rowEsp=[[ToggleRow alloc]initWithTitle:@"ESP" color:C(.27f,.52f,1.f,1) width:cw-20];
    self.rowEsp.frame=CGRectMake(10,ry,cw-20,38); [vc addSubview:self.rowEsp]; ry+=42;
    self.rowWallhack=[[ToggleRow alloc]initWithTitle:@"Wallhack" color:C(.27f,.52f,1.f,1) width:cw-20];
    self.rowWallhack.frame=CGRectMake(10,ry,cw-20,38); [vc addSubview:self.rowWallhack];

    // ── PLAYER card
    UIView *pc=[self makeCard:CGRectMake(12,y,cw,176) title:@"PLAYER" titleColor:C(.40f,.85f,.55f,1)];
    [self addSubview:pc];
    ry=26;
    UIColor *gc=C(.40f,.85f,.55f,1);
    self.rowGod=[[ToggleRow alloc]initWithTitle:@"God Mode" color:gc width:cw-20];
    self.rowGod.frame=CGRectMake(10,ry,cw-20,38); [pc addSubview:self.rowGod]; ry+=42;
    self.rowInfAmmo=[[ToggleRow alloc]initWithTitle:@"Infinite Ammo" color:gc width:cw-20];
    self.rowInfAmmo.frame=CGRectMake(10,ry,cw-20,38); [pc addSubview:self.rowInfAmmo]; ry+=42;
    self.rowSpeed=[[ToggleRow alloc]initWithTitle:@"Speed Hack" color:gc width:cw-20];
    self.rowSpeed.frame=CGRectMake(10,ry,cw-20,38); [pc addSubview:self.rowSpeed]; ry+=42;
    self.rowNoclip=[[ToggleRow alloc]initWithTitle:@"Noclip" color:gc width:cw-20];
    self.rowNoclip.frame=CGRectMake(10,ry,cw-20,38); [pc addSubview:self.rowNoclip];

    // border
    CALayer *bdr=[CALayer layer];
    bdr.frame=CGRectMake(0,0,kMenuW,kMenuH);
    bdr.borderColor=C(.22f,.22f,.28f,.65f).CGColor;
    bdr.borderWidth=1; bdr.cornerRadius=kR; [self.layer addSublayer:bdr];
    return self;
}

-(UIView*)makeCard:(CGRect)frame title:(NSString*)title titleColor:(UIColor*)col {
    UIView *card=[[UIView alloc]initWithFrame:frame];
    card.backgroundColor=C(.10f,.10f,.13f,1); card.layer.cornerRadius=8;
    UILabel *lbl=[[UILabel alloc]initWithFrame:CGRectMake(10,8,frame.size.width-20,12)];
    lbl.text=title; lbl.font=[UIFont systemFontOfSize:9 weight:UIFontWeightSemibold];
    lbl.textColor=col; [card addSubview:lbl];
    return card;
}

-(void)pan:(UIPanGestureRecognizer*)g {
    CGPoint loc=[g locationInView:self.superview];
    if(g.state==UIGestureRecognizerStateBegan) _drag=CGPointMake(loc.x-self.frame.origin.x,loc.y-self.frame.origin.y);
    else if(g.state==UIGestureRecognizerStateChanged){CGRect r=self.frame;r.origin=CGPointMake(loc.x-_drag.x,loc.y-_drag.y);self.frame=r;}
}
@end

// ═══════════════════════════════════════════════════════════════════════════════
// PassthroughWindow / PassthroughView
// ═══════════════════════════════════════════════════════════════════════════════
@interface PassthroughWindow : UIWindow @end
@implementation PassthroughWindow
-(UIView*)hitTest:(CGPoint)p withEvent:(UIEvent*)e {
    UIView *v=[super hitTest:p withEvent:e];
    if(!v||v==self||v==self.rootViewController.view) return nil;
    if(!v.userInteractionEnabled) return nil;
    return v;
}
@end
@interface PassthroughView : UIView @end
@implementation PassthroughView
-(UIView*)hitTest:(CGPoint)p withEvent:(UIEvent*)e {
    for (UIView *sub in [[self subviews]reverseObjectEnumerator]) {
        if(sub.hidden||!sub.userInteractionEnabled||sub.alpha<.01f) continue;
        UIView *hit=[sub hitTest:[self convertPoint:p toView:sub] withEvent:e];
        if(hit) return hit;
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
    static CheatController *inst; static dispatch_once_t o;
    dispatch_once(&o,^{inst=[CheatController new];});
    return inst;
}
-(instancetype)init{self=[super init];[self build];return self;}

-(void)build {
    UIWindowScene *scene=nil;
    for (UIScene *s in [UIApplication sharedApplication].connectedScenes)
        if([s isKindOfClass:[UIWindowScene class]]){scene=(UIWindowScene*)s;break;}
    _win=scene?[[PassthroughWindow alloc]initWithWindowScene:scene]
              :[[PassthroughWindow alloc]initWithFrame:[UIScreen mainScreen].bounds];
    _win.windowLevel=UIWindowLevelAlert+200;
    _win.backgroundColor=[UIColor clearColor];

    PassthroughView *pv=[[PassthroughView alloc]initWithFrame:[UIScreen mainScreen].bounds];
    pv.backgroundColor=[UIColor clearColor];
    UIViewController *vc=[UIViewController new]; vc.view=pv;
    _win.rootViewController=vc; _win.hidden=NO;

    _espView=[ESPView new]; [pv addSubview:_espView];
    _fovView=[FOVCircleView new]; [pv addSubview:_fovView];

    CGSize sz=[UIScreen mainScreen].bounds.size;
    _menu=[[MenuView alloc]initWithFrame:CGRectMake((sz.width-kMenuW)*.5f,(sz.height-kMenuH)*.5f,kMenuW,kMenuH)];
    [pv addSubview:_menu];

    __weak CheatController *ws=self;
    _pill=[PillButton new]; _pill.action=^{[ws doShow];}; _pill.hidden=YES;
    [pv addSubview:_pill];

    [_menu.hideBtn         addTarget:self action:@selector(doHide)           forControlEvents:UIControlEventTouchUpInside];
    [_menu.rowAim.sw       addTarget:self action:@selector(aimChanged:)      forControlEvents:UIControlEventValueChanged];
    [_menu.rowEsp.sw       addTarget:self action:@selector(espChanged:)      forControlEvents:UIControlEventValueChanged];
    [_menu.rowGod.sw       addTarget:self action:@selector(godChanged:)      forControlEvents:UIControlEventValueChanged];
    [_menu.rowInfAmmo.sw   addTarget:self action:@selector(infAmmoChanged:)  forControlEvents:UIControlEventValueChanged];
    [_menu.rowSpeed.sw     addTarget:self action:@selector(speedChanged:)    forControlEvents:UIControlEventValueChanged];
    [_menu.rowNoclip.sw    addTarget:self action:@selector(noclipChanged:)   forControlEvents:UIControlEventValueChanged];
    [_menu.rowNoRecoil.sw  addTarget:self action:@selector(noRecoilChanged:) forControlEvents:UIControlEventValueChanged];
    [_menu.rowWallhack.sw  addTarget:self action:@selector(wallhackChanged:) forControlEvents:UIControlEventValueChanged];
    [_menu.rowRapidFire.sw addTarget:self action:@selector(rapidFireChanged:)forControlEvents:UIControlEventValueChanged];
    [_menu.fovSlider       addTarget:self action:@selector(fovChanged:)      forControlEvents:UIControlEventValueChanged];
    [_menu.boneSegment     addTarget:self action:@selector(boneChanged:)     forControlEvents:UIControlEventValueChanged];

    _dl=[CADisplayLink displayLinkWithTarget:self selector:@selector(tick)];
    _dl.preferredFramesPerSecond=30;
    [_dl addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
}

-(void)aimChanged:(UISwitch*)sw {
    g_aimOn=sw.isOn;
    if (g_aimOn) { if(!g_initDone)InitClasses(); if(!g_hookShoot)InstallHooks(); }
    [_menu.rowAim setOn:g_aimOn]; [_fovView setNeedsDisplay];
}
-(void)espChanged:(UISwitch*)sw {
    g_espOn=sw.isOn;
    if (g_espOn&&!g_initDone) InitClasses();
    [_menu.rowEsp setOn:g_espOn];
    if (!g_espOn){g_espCount=0;[_espView setNeedsDisplay];}
}
-(void)godChanged:(UISwitch*)sw       { g_godOn=sw.isOn;       if(g_godOn&&!g_initDone)InitClasses(); [_menu.rowGod setOn:g_godOn]; }
-(void)infAmmoChanged:(UISwitch*)sw   { g_infAmmoOn=sw.isOn;   if(g_infAmmoOn&&!g_initDone)InitClasses(); [_menu.rowInfAmmo setOn:g_infAmmoOn]; }
-(void)speedChanged:(UISwitch*)sw     { g_speedOn=sw.isOn;     if(g_speedOn&&!g_initDone)InitClasses(); [_menu.rowSpeed setOn:g_speedOn]; }
-(void)noclipChanged:(UISwitch*)sw    { g_noclipOn=sw.isOn;    [_menu.rowNoclip setOn:g_noclipOn]; }
-(void)noRecoilChanged:(UISwitch*)sw  { g_noRecoilOn=sw.isOn;  if(g_noRecoilOn&&!g_initDone)InitClasses(); [_menu.rowNoRecoil setOn:g_noRecoilOn]; }
-(void)wallhackChanged:(UISwitch*)sw  { g_wallhackOn=sw.isOn;  if(g_wallhackOn&&!g_initDone)InitClasses(); [_menu.rowWallhack setOn:g_wallhackOn]; }
-(void)rapidFireChanged:(UISwitch*)sw { g_rapidFireOn=sw.isOn; if(g_rapidFireOn&&!g_initDone)InitClasses(); [_menu.rowRapidFire setOn:g_rapidFireOn]; }
-(void)fovChanged:(UISlider*)sl { g_aimFov=sl.value; _menu.fovLabel.text=[NSString stringWithFormat:@"%.0f°",g_aimFov]; if(g_aimOn)[_fovView setNeedsDisplay]; }
-(void)boneChanged:(UISegmentedControl*)seg { g_aimBone=(int)seg.selectedSegmentIndex; }

-(void)tick {
    if (!g_initDone&&(g_espOn||g_aimOn||g_godOn||g_infAmmoOn||g_speedOn||g_noRecoilOn||g_wallhackOn||g_rapidFireOn)) InitClasses();
    if (g_espOn)       { UpdateESP(); [_espView setNeedsDisplay]; }
    if (g_godOn)       TickGodMode();
    if (g_infAmmoOn)   TickInfAmmo();
    if (g_speedOn)     TickSpeed();
    if (g_noRecoilOn)  TickNoRecoil();
    if (g_wallhackOn)  TickWallhack();
    if (g_rapidFireOn) TickRapidFire();
}

-(void)doShow {
    _pill.hidden=YES; _menu.hidden=NO; _menu.alpha=0;
    _menu.transform=CGAffineTransformMakeScale(.88f,.88f);
    [UIView animateWithDuration:kDur delay:0 options:UIViewAnimationOptionCurveEaseOut animations:^{
        self->_menu.alpha=1; self->_menu.transform=CGAffineTransformIdentity;
    } completion:nil];
}
-(void)doHide {
    [UIView animateWithDuration:kDur delay:0 options:UIViewAnimationOptionCurveEaseIn animations:^{
        self->_menu.alpha=0; self->_menu.transform=CGAffineTransformMakeScale(.94f,.94f);
    } completion:^(BOOL _){
        self->_menu.hidden=YES; self->_menu.transform=CGAffineTransformIdentity; self->_pill.hidden=NO;
    }];
}
-(void)show{[self doShow];}
@end

// ═══════════════════════════════════════════════════════════════════════════════
// Init
// ═══════════════════════════════════════════════════════════════════════════════
__attribute__((constructor))
static void Init(void) {
    dispatch_async(dispatch_get_main_queue(),^{
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(1.5*NSEC_PER_SEC)),
                       dispatch_get_main_queue(),^{
            [[CheatController shared] show];
        });
    });
}
