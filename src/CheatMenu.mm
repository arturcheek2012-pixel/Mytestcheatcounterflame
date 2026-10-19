#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <dlfcn.h>
#import <mach-o/dyld.h>
#import <mach/mach.h>
#import <signal.h>
#import <setjmp.h>
#import <math.h>

static const CGFloat kR    = 10.0f;
static const NSTimeInterval kDur = 0.18;
static inline UIColor* C(CGFloat r,CGFloat g,CGFloat b,CGFloat a){
    return [UIColor colorWithRed:r green:g blue:b alpha:a];
}
typedef struct { float x,y,z; } Vec3;

// ─── offsets — verified against il2cpp_dump.txt ─────────────────────────────
// PlayerCulling static:        Instances                0x08
// PlayerCulling instance:      _controller              0x18  (PlayerController)
//                              _occluded                0x48
// PlayerController:            _fpsCamera               0x28  (PlayerFPSCamera)
//                              _armsController          0x60  (ArmsController)
//                              _view                    0x80  (PhotonView)
//                              _animatorController      0x98  (PlayerAnimatorController)
//                              _isDeath                 0xA8
// PhotonView:                  <IsMine>k__BackingField  0x60
// PlayerAnimatorController:    _skeleton                0x68  (PlayerSkeleton)
// PlayerSkeleton:              _headBone                0xA8  (Transform)
//                              _chestBone               0xB0  (Transform)
// PlayerFPSCamera:             _movement                0x130 (CameraMovementController)
// CameraMovementController:    fpCameraTransform        0x20
//                              pitch                    0x3C  ← input/target pitch
//                              yaw                      0x40  ← input/target yaw
//                              cameraPitch              0x50  ← accumulated/applied pitch
// ArmsController:              knifeWeapon              0x58  (WeaponController)
//                              timeSinceLastShoot       0x134 (float — resets to 0 on shot)
// WeaponController:            Skin                     0xE0  (Il2CppString*)
#define OFF_CULLING_CTRL        0x18
#define OFF_CTRL_VIEW           0x80
#define OFF_VIEW_ISMINE         0x60
#define OFF_CTRL_ISDEATH        0xA8
#define OFF_CULLING_OCCLUDED    0x48
#define OFF_CTRL_ANIMATOR       0x98
#define OFF_ANIMATOR_SKEL       0x68
#define OFF_SKEL_HEAD           0xA8
#define OFF_SKEL_CHEST          0xB0
#define OFF_CTRL_FPSCAM         0x28
#define OFF_FPSCAM_MOVEMENT     0x130
#define OFF_CAMCTRL_PITCH       0x3C
#define OFF_CAMCTRL_YAW         0x40
#define OFF_CAMCTRL_CAMPITCH    0x50
#define OFF_CTRL_ARMS           0x60
#define OFF_ARMS_KNIFE          0x58
#define OFF_ARMS_LASTSHOT       0x134
#define OFF_WC_SKIN             0xE0

static void*    (*fp_domain_get)(void);
static void**   (*fp_domain_assemblies)(void*,size_t*);
static void*    (*fp_assembly_image)(void*);
static char*    (*fp_image_name)(void*);
static size_t   (*fp_image_class_count)(void*);
static void*    (*fp_image_class)(void*,size_t);
static char*    (*fp_class_name)(void*);
static char*    (*fp_class_ns)(void*);
static void*    (*fp_class_parent)(void*);
static void*    (*fp_class_methods)(void*,void**);
static char*    (*fp_method_name)(void*);
static uint32_t (*fp_method_params)(void*);
static void*    (*fp_class_fields)(void*,void**);
static char*    (*fp_field_name)(void*);
static size_t   (*fp_field_offset)(void*);
static void*    (*fp_class_from_name)(void*,const char*,const char*);
static void*    (*fp_class_static_data)(void*);
static void*    (*fp_class_method_from_name)(void*,const char*,int);
static void*    (*fp_runtime_invoke)(void*,void*,void**,void**);
static void*    (*fp_object_unbox)(void*);
static void*    (*fp_string_new)(const char*);

static BOOL g_apiLoaded=NO;
static BOOL LoadAPI(void){
    if(g_apiLoaded)return YES;
#define R(p,s) p=(__typeof__(p))dlsym(RTLD_DEFAULT,s)
    R(fp_domain_get,"il2cpp_domain_get");
    R(fp_domain_assemblies,"il2cpp_domain_get_assemblies");
    R(fp_assembly_image,"il2cpp_assembly_get_image");
    R(fp_image_name,"il2cpp_image_get_name");
    R(fp_image_class_count,"il2cpp_image_get_class_count");
    R(fp_image_class,"il2cpp_image_get_class");
    R(fp_class_name,"il2cpp_class_get_name");
    R(fp_class_ns,"il2cpp_class_get_namespace");
    R(fp_class_parent,"il2cpp_class_get_parent");
    R(fp_class_methods,"il2cpp_class_get_methods");
    R(fp_method_name,"il2cpp_method_get_name");
    R(fp_method_params,"il2cpp_method_get_param_count");
    R(fp_class_fields,"il2cpp_class_get_fields");
    R(fp_field_name,"il2cpp_field_get_name");
    R(fp_field_offset,"il2cpp_field_get_offset");
    R(fp_class_from_name,"il2cpp_class_from_name");
    R(fp_class_static_data,"il2cpp_class_get_static_field_data");
    R(fp_class_method_from_name,"il2cpp_class_get_method_from_name");
    R(fp_runtime_invoke,"il2cpp_runtime_invoke");
    R(fp_object_unbox,"il2cpp_object_unbox");
    R(fp_string_new,"il2cpp_string_new");
#undef R
    g_apiLoaded=(fp_domain_get!=NULL&&fp_class_from_name!=NULL);
    return g_apiLoaded;
}

// ─── safe memory ─────────────────────────────────────────────────────────────

static BOOL IsPtr(const void*p){
    uintptr_t v=(uintptr_t)p;
    return v>0x10000UL&&v<0x00FFFFFFFFFFFFFFULL;
}
static BOOL SafeRead(const void*src,void*dst,vm_size_t size){
    if(!IsPtr(src))return NO;
    vm_size_t out=0;
    return vm_read_overwrite(mach_task_self(),(vm_address_t)src,size,(vm_address_t)dst,&out)==KERN_SUCCESS&&out==size;
}
static void*   RdPtr(const void*b,size_t o){if(!IsPtr(b))return NULL;void*v=NULL;return SafeRead((const uint8_t*)b+o,&v,sizeof(void*))?v:NULL;}
static int32_t RdI32(const void*b,size_t o){int32_t v=0;SafeRead((const uint8_t*)b+o,&v,sizeof(int32_t));return v;}
static float   RdF32(const void*b,size_t o){float v=0;SafeRead((const uint8_t*)b+o,&v,sizeof(float));return v;}
static BOOL    RdBool(const void*b,size_t o){bool v=false;SafeRead((const uint8_t*)b+o,&v,sizeof(bool));return v?YES:NO;}

// ─── signal recovery ─────────────────────────────────────────────────────────

static __thread sigjmp_buf   tls_jmp;
static __thread volatile int tls_armed=0;
static struct sigaction      g_oldSEGV,g_oldBUS;

