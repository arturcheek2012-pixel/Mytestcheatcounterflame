#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <dlfcn.h>
#import <mach-o/dyld.h>
#import <math.h>

// ═══════════════════════════════════════════════════════════════════════════
// GEOMETRY (landscape)
// ═══════════════════════════════════════════════════════════════════════════
static const CGFloat kW      = 440.0f;
static const CGFloat kH      = 250.0f;
static const CGFloat kHdr    = 40.0f;
static const CGFloat kChamfer= 10.0f;
static const NSTimeInterval kDur = 0.22;

// ═══════════════════════════════════════════════════════════════════════════
// PALETTE (black / orange)
// ═══════════════════════════════════════════════════════════════════════════
static inline UIColor* C(CGFloat r,CGFloat g,CGFloat b,CGFloat a){
    return [UIColor colorWithRed:r green:g blue:b alpha:a];
}
static inline UIColor* ORANGE      (void){ return C(1.00f, 0.45f, 0.05f, 1.00f); }
static inline UIColor* ORANGE_DIM  (void){ return C(1.00f, 0.45f, 0.05f, 0.40f); }
static inline UIColor* BG_DARK     (void){ return C(0.06f, 0.06f, 0.07f, 0.97f); }
static inline UIColor* BG_HEADER   (void){ return C(0.09f, 0.09f, 0.10f, 1.00f); }
static inline UIColor* BG_CARD     (void){ return C(0.11f, 0.11f, 0.12f, 1.00f); }
static inline UIColor* BG_BTN      (void){ return C(0.15f, 0.15f, 0.16f, 1.00f); }
static inline UIColor* BG_BTN_DOWN (void){ return C(0.25f, 0.18f, 0.10f, 1.00f); }
static inline UIColor* TXT_MAIN    (void){ return C(0.95f, 0.95f, 0.95f, 1.00f); }
static inline UIColor* TXT_DIM     (void){ return C(0.55f, 0.55f, 0.58f, 1.00f); }

typedef struct { float x,y,z; } Vec3;

// ═══════════════════════════════════════════════════════════════════════════
// FILL (offsets)
// ═══════════════════════════════════════════════════════════════════════════
#define OFF_CTRL_TEAM_ID   0x00
#define OFF_STATIC_LOCAL   0x00

// ═══════════════════════════════════════════════════════════════════════════
// IL2CPP API
// ═══════════════════════════════════════════════════════════════════════════
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
static void*    (*fp_thread_attach)(void*);

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
    R(fp_thread_attach,"il2cpp_thread_attach");
#undef R
    g_apiLoaded=(fp_domain_get&&fp_class_from_name&&fp_runtime_invoke);
    return g_apiLoaded;
}

static BOOL g_threadAttached=NO;
static void EnsureThreadAttached(void){
    if(g_threadAttached)return;
    if(!fp_domain_get||!fp_thread_attach)return;
    void*domain=fp_domain_get(); if(!domain)return;
    fp_thread_attach(domain); g_threadAttached=YES;
}

// ═══════════════════════════════════════════════════════════════════════════
// MEMORY HELPERS
// ═══════════════════════════════════════════════════════════════════════════
static BOOL IsPtr(const void*p){uintptr_t v=(uintptr_t)p;return v>0x10000UL&&v<0x00FFFFFFFFFFFFFFULL;}
static void* RdPtr(const void*b,size_t o){if(!IsPtr(b))return NULL;void**a=(void**)((const uint8_t*)b+o);if(!IsPtr(a))return NULL;return *a;}
static int32_t RdI32(const void*b,size_t o){if(!IsPtr(b))return 0;return *(int32_t*)((const uint8_t*)b+o);}
static BOOL RdBool(const void*b,size_t o){if(!IsPtr(b))return NO;return *(bool*)((const uint8_t*)b+o);}
static BOOL IsUnityObj(const void*p){
    if(!IsPtr(p))return NO;
    void*klass=*(void**)p; if(!IsPtr(klass))return NO;
    return (uintptr_t)klass>0x100000000ULL;
}

static uintptr_t g_unityBase=0;
static uintptr_t UnityBase(void){
    if(g_unityBase)return g_unityBase;
    for(uint32_t i=0,n=_dyld_image_count();i<n;i++){
        const char*nm=_dyld_get_image_name(i);
        if(nm&&strstr(nm,"UnityFramework")){g_unityBase=(uintptr_t)_dyld_get_image_header(i);break;}
    }
    return g_unityBase;
}

// ═══════════════════════════════════════════════════════════════════════════
// CACHED METHODS
// ═══════════════════════════════════════════════════════════════════════════
static void*g_imgCSharp=NULL,*g_imgUnity=NULL,*g_pcClass=NULL;
static void*g_getTransM=NULL,*g_getPosM=NULL,*g_getMainM=NULL,*g_w2sM=NULL,*g_setEulerM=NULL;
static BOOL g_initDone=NO;

