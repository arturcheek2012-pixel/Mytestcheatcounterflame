#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <dlfcn.h>
#import <mach-o/dyld.h>
#import <math.h>

static const CGFloat kR   = 8.0f;
static const NSTimeInterval kDur = 0.18;
static inline UIColor* C(CGFloat r,CGFloat g,CGFloat b,CGFloat a){
    return [UIColor colorWithRed:r green:g blue:b alpha:a];
}
typedef struct { float x,y,z; } Vec3;

// ─── offsets from Counter Flame dump ───────────────────────────────────────
// PlayerCulling.Instances static @ 0x8 → List<PlayerCulling>
// PlayerCulling instance _controller @ 0x18 → PlayerController
// PlayerController._view @ 0x80 → PhotonView
// PhotonView.<IsMine>k__BackingField @ 0x60
// PlayerController._isDeath @ 0xA8
// PlayerCulling._occluded @ 0x48
// PlayerController._animatorController @ 0x98
// PlayerAnimatorController._skeleton @ 0x68
// PlayerSkeleton._headBone @ 0xA8, _chestBone @ 0xB0

#define OFF_CULLING_CTRL      0x18
#define OFF_CTRL_VIEW         0x80
#define OFF_VIEW_ISMINE       0x60
#define OFF_CTRL_ISDEATH      0xA8
#define OFF_CULLING_OCCLUDED  0x48
#define OFF_CTRL_ANIMATOR     0x98
#define OFF_ANIMATOR_SKEL     0x68
#define OFF_SKEL_HEAD         0xA8
#define OFF_SKEL_CHEST        0xB0

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
#undef R
    g_apiLoaded=(fp_domain_get!=NULL&&fp_class_from_name!=NULL);
    return g_apiLoaded;
}

static BOOL    IsPtr(const void*p){uintptr_t v=(uintptr_t)p;return v>0x10000UL&&v<0x00FFFFFFFFFFFFFFULL;}
static void*   RdPtr(const void*b,size_t o){if(!IsPtr(b))return NULL;void**a=(void**)((const uint8_t*)b+o);if(!IsPtr(a))return NULL;return *a;}
static int32_t RdI32(const void*b,size_t o){if(!IsPtr(b))return 0;return *(int32_t*)((const uint8_t*)b+o);}
static BOOL    RdBool(const void*b,size_t o){if(!IsPtr(b))return NO;return *(bool*)((const uint8_t*)b+o);}

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
static void*g_setEulerM=NULL;
static BOOL g_initDone=NO;

