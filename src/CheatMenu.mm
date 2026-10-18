#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <dlfcn.h>
#import <mach-o/dyld.h>

static const CGFloat kW   = 260.0f;
static const CGFloat kH   = 440.0f;
static const CGFloat kHdr = 42.0f;
static const CGFloat kR   = 12.0f;
static const NSTimeInterval kDur = 0.22;
static inline UIColor* C(CGFloat r,CGFloat g,CGFloat b,CGFloat a){
    return [UIColor colorWithRed:r green:g blue:b alpha:a];
}
typedef struct { float x,y,z; } Vec3;

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

static BOOL IsPtr(const void*p){uintptr_t v=(uintptr_t)p;return v>0x10000UL&&v<0x00FFFFFFFFFFFFFFULL;}
static void* RdPtr(const void*base,size_t off){if(!IsPtr(base))return NULL;void**a=(void**)((const uint8_t*)base+off);if(!IsPtr(a))return NULL;return *a;}
static int32_t RdI32(const void*base,size_t off){if(!IsPtr(base))return 0;return *(int32_t*)((const uint8_t*)base+off);}
static BOOL RdBool(const void*base,size_t off){if(!IsPtr(base))return NO;return *(bool*)((const uint8_t*)base+off);}

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
static BOOL g_initDone=NO;

static void InitClasses(void){
    if(g_initDone)return;
    if(!LoadAPI())return;
    void*domain=fp_domain_get();
    size_t n=0;void**asms=fp_domain_assemblies(domain,&n);
    for(size_t i=0;i<n;i++){
        void*img=fp_assembly_image(asms[i]);if(!img)continue;
        const char*nm=fp_image_name(img);if(!nm)continue;
        if(!g_imgCSharp&&strcmp(nm,"Assembly-CSharp.dll")==0)g_imgCSharp=img;
        if(!g_imgUnity&&(strcmp(nm,"UnityEngine.CoreModule.dll")==0||strcmp(nm,"UnityEngine.dll")==0))g_imgUnity=img;
    }
    if(g_imgCSharp)g_pcClass=fp_class_from_name(g_imgCSharp,"","PlayerCulling");
    if(g_imgUnity){
        void*camC=fp_class_from_name(g_imgUnity,"UnityEngine","Camera");
        void*compC=fp_class_from_name(g_imgUnity,"UnityEngine","Component");
        void*trnC=fp_class_from_name(g_imgUnity,"UnityEngine","Transform");
        if(camC){g_getMainM=fp_class_method_from_name(camC,"get_main",0);g_w2sM=fp_class_method_from_name(camC,"WorldToScreenPoint",1);}
        if(compC)g_getTransM=fp_class_method_from_name(compC,"get_transform",0);
        if(trnC)g_getPosM=fp_class_method_from_name(trnC,"get_position",0);
    }
    UnityBase();g_initDone=YES;
}

// ─── ESP entry: храним foot + head в screen coords ────────────────────────────
#define MAX_ESP 64
typedef struct {
    CGFloat fx,fy;   // feet screen
    CGFloat hx,hy;   // head screen
    float   health;
    BOOL    valid;
} ESPEntry;
static ESPEntry g_esp[MAX_ESP];
static int      g_espCount=0;
static BOOL     g_espOn=NO;

static Vec3 GetPos(void*obj){
    Vec3 z={0,0,0};
    if(!IsPtr(obj)||!fp_runtime_invoke||!g_getTransM||!g_getPosM)return z;
    void*exc=NULL;
    void*tr=fp_runtime_invoke(g_getTransM,obj,NULL,&exc);if(!IsPtr(tr)||exc)return z;
    exc=NULL;
    void*bp=fp_runtime_invoke(g_getPosM,tr,NULL,&exc);if(!IsPtr(bp)||exc||!fp_object_unbox)return z;
    Vec3*p=(Vec3*)fp_object_unbox(bp);return p?*p:z;
}