static void InitClasses(void){
    if(g_initDone)return;
    EnsureThreadAttached();
    if(!LoadAPI())return;
    void*domain=fp_domain_get(); if(!domain)return;
    size_t n=0;void**asms=fp_domain_assemblies(domain,&n);
    if(!asms)return;
    for(size_t i=0;i<n;i++){
        void*img=fp_assembly_image(asms[i]); if(!img)continue;
        const char*nm=fp_image_name(img); if(!nm)continue;
        if(!g_imgCSharp&&strcmp(nm,"Assembly-CSharp.dll")==0)g_imgCSharp=img;
        if(!g_imgUnity&&(strcmp(nm,"UnityEngine.CoreModule.dll")==0||strcmp(nm,"UnityEngine.dll")==0))g_imgUnity=img;
    }
    if(g_imgCSharp)g_pcClass=fp_class_from_name(g_imgCSharp,"","PlayerCulling");
    if(g_imgUnity){
        void*camC =fp_class_from_name(g_imgUnity,"UnityEngine","Camera");
        void*compC=fp_class_from_name(g_imgUnity,"UnityEngine","Component");
        void*trnC =fp_class_from_name(g_imgUnity,"UnityEngine","Transform");
        if(camC) {g_getMainM=fp_class_method_from_name(camC,"get_main",0);
                  g_w2sM    =fp_class_method_from_name(camC,"WorldToScreenPoint",1);}
        if(compC)  g_getTransM=fp_class_method_from_name(compC,"get_transform",0);
        if(trnC)  {g_getPosM  =fp_class_method_from_name(trnC,"get_position",0);
                   g_setEulerM=fp_class_method_from_name(trnC,"set_eulerAngles",1);}
    }
    UnityBase();
    if(g_pcClass && g_getMainM && g_w2sM && g_getPosM && g_getTransM)
        g_initDone=YES;
}

// ═══════════════════════════════════════════════════════════════════════════
// UNITY HELPERS
// ═══════════════════════════════════════════════════════════════════════════
static Vec3 GetPos(void*obj){
    Vec3 z={0,0,0};
    if(!IsUnityObj(obj)||!fp_runtime_invoke||!g_getTransM||!g_getPosM)return z;
    void*exc=NULL;
    void*tr=fp_runtime_invoke(g_getTransM,obj,NULL,&exc);
    if(!IsUnityObj(tr)||exc)return z;
    exc=NULL;
    void*bp=fp_runtime_invoke(g_getPosM,tr,NULL,&exc);
    if(!IsPtr(bp)||exc||!fp_object_unbox)return z;
    Vec3*p=(Vec3*)fp_object_unbox(bp);return p?*p:z;
}

static Vec3 GetTransformPos(void*tr){
    Vec3 z={0,0,0};
    if(!IsUnityObj(tr)||!fp_runtime_invoke||!g_getPosM||!fp_object_unbox)return z;
    void*exc=NULL;
    void*bp=fp_runtime_invoke(g_getPosM,tr,NULL,&exc);
    if(!IsPtr(bp)||exc)return z;
    Vec3*p=(Vec3*)fp_object_unbox(bp);return p?*p:z;
}

static CGPoint W2S(Vec3 wp){
    const CGPoint bad={-1,-1};
    if(!fp_runtime_invoke||!g_getMainM||!g_w2sM||!fp_object_unbox)return bad;
    void*exc=NULL;
    void*cam=fp_runtime_invoke(g_getMainM,NULL,NULL,&exc);
    if(!IsUnityObj(cam)||exc)return bad;
    void*params[1]={&wp};exc=NULL;
    void*br=fp_runtime_invoke(g_w2sM,cam,params,&exc);
    if(!IsPtr(br)||exc)return bad;
    Vec3*sv=(Vec3*)fp_object_unbox(br);if(!sv||sv->z<=0.0f)return bad;
    CGFloat sc=[UIScreen mainScreen].scale;
    CGFloat uH=[UIScreen mainScreen].bounds.size.height;
    return CGPointMake(sv->x/sc,uH-sv->y/sc);
}

static void* GetLocalCtrl(void){
    if(!OFF_STATIC_LOCAL||!IsPtr(g_pcClass)||!fp_class_static_data)return NULL;
    void*sd=fp_class_static_data(g_pcClass);if(!IsPtr(sd))return NULL;
    return RdPtr(sd,OFF_STATIC_LOCAL);
}

static BOOL IsTeammate(void*ctrl,int32_t localTeam){
    void*view=RdPtr(ctrl,0x80);
    if(IsUnityObj(view)&&RdBool(view,0x60))return YES;
    if(OFF_CTRL_TEAM_ID&&localTeam!=-9999&&RdI32(ctrl,OFF_CTRL_TEAM_ID)==localTeam)return YES;
    return NO;
}

// ═══════════════════════════════════════════════════════════════════════════
// ESP / AIM STATE
// ═══════════════════════════════════════════════════════════════════════════
#define MAX_ESP 64
typedef struct { CGFloat fx,fy,hx,hy; BOOL valid; } ESPEntry;
static ESPEntry g_esp[MAX_ESP];
static int      g_espCount=0;
static BOOL     g_espOn=NO;

static BOOL    g_aimOn=NO;
static BOOL    g_aimHead=YES;
static CGFloat g_fovRadius=80.0f;

// ═══════════════════════════════════════════════════════════════════════════
// ESP UPDATE
// ═══════════════════════════════════════════════════════════════════════════
static void UpdateESP(void){
    g_espCount=0;
    if(!g_espOn||!IsPtr(g_pcClass)||!fp_class_static_data)return;
    void*sd=fp_class_static_data(g_pcClass);if(!IsPtr(sd))return;
    void*list=RdPtr(sd,0x8);if(!IsPtr(list))return;
    void*arr=RdPtr(list,0x10);int32_t sz=RdI32(list,0x18);
    if(!IsPtr(arr)||sz<=0||sz>200)return;

    void*localCtrl=GetLocalCtrl();
    int32_t localTeam=(OFF_CTRL_TEAM_ID&&IsUnityObj(localCtrl))?RdI32(localCtrl,OFF_CTRL_TEAM_ID):-9999;

    int n=sz<MAX_ESP?sz:MAX_ESP;
    for(int i=0;i<n;i++){
        void*culling=RdPtr(arr,0x20+(size_t)i*8);if(!IsUnityObj(culling))continue;
        void*ctrl   =RdPtr(culling,0x18);          if(!IsUnityObj(ctrl))continue;
        if(RdBool(ctrl,0xA8))continue;
        if(IsTeammate(ctrl,localTeam))continue;

        Vec3 foot=GetPos(culling);
        if(foot.x==0&&foot.y==0&&foot.z==0)continue;
        Vec3 head={foot.x,foot.y+1.8f,foot.z};
        CGPoint fs=W2S(foot);if(fs.x<0)continue;
        CGPoint hs=W2S(head);if(hs.x<0)continue;
        g_esp[g_espCount++]=(ESPEntry){fs.x,fs.y,hs.x,hs.y,YES};
    }
}