static void sig_recover(int sig,siginfo_t*info,void*uctx){
    if(tls_armed){tls_armed=0;siglongjmp(tls_jmp,1);}
    struct sigaction*old=(sig==SIGSEGV)?&g_oldSEGV:&g_oldBUS;
    sigaction(sig,old,NULL);raise(sig);
}
static void InstallRecovery(void){
    static dispatch_once_t once;
    dispatch_once(&once,^{
        struct sigaction sa;memset(&sa,0,sizeof(sa));
        sa.sa_sigaction=sig_recover;sa.sa_flags=SA_SIGINFO;sigemptyset(&sa.sa_mask);
        sigaction(SIGSEGV,&sa,&g_oldSEGV);sigaction(SIGBUS,&sa,&g_oldBUS);
    });
}
static void* SafeInvoke(void*method,void*obj,void**params){
    if(!IsPtr(method)||!fp_runtime_invoke)return NULL;
    void*result=NULL;tls_armed=1;
    if(sigsetjmp(tls_jmp,1)==0){void*exc=NULL;result=fp_runtime_invoke(method,obj,params,&exc);if(exc)result=NULL;}
    tls_armed=0;return result;
}
static void SafeWriteF(void*obj,size_t off,float val){
    if(!IsPtr(obj))return;
    tls_armed=1;
    if(sigsetjmp(tls_jmp,1)==0) *(float*)((uint8_t*)obj+off)=val;
    tls_armed=0;
}
static void SafeWritePtr(void*obj,size_t off,void*val){
    if(!IsPtr(obj))return;
    tls_armed=1;
    if(sigsetjmp(tls_jmp,1)==0) *(void**)((uint8_t*)obj+off)=val;
    tls_armed=0;
}

// ─── unity base ──────────────────────────────────────────────────────────────

static uintptr_t g_unityBase=0;
static uintptr_t UnityBase(void){
    if(g_unityBase)return g_unityBase;
    for(uint32_t i=0,n=_dyld_image_count();i<n;i++){
        const char*nm=_dyld_get_image_name(i);
        if(nm&&strstr(nm,"UnityFramework")){g_unityBase=(uintptr_t)_dyld_get_image_header(i);break;}
    }
    return g_unityBase;
}

static void*g_imgCSharp=NULL,*g_imgUnity=NULL,*g_pcClass=NULL;
static void*g_getTransM=NULL,*g_getPosM=NULL,*g_getMainM=NULL,*g_w2sM=NULL;
static void*g_setEulerM=NULL,*g_getEulerM=NULL;
static void*g_wcClass=NULL,*g_refreshMaterialM=NULL;
static BOOL g_initDone=NO;

static void InitClasses(void){
    if(g_initDone)return;if(!LoadAPI())return;
    void*domain=fp_domain_get();if(!domain)return;
    size_t n=0;void**asms=fp_domain_assemblies(domain,&n);
    for(size_t i=0;i<n;i++){
        void*img=fp_assembly_image(asms[i]);if(!img)continue;
        const char*nm=fp_image_name(img);if(!nm)continue;
        if(!g_imgCSharp&&strcmp(nm,"Assembly-CSharp.dll")==0)g_imgCSharp=img;
        if(!g_imgUnity&&(strcmp(nm,"UnityEngine.CoreModule.dll")==0||
                         strcmp(nm,"UnityEngine.dll")==0))g_imgUnity=img;
    }
    if(g_imgCSharp){
        g_pcClass=fp_class_from_name(g_imgCSharp,"","PlayerCulling");
        g_wcClass=fp_class_from_name(g_imgCSharp,"ScarletWork.Weapon","WeaponController");
        if(g_wcClass)g_refreshMaterialM=fp_class_method_from_name(g_wcClass,"RefreshMaterial",0);
    }
    if(g_imgUnity){
        void*camC =fp_class_from_name(g_imgUnity,"UnityEngine","Camera");
        void*compC=fp_class_from_name(g_imgUnity,"UnityEngine","Component");
        void*trnC =fp_class_from_name(g_imgUnity,"UnityEngine","Transform");
        if(camC){g_getMainM=fp_class_method_from_name(camC,"get_main",0);
                 g_w2sM    =fp_class_method_from_name(camC,"WorldToScreenPoint",1);}
        if(compC) g_getTransM=fp_class_method_from_name(compC,"get_transform",0);
        if(trnC){g_getPosM  =fp_class_method_from_name(trnC,"get_position",0);
                 g_setEulerM=fp_class_method_from_name(trnC,"set_eulerAngles",1);
                 g_getEulerM=fp_class_method_from_name(trnC,"get_eulerAngles",0);}
    }
    UnityBase();
    g_initDone=(g_pcClass!=NULL&&g_getTransM!=NULL&&g_getPosM!=NULL&&
                g_getMainM!=NULL&&g_w2sM!=NULL&&fp_object_unbox!=NULL);
}

// ─── unity helpers ───────────────────────────────────────────────────────────

static Vec3 GetPos(void*obj){
    Vec3 z={0,0,0};
    if(!IsPtr(obj)||!g_getTransM||!g_getPosM||!fp_object_unbox)return z;
    void*tr=SafeInvoke(g_getTransM,obj,NULL);if(!IsPtr(tr))return z;
    void*bp=SafeInvoke(g_getPosM,tr,NULL);if(!IsPtr(bp))return z;
    Vec3*p=(Vec3*)fp_object_unbox(bp);return p?*p:z;
}
static Vec3 GetTransformPos(void*tr){
    Vec3 z={0,0,0};
    if(!IsPtr(tr)||!g_getPosM||!fp_object_unbox)return z;
    void*bp=SafeInvoke(g_getPosM,tr,NULL);if(!IsPtr(bp))return z;
    Vec3*p=(Vec3*)fp_object_unbox(bp);return p?*p:z;
}
static CGPoint W2S(Vec3 wp){
    const CGPoint bad={-1,-1};
    if(!g_getMainM||!g_w2sM||!fp_object_unbox)return bad;
    void*cam=SafeInvoke(g_getMainM,NULL,NULL);if(!IsPtr(cam))return bad;
    void*params[1]={&wp};
    void*br=SafeInvoke(g_w2sM,cam,params);if(!IsPtr(br))return bad;
    Vec3*sv=(Vec3*)fp_object_unbox(br);if(!sv||sv->z<=0.0f)return bad;
    CGFloat sc=[UIScreen mainScreen].scale;
    CGFloat uH=[UIScreen mainScreen].bounds.size.height;
    return CGPointMake(sv->x/sc,uH-sv->y/sc);
}

// читает IL2CPP строку (UTF-16, 0x10=len, 0x14=chars)
static NSString* ReadIL2CppStr(const void*strPtr){
    if(!IsPtr(strPtr))return @"";
    int32_t len=RdI32(strPtr,0x10);
    if(len<=0||len>256)return @"";
    unichar*buf=(unichar*)malloc((size_t)len*sizeof(unichar));
    for(int i=0;i<len;i++){
        uint16_t ch=0;SafeRead((const uint8_t*)strPtr+0x14+(size_t)i*2,&ch,2);buf[i]=ch;
    }
    NSString*s=[NSString stringWithCharacters:buf length:(NSUInteger)len];
    free(buf);return s?s:@"";
}

