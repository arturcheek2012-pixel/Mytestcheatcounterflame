#import <UIKit/UIKit.h>
#include <mach/mach.h>
#include <mach/vm_map.h>
#include <vector>
#include <cstring>
#include <cstdint>

typedef NS_ENUM(NSInteger, VType) { VTi8=0,VTi16,VTi32,VTi64,VTf32,VTf64 };
typedef NS_ENUM(NSInteger, SMode) { SMeq=0,SMne,SMgt,SMlt,SMinc,SMdec,SMchg,SMunchg };

static size_t vsz(VType t){ static const size_t s[]={1,2,4,8,4,8}; return s[t]; }

struct Addr { vm_address_t a; uint8_t prev[8]; };
static std::vector<Addr> gRes;
static bool gHasFirst = false;

static void toBytes(NSString *s, VType t, uint8_t *o) {
    memset(o,0,8);
    switch(t){
        case VTi8:  {int8_t  v=(int8_t)[s intValue];       memcpy(o,&v,1);return;}
        case VTi16: {int16_t v=(int16_t)[s intValue];      memcpy(o,&v,2);return;}
        case VTi32: {int32_t v=(int32_t)[s intValue];      memcpy(o,&v,4);return;}
        case VTi64: {int64_t v=(int64_t)[s longLongValue]; memcpy(o,&v,8);return;}
        case VTf32: {float   v=[s floatValue];              memcpy(o,&v,4);return;}
        case VTf64: {double  v=[s doubleValue];             memcpy(o,&v,8);return;}
    }
}

static NSString *fromBytes(const uint8_t *b, VType t) {
    switch(t){
        case VTi8:  {int8_t  v;memcpy(&v,b,1);return[NSString stringWithFormat:@"%d",v];}
        case VTi16: {int16_t v;memcpy(&v,b,2);return[NSString stringWithFormat:@"%d",v];}
        case VTi32: {int32_t v;memcpy(&v,b,4);return[NSString stringWithFormat:@"%d",v];}
        case VTi64: {int64_t v;memcpy(&v,b,8);return[NSString stringWithFormat:@"%lld",v];}
        case VTf32: {float   v;memcpy(&v,b,4);return[NSString stringWithFormat:@"%.4f",v];}
        case VTf64: {double  v;memcpy(&v,b,8);return[NSString stringWithFormat:@"%.6f",v];}
    }
}

static bool matches(const uint8_t *cur, const uint8_t *prev,
                    const uint8_t *tgt, SMode m, VType t) {
    size_t sz=vsz(t);
    if(m==SMeq)    return memcmp(cur,tgt,sz)==0;
    if(m==SMne)    return memcmp(cur,tgt,sz)!=0;
    if(m==SMchg)   return memcmp(cur,prev,sz)!=0;
    if(m==SMunchg) return memcmp(cur,prev,sz)==0;
    double c=0,p=0,g=0;
    switch(t){
        case VTi8:  {int8_t  x,y,z;memcpy(&x,cur,1);memcpy(&y,prev,1);memcpy(&z,tgt,1);c=x;p=y;g=z;break;}
        case VTi16: {int16_t x,y,z;memcpy(&x,cur,2);memcpy(&y,prev,2);memcpy(&z,tgt,2);c=x;p=y;g=z;break;}
        case VTi32: {int32_t x,y,z;memcpy(&x,cur,4);memcpy(&y,prev,4);memcpy(&z,tgt,4);c=x;p=y;g=z;break;}
        case VTi64: {int64_t x,y,z;memcpy(&x,cur,8);memcpy(&y,prev,8);memcpy(&z,tgt,8);c=(double)x;p=(double)y;g=(double)z;break;}
        case VTf32: {float   x,y,z;memcpy(&x,cur,4);memcpy(&y,prev,4);memcpy(&z,tgt,4);c=x;p=y;g=z;break;}
        case VTf64: {memcpy(&c,cur,8);memcpy(&p,prev,8);memcpy(&g,tgt,8);break;}
    }
    switch(m){
        case SMgt:  return c>g;
        case SMlt:  return c<g;
        case SMinc: return c>p;
        case SMdec: return c<p;
        default:    return false;
    }
}

