// CounterFlame ESP — com.ScarletWork.CounterFlame
// caught-by: скриншот-детект, поведенческий анализ
//
// Архитектура: только прямое чтение памяти через оффсеты, минимум invoke.
// FindObjectsOfType вызывается раз в секунду на фоновом потоке, результат кэшируется.
// WorldToScreenPoint — единственный invoke в тик-цикле.

#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>
#include <dlfcn.h>

// ─── Team ─────────────────────────────────────────────────────────────────
typedef enum { TeamNone = 0, TeamCT = 1, TeamTR = 2 } CFTeam;

// ─── оффсеты ──────────────────────────────────────────────────────────────
// PlayerController
#define PC_IS_DEATH   0xA8   // bool
#define PC_NETWORK    0x88   // PlayerNetwork*
#define PC_HULL       0x00   // FILL: GetComponent нужен, пока через PSkeleton

// PlayerNetwork
#define PN_POSITION   0xBC   // Vector3 (float x,y,z)

// PlayerSkeleton — получаем через PC._movementController цепочку или FindObjectsOfType<PlayerSkeleton>
// Линкуем к PC через IL2CPP Object instanceID сравнением — слишком сложно без символов
// Проще: FindObjectsOfType<PlayerSkeleton> отдельно, потом матчим по позиции
// НО: это 2 invoke. Вместо этого — читаем скелет через field на самом PC.

// PlayerController → _movementController (0x40) → PlayerMovement
// PlayerMovement не содержит скелет напрямую
// Быстрее: FindObjectsOfType<PlayerController> → на каждом PC читаем _network → networkPosition
// Скелет ищем отдельно через FindObjectsOfType<PlayerSkeleton>, матчим к PC по близости позиции

// PlayerSkeleton
#define PS_HEAD       0xA8   // Transform*
#define PS_CHEST      0xB0   // Transform*
#define PS_PELVIS     0xB8   // Transform*
#define PS_LSHOULDER  0xC0   // Transform*
#define PS_RSHOULDER  0xC8   // Transform*
#define PS_LTHIGH     0xD0   // Transform*
#define PS_RTHIGH     0xD8   // Transform*

// PlayerHull
#define PH_TEAM       0x30   // int (CFTeam)

// Transform — нативный Unity Transform (не managed)
// position хранится в TRS: offset зависит от версии Unity
// БЕЗОПАСНО: читаем через get_position invoke только при кэшировании скелета
// В тик-цикле: только networkPosition (прямой read) + W2S

// ─── il2cpp ───────────────────────────────────────────────────────────────
typedef void*  (*fn_t)(void);
typedef void** (*fn_assemblies_t)(void*, size_t*);
typedef void*  (*fn_img_t)(void*);
typedef void*  (*fn_cls_t)(void*, const char*, const char*);
typedef void*  (*fn_meth_t)(void*, const char*, int);
typedef void*  (*fn_invoke_t)(void*, void*, void**, void**);
typedef void*  (*fn_unbox_t)(void*);
typedef void*  (*fn_type_t)(void*);

static fn_t          _domain_get;
static fn_assemblies_t _domain_asms;
static fn_img_t      _asm_img;
static fn_cls_t      _cls;
static fn_meth_t     _meth;
static fn_invoke_t   _invoke;
static fn_unbox_t    _unbox;
static fn_type_t     _type;

typedef struct { float x, y, z; } Vec3;

static inline void*   rp(void *o, ptrdiff_t n)  { return (o && n>=0) ? *(void**)((uint8_t*)o+n) : NULL; }
static inline uint8_t rb(void *o, ptrdiff_t n)  { return o ? *((uint8_t*)o+n) : 0; }
static inline Vec3    rv(void *o, ptrdiff_t n)  {
    if (!o) return (Vec3){0,0,0};
    return *(Vec3*)((uint8_t*)o+n);
}