// localCtrl → PlayerFPSCamera._movement → CameraMovementController
static void* CamCtrlFromLocal(void*localCtrl){
    if(!IsPtr(localCtrl))return NULL;
    void*fpsCam=RdPtr(localCtrl,OFF_CTRL_FPSCAM);   // PlayerController._fpsCamera @0x28
    if(!IsPtr(fpsCam))return NULL;
    void*c=RdPtr(fpsCam,OFF_FPSCAM_MOVEMENT);        // PlayerFPSCamera._movement @0x130
    return IsPtr(c)?c:NULL;
}

// localCtrl → animator → skeleton → bone Transform
static void* BoneFromCtrl(void*ctrl,size_t boneOff){
    void*animator=RdPtr(ctrl,OFF_CTRL_ANIMATOR);if(!IsPtr(animator))return NULL;
    void*skel    =RdPtr(animator,OFF_ANIMATOR_SKEL);if(!IsPtr(skel))return NULL;
    void*bone    =RdPtr(skel,boneOff);return IsPtr(bone)?bone:NULL;
}

// ─── ApplyCamAngle ───────────────────────────────────────────────────────────
// Пишет напрямую в три поля CameraMovementController через SafeWriteF.
// Никаких IL2CPP вызовов — исключает конфликты с Update().
// pitch @0x3C (target), cameraPitch @0x50 (accumulated) — пишем оба
// чтобы не угадывать какой из них игра читает для рендера в текущем кадре.
// defeats: игра читает pitch/yaw как target и применяет в CameraMovementController.Update()
// caught-by: если Update() запускается после нашего write и перетирает — тогда эффект
//            отложен на 1 кадр (16ms); на практике не ощутимо на 60fps
static void ApplyCamAngle(void*camCtrl,float pitch,float yaw){
    if(!IsPtr(camCtrl))return;
    SafeWriteF(camCtrl,OFF_CAMCTRL_PITCH,   pitch);   // 0x3C — input/target pitch
    SafeWriteF(camCtrl,OFF_CAMCTRL_YAW,     yaw);     // 0x40 — input/target yaw
    SafeWriteF(camCtrl,OFF_CAMCTRL_CAMPITCH,pitch);   // 0x50 — accumulated pitch (applied)
}

// ─── ESP / Aim / Silent ──────────────────────────────────────────────────────

#define MAX_ESP 64
typedef struct{CGFloat fx,fy,hx,hy;BOOL valid;}ESPEntry;
static ESPEntry g_esp[MAX_ESP];
static int      g_espCount=0;
static BOOL     g_espOn=NO;
static BOOL     g_aimOn=NO;
static BOOL     g_aimHead=YES;
static CGFloat  g_fovRadius=80.0f;
static BOOL     g_silentOn=NO;
static CGFloat  g_silentFov=200.0f;

// ─── skin changer ─────────────────────────────────────────────────────────────
// Работает в два шага:
// 1. READ — читает текущий skin ID из WeaponController.Skin, строит пул вариантов
//           (базовый ID + инкременты/декременты числового суффикса, до 101 штуки)
// 2. ◄/► — цикл по пулу, каждый вариант пишется в Skin + вызывается RefreshMaterial()
//
// caught-by: сервер может сбросить визуал при следующем RPC sync — только local-side.
// Для смены на конкретный известный ID — жми READ на нужном оружии, запиши строку,
// захардкоди в kKnifeSkins ниже.
static const char* kKnifeSkins[]={
    // FILL: вставь реальные skin ID из дампа или из READ-лога
    // пример: "Skin_Knife_Karambit_Default", "Skin_Knife_Karambit_01" и т.д.
    NULL  // sentinel — массив пустой → READ заполнит пул автоматически
};
static NSMutableArray<NSString*>* g_skinPool=nil;
static int      g_skinPoolIdx=0;
static NSString*g_skinLabel=@"press READ to scan skin ID";

// Строит пул вариантов от базового ID.
// Если ID оканчивается цифрами ("knife_skin_03"), генерирует соседние номера.
static void BuildSkinPool(NSString*base){
    if(!base.length)return;
    NSMutableArray<NSString*>*pool=[NSMutableArray arrayWithObject:base];
    // из hardcoded массива (если не пустой)
    for(int i=0;kKnifeSkins[i];i++){
        NSString*s=[NSString stringWithUTF8String:kKnifeSkins[i]];
        if(![pool containsObject:s])[pool addObject:s];
    }
    // числовой суффикс
    NSUInteger pos=base.length;
    while(pos>0&&isdigit([base characterAtIndex:pos-1]))pos--;
    if(pos<base.length){
        NSString*pfx=[base substringToIndex:pos];
        int num=[[base substringFromIndex:pos]intValue];
        for(int d=1;d<=50;d++){
            [pool addObject:[NSString stringWithFormat:@"%@%d",pfx,num+d]];
            if(num-d>=0)[pool addObject:[NSString stringWithFormat:@"%@%d",pfx,num-d]];
        }
    }
    g_skinPool=pool;
    g_skinPoolIdx=0;
}

static void UpdateESP(void){
    g_espCount=0;
    if(!g_espOn||!IsPtr(g_pcClass)||!fp_class_static_data)return;
    void*sd=fp_class_static_data(g_pcClass);if(!IsPtr(sd))return;
    void*list=RdPtr(sd,0x8);if(!IsPtr(list))return;
    void*arr=RdPtr(list,0x10);int32_t sz=RdI32(list,0x18);
    if(!IsPtr(arr)||sz<=0||sz>200)return;
    int n=sz<MAX_ESP?sz:MAX_ESP;
    for(int i=0;i<n;i++){
        void*culling=RdPtr(arr,0x20+(size_t)i*8);if(!IsPtr(culling))continue;
        void*ctrl   =RdPtr(culling,OFF_CULLING_CTRL);if(!IsPtr(ctrl))continue;
        if(RdBool(ctrl,OFF_CTRL_ISDEATH))continue;
        void*view=RdPtr(ctrl,OFF_CTRL_VIEW);
        if(IsPtr(view)&&RdBool(view,OFF_VIEW_ISMINE))continue;
        if(RdBool(culling,OFF_CULLING_OCCLUDED))continue;
        Vec3 foot=GetPos(culling);
        if(foot.x==0&&foot.y==0&&foot.z==0)continue;
        Vec3 head={foot.x,foot.y+1.75f,foot.z};
        void*hbone=BoneFromCtrl(ctrl,OFF_SKEL_HEAD);
        if(IsPtr(hbone)){Vec3 hp=GetTransformPos(hbone);if(hp.x!=0||hp.y!=0||hp.z!=0)head=hp;}
        CGPoint fs=W2S(foot);if(fs.x<0)continue;
        CGPoint hs=W2S(head);if(hs.x<0)continue;
        g_esp[g_espCount++]=(ESPEntry){fs.x,fs.y,hs.x,hs.y,YES};
    }
}