static std::vector<Addr> firstScan(const uint8_t *tgt, VType type) {
    std::vector<Addr> out;
    size_t sz=vsz(type);
    vm_address_t addr=0; vm_size_t size=0;
    while(1){
        vm_region_basic_info_data_64_t info;
        mach_msg_type_number_t cnt=VM_REGION_BASIC_INFO_COUNT_64;
        mach_port_t obj;
        if(vm_region_64(mach_task_self(),&addr,&size,VM_REGION_BASIC_INFO_64,
                        (vm_region_info_t)&info,&cnt,&obj)!=KERN_SUCCESS) break;
        bool rw=(info.protection&VM_PROT_READ)&&(info.protection&VM_PROT_WRITE);
        if(rw && size<=128*1024*1024){
            uint8_t *buf=(uint8_t*)malloc(size);
            if(buf){
                vm_size_t got=0;
                if(vm_read_overwrite(mach_task_self(),addr,size,
                                     (vm_address_t)buf,&got)==KERN_SUCCESS){
                    for(vm_size_t off=0;off+sz<=got;off+=sz){
                        if(matches(buf+off,nullptr,tgt,SMeq,type)){
                            Addr r; r.a=addr+off; memcpy(r.prev,buf+off,sz);
                            out.push_back(r);
                        }
                    }
                }
                free(buf);
            }
        }
        addr+=size;
    }
    return out;
}

static std::vector<Addr> nextScan(const std::vector<Addr> &prev,
                                   const uint8_t *tgt, SMode mode, VType type) {
    std::vector<Addr> out;
    size_t sz=vsz(type); uint8_t cur[8]={};
    for(auto &r:prev){
        vm_size_t got=0;
        if(vm_read_overwrite(mach_task_self(),r.a,sz,
                             (vm_address_t)cur,&got)!=KERN_SUCCESS) continue;
        if(matches(cur,r.prev,tgt,mode,type)){
            Addr n; n.a=r.a; memcpy(n.prev,cur,sz);
            out.push_back(n);
        }
    }
    return out;
}

static BOOL writeMem(vm_address_t addr, const uint8_t *val, size_t sz) {
    return vm_write(mach_task_self(),addr,(vm_offset_t)val,
                    (mach_msg_type_number_t)sz)==KERN_SUCCESS;
}

// ═══ Freeze ══════════════════════════════════════════════════════════════════

static NSMutableArray *gTimers;
static NSUInteger gFreezeCount = 0;

static void addFreeze(vm_address_t addr, NSData *val) {
    vm_address_t a=addr;
    gFreezeCount++;
    dispatch_source_t t=dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER,0,0,
                         dispatch_get_global_queue(QOS_CLASS_UTILITY,0));
    dispatch_source_set_timer(t,DISPATCH_TIME_NOW,50*NSEC_PER_MSEC,5*NSEC_PER_MSEC);
    dispatch_source_set_event_handler(t,^{
        vm_write(mach_task_self(),a,(vm_offset_t)val.bytes,(mach_msg_type_number_t)val.length);
    });
    dispatch_resume(t);
    [gTimers addObject:t];
}

static void clearFreeze() {
    for(dispatch_source_t t in gTimers) dispatch_source_cancel(t);
    [gTimers removeAllObjects]; gFreezeCount=0;
}

// ═══ UI helpers ══════════════════════════════════════════════════════════════

static UIColor *cBg()     { return [UIColor colorWithRed:.07f green:.07f blue:.07f alpha:.97f]; }
static UIColor *cCell()   { return [UIColor colorWithRed:.10f green:.10f blue:.10f alpha:1]; }
static UIColor *cBtn()    { return [UIColor colorWithRed:.17f green:.17f blue:.17f alpha:1]; }
static UIColor *cAccent() { return [UIColor colorWithRed:.32f green:.65f blue:1.f  alpha:1]; }
static UIColor *cText()   { return [UIColor colorWithWhite:.9f alpha:1]; }
static UIColor *cSub()    { return [UIColor colorWithWhite:.45f alpha:1]; }
static UIColor *cRed()    { return [UIColor colorWithRed:1.f green:.3f blue:.3f alpha:1]; }