// ─── cached methods ───────────────────────────────────────────────────────
static void *gPCClass     = NULL;
static void *gPSClass     = NULL;
static void *gFindObjs    = NULL;
static void *gGetComp     = NULL;
static void *gTrPos       = NULL;
static void *gCamMain     = NULL;
static void *gW2S         = NULL;
static void *gPSType      = NULL;
static void *gHullClass   = NULL;
static void *gHullType    = NULL;
static BOOL  gReady       = NO;
static int   gLocalTeam   = TeamNone;

// ─── ESP overlay ──────────────────────────────────────────────────────────
typedef struct {
    CGRect  box;
    CGPoint pts[7]; // head,chest,pelvis,lsh,rsh,lth,rth
    BOOL    valid;
} ESPEntry;

@interface ESPView : UIView
@property (nonatomic, strong) NSArray *entries;
@end
@implementation ESPView
- (instancetype)initWithFrame:(CGRect)f {
    self = [super initWithFrame:f];
    self.backgroundColor = [UIColor clearColor];
    self.userInteractionEnabled = NO;
    _entries = @[];
    return self;
}
- (void)drawRect:(CGRect)__unused r {
    CGContextRef ctx = UIGraphicsGetCurrentContext();
    CGContextSetLineWidth(ctx, 1.8f);

    for (NSData *d in _entries) {
        if (d.length != sizeof(ESPEntry)) continue;
        ESPEntry e; [d getBytes:&e length:sizeof(e)];
        if (!e.valid) continue;

        // бокс красный
        CGContextSetStrokeColorWithColor(ctx,
            [UIColor colorWithRed:1 green:0.15 blue:0.15 alpha:0.9].CGColor);
        CGContextStrokeRect(ctx, e.box);

        // скелет зелёный
        CGContextSetStrokeColorWithColor(ctx,
            [UIColor colorWithRed:0 green:1 blue:0.2 alpha:0.85].CGColor);

        CGPoint head=e.pts[0], chest=e.pts[1], pelv=e.pts[2];
        CGPoint ls=e.pts[3],   rs=e.pts[4];
        CGPoint lt=e.pts[5],   rt=e.pts[6];

        // позвоночник
        if (head.x&&chest.x) {
            CGContextMoveToPoint(ctx,head.x,head.y);
            CGContextAddLineToPoint(ctx,chest.x,chest.y);
        }
        if (chest.x&&pelv.x) {
            CGContextMoveToPoint(ctx,chest.x,chest.y);
            CGContextAddLineToPoint(ctx,pelv.x,pelv.y);
        }
        // руки
        if (ls.x&&rs.x&&chest.x) {
            CGContextMoveToPoint(ctx,ls.x,ls.y);
            CGContextAddLineToPoint(ctx,chest.x,chest.y);
            CGContextAddLineToPoint(ctx,rs.x,rs.y);
        }
        // ноги
        if (lt.x&&rt.x&&pelv.x) {
            CGContextMoveToPoint(ctx,lt.x,lt.y);
            CGContextAddLineToPoint(ctx,pelv.x,pelv.y);
            CGContextAddLineToPoint(ctx,rt.x,rt.y);
        }
        CGContextStrokePath(ctx);

        // голова — кружок
        if (head.x) {
            float rr = e.box.size.width * 0.14f;
            CGContextStrokeEllipseInRect(ctx,
                CGRectMake(head.x-rr, head.y-rr, rr*2, rr*2));
        }
    }
}
@end

// ─── menu ─────────────────────────────────────────────────────────────────
@interface ESPMenuView : UIView
@property (nonatomic, strong) UISwitch *sw;
- (void)show;
@end

static ESPView     *gESPView  = nil;
static ESPMenuView *gMenu     = nil;
static BOOL         gESPOn    = NO;