static CGPoint W2S(Vec3 wp){
    const CGPoint bad={-1,-1};
    if(!fp_runtime_invoke||!g_getMainM||!g_w2sM||!fp_object_unbox)return bad;
    void*exc=NULL;
    void*cam=fp_runtime_invoke(g_getMainM,NULL,NULL,&exc);if(!IsPtr(cam)||exc)return bad;
    void*params[1]={&wp};exc=NULL;
    void*br=fp_runtime_invoke(g_w2sM,cam,params,&exc);if(!IsPtr(br)||exc)return bad;
    Vec3*sv=(Vec3*)fp_object_unbox(br);if(!sv||sv->z<=0.0f)return bad;
    CGFloat sc=[UIScreen mainScreen].scale;
    CGFloat uH=[UIScreen mainScreen].bounds.size.height;
    return CGPointMake(sv->x/sc,uH-sv->y/sc);
}

static float GetHealth(void*ctrl){
    uintptr_t base=UnityBase();if(!base||!IsPtr(ctrl))return 0;
    // PlayerController.get_Health RVA: 0x1579C3C
    // FILL: re-derive if game updates
    typedef float(*HFn)(void*,void*);
    float h=0;
    @try{h=((HFn)(base+0x1579C3C))(ctrl,NULL);}@catch(...){}
    return(h<0||h>1000)?0:h;
}

static void UpdateESP(void){
    g_espCount=0;
    if(!g_espOn||!IsPtr(g_pcClass)||!fp_class_static_data)return;
    void*sd=fp_class_static_data(g_pcClass);if(!IsPtr(sd))return;
    void*list=RdPtr(sd,0x8);if(!IsPtr(list))return;
    void*arr=RdPtr(list,0x10);
    int32_t sz=RdI32(list,0x18);
    if(!IsPtr(arr)||sz<=0||sz>200)return;
    int n=sz<MAX_ESP?sz:MAX_ESP;
    for(int i=0;i<n;i++){
        void*culling=RdPtr(arr,0x20+(size_t)i*8);if(!IsPtr(culling))continue;
        void*ctrl=RdPtr(culling,0x18);if(!IsPtr(ctrl))continue;
        if(RdBool(ctrl,0xA8))continue;

        Vec3 foot=GetPos(culling);
        if(foot.x==0&&foot.y==0&&foot.z==0)continue;

        // голова = foot + 1.8 по Y (мировые координаты Unity)
        Vec3 head={foot.x, foot.y+1.8f, foot.z};

        CGPoint fs=W2S(foot);if(fs.x<0)continue;
        CGPoint hs=W2S(head);if(hs.x<0)continue;

        float hp=GetHealth(ctrl);
        g_esp[g_espCount++]=(ESPEntry){fs.x,fs.y,hs.x,hs.y,hp,YES};
    }
}