static void InitClasses(void){
    if(g_initDone)return;
    if(!LoadAPI())return;
    void*domain=fp_domain_get();if(!domain)return;
    uintptr_t base=UnityBase();
    size_t n=0;void**asms=fp_domain_assemblies(domain,&n);
    for(size_t i=0;i<n;i++){
        void*img=fp_assembly_image(asms[i]);if(!img)continue;
        const char*nm=fp_image_name(img);if(!nm)continue;
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
    UnityBase();g_initDone=YES;
}

static Vec3 GetPos(void*obj){
    Vec3 z={0,0,0};
    if(!IsPtr(obj)||!fp_runtime_invoke||!g_getTransM||!g_getPosM)return z;
    @try{
        void*exc=NULL;
        void*tr=fp_runtime_invoke(g_getTransM,obj,NULL,&exc);if(!IsPtr(tr)||exc)return z;
        exc=NULL;
        void*bp=fp_runtime_invoke(g_getPosM,tr,NULL,&exc);if(!IsPtr(bp)||exc||!fp_object_unbox)return z;
        Vec3*p=(Vec3*)fp_object_unbox(bp);return p?*p:z;
    }@catch(NSException*e){return z;}
}

static Vec3 GetTransformPos(void*tr){
    Vec3 z={0,0,0};
    if(!IsPtr(tr)||!fp_runtime_invoke||!g_getPosM||!fp_object_unbox)return z;
    @try{
        void*exc=NULL;
        void*bp=fp_runtime_invoke(g_getPosM,tr,NULL,&exc);
        if(!IsPtr(bp)||exc)return z;
        Vec3*p=(Vec3*)fp_object_unbox(bp);return p?*p:z;
    }@catch(NSException*e){return z;}
}

static CGPoint W2S(Vec3 wp){
    const CGPoint bad={-1,-1};
    if(!fp_runtime_invoke||!g_getMainM||!g_w2sM||!fp_object_unbox)return bad;
    @try{
        void*exc=NULL;
        void*cam=fp_runtime_invoke(g_getMainM,NULL,NULL,&exc);if(!IsPtr(cam)||exc)return bad;
        void*params[1]={&wp};exc=NULL;
        void*br=fp_runtime_invoke(g_w2sM,cam,params,&exc);if(!IsPtr(br)||exc)return bad;
        Vec3*sv=(Vec3*)fp_object_unbox(br);if(!sv||sv->z<=0.0f)return bad;
        CGFloat sc=[UIScreen mainScreen].scale;
        CGFloat uH=[UIScreen mainScreen].bounds.size.height;
        return CGPointMake(sv->x/sc,uH-sv->y/sc);
    }@catch(NSException*e){return bad;}
}

#define MAX_ESP 64
typedef struct { CGFloat fx,fy,hx,hy; BOOL valid; } ESPEntry;
static ESPEntry g_esp[MAX_ESP];
static int      g_espCount=0;
static BOOL     g_espOn=NO;
static BOOL    g_aimOn=NO;
static BOOL    g_aimHead=YES;
static CGFloat g_fovRadius=80.0f;

static void UpdateESP(void){
    g_espCount=0;
    if(!g_espOn||!IsPtr(g_pcClass)||!fp_class_static_data)return;
    @try{
        void*sd=fp_class_static_data(g_pcClass);if(!IsPtr(sd))return;
        void*list=RdPtr(sd,0x8);if(!IsPtr(list))return;
        void*arr=RdPtr(list,0x10);int32_t sz=RdI32(list,0x18);
        if(!IsPtr(arr)||sz<=0||sz>200)return;

        int n=sz<MAX_ESP?sz:MAX_ESP;
        for(int i=0;i<n;i++){
            void*culling=RdPtr(arr,0x20+(size_t)i*8);if(!IsPtr(culling))continue;
            void*ctrl   =RdPtr(culling,OFF_CULLING_CTRL);if(!IsPtr(ctrl))continue;
            
            // проверки
            if(RdBool(ctrl,OFF_CTRL_ISDEATH))continue;                        // мёртвый
            void*view=RdPtr(ctrl,OFF_CTRL_VIEW);
            if(IsPtr(view)&&RdBool(view,OFF_VIEW_ISMINE))continue;            // сам
            if(RdBool(culling,OFF_CULLING_OCCLUDED))continue;                 // за стеной
            
            // позиция
            Vec3 foot=GetPos(culling);
            if(foot.x==0&&foot.y==0&&foot.z==0)continue;
            Vec3 head={foot.x,foot.y+1.8f,foot.z};
            CGPoint fs=W2S(foot);if(fs.x<0)continue;
            CGPoint hs=W2S(head);if(hs.x<0)continue;
            g_esp[g_espCount++]=(ESPEntry){fs.x,fs.y,hs.x,hs.y,YES};
        }
    }@catch(NSException*e){}
}

static void UpdateAim(void){
    if(!g_aimOn||!g_initDone||!IsPtr(g_pcClass)||!fp_class_static_data)return;
    if(!fp_runtime_invoke||!g_getMainM||!g_getTransM||!g_getPosM||!g_setEulerM||!fp_object_unbox)return;

    @try{
        void*sd=fp_class_static_data(g_pcClass);if(!IsPtr(sd))return;
        void*list=RdPtr(sd,0x8);if(!IsPtr(list))return;
        void*arr=RdPtr(list,0x10);int32_t sz=RdI32(list,0x18);
        if(!IsPtr(arr)||sz<=0||sz>200)return;

        void*exc=NULL;
        void*cam=fp_runtime_invoke(g_getMainM,NULL,NULL,&exc);if(!IsPtr(cam)||exc)return;
        exc=NULL;
        void*camTr=fp_runtime_invoke(g_getTransM,cam,NULL,&exc);if(!IsPtr(camTr)||exc)return;

        CGSize  scr=[UIScreen mainScreen].bounds.size;
        CGPoint ctr=CGPointMake(scr.width*0.5f,scr.height*0.5f);

        CGFloat bestDist=g_fovRadius;
        Vec3    bestWP  ={0,0,0};
        BOOL    found   =NO;

        int n=sz<MAX_ESP?sz:MAX_ESP;
        for(int i=0;i<n;i++){
            void*culling=RdPtr(arr,0x20+(size_t)i*8);if(!IsPtr(culling))continue;
            void*ctrl   =RdPtr(culling,OFF_CULLING_CTRL);if(!IsPtr(ctrl))continue;
            
            // проверки
            if(RdBool(ctrl,OFF_CTRL_ISDEATH))continue;
            void*view=RdPtr(ctrl,OFF_CTRL_VIEW);
            if(IsPtr(view)&&RdBool(view,OFF_VIEW_ISMINE))continue;
            if(RdBool(culling,OFF_CULLING_OCCLUDED))continue;

            // кость: ctrl → animator (0x98) → skeleton (0x68) → bone (0xA8/0xB0)
            void*animator=RdPtr(ctrl,OFF_CTRL_ANIMATOR);if(!IsPtr(animator))continue;
            void*skel=RdPtr(animator,OFF_ANIMATOR_SKEL);if(!IsPtr(skel))continue;
            void*bone=RdPtr(skel,g_aimHead?OFF_SKEL_HEAD:OFF_SKEL_CHEST);if(!IsPtr(bone))continue;

            Vec3 bwp=GetTransformPos(bone);
            if(bwp.x==0&&bwp.y==0&&bwp.z==0)continue;
            CGPoint sp=W2S(bwp);if(sp.x<0)continue;

            CGFloat dx=sp.x-ctr.x, dy=sp.y-ctr.y;
            CGFloat d=sqrtf(dx*dx+dy*dy);
            if(d<bestDist){bestDist=d;bestWP=bwp;found=YES;}
        }

        if(!found)return;

        Vec3 cp=GetTransformPos(camTr);
        float ddx=bestWP.x-cp.x, ddy=bestWP.y-cp.y, ddz=bestWP.z-cp.z;
        float dist3d=sqrtf(ddx*ddx+ddy*ddy+ddz*ddz);
        if(dist3d<0.01f)return;

        float pitch=-asinf(ddy/dist3d)*(180.0f/(float)M_PI);
        float yaw  = atan2f(ddx,ddz) *(180.0f/(float)M_PI);
        Vec3 euler={pitch,yaw,0.0f};
        void*params[1]={&euler};
        exc=NULL;
        fp_runtime_invoke(g_setEulerM,camTr,params,&exc);
    }@catch(NSException*e){}
}

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
    return err?[NSString stringWithFormat:@"error: %@",err.localizedDescription]
              :[NSString stringWithFormat:@"✓ %lu classes",(unsigned long)total];
}