// ═══════════════════════════════════════════════════════════════════════════
// AIM UPDATE
// ═══════════════════════════════════════════════════════════════════════════
static void UpdateAim(void){
    if(!g_aimOn||!g_initDone||!IsPtr(g_pcClass)||!fp_class_static_data)return;
    if(!fp_runtime_invoke||!g_getMainM||!g_getTransM||!g_getPosM||!g_setEulerM||!fp_object_unbox)return;

    void*sd=fp_class_static_data(g_pcClass);if(!IsPtr(sd))return;
    void*list=RdPtr(sd,0x8);if(!IsPtr(list))return;
    void*arr=RdPtr(list,0x10);int32_t sz=RdI32(list,0x18);
    if(!IsPtr(arr)||sz<=0||sz>200)return;

    void*exc=NULL;
    void*cam=fp_runtime_invoke(g_getMainM,NULL,NULL,&exc);
    if(!IsUnityObj(cam)||exc)return;
    exc=NULL;
    void*camTr=fp_runtime_invoke(g_getTransM,cam,NULL,&exc);
    if(!IsUnityObj(camTr)||exc)return;

    CGSize  scr=[UIScreen mainScreen].bounds.size;
    CGPoint ctr=CGPointMake(scr.width*0.5f,scr.height*0.5f);

    void*localCtrl=GetLocalCtrl();
    int32_t localTeam=(OFF_CTRL_TEAM_ID&&IsUnityObj(localCtrl))?RdI32(localCtrl,OFF_CTRL_TEAM_ID):-9999;

    CGFloat bestDist=g_fovRadius;
    Vec3    bestWP  ={0,0,0};
    BOOL    found   =NO;

    int n=sz<MAX_ESP?sz:MAX_ESP;
    for(int i=0;i<n;i++){
        void*culling=RdPtr(arr,0x20+(size_t)i*8);if(!IsUnityObj(culling))continue;
        void*ctrl   =RdPtr(culling,0x18);          if(!IsUnityObj(ctrl))continue;
        if(RdBool(ctrl,0xA8))continue;
        if(IsTeammate(ctrl,localTeam))continue;
        if(RdBool(culling,0x48))continue;

        Vec3 bwp={0,0,0};
        void*animCtrl=RdPtr(ctrl,0x98);
        void*skeleton=IsUnityObj(animCtrl)?RdPtr(animCtrl,0x68):NULL;
        void*bone    =IsUnityObj(skeleton)?RdPtr(skeleton,g_aimHead?0xA8:0xB0):NULL;
        if(IsUnityObj(bone)) bwp=GetTransformPos(bone);

        if(bwp.x==0&&bwp.y==0&&bwp.z==0){
            Vec3 foot=GetPos(culling);
            if(foot.x==0&&foot.y==0&&foot.z==0)continue;
            bwp.x=foot.x; bwp.y=foot.y+1.4f; bwp.z=foot.z;
        }

        CGPoint sp=W2S(bwp);if(sp.x<0)continue;
        CGFloat dx=sp.x-ctr.x, dy=sp.y-ctr.y;
        CGFloat d=sqrtf(dx*dx+dy*dy);
        if(d<bestDist){bestDist=d;bestWP=bwp;found=YES;}
    }

    if(!found)return;

    Vec3 cp=GetTransformPos(camTr);
    if(cp.x==0&&cp.y==0&&cp.z==0)return;

    float ddx=bestWP.x-cp.x, ddy=bestWP.y-cp.y, ddz=bestWP.z-cp.z;
    float dist3d=sqrtf(ddx*ddx+ddy*ddy+ddz*ddz);
    if(dist3d<0.01f)return;

    float pitch=-asinf(ddy/dist3d)*(180.0f/(float)M_PI);
    float yaw  = atan2f(ddx,ddz) *(180.0f/(float)M_PI);

    Vec3 euler={pitch,yaw,0.0f};
    void*params[1]={&euler};
    exc=NULL;
    fp_runtime_invoke(g_setEulerM,camTr,params,&exc);
}

// ═══════════════════════════════════════════════════════════════════════════
// DUMP
// ═══════════════════════════════════════════════════════════════════════════
static NSString* PerformDump(void){
    if(!LoadAPI())return @"ошибка: API не найден";
    EnsureThreadAttached();
    void*domain=fp_domain_get();if(!domain)return @"ошибка: domain NULL";
    uintptr_t base=UnityBase();
    size_t ac=0;void**asms=fp_domain_assemblies(domain,&ac);
    if(!asms)return @"ошибка: assemblies NULL";
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
                const char*mn=fp_method_name(mth);uint32_t np=fp_method_params(mth);
                uintptr_t ptr=*(uintptr_t*)mth;
                (ptr>base)?[out appendFormat:@"\t// RVA: 0x%llX  p:%u  %s\n",(unsigned long long)(ptr-base),np,mn?:"?"]
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
    return err?[NSString stringWithFormat:@"ошибка: %@",err.localizedDescription]
              :[NSString stringWithFormat:@"✓ %lu классов",(unsigned long)total];
}