static UIFont *mono(CGFloat s) { return [UIFont monospacedSystemFontOfSize:s weight:UIFontWeightRegular]; }
static UIFont *med(CGFloat s)  { return [UIFont systemFontOfSize:s weight:UIFontWeightMedium]; }

static UIButton *mkBtn(NSString *t, UIColor *bg, CGFloat fs) {
    UIButton *b=[UIButton buttonWithType:UIButtonTypeCustom];
    b.backgroundColor=bg; b.layer.cornerRadius=5; b.titleLabel.font=med(fs);
    [b setTitle:t forState:UIControlStateNormal];
    [b setTitleColor:cText() forState:UIControlStateNormal];
    [b setTitleColor:[UIColor colorWithWhite:.4 alpha:1] forState:UIControlStateHighlighted];
    return b;
}

static UITextField *mkField(NSString *ph) {
    UITextField *f=[[UITextField alloc]init];
    f.backgroundColor=cCell(); f.textColor=cText(); f.font=mono(13);
    f.keyboardType=UIKeyboardTypeDecimalPad; f.layer.cornerRadius=5;
    f.leftView=[[UIView alloc]initWithFrame:CGRectMake(0,0,8,0)];
    f.leftViewMode=UITextFieldViewModeAlways;
    f.attributedPlaceholder=[[NSAttributedString alloc]
        initWithString:ph attributes:@{NSForegroundColorAttributeName:cSub(),
                                       NSFontAttributeName:mono(13)}];
    return f;
}

// ═══ Window ══════════════════════════════════════════════════════════════════

@interface MSWindow : UIWindow
@end
@implementation MSWindow
-(BOOL)pointInside:(CGPoint)p withEvent:(UIEvent *)e {
    for(UIView *v in self.rootViewController.view.subviews)
        if(!v.hidden && v.alpha>.01 && CGRectContainsPoint(v.frame,p)) return YES;
    return NO;
}
@end

// ═══ ViewController ══════════════════════════════════════════════════════════

@interface MSVC : UIViewController<UITableViewDataSource,UITableViewDelegate>
@end

@implementation MSVC {
    UIButton            *_fab;
    UIView              *_panel;
    BOOL                 _open;
    UITextField         *_valF, *_patchF;
    UILabel             *_status;
    UITableView         *_table;
    NSArray<UIButton*>  *_typeBtns, *_modeBtns;
    NSArray<NSString*>  *_rows;
    VType  _vt;
    SMode  _sm;
}

-(void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor=UIColor.clearColor;
    _vt=VTi32; _sm=SMeq; _rows=@[];
    gTimers=[NSMutableArray array];
    [self setupFAB];
    [self setupPanel];
    _panel.alpha=0; _panel.hidden=YES; _open=NO;
}

-(void)setupFAB {
    _fab=mkBtn(@"M",cAccent(),14);
    _fab.frame=CGRectMake(18,120,36,36);
    _fab.layer.cornerRadius=18; _fab.alpha=.88f;
    [_fab addTarget:self action:@selector(toggle) forControlEvents:UIControlEventTouchUpInside];
    [_fab addGestureRecognizer:[[UIPanGestureRecognizer alloc]
        initWithTarget:self action:@selector(dragFAB:)]];
    [self.view addSubview:_fab];
}

-(void)dragFAB:(UIPanGestureRecognizer*)g {
    CGPoint d=[g translationInView:self.view];
    _fab.center=CGPointMake(_fab.center.x+d.x,_fab.center.y+d.y);
    [g setTranslation:CGPointZero inView:self.view];
}