@interface PassthroughWindow : UIWindow @end
@implementation PassthroughWindow
-(UIView*)hitTest:(CGPoint)p withEvent:(UIEvent*)e{
    UIView*v=[super hitTest:p withEvent:e];
    return (v==self||v==self.rootViewController.view)?nil:v;
}
@end

@interface PassthroughView : UIView @end
@implementation PassthroughView
-(UIView*)hitTest:(CGPoint)p withEvent:(UIEvent*)e{UIView*v=[super hitTest:p withEvent:e];return v==self?nil:v;}
@end

@interface ESPView : UIView @end
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
            CGFloat boxW=boxH*0.55f;
            CGFloat cx=(e->fx+e->hx)*0.5f;
            CGRect  box=CGRectMake(cx-boxW*0.5f,e->hy,boxW,boxH);
            CGContextSetRGBStrokeColor(ctx,0,0,0,0.60f);CGContextSetLineWidth(ctx,2.2f);
            CGContextStrokeRect(ctx,box);
            CGContextSetRGBStrokeColor(ctx,1.0f,0.55f,0.0f,0.90f);CGContextSetLineWidth(ctx,1.2f);
            CGContextStrokeRect(ctx,box);
        }
    }
    if(g_aimOn){
        CGFloat cx=self.bounds.size.width*0.5f;
        CGFloat cy=self.bounds.size.height*0.5f;
        CGContextSetRGBStrokeColor(ctx,1.0f,0.55f,0.0f,0.35f);CGContextSetLineWidth(ctx,0.9f);
        CGContextStrokeEllipseInRect(ctx,CGRectMake(cx-g_fovRadius,cy-g_fovRadius,g_fovRadius*2,g_fovRadius*2));
        CGContextSetLineWidth(ctx,0.7f);
        CGContextMoveToPoint(ctx,cx-5,cy);CGContextAddLineToPoint(ctx,cx+5,cy);
        CGContextMoveToPoint(ctx,cx,cy-5);CGContextAddLineToPoint(ctx,cx,cy+5);
        CGContextStrokePath(ctx);
    }
}
@end