// ═══════════════════════════════════════════════════════════════════════════
// CHAMFERED SHAPE HELPERS
// ═══════════════════════════════════════════════════════════════════════════
// Возвращает UIBezierPath прямоугольника с срезанными (chamfered) углами.
static UIBezierPath* ChamferPath(CGRect rect, CGFloat ch){
    CGFloat x=rect.origin.x, y=rect.origin.y;
    CGFloat w=rect.size.width, h=rect.size.height;
    if(ch<=0||ch>w*0.5f||ch>h*0.5f) ch = MIN(w,h)*0.15f;
    UIBezierPath*p=[UIBezierPath bezierPath];
    [p moveToPoint   :CGPointMake(x+ch, y)];
    [p addLineToPoint:CGPointMake(x+w-ch, y)];
    [p addLineToPoint:CGPointMake(x+w,    y+ch)];
    [p addLineToPoint:CGPointMake(x+w,    y+h-ch)];
    [p addLineToPoint:CGPointMake(x+w-ch, y+h)];
    [p addLineToPoint:CGPointMake(x+ch,   y+h)];
    [p addLineToPoint:CGPointMake(x,      y+h-ch)];
    [p addLineToPoint:CGPointMake(x,      y+ch)];
    [p closePath];
    return p;
}

// Прямоугольник с чёрным фоном + оранжевой рамкой и срезанными углами.
// Использует CAShapeLayer, поэтому обновляется при изменении bounds.
@interface ChamferView : UIView
@property (strong) CAShapeLayer *fillLayer;
@property (strong) CAShapeLayer *borderLayer;
@property (assign) CGFloat chamfer;
@property (assign) CGFloat borderWidth;
@end
@implementation ChamferView
-(instancetype)initWithFrame:(CGRect)f{
    self=[super initWithFrame:f];
    self.backgroundColor=[UIColor clearColor];
    self.chamfer=kChamfer;
    self.borderWidth=1.0f;
    _fillLayer=[CAShapeLayer layer];
    _fillLayer.fillColor=BG_DARK().CGColor;
    [self.layer addSublayer:_fillLayer];
    _borderLayer=[CAShapeLayer layer];
    _borderLayer.fillColor=[UIColor clearColor].CGColor;
    _borderLayer.strokeColor=ORANGE_DIM().CGColor;
    _borderLayer.lineWidth=_borderWidth;
    [self.layer addSublayer:_borderLayer];
    return self;
}
-(void)layoutSubviews{
    [super layoutSubviews];
    UIBezierPath*p=ChamferPath(self.bounds,self.chamfer);
    _fillLayer.path=p.CGPath;
    _fillLayer.frame=self.bounds;
    _borderLayer.path=p.CGPath;
    _borderLayer.frame=self.bounds;
    _borderLayer.lineWidth=self.borderWidth;
}
-(void)setChamfer:(CGFloat)chamfer{_chamfer=chamfer;[self setNeedsLayout];}
-(void)setBorderWidth:(CGFloat)bw{_borderWidth=bw;[self setNeedsLayout];}
@end

// ═══════════════════════════════════════════════════════════════════════════
// PASSTHROUGH WINDOW / VIEW
// ═══════════════════════════════════════════════════════════════════════════
@interface PassthroughWindow : UIWindow @end
@implementation PassthroughWindow
-(UIView*)hitTest:(CGPoint)p withEvent:(UIEvent*)e{
    UIView*v=[super hitTest:p withEvent:e];
    if(!v||v==self||v==self.rootViewController.view)return nil;
    if(!v.userInteractionEnabled)return nil;
    return v;
}
@end

@interface PassthroughView : UIView @end
@implementation PassthroughView
-(UIView*)hitTest:(CGPoint)p withEvent:(UIEvent*)e{
    UIView*v=[super hitTest:p withEvent:e];return v==self?nil:v;
}
@end

// ═══════════════════════════════════════════════════════════════════════════
// ESP VIEW
// ═══════════════════════════════════════════════════════════════════════════
@interface ESPView : UIView @end
@implementation ESPView
-(instancetype)init{
    self=[super initWithFrame:[UIScreen mainScreen].bounds];
    self.backgroundColor=[UIColor clearColor];
    self.userInteractionEnabled=NO;
    self.autoresizingMask=UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight;
    return self;
}
-(void)drawRect:(CGRect)r{
    CGContextRef ctx=UIGraphicsGetCurrentContext();
    if(g_espOn&&g_espCount>0){
        for(int i=0;i<g_espCount;i++){
            ESPEntry*e=&g_esp[i];if(!e->valid)continue;
            CGFloat boxH=e->fy-e->hy;if(boxH<8.0f)boxH=8.0f;
            CGFloat boxW=boxH*0.55f;
            CGFloat cx=(e->fx+e->hx)*0.5f;
            CGRect  box=CGRectMake(cx-boxW*0.5f,e->hy,boxW,boxH);
            CGContextSetRGBStrokeColor(ctx,0,0,0,0.70f);
            CGContextSetLineWidth(ctx,2.5f);
            CGContextStrokeRect(ctx,CGRectInset(box,-0.5f,-0.5f));
            CGContextSetRGBStrokeColor(ctx,1.00f,0.45f,0.05f,0.95f);
            CGContextSetLineWidth(ctx,1.5f);
            CGContextStrokeRect(ctx,box);
        }
    }
    if(g_aimOn){
        CGFloat cx=self.bounds.size.width*0.5f;
        CGFloat cy=self.bounds.size.height*0.5f;
        CGContextSetRGBStrokeColor(ctx,1.00f,0.45f,0.05f,0.45f);
        CGContextSetLineWidth(ctx,1.0f);
        CGContextStrokeEllipseInRect(ctx,CGRectMake(cx-g_fovRadius,cy-g_fovRadius,
                                                     g_fovRadius*2,g_fovRadius*2));
        CGContextSetLineWidth(ctx,0.8f);
        CGContextMoveToPoint(ctx,cx-6,cy);CGContextAddLineToPoint(ctx,cx+6,cy);
        CGContextMoveToPoint(ctx,cx,cy-6);CGContextAddLineToPoint(ctx,cx,cy+6);
        CGContextStrokePath(ctx);
    }
}
@end