-(UIToolbar*)doneBar {
    UIToolbar *tb=[[UIToolbar alloc]initWithFrame:CGRectMake(0,0,320,44)];
    tb.barStyle=UIBarStyleBlack;
    UIBarButtonItem *sp=[[UIBarButtonItem alloc]
        initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace target:nil action:nil];
    UIBarButtonItem *dn=[[UIBarButtonItem alloc]
        initWithTitle:@"Done" style:UIBarButtonItemStyleDone target:self action:@selector(dismissKB)];
    dn.tintColor=cAccent(); tb.items=@[sp,dn];
    return tb;
}
-(void)dismissKB { [_valF resignFirstResponder]; [_patchF resignFirstResponder]; }

-(void)setupPanel {
    CGFloat W=MIN(self.view.bounds.size.width-20, 320);
    CGFloat H=464;
    _panel=[[UIView alloc]initWithFrame:CGRectMake(10,80,W,H)];
    _panel.backgroundColor=cBg(); _panel.layer.cornerRadius=10; _panel.clipsToBounds=YES;
    [_panel addGestureRecognizer:[[UIPanGestureRecognizer alloc]
        initWithTarget:self action:@selector(dragPanel:)]];
    [self.view addSubview:_panel];

    UIView *hdl=[[UIView alloc]initWithFrame:CGRectMake(W/2-16,7,32,4)];
    hdl.backgroundColor=cBtn(); hdl.layer.cornerRadius=2;
    [_panel addSubview:hdl];

    UILabel *title=[[UILabel alloc]initWithFrame:CGRectMake(0,5,W,18)];
    title.text=@"MemScan"; title.font=med(13);
    title.textColor=cAccent(); title.textAlignment=NSTextAlignmentCenter;
    [_panel addSubview:title];

    CGFloat y=26, x=10;

    _valF=mkField(@"value");
    _valF.frame=CGRectMake(x,y,W-108,34);
    _valF.inputAccessoryView=[self doneBar];
    [_panel addSubview:_valF];

    UIButton *fb=mkBtn(@"First Scan",cAccent(),12);
    fb.frame=CGRectMake(W-96,y,86,34);
    [fb addTarget:self action:@selector(doFirst) forControlEvents:UIControlEventTouchUpInside];
    [_panel addSubview:fb];
    y+=40;

    NSArray *tl=@[@"i8",@"i16",@"i32",@"i64",@"f32",@"f64"];
    CGFloat tw=(W-20)/6.f;
    NSMutableArray *tb=[NSMutableArray array];
    for(int i=0;i<6;i++){
        UIButton *b=mkBtn(tl[i],i==2?cAccent():cBtn(),11);
        b.frame=CGRectMake(x+i*tw,y,tw-2,26);
        b.tag=i;
        [b addTarget:self action:@selector(selType:) forControlEvents:UIControlEventTouchUpInside];
        [_panel addSubview:b]; [tb addObject:b];
    }
    _typeBtns=tb; y+=32;

    NSArray *ml=@[@"==",@"!=",@">",@"<",@"↑",@"↓",@"chg",@"unch"];
    CGFloat mw=(W-20)/4.f;
    NSMutableArray *mb=[NSMutableArray array];
    for(int i=0;i<8;i++){
        UIButton *b=mkBtn(ml[i],i==0?cAccent():cBtn(),12);
        b.frame=CGRectMake(x+(i%4)*mw,y+(i/4)*30,mw-2,26);
        b.tag=i;
        [b addTarget:self action:@selector(selMode:) forControlEvents:UIControlEventTouchUpInside];
        [_panel addSubview:b]; [mb addObject:b];
    }
    _modeBtns=mb; y+=66;

    CGFloat hw=(W-24)/2.f;
    UIButton *nb=mkBtn(@"Next Scan",cBtn(),12);
    nb.frame=CGRectMake(x,y,hw,30);
    [nb addTarget:self action:@selector(doNext) forControlEvents:UIControlEventTouchUpInside];
    [_panel addSubview:nb];

    UIButton *rb=mkBtn(@"Reset",cRed(),12);
    rb.frame=CGRectMake(x+hw+4,y,hw,30);
    [rb addTarget:self action:@selector(doReset) forControlEvents:UIControlEventTouchUpInside];
    [_panel addSubview:rb];
    y+=36;

    _status=[[UILabel alloc]initWithFrame:CGRectMake(x,y,W-20,16)];
    _status.font=mono(10); _status.textColor=cSub(); _status.text=@"no scan";
    [_panel addSubview:_status];
    y+=20;

    CGFloat th=H-y-46;
    _table=[[UITableView alloc]initWithFrame:CGRectMake(0,y,W,th) style:UITableViewStylePlain];
    _table.backgroundColor=cCell();
    _table.separatorColor=[UIColor colorWithWhite:.14 alpha:1];
    _table.dataSource=self; _table.delegate=self; _table.rowHeight=32;
    [_panel addSubview:_table];
    y+=th+2;

    _patchF=mkField(@"patch value");
    _patchF.frame=CGRectMake(x,y,W-96,34);
    _patchF.inputAccessoryView=[self doneBar];
    [_panel addSubview:_patchF];

    UIButton *pb=mkBtn(@"Patch All",cBtn(),12);
    pb.frame=CGRectMake(W-84,y,74,34);
    [pb addTarget:self action:@selector(doPatchAll) forControlEvents:UIControlEventTouchUpInside];
    [_panel addSubview:pb];
}