@interface MenuView : UIView
@property (strong) UIButton*espBtn,*aimBtn,*targetBtn,*dumpBtn,*closeBtn;
@property (strong) UILabel *statusLabel,*fovLabel;
@property (strong) UISlider*fovSlider;
@end
@implementation MenuView{CGPoint _drag;}
-(instancetype)initWithFrame:(CGRect)f{
    self=[super initWithFrame:f];
    self.backgroundColor=C(0.08f,0.08f,0.09f,0.95f);
    self.layer.cornerRadius=kR;self.layer.masksToBounds=YES;

    CGSize scr=[UIScreen mainScreen].bounds.size;
    CGFloat pad=(scr.width>500)?20:14;
    CGFloat btnW=((f.size.width-pad*2)-6)*0.5f;
    CGFloat y=pad;

    UIView*hdr=[[UIView alloc]initWithFrame:CGRectMake(0,0,f.size.width,44)];
    hdr.backgroundColor=C(0.10f,0.10f,0.11f,1);[self addSubview:hdr];
    UILabel*ttl=[[UILabel alloc]initWithFrame:CGRectMake(pad,0,f.size.width-pad*2-32,44)];
    ttl.text=@"cheat";ttl.textAlignment=NSTextAlignmentLeft;
    ttl.font=[UIFont systemFontOfSize:14 weight:UIFontWeightSemibold];
    ttl.textColor=C(1.0f,1.0f,1.0f,0.95f);[hdr addSubview:ttl];
    self.closeBtn=[UIButton buttonWithType:UIButtonTypeCustom];
    self.closeBtn.frame=CGRectMake(f.size.width-32,12,24,24);
    self.closeBtn.backgroundColor=C(0,0,0,0.3f);self.closeBtn.layer.cornerRadius=6;
    [self.closeBtn setTitle:@"✕" forState:UIControlStateNormal];
    [self.closeBtn setTitleColor:C(1,1,1,0.7f) forState:UIControlStateNormal];
    self.closeBtn.titleLabel.font=[UIFont systemFontOfSize:12 weight:UIFontWeightBold];
    [hdr addSubview:self.closeBtn];

    y=60;
    self.espBtn =[self btn:@"ESP" y:y w:btnW];y+=btnW+6;
    self.aimBtn =[self btn:@"AIM" y:y w:btnW];y+=btnW+18;

    UILabel*lbl=[[UILabel alloc]initWithFrame:CGRectMake(pad,y,f.size.width-pad*2,12)];
    lbl.text=@"target";lbl.font=[UIFont systemFontOfSize:9 weight:UIFontWeightSemibold];
    lbl.textColor=C(0.5f,0.5f,0.5f,1);[self addSubview:lbl];y+=16;

    self.targetBtn=[self btn:@"HEAD" y:y w:btnW];y+=btnW+18;

    lbl=[[UILabel alloc]initWithFrame:CGRectMake(pad,y,f.size.width-pad*2,12)];
    lbl.text=@"fov";lbl.font=[UIFont systemFontOfSize:9 weight:UIFontWeightSemibold];
    lbl.textColor=C(0.5f,0.5f,0.5f,1);[self addSubview:lbl];y+=16;

    self.fovLabel=[[UILabel alloc]initWithFrame:CGRectMake(pad,y,f.size.width-pad*2,11)];
    self.fovLabel.font=[UIFont monospacedSystemFontOfSize:8 weight:UIFontWeightRegular];
    self.fovLabel.textColor=C(0.6f,0.6f,0.6f,1);
    self.fovLabel.text=[NSString stringWithFormat:@"%.0f px",g_fovRadius];[self addSubview:self.fovLabel];y+=16;

    self.fovSlider=[[UISlider alloc]initWithFrame:CGRectMake(pad,y,f.size.width-pad*2,22)];
    self.fovSlider.minimumValue=20;self.fovSlider.maximumValue=300;self.fovSlider.value=g_fovRadius;
    self.fovSlider.minimumTrackTintColor=C(1.0f,0.55f,0.0f,0.85f);
    self.fovSlider.maximumTrackTintColor=C(0.20f,0.20f,0.20f,1);
    [self.fovSlider setThumbImage:[self thumbImg] forState:UIControlStateNormal];
    [self addSubview:self.fovSlider];y+=32;

    self.statusLabel=[[UILabel alloc]initWithFrame:CGRectMake(pad,y,f.size.width-pad*2,42)];
    self.statusLabel.font=[UIFont monospacedSystemFontOfSize:8 weight:UIFontWeightRegular];
    self.statusLabel.textColor=C(0.35f,0.70f,0.40f,1);
    self.statusLabel.numberOfLines=3;[self addSubview:self.statusLabel];y+=50;

    self.dumpBtn=[self btn:@"DUMP" y:y w:(f.size.width-pad*2)];

    [hdr addGestureRecognizer:[[UIPanGestureRecognizer alloc]initWithTarget:self action:@selector(pan:)]];
    return self;
}
-(UIImage*)thumbImg{
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(12,12),NO,0);
    CGContextRef c=UIGraphicsGetCurrentContext();
    CGContextSetRGBFillColor(c,1.0f,0.55f,0.0f,1);
    CGContextFillEllipseInRect(c,CGRectMake(0,0,12,12));
    UIImage*i=UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();return i;
}
-(UIButton*)btn:(NSString*)t y:(CGFloat)y w:(CGFloat)w{
    CGSize scr=[UIScreen mainScreen].bounds.size;
    CGFloat pad=(scr.width>500)?20:14;
    UIButton*b=[UIButton buttonWithType:UIButtonTypeCustom];
    b.frame=CGRectMake(pad,y,w,32);
    b.backgroundColor=C(0.12f,0.12f,0.14f,1);
    b.layer.cornerRadius=6;b.layer.borderWidth=1;
    b.layer.borderColor=C(1.0f,0.55f,0.0f,0.25f).CGColor;
    b.titleLabel.font=[UIFont systemFontOfSize:10 weight:UIFontWeightSemibold];
    [b setTitle:t forState:UIControlStateNormal];
    [b setTitleColor:C(0.85f,0.85f,0.85f,1) forState:UIControlStateNormal];
    [b setTitleColor:C(1.0f,0.55f,0.0f,1) forState:UIControlStateHighlighted];
    [b addTarget:self action:@selector(down:) forControlEvents:UIControlEventTouchDown];
    [b addTarget:self action:@selector(up:)   forControlEvents:UIControlEventTouchUpInside|UIControlEventTouchUpOutside];
    [self addSubview:b];return b;
}
-(void)down:(UIButton*)b{
    [UIView animateWithDuration:0.06 animations:^{
        b.backgroundColor=C(0.22f,0.22f,0.25f,1);
        b.layer.borderColor=C(1.0f,0.55f,0.0f,0.6f).CGColor;
    }];
}
-(void)up:(UIButton*)b{
    [UIView animateWithDuration:0.12 animations:^{
        b.backgroundColor=C(0.12f,0.12f,0.14f,1);
        b.layer.borderColor=C(1.0f,0.55f,0.0f,0.25f).CGColor;
    }];
}
-(void)pan:(UIPanGestureRecognizer*)g{
    CGPoint loc=[g locationInView:self.superview];
    if(g.state==UIGestureRecognizerStateBegan)_drag=CGPointMake(loc.x-self.frame.origin.x,loc.y-self.frame.origin.y);
    else if(g.state==UIGestureRecognizerStateChanged){CGRect r=self.frame;r.origin=CGPointMake(loc.x-_drag.x,loc.y-_drag.y);self.frame=r;}
}
@end