// ═══════════════════════════════════════════════════════════════════════════
// PILL BUTTON (плавающий «☰»)
// ═══════════════════════════════════════════════════════════════════════════
@interface PillButton : UIView
@property (copy) dispatch_block_t action;
@end
@implementation PillButton{CGPoint _off;BOOL _moved;}
-(instancetype)init{
    self=[super initWithFrame:CGRectMake(24,80,46,30)];
    self.backgroundColor=BG_HEADER();
    self.layer.cornerRadius=0; // срезанные углы рисуем ниже
    self.layer.borderColor=ORANGE_DIM().CGColor;
    self.layer.borderWidth=1;

    CAShapeLayer*sh=[CAShapeLayer layer];
    sh.fillColor=BG_HEADER().CGColor;
    sh.strokeColor=ORANGE_DIM().CGColor;
    sh.lineWidth=1;
    sh.path=ChamferPath(self.bounds,6).CGPath;
    [self.layer insertSublayer:sh atIndex:0];
    self.layer.borderWidth=0;

    UILabel*l=[[UILabel alloc]initWithFrame:self.bounds];
    l.text=@"☰";l.textAlignment=NSTextAlignmentCenter;
    l.font=[UIFont systemFontOfSize:14 weight:UIFontWeightSemibold];
    l.textColor=ORANGE();
    [self addSubview:l];

    [self addGestureRecognizer:[[UIPanGestureRecognizer alloc]initWithTarget:self action:@selector(pan:)]];
    return self;
}
-(void)layoutSubviews{
    [super layoutSubviews];
    for(CALayer*s in self.layer.sublayers){
        if([s isKindOfClass:[CAShapeLayer class]]){
            ((CAShapeLayer*)s).path=ChamferPath(self.bounds,6).CGPath;
        }
    }
}
-(void)pan:(UIPanGestureRecognizer*)g{
    CGPoint loc=[g locationInView:self.superview];
    if(g.state==UIGestureRecognizerStateBegan){
        _moved=NO;
        _off=CGPointMake(loc.x-self.frame.origin.x,loc.y-self.frame.origin.y);
    }else if(g.state==UIGestureRecognizerStateChanged){
        _moved=YES;
        CGRect f=self.frame;f.origin=CGPointMake(loc.x-_off.x,loc.y-_off.y);self.frame=f;
    }
}
-(void)touchesEnded:(NSSet*)t withEvent:(UIEvent*)e{if(!_moved&&_action)_action();}
@end

// ═══════════════════════════════════════════════════════════════════════════
// CHAMFER BUTTON (для карточек меню)
// ═══════════════════════════════════════════════════════════════════════════
@interface ChamferButton : UIButton
@property (strong) CAShapeLayer *bg;
@property (strong) CAShapeLayer *bd;
@property (assign) BOOL isActive;
@end
@implementation ChamferButton
-(instancetype)initWithFrame:(CGRect)f{
    self=[super initWithFrame:f];
    self.titleLabel.font=[UIFont systemFontOfSize:12 weight:UIFontWeightSemibold];
    [self setTitleColor:TXT_MAIN() forState:UIControlStateNormal];
    [self setTitleColor:ORANGE()    forState:UIControlStateHighlighted];
    self.backgroundColor=[UIColor clearColor];
    _bg=[CAShapeLayer layer];
    _bg.fillColor=BG_BTN().CGColor;
    [self.layer addSublayer:_bg];
    _bd=[CAShapeLayer layer];
    _bd.fillColor=[UIColor clearColor].CGColor;
    _bd.strokeColor=ORANGE_DIM().CGColor;
    _bd.lineWidth=1;
    [self.layer addSublayer:_bd];
    [self addTarget:self action:@selector(bDown) forControlEvents:UIControlEventTouchDown];
    [self addTarget:self action:@selector(bUp)   forControlEvents:UIControlEventTouchUpInside|UIControlEventTouchUpOutside];
    return self;
}
-(void)layoutSubviews{
    [super layoutSubviews];
    UIBezierPath*p=ChamferPath(self.bounds,6);
    _bg.path=p.CGPath; _bg.frame=self.bounds;
    _bd.path=p.CGPath; _bd.frame=self.bounds;
}
-(void)bDown{
    [CATransaction begin];[CATransaction setDisableActions:YES];
    _bg.fillColor=BG_BTN_DOWN().CGColor;
    [CATransaction commit];
}
-(void)bUp{
    [CATransaction begin];[CATransaction setDisableActions:YES];
    _bg.fillColor=BG_BTN().CGColor;
    [CATransaction commit];
}
-(void)setIsActive:(BOOL)a{
    _isActive=a;
    _bd.strokeColor = a ? ORANGE().CGColor : ORANGE_DIM().CGColor;
    _bd.lineWidth   = a ? 1.6f : 1.0f;
    [self setTitleColor:(a?ORANGE():TXT_MAIN()) forState:UIControlStateNormal];
}
@end

// ═══════════════════════════════════════════════════════════════════════════
// MENU VIEW (landscape, black/orange, chamfered)
// ═══════════════════════════════════════════════════════════════════════════
@interface MenuView : ChamferView
@property (strong) UIButton *hideBtn,*closeBtn,*dumpBtn;
@property (strong) ChamferButton *espBtn,*aimBtn,*targetBtn;
@property (strong) UILabel *statusLabel,*fovLabel;
@property (strong) UISlider *fovSlider;
@property (strong) UIView *header;
@end