@implementation ESPMenuView {
    ESPView *_ev;
}
- (instancetype)initWithESP:(ESPView*)ev {
    self = [super initWithFrame:CGRectMake(0,0,165,95)];
    _ev = ev;
    self.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.75];
    self.layer.cornerRadius = 10;
    self.layer.zPosition = 1000;
    self.userInteractionEnabled = YES;

    UILabel *t = [[UILabel alloc] initWithFrame:CGRectMake(0,4,165,22)];
    t.text=@"CF ESP"; t.textColor=[UIColor colorWithRed:0 green:1 blue:0 alpha:1];
    t.font=[UIFont boldSystemFontOfSize:13]; t.textAlignment=NSTextAlignmentCenter;
    [self addSubview:t];

    UILabel *l = [[UILabel alloc] initWithFrame:CGRectMake(10,31,52,22)];
    l.text=@"ESP"; l.textColor=[UIColor whiteColor];
    l.font=[UIFont systemFontOfSize:12]; [self addSubview:l];

    _sw = [UISwitch new];
    _sw.transform = CGAffineTransformMakeScale(0.75,0.75);
    _sw.frame = CGRectMake(62,29,51,31);
    [_sw addTarget:self action:@selector(tog:) forControlEvents:UIControlEventValueChanged];
    [self addSubview:_sw];

    for (int i=0;i<2;i++) {
        UIButton *b = [UIButton buttonWithType:UIButtonTypeSystem];
        b.frame = CGRectMake(i?88:8, 65, 66, 22);
        b.tag = i;
        [b setTitle:i?@"Закрыть":@"Скрыть" forState:UIControlStateNormal];
        [b setTitleColor:i?[UIColor redColor]:[UIColor lightGrayColor]
                forState:UIControlStateNormal];
        b.titleLabel.font = [UIFont systemFontOfSize:11];
        [b addTarget:self action:@selector(btn:) forControlEvents:UIControlEventTouchUpInside];
        [self addSubview:b];
    }

    UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc]
        initWithTarget:self action:@selector(pan:)];
    [self addGestureRecognizer:pan];
    return self;
}
- (void)pan:(UIPanGestureRecognizer*)g {
    CGPoint t=[g translationInView:self.superview];
    self.center=CGPointMake(self.center.x+t.x,self.center.y+t.y);
    [g setTranslation:CGPointZero inView:self.superview];
}
- (void)tog:(UISwitch*)s { gESPOn=s.isOn; _ev.hidden=!gESPOn; }
- (void)btn:(UIButton*)b {
    if (b.tag==1){ gESPOn=NO; _ev.hidden=YES; _sw.on=NO; }
    self.hidden=YES;
}
- (void)show { self.hidden=NO; }
@end

// ─── W2S ──────────────────────────────────────────────────────────────────
static CGPoint w2s(Vec3 w) {
    void *exc=NULL;
    void *cam=_invoke(gCamMain,NULL,NULL,&exc);
    if (!cam||exc) return CGPointZero;
    void *a[1]={&w};
    void *res=_invoke(gW2S,cam,a,&exc);
    if (!res||exc) return CGPointZero;
    Vec3 *sp=(Vec3*)_unbox(res);
    if (!sp||sp->z<0) return CGPointZero;
    CGFloat sc=[UIScreen mainScreen].scale;
    CGFloat sh=[UIScreen mainScreen].bounds.size.height;
    return CGPointMake(sp->x/sc, sh-sp->y/sc);
}

// Transform.get_position — только для скелет-кэша, не в тик-цикле
static Vec3 trPos(void *tr) {
    if (!tr||!gTrPos) return (Vec3){0,0,0};
    void *exc=NULL;
    void *r=_invoke(gTrPos,tr,NULL,&exc);
    if (!r||exc) return (Vec3){0,0,0};
    Vec3 *p=(Vec3*)_unbox(r);
    return p?*p:(Vec3){0,0,0};
}

// ─── скелет-кэш ───────────────────────────────────────────────────────────
// Обновляем редко (раз в секунду), матчим PlayerSkeleton → PlayerController
// по близости позиции: берём pelvis/head из PS и networkPosition из PC
// Если расстояние < 0.5 — это скелет данного PC