-(void)dragPanel:(UIPanGestureRecognizer*)g {
    CGPoint d=[g translationInView:self.view];
    _panel.center=CGPointMake(_panel.center.x+d.x,_panel.center.y+d.y);
    [g setTranslation:CGPointZero inView:self.view];
}

-(void)toggle {
    _open=!_open;
    if(_open){
        _panel.hidden=NO;
        [UIView animateWithDuration:.15 animations:^{self->_panel.alpha=1;}];
    } else {
        [UIView animateWithDuration:.12 animations:^{self->_panel.alpha=0;}
                         completion:^(BOOL f){self->_panel.hidden=YES;}];
        [self dismissKB];
    }
}

-(void)selType:(UIButton*)s {
    _vt=(VType)s.tag;
    for(UIButton *b in _typeBtns) b.backgroundColor=cBtn();
    s.backgroundColor=cAccent();
}

-(void)selMode:(UIButton*)s {
    _sm=(SMode)s.tag;
    for(UIButton *b in _modeBtns) b.backgroundColor=cBtn();
    s.backgroundColor=cAccent();
}

-(void)updateUI {
    dispatch_async(dispatch_get_main_queue(),^{
        self->_status.text=[NSString stringWithFormat:@"%zu result%s | %lu frozen",
                            gRes.size(), gRes.size()==1?"":"s",
                            (unsigned long)gFreezeCount];
        NSMutableArray *r=[NSMutableArray array];
        size_t n=MIN(gRes.size(),(size_t)300);
        for(size_t i=0;i<n;i++)
            [r addObject:[NSString stringWithFormat:@"0x%lX  %@",
                          (unsigned long)gRes[i].a, fromBytes(gRes[i].prev,self->_vt)]];
        self->_rows=r;
        [self->_table reloadData];
    });
}

-(void)doFirst {
    if(!_valF.text.length) return;
    [self dismissKB];
    uint8_t tmp[8]; toBytes(_valF.text,_vt,tmp);
    NSData *tgtData=[NSData dataWithBytes:tmp length:8];
    VType t=_vt; _status.text=@"scanning…";
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0),^{
        gRes=firstScan((const uint8_t*)tgtData.bytes,t); gHasFirst=YES;
        [self updateUI];
    });
}

-(void)doNext {
    if(!gHasFirst){ [self doFirst]; return; }
    uint8_t tmp[8]={}; if(_valF.text.length) toBytes(_valF.text,_vt,tmp);
    NSData *tgtData=[NSData dataWithBytes:tmp length:8];
    SMode m=_sm; VType t=_vt;
    _status.text=@"filtering…"; [self dismissKB];
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0),^{
        auto p=gRes; gRes=nextScan(p,(const uint8_t*)tgtData.bytes,m,t);
        [self updateUI];
    });
}