// ─── FindLocalCtrl ───────────────────────────────────────────────────────────
// Выделено в отдельную функцию — не зависит от наличия врагов в списке.
// Сканирует PlayerCulling.Instances, возвращает PlayerController с IsMine=YES.
static void* FindLocalCtrl(void){
    if(!IsPtr(g_pcClass)||!fp_class_static_data)return NULL;
    void*sd=fp_class_static_data(g_pcClass);if(!IsPtr(sd))return NULL;
    void*list=RdPtr(sd,0x8);if(!IsPtr(list))return NULL;
    void*arr=RdPtr(list,0x10);int32_t sz=RdI32(list,0x18);
    if(!IsPtr(arr)||sz<=0||sz>200)return NULL;
    int n=sz<MAX_ESP?sz:MAX_ESP;
    for(int i=0;i<n;i++){
        void*culling=RdPtr(arr,0x20+(size_t)i*8);if(!IsPtr(culling))continue;
        void*ctrl   =RdPtr(culling,OFF_CULLING_CTRL);if(!IsPtr(ctrl))continue;
        void*view   =RdPtr(ctrl,OFF_CTRL_VIEW);
        if(IsPtr(view)&&RdBool(view,OFF_VIEW_ISMINE))return ctrl;
    }
    return NULL;
}

// ─── FindBestTarget ──────────────────────────────────────────────────────────
// Ищет ближайшего к центру экрана видимого живого врага в радиусе fovR.
// Возвращает YES + мировую позицию кости в outWP.
static BOOL FindBestTarget(CGFloat fovR,Vec3*outWP){
    if(!IsPtr(g_pcClass)||!fp_class_static_data)return NO;
    void*sd=fp_class_static_data(g_pcClass);if(!IsPtr(sd))return NO;
    void*list=RdPtr(sd,0x8);if(!IsPtr(list))return NO;
    void*arr=RdPtr(list,0x10);int32_t sz=RdI32(list,0x18);
    if(!IsPtr(arr)||sz<=0||sz>200)return NO;
    CGSize scr=[UIScreen mainScreen].bounds.size;
    CGPoint ctr=CGPointMake(scr.width*0.5f,scr.height*0.5f);
    CGFloat bestDist=fovR;
    BOOL found=NO;
    int n=sz<MAX_ESP?sz:MAX_ESP;
    for(int i=0;i<n;i++){
        void*culling=RdPtr(arr,0x20+(size_t)i*8);if(!IsPtr(culling))continue;
        void*ctrl   =RdPtr(culling,OFF_CULLING_CTRL);if(!IsPtr(ctrl))continue;
        if(RdBool(ctrl,OFF_CTRL_ISDEATH))continue;
        void*view=RdPtr(ctrl,OFF_CTRL_VIEW);
        if(IsPtr(view)&&RdBool(view,OFF_VIEW_ISMINE))continue; // пропускаем себя
        if(RdBool(culling,OFF_CULLING_OCCLUDED))continue;
        void*bone=BoneFromCtrl(ctrl,g_aimHead?OFF_SKEL_HEAD:OFF_SKEL_CHEST);
        if(!IsPtr(bone))continue;
        Vec3 bwp=GetTransformPos(bone);
        if(bwp.x==0&&bwp.y==0&&bwp.z==0)continue;
        CGPoint sp=W2S(bwp);if(sp.x<0)continue;
        CGFloat dx=sp.x-ctr.x,dy=sp.y-ctr.y;
        CGFloat d=sqrtf(dx*dx+dy*dy);
        if(d<bestDist){bestDist=d;*outWP=bwp;found=YES;}
    }
    return found;
}

// Pitch/yaw от позиции камеры до мировой точки
static BOOL CalcAngles(Vec3 worldPos,float*outPitch,float*outYaw){
    if(!g_getMainM||!g_getTransM)return NO;
    void*cam=SafeInvoke(g_getMainM,NULL,NULL);if(!IsPtr(cam))return NO;
    void*camTr=SafeInvoke(g_getTransM,cam,NULL);if(!IsPtr(camTr))return NO;
    Vec3 cp=GetTransformPos(camTr);
    float ddx=worldPos.x-cp.x,ddy=worldPos.y-cp.y,ddz=worldPos.z-cp.z;
    float dist3d=sqrtf(ddx*ddx+ddy*ddy+ddz*ddz);
    if(dist3d<0.01f)return NO;
    *outPitch=-asinf(ddy/dist3d)*(180.0f/(float)M_PI);
    *outYaw  = atan2f(ddx,ddz)*(180.0f/(float)M_PI);
    return YES;
}

// ─── UpdateAim ───────────────────────────────────────────────────────────────
// 1. FindLocalCtrl() — независимо от наличия врагов
// 2. CamCtrlFromLocal() — по verified chain: ctrl→fpsCam(0x28)→camCtrl(0x130)
// 3. FindBestTarget() — ближайший враг в FOV
// 4. CalcAngles() — pitch/yaw от камеры до кости
// 5. ApplyCamAngle() — 3x SafeWriteF, без IL2CPP
static void UpdateAim(void){
    if(!g_aimOn||!g_initDone)return;

    void*localCtrl=FindLocalCtrl();
    if(!IsPtr(localCtrl))return;  // нет локального игрока в списке — ждём spawn

    void*camCtrl=CamCtrlFromLocal(localCtrl);
    if(!IsPtr(camCtrl))return;    // нет CameraMovementController — неожиданная ситуация

    Vec3 bestWP={0,0,0};
    if(!FindBestTarget(g_fovRadius,&bestWP))return;

    float pitch=0,yaw=0;
    if(!CalcAngles(bestWP,&pitch,&yaw))return;

    ApplyCamAngle(camCtrl,pitch,yaw);
    // body yaw не трогаем: ApplyBodyYaw использует IL2CPP invoke и может упасть;
    // в TPS тело поворачивается собственной анимационной системой по velocity
}

// ─── UpdateSilentAim ─────────────────────────────────────────────────────────
// Снапает камеру только в момент выстрела.
// Выстрел определяется по сбросу ArmsController.timeSinceLastShoot (0x134):
//   предыдущий тик: 1.2s → текущий тик: 0.001s → разница > 5ms → выстрел.
// defeats: камера не дёргается при обычном движении, только на 1 кадр выстрела.
// caught-by: если Unity Update идёт после нашего write в этом же кадре —
//            bullet direction уже зафиксирована; обычно не критично на 60fps WiFi.
static float g_prevShotTime=999.0f;
static void UpdateSilentAim(void){
    if(!g_silentOn||!g_initDone)return;

    void*localCtrl=FindLocalCtrl();
    if(!IsPtr(localCtrl))return;

    void*armsCtrl=RdPtr(localCtrl,OFF_CTRL_ARMS);    // PlayerController._armsController @0x60
    if(!IsPtr(armsCtrl))return;

    float shotTime=RdF32(armsCtrl,OFF_ARMS_LASTSHOT); // ArmsController.timeSinceLastShoot @0x134
    BOOL justFired=(shotTime<g_prevShotTime-0.005f);   // таймер сбросился → выстрел
    g_prevShotTime=shotTime;
    if(!justFired)return;

    void*camCtrl=CamCtrlFromLocal(localCtrl);
    if(!IsPtr(camCtrl))return;

    Vec3 bestWP={0,0,0};
    if(!FindBestTarget(g_silentFov,&bestWP))return;

    float pitch=0,yaw=0;
    if(!CalcAngles(bestWP,&pitch,&yaw))return;

    ApplyCamAngle(camCtrl,pitch,yaw);
    // тело не трогаем при silent — меньше заметно
}

// ─── knife skin changer helpers ───────────────────────────────────────────────