typedef struct {
    void *pc;       // PlayerController*
    void *ps;       // PlayerSkeleton* (может быть NULL)
    int   team;
    Vec3  bonePos[7]; // head,chest,pelv,ls,rs,lt,rt — кэш на момент обновления
    BOOL  hasBones;
} PCCache;

#define MAX_PLAYERS 32
static PCCache gCache[MAX_PLAYERS];
static int     gCacheCount = 0;
static NSLock *gCacheLock;

// Обновление кэша — вызывается на фоновом потоке раз в секунду
static void updateCache(void) {
    if (!gFindObjs||!gPCClass) return;

    void *pcType=_type(gPCClass);
    void *exc=NULL, *a[1]={pcType};
    void *arr=_invoke(gFindObjs,NULL,a,&exc);
    if (!arr||exc) return;

    int32_t cnt=*(int32_t*)((uint8_t*)arr+0x18);
    void **data=(void**)((uint8_t*)arr+0x20);
    if (!data||cnt<=0) return;

    // массив PlayerSkeleton для матчинга
    void *psArr=NULL;
    int32_t psCnt=0;
    void **psData=NULL;
    if (gPSClass&&gPSType) {
        void *pa[1]={gPSType};
        psArr=_invoke(gFindObjs,NULL,pa,&exc);
        if (psArr&&!exc) {
            psCnt=*(int32_t*)((uint8_t*)psArr+0x18);
            psData=(void**)((uint8_t*)psArr+0x20);
        }
    }

    PCCache tmp[MAX_PLAYERS];
    int tmpCnt=0;

    for (int i=0;i<cnt&&i<MAX_PLAYERS;i++) {
        void *pc=data[i];
        if (!pc) continue;

        PCCache c={0};
        c.pc=pc;

        // команда через PlayerHull
        if (gGetComp&&gHullType) {
            void *ha[1]={gHullType};
            void *hull=_invoke(gGetComp,pc,ha,&exc);
            if (hull&&!exc) {
                int team=*(int*)((uint8_t*)hull+PH_TEAM);
                c.team=team;

                // кэшируем нашу команду через IsMine у PhotonView — не нужно,
                // просто: если это первый раз видим локального игрока и isDeath=0
                // определяем его позже. Пока — просто сохраняем team.
                // gLocalTeam кэшируем снаружи отдельно.
            }
        }

        // PlayerNetwork → networkPosition
        void *pn=rp(pc,PC_NETWORK);
        if (!pn) continue;
        Vec3 netPos=rv(pn,PN_POSITION);

        // матчим PlayerSkeleton по позиции pelvis/head
        if (psData&&psCnt>0) {
            for (int j=0;j<psCnt&&j<MAX_PLAYERS;j++) {
                void *ps=psData[j];
                if (!ps) continue;
                void *pelTr=rp(ps,PS_PELVIS);
                if (!pelTr) continue;
                Vec3 pelv=trPos(pelTr);
                // расстояние XZ
                float dx=pelv.x-netPos.x, dz=pelv.z-netPos.z;
                if (dx*dx+dz*dz < 0.5f*0.5f) {
                    c.ps=ps;
                    // читаем все кости сразу пока мы в updateCache
                    void *trs[7]={
                        rp(ps,PS_HEAD), rp(ps,PS_CHEST),  rp(ps,PS_PELVIS),
                        rp(ps,PS_LSHOULDER), rp(ps,PS_RSHOULDER),
                        rp(ps,PS_LTHIGH),    rp(ps,PS_RTHIGH)
                    };
                    for (int k=0;k<7;k++)
                        c.bonePos[k]=trs[k]?trPos(trs[k]):(Vec3){0,0,0};
                    c.hasBones=YES;
                    break;
                }
            }
        }

        tmp[tmpCnt++]=c;
    }

    [gCacheLock lock];
    memcpy(gCache,tmp,sizeof(PCCache)*tmpCnt);
    gCacheCount=tmpCnt;
    [gCacheLock unlock];
}