@implementation MenuView{CGPoint _drag;}

-(instancetype)initWithFrame:(CGRect)f{
    self=[super initWithFrame:f];
    self.chamfer=kChamfer;
    self.borderWidth=1.2f;
    self.fillLayer.fillColor=BG_DARK().CGColor;
    self.borderLayer.strokeColor=ORANGE_DIM().CGColor;

    // ─── HEADER ─────────────────────────────────────────────────────────
    _header=[[UIView alloc]initWithFrame:CGRectMake(0,0,f.size.width,kHdr)];
    _header.backgroundColor=[UIColor clearColor];
    [self addSubview:_header];

    // оранжевая полоса-акцент под хедером
    UIView*acc=[[UIView alloc]initWithFrame:CGRectMake(8,kHdr-1,f.size.width-16,1)];
    acc.backgroundColor=ORANGE();
    [_header addSubview:acc];

    UILabel*ttl=[[UILabel alloc]initWithFrame:CGRectMake(14,0,220,kHdr)];
    ttl.text=@"MENU";
    ttl.textAlignment=NSTextAlignmentLeft;
    ttl.font=[UIFont systemFontOfSize:13 weight:UIFontWeightHeavy];
    ttl.textColor=ORANGE();
    [_header addSubview:ttl];

    // ─── HIDE / CLOSE ───────────────────────────────────────────────────
    _hideBtn =[self hdrBtn:@"−" x:f.size.width-64];
    _closeBtn=[self hdrBtn:@"×" x:f.size.width-36];
    [_header addSubview:_hideBtn];
    [_header addSubview:_closeBtn];

    // ─── LEFT COLUMN (ESP / AIM / TARGET) ───────────────────────────────
    CGFloat padL=14, padR=14, colGap=12;
    CGFloat cardY = kHdr + 14;
    CGFloat cardH = f.size.height - cardY - 14;
    CGFloat colW  = (f.size.width - padL - padR - colGap) * 0.5f;

    UIView*leftCol=[[UIView alloc]initWithFrame:CGRectMake(padL,cardY,colW,cardH)];
    leftCol.backgroundColor=[UIColor clearColor];
    [self addSubview:leftCol];

    UILabel*lblL=[[UILabel alloc]initWithFrame:CGRectMake(0,0,colW,14)];
    lblL.text=@"COMBAT";
    lblL.font=[UIFont systemFontOfSize:9 weight:UIFontWeightHeavy];
    lblL.textColor=ORANGE_DIM();
    [leftCol addSubview:lblL];

    CGFloat bw = colW;
    CGFloat bh = 36;
    CGFloat y  = 20;

    _espBtn =[self makeBtn:@"ESP: OFF"  frame:CGRectMake(0,y,bw,bh)]; [leftCol addSubview:_espBtn]; y+=bh+8;
    _aimBtn =[self makeBtn:@"AIM: OFF"  frame:CGRectMake(0,y,bw,bh)]; [leftCol addSubview:_aimBtn]; y+=bh+8;
    _targetBtn=[self makeBtn:@"HEAD"    frame:CGRectMake(0,y,bw,bh)]; [leftCol addSubview:_targetBtn]; y+=bh+12;

    _fovLabel=[[UILabel alloc]initWithFrame:CGRectMake(0,y,colW,14)];
    _fovLabel.font=[UIFont monospacedSystemFontOfSize:9 weight:UIFontWeightRegular];
    _fovLabel.textColor=TXT_DIM();
    _fovLabel.text=[NSString stringWithFormat:@"FOV: %.0f px",g_fovRadius];
    [leftCol addSubview:_fovLabel]; y+=16;

    _fovSlider=[[UISlider alloc]initWithFrame:CGRectMake(0,y,colW,26)];
    _fovSlider.minimumValue=20; _fovSlider.maximumValue=300;
    _fovSlider.value=g_fovRadius;
    _fovSlider.minimumTrackTintColor=ORANGE();
    _fovSlider.maximumTrackTintColor=C(0.25f,0.20f,0.15f,1.0f);
    [_fovSlider setThumbImage:[self thumbImg] forState:UIControlStateNormal];
    [leftCol addSubview:_fovSlider];

    // ─── RIGHT COLUMN (STATUS / DUMP) ───────────────────────────────────
    UIView*rightCol=[[UIView alloc]initWithFrame:CGRectMake(padL+colW+colGap,cardY,colW,cardH)];
    rightCol.backgroundColor=[UIColor clearColor];
    [self addSubview:rightCol];

    UILabel*lblR=[[UILabel alloc]initWithFrame:CGRectMake(0,0,colW,14)];
    lblR.text=@"SYSTEM";
    lblR.font=[UIFont systemFontOfSize:9 weight:UIFontWeightHeavy];
    lblR.textColor=ORANGE_DIM();
    [rightCol addSubview:lblR];

    _dumpBtn=[self makeBtn:@"DUMP IL2CPP" frame:CGRectMake(0,20,colW,36)];
    [rightCol addSubview:_dumpBtn];

    UILabel*stLbl=[[UILabel alloc]initWithFrame:CGRectMake(0,20+36+10,colW,12)];
    stLbl.text=@"STATUS";
    stLbl.font=[UIFont systemFontOfSize:9 weight:UIFontWeightHeavy];
    stLbl.textColor=ORANGE_DIM();
    [rightCol addSubview:stLbl];

    _statusLabel=[[UILabel alloc]initWithFrame:CGRectMake(0,20+36+26,colW,cardH-(20+36+30))];
    _statusLabel.font=[UIFont monospacedSystemFontOfSize:9 weight:UIFontWeightRegular];
    _statusLabel.textColor=TXT_DIM();
    _statusLabel.numberOfLines=0;
    _statusLabel.text=@"idle";
    [rightCol addSubview:_statusLabel];

    // ─── DRAG ───────────────────────────────────────────────────────────
    [_header addGestureRecognizer:[[UIPanGestureRecognizer alloc]initWithTarget:self action:@selector(pan:)]];
    return self;
}