// Находит WeaponController ножа через localCtrl → _armsController → knifeWeapon
static void* GetKnifeWC(void){
    void*localCtrl=FindLocalCtrl();if(!IsPtr(localCtrl))return NULL;
    void*armsCtrl=RdPtr(localCtrl,OFF_CTRL_ARMS);if(!IsPtr(armsCtrl))return NULL;
    void*knifeWC =RdPtr(armsCtrl,OFF_ARMS_KNIFE);  // ArmsController.knifeWeapon @0x58
    return IsPtr(knifeWC)?knifeWC:NULL;
}

// Читает WeaponController.Skin (IL2CPP string @0xE0)
static NSString* ReadKnifeSkinId(void){
    void*wc=GetKnifeWC();if(!IsPtr(wc))return @"knife WC not found";
    void*skinStr=RdPtr(wc,OFF_WC_SKIN);
    if(!IsPtr(skinStr))return @"skin ptr null";
    NSString*s=ReadIL2CppStr(skinStr);
    return s.length?s:@"(empty string)";
}

// Записывает skin ID и вызывает RefreshMaterial()
// caught-by: сервер может откатить визуал при следующем network sync — только client-side
static BOOL ApplyKnifeSkinId(const char*skinId){
    if(!skinId||!fp_string_new)return NO;
    void*wc=GetKnifeWC();if(!IsPtr(wc))return NO;
    void*newStr=fp_string_new(skinId);if(!IsPtr(newStr))return NO;
    SafeWritePtr(wc,OFF_WC_SKIN,newStr);            // WeaponController.Skin @0xE0
    if(g_refreshMaterialM)SafeInvoke(g_refreshMaterialM,wc,NULL);
    return YES;
}

// ─── il2cpp dump ─────────────────────────────────────────────────────────────

static NSString* PerformDump(void){
    if(!LoadAPI())return @"error: API not loaded";
    void*domain=fp_domain_get();if(!domain)return @"error: domain NULL";
    uintptr_t base=UnityBase();
    size_t ac=0;void**asms=fp_domain_assemblies(domain,&ac);
    if(!asms)return @"error: assemblies NULL";
    NSMutableString*out=[NSMutableString string];
    [out appendFormat:@"// IL2CPP Dump\n// base: 0x%lx\n\n",base];
    NSUInteger total=0;
    for(size_t ai=0;ai<ac;ai++){
        void*img=fp_assembly_image(asms[ai]);if(!img)continue;
        const char*inm=fp_image_name(img);
        size_t cc=fp_image_class_count(img);
        [out appendFormat:@"\n// === %s (%zu) ===\n",inm?:"?",cc];
        for(size_t ci=0;ci<cc;ci++){
            void*klass=fp_image_class(img,ci);if(!klass)continue;
            const char*ns=fp_class_ns(klass),*nm=fp_class_name(klass);
            void*par=fp_class_parent(klass);const char*pn=par?fp_class_name(par):NULL;
            NSString*full=(ns&&*ns)?[NSString stringWithFormat:@"%s.%s",ns,nm?:"?"]
                                   :[NSString stringWithUTF8String:nm?:"?"];
            pn?[out appendFormat:@"\npublic class %@ : %s {\n",full,pn]
              :[out appendFormat:@"\npublic class %@ {\n",full];
            void*fi=NULL,*fld;
            while((fld=fp_class_fields(klass,&fi)))
                [out appendFormat:@"\t// 0x%zX  %s\n",fp_field_offset(fld),fp_field_name(fld)?:"?"];
            void*mi=NULL,*mth;
            while((mth=fp_class_methods(klass,&mi))){
                const char*mn=fp_method_name(mth);
                uint32_t np=fp_method_params(mth);
                uintptr_t ptr=0;SafeRead(mth,&ptr,sizeof(uintptr_t));
                (base&&ptr>base)?
                    [out appendFormat:@"\t// RVA: 0x%llX  p:%u  %s\n",(unsigned long long)(ptr-base),np,mn?:"?"]
                   :[out appendFormat:@"\t// RVA: N/A  p:%u  %s\n",np,mn?:"?"];
            }
            [out appendString:@"}\n"];total++;
        }
    }
    [out appendFormat:@"\n// Total: %lu classes\n",(unsigned long)total];
    NSString*docs=NSSearchPathForDirectoriesInDomains(NSDocumentDirectory,NSUserDomainMask,YES).firstObject;
    NSString*path=[docs stringByAppendingPathComponent:@"il2cpp_dump.txt"];
    NSError*err=nil;
    [out writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:&err];
    return err?[NSString stringWithFormat:@"error: %@",err.localizedDescription]
              :[NSString stringWithFormat:@"✓ %lu classes",(unsigned long)total];
}

// ─── passthrough ─────────────────────────────────────────────────────────────

@interface PassthroughWindow:UIWindow @end
@implementation PassthroughWindow
-(UIView*)hitTest:(CGPoint)p withEvent:(UIEvent*)e{
    UIView*v=[super hitTest:p withEvent:e];
    return(v==self||v==self.rootViewController.view)?nil:v;
}
@end

@interface PassthroughView:UIView @end
@implementation PassthroughView
-(UIView*)hitTest:(CGPoint)p withEvent:(UIEvent*)e{
    UIView*v=[super hitTest:p withEvent:e];return v==self?nil:v;
}
@end

// ─── ESP overlay ─────────────────────────────────────────────────────────────

@interface ESPView:UIView @end
@implementation ESPView
-(instancetype)init{
    self=[super initWithFrame:[UIScreen mainScreen].bounds];
    self.backgroundColor=[UIColor clearColor];self.userInteractionEnabled=NO;return self;
}
-(void)drawRect:(CGRect)r{
    CGContextRef ctx=UIGraphicsGetCurrentContext();
    if(g_espOn&&g_espCount>0){
        for(int i=0;i<g_espCount;i++){
            ESPEntry*e=&g_esp[i];if(!e->valid)continue;
            CGFloat boxH=e->fy-e->hy;if(boxH<8.0f)boxH=8.0f;
            CGFloat boxW=boxH*0.55f,cx=(e->fx+e->hx)*0.5f;
            CGRect  box=CGRectMake(cx-boxW*0.5f,e->hy,boxW,boxH);
            CGContextSetRGBStrokeColor(ctx,0,0,0,0.60f);CGContextSetLineWidth(ctx,2.2f);CGContextStrokeRect(ctx,box);
            CGContextSetRGBStrokeColor(ctx,1.0f,0.55f,0.0f,0.90f);CGContextSetLineWidth(ctx,1.2f);CGContextStrokeRect(ctx,box);
        }
    }
    if(g_aimOn||g_silentOn){
        CGFloat cx=self.bounds.size.width*0.5f,cy=self.bounds.size.height*0.5f;
        CGFloat fov=g_silentOn?g_silentFov:g_fovRadius;
        CGContextSetRGBStrokeColor(ctx,1.0f,0.55f,g_silentOn?0.80f:0.0f,0.35f);
        CGContextSetLineWidth(ctx,0.9f);
        CGContextStrokeEllipseInRect(ctx,CGRectMake(cx-fov,cy-fov,fov*2,fov*2));
        CGContextSetLineWidth(ctx,0.7f);
        CGContextMoveToPoint(ctx,cx-6,cy);CGContextAddLineToPoint(ctx,cx+6,cy);
        CGContextMoveToPoint(ctx,cx,cy-6);CGContextAddLineToPoint(ctx,cx,cy+6);
        CGContextStrokePath(ctx);
    }
}
@end