@interface CheatController : NSObject
+(instancetype)shared;-(void)toggle;
@end
@implementation CheatController{
    PassthroughWindow*_win;MenuView*_menu;ESPView*_espView;CADisplayLink*_dl;BOOL _visible;
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
    _win.windowLevel=UIWindowLevelAlert+200;_win.backgroundColor=[UIColor clearColor];
    PassthroughView*pv=[[PassthroughView alloc]initWithFrame:[UIScreen mainScreen].bounds];
    pv.backgroundColor=[UIColor clearColor];
    UIViewController*vc=[UIViewController new];vc.view=pv;
    _win.rootViewController=vc;_win.hidden=NO;

    _espView=[ESPView new];[pv addSubview:_espView];

    CGSize sz=[UIScreen mainScreen].bounds.size;
    CGFloat w=(sz.width>500)?400:min(sz.width-28,360);
    CGFloat h=(sz.width>500)?520:480;
    _menu=[[MenuView alloc]initWithFrame:CGRectMake((sz.width-w)*0.5f,(sz.height-h)*0.5f,w,h)];
    [pv addSubview:_menu];

    __weak CheatController*ws=self;
    [_menu.closeBtn  addTarget:self action:@selector(doClose)  forControlEvents:UIControlEventTouchUpInside];
    [_menu.espBtn    addTarget:self action:@selector(doESP)    forControlEvents:UIControlEventTouchUpInside];
    [_menu.aimBtn    addTarget:self action:@selector(doAim)    forControlEvents:UIControlEventTouchUpInside];
    [_menu.targetBtn addTarget:self action:@selector(doTarget) forControlEvents:UIControlEventTouchUpInside];
    [_menu.dumpBtn   addTarget:self action:@selector(doDump)   forControlEvents:UIControlEventTouchUpInside];
    [_menu.fovSlider addTarget:self action:@selector(fovChanged:) forControlEvents:UIControlEventValueChanged];

    _dl=[CADisplayLink displayLinkWithTarget:self selector:@selector(tick)];
    _dl.preferredFramesPerSecond=30;
    [_dl addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
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
    [_menu.espBtn setTitle:g_espOn?@"ON":@"OFF" forState:UIControlStateNormal];
    _menu.statusLabel.text=g_espOn?@"esp active":@"esp inactive";
    if(!g_espOn){g_espCount=0;[_espView setNeedsDisplay];}
}

-(void)doAim{
    g_aimOn=!g_aimOn;
    if(g_aimOn&&!g_initDone)InitClasses();
    [_menu.aimBtn setTitle:g_aimOn?@"ON":@"OFF" forState:UIControlStateNormal];
    _menu.aimBtn.layer.borderColor=g_aimOn
        ?C(1.0f,0.55f,0.0f,0.6f).CGColor
        :C(1.0f,0.55f,0.0f,0.25f).CGColor;
    _menu.statusLabel.text=g_aimOn?@"aim active":@"aim inactive";
    if(!g_aimOn)[_espView setNeedsDisplay];
}

-(void)doTarget{
    g_aimHead=!g_aimHead;
    [_menu.targetBtn setTitle:g_aimHead?@"HEAD":@"BODY" forState:UIControlStateNormal];
}

-(void)fovChanged:(UISlider*)s{
    g_fovRadius=s.value;
    _menu.fovLabel.text=[NSString stringWithFormat:@"%.0f px",g_fovRadius];
    if(g_aimOn)[_espView setNeedsDisplay];
}

-(void)doDump{
    _menu.dumpBtn.enabled=NO;
    _menu.statusLabel.text=@"dumping...";
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0),^{
        NSString*res=PerformDump();
        dispatch_async(dispatch_get_main_queue(),^{
            self->_menu.dumpBtn.enabled=YES;
            self->_menu.statusLabel.text=res;
        });
    });
}

-(void)doClose{
    [UIView animateWithDuration:kDur delay:0 options:UIViewAnimationOptionCurveEaseIn animations:^{
        self->_menu.alpha=0;self->_menu.transform=CGAffineTransformMakeScale(0.85f,0.85f);
    }completion:^(BOOL _){
        self->_menu.hidden=YES;self->_menu.transform=CGAffineTransformIdentity;self->_visible=NO;
    }];
}

-(void)toggle{_visible?[self doClose]:^{_visible=YES;_menu.hidden=NO;_menu.alpha=0;_menu.transform=CGAffineTransformMakeScale(0.88f,0.88f);[UIView animateWithDuration:kDur animations:^{self->_menu.alpha=1;self->_menu.transform=CGAffineTransformIdentity;}];}();}
@end

__attribute__((constructor))
static void Init(void){
    dispatch_async(dispatch_get_main_queue(),^{
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(1.5*NSEC_PER_SEC)),
                       dispatch_get_main_queue(),^{
            [[CheatController shared]toggle];
        });
    });
}