-(UIImage*)thumbImg{
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(14,14),NO,0);
    CGContextRef c=UIGraphicsGetCurrentContext();
    CGContextSetRGBFillColor(c,1.00f,0.45f,0.05f,1);
    CGContextFillEllipseInRect(c,CGRectMake(0,0,14,14));
    UIImage*img=UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();return img;
}

-(UIButton*)hdrBtn:(NSString*)g x:(CGFloat)x{
    UIButton*b=[UIButton buttonWithType:UIButtonTypeCustom];
    b.frame=CGRectMake(x,(kHdr-26)*.5f,26,26);
    b.backgroundColor=BG_BTN();
    b.layer.cornerRadius=6;   // внутри хедера — простые скругления
    b.titleLabel.font=[UIFont systemFontOfSize:14 weight:UIFontWeightBold];
    [b setTitle:g forState:UIControlStateNormal];
    [b setTitleColor:TXT_DIM() forState:UIControlStateNormal];
    [b setTitleColor:ORANGE()  forState:UIControlStateHighlighted];
    [b addTarget:self action:@selector(hdrDown:) forControlEvents:UIControlEventTouchDown];
    [b addTarget:self action:@selector(hdrUp:)   forControlEvents:UIControlEventTouchUpInside|UIControlEventTouchUpOutside];
    return b;
}
-(void)hdrDown:(UIButton*)b{b.backgroundColor=BG_BTN_DOWN();}
-(void)hdrUp:  (UIButton*)b{b.backgroundColor=BG_BTN();}

-(ChamferButton*)makeBtn:(NSString*)t frame:(CGRect)f{
    ChamferButton*b=[[ChamferButton alloc]initWithFrame:f];
    [b setTitle:t forState:UIControlStateNormal];
    return b;
}

-(void)pan:(UIPanGestureRecognizer*)g{
    CGPoint loc=[g locationInView:self.superview];
    if(g.state==UIGestureRecognizerStateBegan)
        _drag=CGPointMake(loc.x-self.frame.origin.x,loc.y-self.frame.origin.y);
    else if(g.state==UIGestureRecognizerStateChanged){
        CGRect r=self.frame;r.origin=CGPointMake(loc.x-_drag.x,loc.y-_drag.y);self.frame=r;
    }
}
@end

// ═══════════════════════════════════════════════════════════════════════════
// CHEAT CONTROLLER
// ═══════════════════════════════════════════════════════════════════════════
@interface CheatController : NSObject
+(instancetype)shared;
-(void)toggle;
@end

@implementation CheatController{
    PassthroughWindow *_win;
    MenuView          *_menu;
    ESPView           *_espView;
    PillButton        *_pill;
    BOOL               _visible;
    CADisplayLink     *_dl;
}

+(instancetype)shared{
    static CheatController*inst; static dispatch_once_t once;
    dispatch_once(&once,^{ inst=[CheatController new]; }); return inst;
}
-(instancetype)init{self=[super init];[self build];return self;}

-(void)build{
    // ─── WINDOW ─────────────────────────────────────────────────────────
    UIWindowScene*scene=nil;
    for(UIScene*s in [UIApplication sharedApplication].connectedScenes)
        if([s isKindOfClass:[UIWindowScene class]]){scene=(UIWindowScene*)s;break;}

    _win=scene?[[PassthroughWindow alloc]initWithWindowScene:scene]
              :[[PassthroughWindow alloc]initWithFrame:[UIScreen mainScreen].bounds];
    _win.windowLevel=UIWindowLevelAlert+200;
    _win.backgroundColor=[UIColor clearColor];
    _win.rootViewController=[UIViewController new];

    PassthroughView*pv=[[PassthroughView alloc]initWithFrame:[UIScreen mainScreen].bounds];
    pv.backgroundColor=[UIColor clearColor];
    pv.autoresizingMask=UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight;
    _win.rootViewController.view=pv;
    _win.hidden=NO;

    _espView=[ESPView new];
    [pv addSubview:_espView];

    // ─── MENU ───────────────────────────────────────────────────────────
    CGSize sz=[UIScreen mainScreen].bounds.size;
    CGRect mf=CGRectMake((sz.width-kW)*0.5f,(sz.height-kH)*0.5f,kW,kH);
    _menu=[[MenuView alloc]initWithFrame:mf];
    [pv addSubview:_menu];

    // ─── PILL ───────────────────────────────────────────────────────────
    __weak CheatController*ws=self;
    _pill=[PillButton new];
    _pill.action=^{ [ws doShow]; };
    _pill.hidden=YES;
    [pv addSubview:_pill];

    // ─── TARGETS ────────────────────────────────────────────────────────
    [_menu.hideBtn   addTarget:self action:@selector(doHide)    forControlEvents:UIControlEventTouchUpInside];
    [_menu.closeBtn  addTarget:self action:@selector(doClose)   forControlEvents:UIControlEventTouchUpInside];
    [_menu.dumpBtn   addTarget:self action:@selector(doDump)    forControlEvents:UIControlEventTouchUpInside];
    [_menu.espBtn    addTarget:self action:@selector(doESP)     forControlEvents:UIControlEventTouchUpInside];
    [_menu.aimBtn    addTarget:self action:@selector(doAim)     forControlEvents:UIControlEventTouchUpInside];
    [_menu.targetBtn addTarget:self action:@selector(doTarget)  forControlEvents:UIControlEventTouchUpInside];
    [_menu.fovSlider addTarget:self action:@selector(fovChanged:) forControlEvents:UIControlEventValueChanged];

    // ─── ORIENTATION ────────────────────────────────────────────────────
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(orientationChanged)
                                                 name:UIDeviceOrientationDidChangeNotification
                                               object:nil];

    // ─── DISPLAY LINK ───────────────────────────────────────────────────
    _dl=[CADisplayLink displayLinkWithTarget:self selector:@selector(tick)];
    _dl.preferredFramesPerSecond=30;
    [_dl addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
}