// ─── menu ────────────────────────────────────────────────────────────────────

static const CGFloat kPad   =12.0f;
static const CGFloat kBtnH  =34.0f;
static const CGFloat kGap   = 8.0f;
static const CGFloat kSecGap=13.0f;

@interface MenuView:UIView
@property(strong)UIButton*espBtn,*aimBtn,*silentBtn;
@property(strong)UIButton*targetBtn,*skinBtn;
@property(strong)UIButton*dumpBtn,*closeBtn;
@property(strong)UIButton*skinReadBtn,*skinPrevBtn,*skinNextBtn;
@property(strong)UILabel*statusLabel,*fovLabel,*skinLabel;
@property(strong)UISlider*fovSlider;
@end
@implementation MenuView{CGPoint _drag;}

-(UILabel*)sectionLabel:(NSString*)t y:(CGFloat)y{
    UILabel*l=[[UILabel alloc]initWithFrame:CGRectMake(kPad,y,self.bounds.size.width-kPad*2,12)];
    l.text=t;l.font=[UIFont systemFontOfSize:9 weight:UIFontWeightSemibold];
    l.textColor=C(0.45f,0.45f,0.50f,1);[self addSubview:l];return l;
}
-(UIButton*)makeBtn:(NSString*)title frame:(CGRect)f{
    UIButton*b=[UIButton buttonWithType:UIButtonTypeCustom];
    b.frame=f;b.backgroundColor=C(0.14f,0.14f,0.16f,1);
    b.layer.cornerRadius=6;b.layer.borderWidth=1;b.layer.borderColor=C(1.0f,0.55f,0.0f,0.22f).CGColor;
    b.titleLabel.font=[UIFont systemFontOfSize:10 weight:UIFontWeightSemibold];
    [b setTitle:title forState:UIControlStateNormal];
    [b setTitleColor:C(0.88f,0.88f,0.88f,1) forState:UIControlStateNormal];
    [b setTitleColor:C(1.0f,0.55f,0.0f,1)   forState:UIControlStateHighlighted];
    [b addTarget:self action:@selector(btnDown:) forControlEvents:UIControlEventTouchDown];
    [b addTarget:self action:@selector(btnUp:)   forControlEvents:UIControlEventTouchUpInside|UIControlEventTouchUpOutside];
    [self addSubview:b];return b;
}
-(UIImage*)thumbImg{
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(12,12),NO,0);
    CGContextRef c=UIGraphicsGetCurrentContext();
    CGContextSetRGBFillColor(c,1.0f,0.55f,0.0f,1);
    CGContextFillEllipseInRect(c,CGRectMake(0,0,12,12));
    UIImage*i=UIGraphicsGetImageFromCurrentImageContext();UIGraphicsEndImageContext();return i;
}
-(instancetype)initWithFrame:(CGRect)f{
    self=[super initWithFrame:f];
    self.backgroundColor=C(0.08f,0.08f,0.09f,0.96f);
    self.layer.cornerRadius=kR;self.layer.masksToBounds=YES;
    self.layer.borderWidth=1;self.layer.borderColor=C(1.0f,0.55f,0.0f,0.18f).CGColor;
    CGFloat W=f.size.width,innerW=W-kPad*2;
    CGFloat thirdW=(innerW-kGap*2)/3.0f;
    CGFloat halfW =(innerW-kGap)/2.0f;
    // header
    UIView*hdr=[[UIView alloc]initWithFrame:CGRectMake(0,0,W,40)];
    hdr.backgroundColor=C(0.11f,0.11f,0.12f,1);[self addSubview:hdr];
    UILabel*ttl=[[UILabel alloc]initWithFrame:CGRectMake(kPad,0,innerW-32,40)];
    ttl.text=@"cheat";ttl.textAlignment=NSTextAlignmentLeft;
    ttl.font=[UIFont systemFontOfSize:12 weight:UIFontWeightSemibold];
    ttl.textColor=C(1,1,1,0.90f);[hdr addSubview:ttl];
    self.closeBtn=[UIButton buttonWithType:UIButtonTypeCustom];
    self.closeBtn.frame=CGRectMake(W-34,8,24,24);
    self.closeBtn.backgroundColor=C(0.55f,0.10f,0.10f,1);
    self.closeBtn.layer.cornerRadius=6;
    [self.closeBtn setTitle:@"✕" forState:UIControlStateNormal];
    [self.closeBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    self.closeBtn.titleLabel.font=[UIFont systemFontOfSize:12 weight:UIFontWeightBold];
    [hdr addSubview:self.closeBtn];
    UIPanGestureRecognizer*hdrPan=[[UIPanGestureRecognizer alloc]initWithTarget:self action:@selector(pan:)];
    hdrPan.cancelsTouchesInView=NO;[hdr addGestureRecognizer:hdrPan];
    // layout
    CGFloat y=40+kGap;
    // row 1: ESP | AIM | SILENT
    self.espBtn   =[self makeBtn:@"ESP"    frame:CGRectMake(kPad,                    y,thirdW,kBtnH)];
    self.aimBtn   =[self makeBtn:@"AIM"    frame:CGRectMake(kPad+thirdW+kGap,        y,thirdW,kBtnH)];
    self.silentBtn=[self makeBtn:@"SILENT" frame:CGRectMake(kPad+(thirdW+kGap)*2.0f, y,thirdW,kBtnH)];
    y+=kBtnH+kSecGap;
    // row 2: TARGET | KNIFE
    [self sectionLabel:@"TARGET / KNIFE SKIN" y:y];y+=13;
    self.targetBtn=[self makeBtn:@"HEAD"    frame:CGRectMake(kPad,            y,halfW,kBtnH)];
    self.skinBtn  =[self makeBtn:@"KNIFE ▶" frame:CGRectMake(kPad+halfW+kGap,y,halfW,kBtnH)];
    y+=kBtnH+kSecGap;
    // skin read/prev/next row
    CGFloat thirdKnife=(innerW-kGap*2)/3.0f;
    self.skinReadBtn=[self makeBtn:@"READ" frame:CGRectMake(kPad,                    y,thirdKnife,28)];
    self.skinPrevBtn=[self makeBtn:@"◄"   frame:CGRectMake(kPad+thirdKnife+kGap,    y,thirdKnife,28)];
    self.skinNextBtn=[self makeBtn:@"►"   frame:CGRectMake(kPad+(thirdKnife+kGap)*2,y,thirdKnife,28)];
    y+=28+kGap;
    self.skinLabel=[[UILabel alloc]initWithFrame:CGRectMake(kPad,y,innerW,12)];
    self.skinLabel.font=[UIFont monospacedSystemFontOfSize:9 weight:UIFontWeightRegular];
    self.skinLabel.textColor=C(0.5f,0.85f,0.5f,0.90f);
    self.skinLabel.text=g_skinLabel;[self addSubview:self.skinLabel];y+=14;
    // FOV
    [self sectionLabel:@"FOV" y:y];y+=13;
    self.fovLabel=[[UILabel alloc]initWithFrame:CGRectMake(kPad,y,innerW,12)];
    self.fovLabel.font=[UIFont monospacedSystemFontOfSize:10 weight:UIFontWeightRegular];
    self.fovLabel.textColor=C(1.0f,0.55f,0.0f,0.85f);
    self.fovLabel.text=[NSString stringWithFormat:@"%.0f px",g_fovRadius];
    [self addSubview:self.fovLabel];y+=14;
    self.fovSlider=[[UISlider alloc]initWithFrame:CGRectMake(kPad,y,innerW,22)];
    self.fovSlider.minimumValue=20;self.fovSlider.maximumValue=300;self.fovSlider.value=g_fovRadius;
    self.fovSlider.minimumTrackTintColor=C(1.0f,0.55f,0.0f,0.85f);
    self.fovSlider.maximumTrackTintColor=C(0.18f,0.18f,0.18f,1);
    [self.fovSlider setThumbImage:[self thumbImg] forState:UIControlStateNormal];
    [self addSubview:self.fovSlider];y+=28;
    // status
    self.statusLabel=[[UILabel alloc]initWithFrame:CGRectMake(kPad,y,innerW,26)];
    self.statusLabel.font=[UIFont monospacedSystemFontOfSize:9 weight:UIFontWeightRegular];
    self.statusLabel.textColor=C(0.30f,0.70f,0.35f,1);
    self.statusLabel.numberOfLines=2;[self addSubview:self.statusLabel];y+=30;
    self.dumpBtn=[self makeBtn:@"DUMP IL2CPP" frame:CGRectMake(kPad,y,innerW,kBtnH)];
    return self;
}
-(void)btnDown:(UIButton*)b{[UIView animateWithDuration:0.07 animations:^{b.backgroundColor=C(0.22f,0.22f,0.26f,1);b.layer.borderColor=C(1.0f,0.55f,0.0f,0.65f).CGColor;}];}
-(void)btnUp:(UIButton*)b  {[UIView animateWithDuration:0.14 animations:^{b.backgroundColor=C(0.14f,0.14f,0.16f,1);b.layer.borderColor=C(1.0f,0.55f,0.0f,0.22f).CGColor;}];}
-(void)pan:(UIPanGestureRecognizer*)g{
    CGPoint loc=[g locationInView:self.superview];
    if(g.state==UIGestureRecognizerStateBegan)_drag=CGPointMake(loc.x-self.frame.origin.x,loc.y-self.frame.origin.y);
    else if(g.state==UIGestureRecognizerStateChanged){CGRect r=self.frame;r.origin=CGPointMake(loc.x-_drag.x,loc.y-_drag.y);self.frame=r;}
}
@end

// ─── controller ──────────────────────────────────────────────────────────────

@interface CheatController:NSObject
+(instancetype)shared;-(void)toggle;
@end
@implementation CheatController{
    PassthroughWindow*_win;
    MenuView*_menu;
    ESPView*_espView;
    UIButton*_fab;
    CADisplayLink*_dl;
    BOOL _visible;
}
+(instancetype)shared{
    static CheatController*inst;static dispatch_once_t once;
    dispatch_once(&once,^{inst=[CheatController new];});return inst;
}
-(instancetype)init{self=[super init];[self build];return self;}

-(void)build{
    UIWindowScene*scene=nil;
    for(UIScene*s in [UIApplication sharedApplication].connectedScenes)
        if([s isKindOfClass:[UIWindowScene class]]){scene=(UIWindowScene*)s;break;}
    _win=scene?[[PassthroughWindow alloc]initWithWindowScene:scene]
              :[[PassthroughWindow alloc]initWithFrame:[UIScreen mainScreen].bounds];
    _win.windowLevel=UIWindowLevelNormal+100;
    _win.backgroundColor=[UIColor clearColor];
    PassthroughView*pv=[[PassthroughView alloc]initWithFrame:[UIScreen mainScreen].bounds];
    pv.backgroundColor=[UIColor clearColor];
    UIViewController*vc=[UIViewController new];vc.view=pv;
    _win.rootViewController=vc;_win.hidden=NO;
    _espView=[ESPView new];[pv addSubview:_espView];
    CGSize sz=[UIScreen mainScreen].bounds.size;
    CGFloat w=fminf(sz.width-24,310);
    CGFloat h=420;
    _menu=[[MenuView alloc]initWithFrame:CGRectMake((sz.width-w)*0.5f,(sz.height-h)*0.5f,w,h)];
    [pv addSubview:_menu];
    [_menu.closeBtn     addTarget:self action:@selector(doClose)      forControlEvents:UIControlEventTouchUpInside];
    [_menu.espBtn       addTarget:self action:@selector(doESP)        forControlEvents:UIControlEventTouchUpInside];
    [_menu.aimBtn       addTarget:self action:@selector(doAim)        forControlEvents:UIControlEventTouchUpInside];
    [_menu.silentBtn    addTarget:self action:@selector(doSilent)     forControlEvents:UIControlEventTouchUpInside];
    [_menu.targetBtn    addTarget:self action:@selector(doTarget)     forControlEvents:UIControlEventTouchUpInside];
    [_menu.skinBtn      addTarget:self action:@selector(doSkinNext)   forControlEvents:UIControlEventTouchUpInside];
    [_menu.skinReadBtn  addTarget:self action:@selector(doSkinRead)   forControlEvents:UIControlEventTouchUpInside];
    [_menu.skinPrevBtn  addTarget:self action:@selector(doSkinPrev)   forControlEvents:UIControlEventTouchUpInside];
    [_menu.skinNextBtn  addTarget:self action:@selector(doSkinNext)   forControlEvents:UIControlEventTouchUpInside];
    [_menu.dumpBtn      addTarget:self action:@selector(doDump)       forControlEvents:UIControlEventTouchUpInside];
    [_menu.fovSlider    addTarget:self action:@selector(fovChanged:)  forControlEvents:UIControlEventValueChanged];

    _fab=[UIButton buttonWithType:UIButtonTypeCustom];
    _fab.frame=CGRectMake(sz.width-52,90,38,38);
    _fab.backgroundColor=C(1.0f,0.55f,0.0f,0.88f);
    _fab.layer.cornerRadius=19;_fab.layer.borderWidth=1.5f;
    _fab.layer.borderColor=C(1,1,1,0.35f).CGColor;
    [_fab setTitle:@"☰" forState:UIControlStateNormal];
    _fab.titleLabel.font=[UIFont systemFontOfSize:16 weight:UIFontWeightBold];
    [_fab setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    [_fab addTarget:self action:@selector(toggle) forControlEvents:UIControlEventTouchUpInside];
    UIPanGestureRecognizer*fabPan=[[UIPanGestureRecognizer alloc]initWithTarget:self action:@selector(dragFAB:)];
    fabPan.cancelsTouchesInView=NO;[_fab addGestureRecognizer:fabPan];
    [pv addSubview:_fab];

    _dl=[CADisplayLink displayLinkWithTarget:self selector:@selector(tick)];
    _dl.preferredFramesPerSecond=60;
    [_dl addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
}

-(void)dragFAB:(UIPanGestureRecognizer*)g{
    static CGPoint drag;UIView*v=g.view;
    CGPoint loc=[g locationInView:v.superview];
    if(g.state==UIGestureRecognizerStateBegan)
        drag=CGPointMake(loc.x-v.frame.origin.x,loc.y-v.frame.origin.y);
    else if(g.state==UIGestureRecognizerStateChanged){
        CGRect r=v.frame;r.origin=CGPointMake(loc.x-drag.x,loc.y-drag.y);v.frame=r;
    }
}
-(void)tick{
    if(!g_espOn&&!g_aimOn&&!g_silentOn)return;
    if(!g_initDone)InitClasses();
    if(g_espOn)UpdateESP();
    if(g_aimOn)UpdateAim();
    if(g_silentOn)UpdateSilentAim();
    [_espView setNeedsDisplay];
}

-(void)setBtn:(UIButton*)b active:(BOOL)on{
    b.layer.borderColor=on?C(1.0f,0.55f,0.0f,0.65f).CGColor:C(1.0f,0.55f,0.0f,0.22f).CGColor;
    [b setTitleColor:on?C(1.0f,0.55f,0.0f,1):C(0.88f,0.88f,0.88f,1) forState:UIControlStateNormal];
}

-(void)doESP{
    g_espOn=!g_espOn;
    if(g_espOn&&!g_initDone)InitClasses();
    [_menu.espBtn setTitle:g_espOn?@"ESP ON":@"ESP" forState:UIControlStateNormal];
    [self setBtn:_menu.espBtn active:g_espOn];
    _menu.statusLabel.text=g_espOn?@"esp active":@"esp off";
    if(!g_espOn){g_espCount=0;[_espView setNeedsDisplay];}
}
-(void)doAim{
    g_aimOn=!g_aimOn;
    if(g_aimOn&&!g_initDone)InitClasses();
    [_menu.aimBtn setTitle:g_aimOn?@"AIM ON":@"AIM" forState:UIControlStateNormal];
    [self setBtn:_menu.aimBtn active:g_aimOn];
    _menu.statusLabel.text=g_aimOn?@"aim on":@"aim off";
    if(!g_aimOn)[_espView setNeedsDisplay];
}
-(void)doSilent{
    g_silentOn=!g_silentOn;
    if(g_silentOn&&!g_initDone)InitClasses();
    g_prevShotTime=999.0f; // сброс детектора чтобы не сработал сразу
    [_menu.silentBtn setTitle:g_silentOn?@"SILENT ON":@"SILENT" forState:UIControlStateNormal];
    [self setBtn:_menu.silentBtn active:g_silentOn];
    _menu.statusLabel.text=g_silentOn?@"silent on":@"silent off";
    if(!g_silentOn)[_espView setNeedsDisplay];
}
-(void)doTarget{
    g_aimHead=!g_aimHead;
    [_menu.targetBtn setTitle:g_aimHead?@"HEAD":@"BODY" forState:UIControlStateNormal];
}
-(void)fovChanged:(UISlider*)s{
    g_fovRadius=s.value;g_silentFov=s.value*2.5f;
    _menu.fovLabel.text=[NSString stringWithFormat:@"%.0f px",g_fovRadius];
    [_espView setNeedsDisplay];
}

// ── knife skin ──────────────────────────────────────────────────────────────
// READ: читает текущий skin ID → строит пул вариантов (базовый + числовые инкременты)
// ◄/►: цикл по пулу, каждый вариант пишется в WeaponController.Skin + RefreshMaterial
-(void)doSkinRead{
    if(!g_initDone)InitClasses();
    // step-by-step: показывает где именно NULL
    void*localCtrl=FindLocalCtrl();
    if(!IsPtr(localCtrl)){
        _menu.statusLabel.text=@"DIAG: localCtrl NULL\n(not in Instances list)";return;
    }
    void*armsCtrl=RdPtr(localCtrl,OFF_CTRL_ARMS);  // 0x60
    if(!IsPtr(armsCtrl)){
        _menu.statusLabel.text=@"DIAG: armsCtrl NULL @0x60";return;
    }
    void*knifeWC=RdPtr(armsCtrl,OFF_ARMS_KNIFE);   // 0x58
    if(!IsPtr(knifeWC)){
        _menu.statusLabel.text=@"DIAG: knifeWC NULL @0x58\n(take knife out)";return;
    }
    void*skinStr=RdPtr(knifeWC,OFF_WC_SKIN);        // 0xE0
    if(!IsPtr(skinStr)){
        _menu.statusLabel.text=@"DIAG: skinStr NULL @0xE0";return;
    }
    NSString*sid=ReadIL2CppStr(skinStr);
    BuildSkinPool(sid);
    g_skinLabel=sid;
    _menu.skinLabel.text=sid;
    _menu.statusLabel.text=[NSString stringWithFormat:@"pool: %d IDs",(int)g_skinPool.count];
}
-(void)doSkinPrev{
    if(!g_skinPool||g_skinPool.count==0){[self doSkinRead];return;}
    g_skinPoolIdx=(g_skinPoolIdx-1+(int)g_skinPool.count)%(int)g_skinPool.count;
    [self _applySkinFromPool];
}
-(void)doSkinNext{
    if(!g_skinPool||g_skinPool.count==0){[self doSkinRead];return;}
    g_skinPoolIdx=(g_skinPoolIdx+1)%(int)g_skinPool.count;
    [self _applySkinFromPool];
}
-(void)_applySkinFromPool{
    if(!g_skinPool||g_skinPool.count==0)return;
    if(!g_initDone)InitClasses();
    NSString*sid=g_skinPool[(NSUInteger)g_skinPoolIdx];
    BOOL ok=ApplyKnifeSkinId(sid.UTF8String);
    g_skinLabel=sid;
    _menu.skinLabel.text=[NSString stringWithFormat:@"[%d/%d] %@",
                          g_skinPoolIdx+1,(int)g_skinPool.count,sid];
    _menu.statusLabel.text=ok?@"skin applied":@"wc not found";
}

-(void)doDump{
    _menu.dumpBtn.enabled=NO;_menu.statusLabel.text=@"dumping...";
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0),^{
        NSString*res=PerformDump();
        dispatch_async(dispatch_get_main_queue(),^{
            self->_menu.dumpBtn.enabled=YES;self->_menu.statusLabel.text=res;
        });
    });
}
-(void)doClose{
    [UIView animateWithDuration:kDur delay:0 options:UIViewAnimationOptionCurveEaseIn
                     animations:^{self->_menu.alpha=0;self->_menu.transform=CGAffineTransformMakeScale(0.88f,0.88f);}
                     completion:^(BOOL _){self->_menu.hidden=YES;self->_menu.transform=CGAffineTransformIdentity;self->_visible=NO;}];
}
-(void)toggle{
    if(_visible){[self doClose];return;}
    _visible=YES;_menu.hidden=NO;_menu.alpha=0;_menu.transform=CGAffineTransformMakeScale(0.88f,0.88f);
    [UIView animateWithDuration:kDur animations:^{self->_menu.alpha=1;self->_menu.transform=CGAffineTransformIdentity;}];
}
@end

__attribute__((constructor))
static void Init(void){
    InstallRecovery();
    dispatch_async(dispatch_get_main_queue(),^{
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(1.5*NSEC_PER_SEC)),
                       dispatch_get_main_queue(),^{[[CheatController shared]toggle];});
    });
}