static NSString* PerformDump(void){
    if(!LoadAPI())return @"ошибка: API не найден";
    void*domain=fp_domain_get();if(!domain)return @"ошибка: domain NULL";
    uintptr_t base=UnityBase();
    size_t ac=0;void**asms=fp_domain_assemblies(domain,&ac);
    if(!asms)return @"ошибка: assemblies NULL";
    NSMutableString*out=[NSMutableString string];
    [out appendFormat:@"// Counter Flame IL2CPP Dump\n// base: 0x%lx\n\n",base];
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
            NSString*full=(ns&&*ns)?[NSString stringWithFormat:@"%s.%s",ns,nm?:"?"]:[NSString stringWithUTF8String:nm?:"?"];
            pn?[out appendFormat:@"\npublic class %@ : %s {\n",full,pn]:[out appendFormat:@"\npublic class %@ {\n",full];
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

// ─── PassthroughWindow ────────────────────────────────────────────────────────
@interface PassthroughWindow : UIWindow @end
@implementation PassthroughWindow
- (UIView*)hitTest:(CGPoint)p withEvent:(UIEvent*)e{
    UIView*v=[super hitTest:p withEvent:e];
    if(!v||v==self||v==self.rootViewController.view)return nil;
    if(!v.userInteractionEnabled)return nil;
    return v;
}
@end

@interface PassthroughView : UIView @end
@implementation PassthroughView
- (UIView*)hitTest:(CGPoint)p withEvent:(UIEvent*)e{
    UIView*v=[super hitTest:p withEvent:e];return v==self?nil:v;
}
@end

// ─── ESPView ──────────────────────────────────────────────────────────────────
@interface ESPView : UIView @end
@implementation ESPView
- (instancetype)init{
    self=[super initWithFrame:[UIScreen mainScreen].bounds];
    self.backgroundColor=[UIColor clearColor];
    self.userInteractionEnabled=NO;
    return self;
}
- (void)drawRect:(CGRect)r{
    if(!g_espOn||g_espCount==0)return;
    CGContextRef ctx=UIGraphicsGetCurrentContext();
    NSDictionary*txtAttr=@{
        NSFontAttributeName:[UIFont monospacedSystemFontOfSize:9 weight:UIFontWeightBold],
        NSForegroundColorAttributeName:[UIColor whiteColor]
    };

    for(int i=0;i<g_espCount;i++){
        ESPEntry*e=&g_esp[i];
        if(!e->valid)continue;

        // размер бокса
        CGFloat boxH = e->fy - e->hy;          // foot.y - head.y (экран: Y вниз)
        if(boxH < 8.0f) boxH = 8.0f;
        CGFloat boxW = boxH * 0.40f;
        CGFloat cx   = (e->fx + e->hx) * 0.5f;
        CGFloat top  = e->hy;
        CGFloat left = cx - boxW * 0.5f;

        CGRect box = CGRectMake(left, top, boxW, boxH);

        // цвет по HP
        float hp = e->health;
        CGFloat gr = (hp>0) ? (hp/100.0f) : 0.5f;
        gr = gr>1?1:(gr<0?0:gr);

        // тень (чёрный контур чуть толще)
        CGContextSetRGBStrokeColor(ctx,0,0,0,0.75f);
        CGContextSetLineWidth(ctx,2.5f);
        CGContextStrokeRect(ctx,CGRectInset(box,-0.5f,-0.5f));

        // основной бокс
        CGContextSetRGBStrokeColor(ctx,1.0f-gr,gr,0.15f,0.95f);
        CGContextSetLineWidth(ctx,1.5f);
        CGContextStrokeRect(ctx,box);

        // HP бар справа от бокса (ширина 3px)
        CGFloat barX  = left + boxW + 3.0f;
        CGFloat barH  = boxH;
        CGFloat fillH = barH * (hp>0?(hp/100.0f):0);

        // фон бара
        CGContextSetRGBFillColor(ctx,0,0,0,0.45f);
        CGContextFillRect(ctx,CGRectMake(barX,top,3,barH));
        // заливка
        CGContextSetRGBFillColor(ctx,1.0f-gr,gr,0.15f,0.90f);
        CGContextFillRect(ctx,CGRectMake(barX,top+barH-fillH,3,fillH));

        // HP текст над боксом
        if(hp>0){
            NSString*s=[NSString stringWithFormat:@"%.0f",hp];
            CGSize ts=[s sizeWithAttributes:txtAttr];
            [s drawAtPoint:CGPointMake(cx-ts.width*0.5f,top-12) withAttributes:txtAttr];
        }
    }
}
@end

// ─── PillButton ───────────────────────────────────────────────────────────────
@interface PillButton : UIView
@property (copy) dispatch_block_t action;
@end
@implementation PillButton{CGPoint _off;BOOL _moved;}
- (instancetype)init{
    self=[super initWithFrame:CGRectMake(20,120,44,28)];
    self.backgroundColor=C(0.10f,0.10f,0.13f,0.92f);
    self.layer.cornerRadius=14;self.layer.borderColor=C(0.27f,0.52f,1.00f,0.45f).CGColor;self.layer.borderWidth=1;
    UILabel*l=[[UILabel alloc]initWithFrame:self.bounds];
    l.text=@"☰";l.textAlignment=NSTextAlignmentCenter;l.font=[UIFont systemFontOfSize:13];l.textColor=C(0.75f,0.75f,0.80f,1);
    [self addSubview:l];
    [self addGestureRecognizer:[[UIPanGestureRecognizer alloc]initWithTarget:self action:@selector(pan:)]];
    return self;
}
- (void)pan:(UIPanGestureRecognizer*)g{
    CGPoint loc=[g locationInView:self.superview];
    if(g.state==UIGestureRecognizerStateBegan){_moved=NO;_off=CGPointMake(loc.x-self.frame.origin.x,loc.y-self.frame.origin.y);}
    else if(g.state==UIGestureRecognizerStateChanged){_moved=YES;CGRect f=self.frame;f.origin=CGPointMake(loc.x-_off.x,loc.y-_off.y);self.frame=f;}
}
- (void)touchesEnded:(NSSet*)t withEvent:(UIEvent*)e{if(!_moved&&_action)_action();}
@end

// ─── MenuView ─────────────────────────────────────────────────────────────────
@interface MenuView : UIView
@property (strong) UIButton*hideBtn,*closeBtn,*dumpBtn,*espBtn;
@property (strong) UILabel*statusLabel;
@end
@implementation MenuView{CGPoint _drag;}
- (instancetype)initWithFrame:(CGRect)f{
    self=[super initWithFrame:f];
    self.backgroundColor=C(0.07f,0.07f,0.09f,0.93f);
    self.layer.cornerRadius=kR;self.layer.masksToBounds=YES;

    UIView*hdr=[[UIView alloc]initWithFrame:CGRectMake(0,0,kW,kHdr)];
    hdr.backgroundColor=C(0.10f,0.10f,0.13f,1);[self addSubview:hdr];
    UIView*acc=[[UIView alloc]initWithFrame:CGRectMake(0,kHdr-1,kW,1)];
    acc.backgroundColor=C(0.27f,0.52f,1.00f,0.55f);[self addSubview:acc];
    UILabel*ttl=[[UILabel alloc]initWithFrame:CGRectMake(0,(kHdr-17)*.5f,kW,17)];
    ttl.text=@"Cheat Menu";ttl.textAlignment=NSTextAlignmentCenter;
    ttl.font=[UIFont systemFontOfSize:13 weight:UIFontWeightSemibold];
    ttl.textColor=C(0.92f,0.92f,0.95f,1);[self addSubview:ttl];

    UIView*card=[[UIView alloc]initWithFrame:CGRectMake(12,kHdr+14,kW-24,200)];
    card.backgroundColor=C(0.10f,0.10f,0.13f,1);card.layer.cornerRadius=8;[self addSubview:card];
    UILabel*sl=[[UILabel alloc]initWithFrame:CGRectMake(10,10,(kW-24)-20,12)];
    sl.text=@"TOOLS";sl.font=[UIFont systemFontOfSize:9 weight:UIFontWeightSemibold];
    sl.textColor=C(0.27f,0.52f,1.00f,1);[card addSubview:sl];

    self.espBtn =[self cardBtn:@"ESP: OFF"    y:28  card:card];
    self.dumpBtn=[self cardBtn:@"Dump IL2CPP" y:74  card:card];
    self.statusLabel=[[UILabel alloc]initWithFrame:CGRectMake(10,120,(kW-24)-20,60)];
    self.statusLabel.font=[UIFont monospacedSystemFontOfSize:9 weight:UIFontWeightRegular];
    self.statusLabel.textColor=C(0.35f,0.70f,0.40f,1);self.statusLabel.numberOfLines=4;
    [card addSubview:self.statusLabel];

    CALayer*bdr=[CALayer layer];bdr.frame=CGRectMake(0,0,kW,kH);
    bdr.borderColor=C(0.22f,0.22f,0.28f,0.65f).CGColor;bdr.borderWidth=1;bdr.cornerRadius=kR;
    [self.layer addSublayer:bdr];
    self.hideBtn=[self hdrBtn:@"−" x:kW-58];self.closeBtn=[self hdrBtn:@"×" x:kW-30];
    [hdr addGestureRecognizer:[[UIPanGestureRecognizer alloc]initWithTarget:self action:@selector(pan:)]];
    return self;
}
- (UIButton*)cardBtn:(NSString*)t y:(CGFloat)y card:(UIView*)card{
    UIButton*b=[UIButton buttonWithType:UIButtonTypeCustom];
    b.frame=CGRectMake(10,y,(kW-24)-20,34);b.backgroundColor=C(0.14f,0.14f,0.18f,1);
    b.layer.cornerRadius=6;b.layer.borderWidth=1;b.layer.borderColor=C(0.27f,0.52f,1.00f,0.30f).CGColor;
    b.titleLabel.font=[UIFont systemFontOfSize:11 weight:UIFontWeightMedium];
    [b setTitle:t forState:UIControlStateNormal];
    [b setTitleColor:C(0.80f,0.80f,0.90f,1) forState:UIControlStateNormal];
    [b setTitleColor:C(0.27f,0.52f,1.00f,1) forState:UIControlStateHighlighted];
    [b addTarget:self action:@selector(bDown:) forControlEvents:UIControlEventTouchDown];
    [b addTarget:self action:@selector(bUp:) forControlEvents:UIControlEventTouchUpInside|UIControlEventTouchUpOutside];
    [card addSubview:b];return b;
}
- (UIButton*)hdrBtn:(NSString*)g x:(CGFloat)x{
    UIButton*b=[UIButton buttonWithType:UIButtonTypeCustom];
    b.frame=CGRectMake(x,(kHdr-24)*.5f,24,24);b.layer.cornerRadius=12;b.layer.masksToBounds=YES;
    b.backgroundColor=C(0.17f,0.17f,0.21f,1);b.titleLabel.font=[UIFont systemFontOfSize:11 weight:UIFontWeightMedium];
    [b setTitle:g forState:UIControlStateNormal];[b setTitleColor:C(0.55f,0.55f,0.60f,1) forState:UIControlStateNormal];
    [b setTitleColor:[UIColor whiteColor] forState:UIControlStateHighlighted];
    [b addTarget:self action:@selector(bDown:) forControlEvents:UIControlEventTouchDown];
    [b addTarget:self action:@selector(bUp:) forControlEvents:UIControlEventTouchUpInside|UIControlEventTouchUpOutside];
    [self addSubview:b];return b;
}
- (void)bDown:(UIButton*)b{[UIView animateWithDuration:0.08 animations:^{b.backgroundColor=C(0.28f,0.28f,0.36f,1);}];}
- (void)bUp:(UIButton*)b  {[UIView animateWithDuration:0.12 animations:^{b.backgroundColor=C(0.17f,0.17f,0.21f,1);}];}
- (void)pan:(UIPanGestureRecognizer*)g{
    CGPoint loc=[g locationInView:self.superview];
    if(g.state==UIGestureRecognizerStateBegan)_drag=CGPointMake(loc.x-self.frame.origin.x,loc.y-self.frame.origin.y);
    else if(g.state==UIGestureRecognizerStateChanged){CGRect r=self.frame;r.origin=CGPointMake(loc.x-_drag.x,loc.y-_drag.y);self.frame=r;}
}
@end

// ─── CheatController ──────────────────────────────────────────────────────────
@interface CheatController : NSObject
+(instancetype)shared;-(void)toggle;
@end
@implementation CheatController{
    PassthroughWindow*_win;MenuView*_menu;ESPView*_espView;PillButton*_pill;BOOL _visible;CADisplayLink*_dl;
}
+(instancetype)shared{static CheatController*inst;static dispatch_once_t once;dispatch_once(&once,^{inst=[CheatController new];});return inst;}
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
    _win.rootViewController=vc;
    _win.hidden=NO;   // не makeKeyAndVisible — иначе игра теряет тачи

    _espView=[ESPView new];[pv addSubview:_espView];
    CGSize sz=[UIScreen mainScreen].bounds.size;
    _menu=[[MenuView alloc]initWithFrame:CGRectMake((sz.width-kW)*.5f,(sz.height-kH)*.5f,kW,kH)];
    [pv addSubview:_menu];
    __weak CheatController*ws=self;
    _pill=[PillButton new];_pill.action=^{[ws doShow];};_pill.hidden=YES;[pv addSubview:_pill];

    [_menu.hideBtn  addTarget:self action:@selector(doHide)  forControlEvents:UIControlEventTouchUpInside];
    [_menu.closeBtn addTarget:self action:@selector(doClose) forControlEvents:UIControlEventTouchUpInside];
    [_menu.dumpBtn  addTarget:self action:@selector(doDump)  forControlEvents:UIControlEventTouchUpInside];
    [_menu.espBtn   addTarget:self action:@selector(doESP)   forControlEvents:UIControlEventTouchUpInside];

    _dl=[CADisplayLink displayLinkWithTarget:self selector:@selector(tick)];
    _dl.preferredFramesPerSecond=30;
    [_dl addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
}

-(void)tick{if(!g_espOn)return;if(!g_initDone)InitClasses();UpdateESP();[_espView setNeedsDisplay];}

-(void)doESP{
    g_espOn=!g_espOn;
    if(g_espOn&&!g_initDone)InitClasses();
    [_menu.espBtn setTitle:g_espOn?@"ESP: ON":@"ESP: OFF" forState:UIControlStateNormal];
    _menu.statusLabel.text=g_espOn?@"ESP активен":@"ESP выключен";
    _menu.statusLabel.textColor=g_espOn?C(0.35f,0.70f,0.40f,1):C(0.55f,0.55f,0.60f,1);
    if(!g_espOn){g_espCount=0;[_espView setNeedsDisplay];}
}
-(void)doDump{
    _menu.dumpBtn.enabled=NO;_menu.statusLabel.text=@"dumping...";_menu.statusLabel.textColor=C(0.70f,0.70f,0.35f,1);
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0),^{
        NSString*res=PerformDump();
        dispatch_async(dispatch_get_main_queue(),^{
            self->_menu.dumpBtn.enabled=YES;self->_menu.statusLabel.text=res;
            self->_menu.statusLabel.textColor=[res hasPrefix:@"ошибка"]?C(0.80f,0.30f,0.30f,1):C(0.35f,0.70f,0.40f,1);
        });
    });
}
-(void)doShow{
    _pill.hidden=YES;_menu.hidden=NO;_menu.alpha=0;_menu.transform=CGAffineTransformMakeScale(0.88f,0.88f);
    [UIView animateWithDuration:kDur delay:0 options:UIViewAnimationOptionCurveEaseOut animations:^{
        self->_menu.alpha=1;self->_menu.transform=CGAffineTransformIdentity;
    }completion:nil];_visible=YES;
}
-(void)doHide{
    [UIView animateWithDuration:kDur delay:0 options:UIViewAnimationOptionCurveEaseIn animations:^{
        self->_menu.alpha=0;self->_menu.transform=CGAffineTransformMakeScale(0.94f,0.94f);
    }completion:^(BOOL _){self->_menu.hidden=YES;self->_menu.transform=CGAffineTransformIdentity;self->_pill.hidden=NO;self->_visible=NO;}];
}
-(void)doClose{
    [UIView animateWithDuration:kDur delay:0 options:UIViewAnimationOptionCurveEaseIn animations:^{
        self->_menu.alpha=0;self->_menu.transform=CGAffineTransformMakeScale(0.88f,0.88f);
    }completion:^(BOOL _){self->_menu.hidden=YES;self->_menu.transform=CGAffineTransformIdentity;self->_pill.hidden=NO;self->_visible=NO;}];
}
-(void)toggle{_visible?[self doHide]:[self doShow];}
@end

__attribute__((constructor))
static void Init(void){
    dispatch_async(dispatch_get_main_queue(),^{
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(1.5*NSEC_PER_SEC)),dispatch_get_main_queue(),^{
            [[CheatController shared]toggle];
        });
    });
}