-(void)orientationChanged{
    CGSize sz=[UIScreen mainScreen].bounds.size;
    _espView.frame=CGRectMake(0,0,sz.width,sz.height);
    // если меню видимо — центрируем его заново
    if(_visible){
        CGRect f=_menu.frame;
        f.size=CGSizeMake(kW,kH);
        f.origin=CGPointMake((sz.width-kW)*0.5f,(sz.height-kH)*0.5f);
        _menu.frame=f;
        [_menu setNeedsLayout];
    }
    [_espView setNeedsDisplay];
}

-(void)tick{
    if(!g_espOn&&!g_aimOn)return;
    if(!g_initDone)InitClasses();
    if(g_espOn) UpdateESP();
    if(g_aimOn) UpdateAim();
    [_espView setNeedsDisplay];
}

-(void)doESP{
    g_espOn=!g_espOn;
    if(g_espOn&&!g_initDone)InitClasses();
    [_menu.espBtn setTitle:(g_espOn?@"ESP: ON":@"ESP: OFF") forState:UIControlStateNormal];
    _menu.espBtn.isActive=g_espOn;
    _menu.statusLabel.text=g_espOn?@"ESP активен":@"ESP выключен";
    _menu.statusLabel.textColor=g_espOn?ORANGE():TXT_DIM();
    if(!g_espOn){g_espCount=0;[_espView setNeedsDisplay];}
}

-(void)doAim{
    g_aimOn=!g_aimOn;
    if(g_aimOn&&!g_initDone)InitClasses();
    [_menu.aimBtn setTitle:(g_aimOn?@"AIM: ON":@"AIM: OFF") forState:UIControlStateNormal];
    _menu.aimBtn.isActive=g_aimOn;
    _menu.statusLabel.text=g_aimOn?@"Aimbot активен":@"Aimbot выключен";
    _menu.statusLabel.textColor=g_aimOn?ORANGE():TXT_DIM();
    if(!g_aimOn)[_espView setNeedsDisplay];
}

-(void)doTarget{
    g_aimHead=!g_aimHead;
    NSString*t=g_aimHead?@"HEAD":@"BODY";
    [_menu.targetBtn setTitle:t forState:UIControlStateNormal];
}

-(void)fovChanged:(UISlider*)s{
    g_fovRadius=s.value;
    _menu.fovLabel.text=[NSString stringWithFormat:@"FOV: %.0f px",g_fovRadius];
    if(g_aimOn)[_espView setNeedsDisplay];
}

-(void)doDump{
    _menu.dumpBtn.enabled=NO;
    _menu.statusLabel.text=@"dumping...";
    _menu.statusLabel.textColor=ORANGE();
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0),^{
        NSString*res=PerformDump();
        dispatch_async(dispatch_get_main_queue(),^{
            self->_menu.dumpBtn.enabled=YES;
            self->_menu.statusLabel.text=res;
            self->_menu.statusLabel.textColor=[res hasPrefix:@"ошибка"]?C(1,0.3,0.3,1):ORANGE();
        });
    });
}

-(void)doShow{
    _pill.hidden=YES; _menu.hidden=NO; _menu.alpha=0;
    _menu.transform=CGAffineTransformMakeScale(0.92f,0.92f);
    [UIView animateWithDuration:kDur delay:0 options:UIViewAnimationOptionCurveEaseOut animations:^{
        self->_menu.alpha=1; self->_menu.transform=CGAffineTransformIdentity;
    } completion:nil];
    _visible=YES;
}

-(void)doHide{
    [UIView animateWithDuration:kDur delay:0 options:UIViewAnimationOptionCurveEaseIn animations:^{
        self->_menu.alpha=0;
        self->_menu.transform=CGAffineTransformMakeScale(0.94f,0.94f);
    } completion:^(BOOL _){
        self->_menu.hidden=YES;
        self->_menu.transform=CGAffineTransformIdentity;
        self->_pill.hidden=NO;
        self->_visible=NO;
    }];
}

-(void)doClose{
    [UIView animateWithDuration:kDur delay:0 options:UIViewAnimationOptionCurveEaseIn animations:^{
        self->_menu.alpha=0;
        self->_menu.transform=CGAffineTransformMakeScale(0.90f,0.90f);
    } completion:^(BOOL _){
        self->_menu.hidden=YES;
        self->_menu.transform=CGAffineTransformIdentity;
        self->_pill.hidden=NO;
        self->_visible=NO;
    }];
}

-(void)toggle{ _visible?[self doHide]:[self doShow]; }
@end

// ═══════════════════════════════════════════════════════════════════════════
// ENTRY POINT
// ═══════════════════════════════════════════════════════════════════════════
__attribute__((constructor))
static void Init(void){
    dispatch_async(dispatch_get_main_queue(),^{
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(1.5*NSEC_PER_SEC)),
                       dispatch_get_main_queue(),^{
            [[CheatController shared] toggle];
        });
    });
}