-(void)doReset {
    gRes.clear(); gHasFirst=false; clearFreeze();
    _rows=@[]; [_table reloadData]; _status.text=@"reset";
}

-(void)doPatchAll {
    if(!_patchF.text.length || gRes.empty()) return;
    uint8_t val[8]; toBytes(_patchF.text,_vt,val);
    size_t sz=vsz(_vt);
    for(auto &r:gRes){ writeMem(r.a,val,sz); memcpy(r.prev,val,sz); }
    _status.text=[NSString stringWithFormat:@"patched %zu",gRes.size()];
}

-(NSInteger)tableView:(UITableView*)tv numberOfRowsInSection:(NSInteger)s {
    return (NSInteger)_rows.count;
}

-(UITableViewCell*)tableView:(UITableView*)tv cellForRowAtIndexPath:(NSIndexPath*)ip {
    UITableViewCell *c=[tv dequeueReusableCellWithIdentifier:@"c"] ?:
        [[UITableViewCell alloc]initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"c"];
    c.backgroundColor=cCell(); c.textLabel.font=mono(11); c.textLabel.textColor=cText();
    c.textLabel.text=_rows[ip.row];
    return c;
}

-(void)tableView:(UITableView*)tv didSelectRowAtIndexPath:(NSIndexPath*)ip {
    [tv deselectRowAtIndexPath:ip animated:NO];
    NSUInteger idx=(NSUInteger)ip.row;
    if(idx>=gRes.size()) return;
    vm_address_t addr=gRes[idx].a;
    VType vt=_vt; size_t sz=vsz(vt);
    NSString *pv=_patchF.text;

    UIAlertController *ac=[UIAlertController
        alertControllerWithTitle:[NSString stringWithFormat:@"0x%lX",(unsigned long)addr]
                         message:nil preferredStyle:UIAlertControllerStyleActionSheet];

    [ac addAction:[UIAlertAction actionWithTitle:@"Patch" style:UIAlertActionStyleDefault handler:^(id _){
        if(!pv.length) return;
        uint8_t val[8]; toBytes(pv,vt,val);
        writeMem(addr,val,sz); memcpy(gRes[idx].prev,val,sz);
        [self updateUI];
    }]];
    [ac addAction:[UIAlertAction actionWithTitle:@"Freeze" style:UIAlertActionStyleDefault handler:^(id _){
        if(!pv.length) return;
        uint8_t val[8]; toBytes(pv,vt,val);
        addFreeze(addr,[NSData dataWithBytes:val length:sz]);
        dispatch_async(dispatch_get_main_queue(),^{
            self->_status.text=[NSString stringWithFormat:@"%zu result%s | %lu frozen",
                                gRes.size(),gRes.size()==1?"":"s",(unsigned long)gFreezeCount];
        });
    }]];
    [ac addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:ac animated:YES completion:nil];
}

@end

// ═══ Init ════════════════════════════════════════════════════════════════════

static MSWindow *gWin;

__attribute__((constructor))
static void ms_init() {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(1.5*NSEC_PER_SEC)),
                   dispatch_get_main_queue(),^{
        UIWindowScene *scene=nil;
        for(UIScene *s in UIApplication.sharedApplication.connectedScenes)
            if([s isKindOfClass:[UIWindowScene class]]){
                scene=(UIWindowScene*)s;
                if(s.activationState==UISceneActivationStateForegroundActive) break;
            }
        if(scene){
            gWin=[[MSWindow alloc]initWithWindowScene:scene];
            gWin.frame=scene.coordinateSpace.bounds;
        } else {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
            gWin=[[MSWindow alloc]initWithFrame:UIScreen.mainScreen.bounds];
#pragma clang diagnostic pop
        }
        gWin.windowLevel=UIWindowLevelStatusBar+200;
        gWin.backgroundColor=UIColor.clearColor;
        gWin.rootViewController=[MSVC new];
        [gWin makeKeyAndVisible];
    });
}