// ─── ticker ───────────────────────────────────────────────────────────────
@interface ESPTicker : NSObject {
    NSTimeInterval _lastCacheUpdate;
}
- (void)tick;
@end
@implementation ESPTicker
- (void)tick {
    if (!gESPOn||!gReady) return;

    // обновляем кэш раз в секунду на фоновом потоке
    NSTimeInterval now=CACurrentMediaTime();
    if (now-_lastCacheUpdate > 1.0) {
        _lastCacheUpdate=now;
        dispatch_async(dispatch_get_global_queue(0,0), ^{ updateCache(); });
    }

    [gCacheLock lock];
    int count=gCacheCount;
    PCCache snap[MAX_PLAYERS];
    memcpy(snap,gCache,sizeof(PCCache)*count);
    [gCacheLock unlock];

    CGFloat sh=[UIScreen mainScreen].bounds.size.height;
    NSMutableArray *res=[NSMutableArray arrayWithCapacity:count];

    for (int i=0;i<count;i++) {
        PCCache *c=&snap[i];
        if (!c->pc) continue;
        if (rb(c->pc,PC_IS_DEATH)) continue;
        if (c->team==TeamNone) continue;
        if (gLocalTeam!=TeamNone && c->team==gLocalTeam) continue;

        void *pn=rp(c->pc,PC_NETWORK);
        if (!pn) continue;
        Vec3 netPos=rv(pn,PN_POSITION);

        // высота игрока: стоя ~1.75, присел ~1.1
        Vec3 headPos={netPos.x, netPos.y+1.75f, netPos.z};
        Vec3 feetPos=netPos;

        CGPoint sHead=w2s(headPos);
        CGPoint sFeet=w2s(feetPos);
        if (CGPointEqualToPoint(sHead,CGPointZero)) continue;
        if (CGPointEqualToPoint(sFeet,CGPointZero)) continue;
        if (sFeet.y<0||sFeet.y>sh) continue;

        CGFloat h=fabs(sFeet.y-sHead.y);
        if (h<8.f) continue;
        CGFloat w=h*0.45f;

        ESPEntry e={0};
        e.valid=YES;
        e.box=CGRectMake(sHead.x-w*.5f, sHead.y, w, h);

        if (c->hasBones) {
            for (int k=0;k<7;k++) e.pts[k]=w2s(c->bonePos[k]);
        } else {
            // фоллбек без скелета
            e.pts[0]=sHead;
            e.pts[1]=w2s((Vec3){netPos.x,netPos.y+1.3f,netPos.z});
            e.pts[2]=w2s((Vec3){netPos.x,netPos.y+0.9f,netPos.z});
            e.pts[3]=w2s((Vec3){netPos.x-.3f,netPos.y+1.3f,netPos.z});
            e.pts[4]=w2s((Vec3){netPos.x+.3f,netPos.y+1.3f,netPos.z});
            e.pts[5]=w2s((Vec3){netPos.x-.15f,netPos.y+.5f,netPos.z});
            e.pts[6]=w2s((Vec3){netPos.x+.15f,netPos.y+.5f,netPos.z});
        }

        [res addObject:[NSData dataWithBytes:&e length:sizeof(e)]];
    }

    NSArray *final=[res copy];
    dispatch_async(dispatch_get_main_queue(),^{
        gESPView.entries=final;
        [gESPView setNeedsDisplay];
    });
}
@end

// ─── il2cpp init ──────────────────────────────────────────────────────────
static BOOL bindSymbols(void) {
    void *h=dlopen(NULL,RTLD_LAZY);
    if (!h) return NO;
#define B(v,n) v=(__typeof__(v))dlsym(h,n); if(!v){NSLog(@"[esp] ?" n);return NO;}
    B(_domain_get,  "il2cpp_domain_get")
    B(_domain_asms, "il2cpp_domain_get_assemblies")
    B(_asm_img,     "il2cpp_assembly_get_image")
    B(_cls,         "il2cpp_class_from_name")
    B(_meth,        "il2cpp_class_get_method_from_name")
    B(_invoke,      "il2cpp_runtime_invoke")
    B(_unbox,       "il2cpp_object_unbox")
    B(_type,        "il2cpp_class_get_type")
#undef B
    return YES;
}

static void* findImg(void **a,size_t n,const char *ns,const char *c){
    for(size_t i=0;i<n;i++){void *img=_asm_img(a[i]);if(img&&_cls(img,ns,c))return img;}
    return NULL;
}

static void initMethods(void){
    void *d=_domain_get(); size_t n=0;
    void **a=_domain_asms(d,&n);
    if(!a||!n){NSLog(@"[esp] no assemblies");return;}

    void *main=findImg(a,n,"","PlayerController");
    void *ue  =findImg(a,n,"UnityEngine","Camera");
    if(!main||!ue){NSLog(@"[esp] images not found");return;}

    gPCClass   =_cls(main,"","PlayerController");
    gPSClass   =_cls(main,"","PlayerSkeleton");
    gHullClass =_cls(main,"","PlayerHull");
    if(gPSClass)   gPSType  =_type(gPSClass);
    if(gHullClass) gHullType=_type(gHullClass);

    void *objC=_cls(ue,"UnityEngine","Object");
    void *cmpC=_cls(ue,"UnityEngine","Component");
    void *trC =_cls(ue,"UnityEngine","Transform");
    void *camC=_cls(ue,"UnityEngine","Camera");

    if(objC) gFindObjs=_meth(objC,"FindObjectsOfType",1);
    if(cmpC) gGetComp =_meth(cmpC,"GetComponent",1);
    if(trC)  gTrPos   =_meth(trC, "get_position",0);
    if(camC){gCamMain =_meth(camC,"get_main",0);
             gW2S     =_meth(camC,"WorldToScreenPoint",1);}

    gReady=(gFindObjs&&gCamMain&&gW2S&&gPCClass);
    NSLog(@"[esp] ready=%d ps=%d hull=%d",gReady,!!gPSClass,!!gHullClass);
}

// ─── UI ───────────────────────────────────────────────────────────────────
static void setupUI(void){
    UIWindow *kw=nil;
    for(UIScene *s in UIApplication.sharedApplication.connectedScenes)
        if([s isKindOfClass:[UIWindowScene class]]&&
           s.activationState==UISceneActivationStateForegroundActive)
        {kw=((UIWindowScene*)s).windows.firstObject;break;}
    if(!kw){NSLog(@"[esp] no window");return;}

    CGRect sc=[UIScreen mainScreen].bounds;
    gESPView=[[ESPView alloc]initWithFrame:sc];
    gESPView.hidden=YES;
    [kw addSubview:gESPView];

    gMenu=[[ESPMenuView alloc]initWithESP:gESPView];
    gMenu.center=CGPointMake(sc.size.width-92,110);
    [kw addSubview:gMenu];

    UITapGestureRecognizer *tap=[[UITapGestureRecognizer alloc]
        initWithTarget:gMenu action:@selector(show)];
    tap.numberOfTouchesRequired=3;
    [kw addGestureRecognizer:tap];

    gCacheLock=[NSLock new];

    ESPTicker *ticker=[ESPTicker new];
    objc_setAssociatedObject(kw,"cf_t",ticker,OBJC_ASSOCIATION_RETAIN);
    CADisplayLink *dl=[CADisplayLink displayLinkWithTarget:ticker selector:@selector(tick)];
    dl.preferredFramesPerSecond=30;
    [dl addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
}

// ─── entry ────────────────────────────────────────────────────────────────
__attribute__((constructor))
static void cfEspInit(void){
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(4*NSEC_PER_SEC)),
                   dispatch_get_global_queue(0,0),^{
        if(!bindSymbols())return;
        initMethods();
        dispatch_async(dispatch_get_main_queue(),^{setupUI();});
    });
}
