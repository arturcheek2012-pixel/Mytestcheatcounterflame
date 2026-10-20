#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <dlfcn.h>
#import <mach-o/dyld.h>

// ═══════════════════════════════════════════════════════════════════════════════
// IL2CPP API
// ═══════════════════════════════════════════════════════════════════════════════
static void*   (*fp_domain_get)(void);
static void**  (*fp_domain_assemblies)(void*,size_t*);
static void*   (*fp_assembly_image)(void*);
static char*   (*fp_image_name)(void*);
static void*   (*fp_image_classes)(void*,size_t*);
static char*   (*fp_class_name)(void*);
static char*   (*fp_class_namespace)(void*);
static void*   (*fp_class_get_methods)(void*,void**);
static char*   (*fp_method_name)(void*);
static int     (*fp_method_param_count)(void*);
static void*   (*fp_method_return_type)(void*);
static char*   (*fp_type_name)(void*);
static void*   (*fp_class_get_fields)(void*,void**);
static char*   (*fp_field_name)(void*);
static int     (*fp_field_offset)(void*);
static void*   (*fp_field_type)(void*);

static BOOL LoadDumpAPI(void) {
#define R(p,s) p=(__typeof__(p))dlsym(RTLD_DEFAULT,s)
    R(fp_domain_get,          "il2cpp_domain_get");
    R(fp_domain_assemblies,   "il2cpp_domain_get_assemblies");
    R(fp_assembly_image,      "il2cpp_assembly_get_image");
    R(fp_image_name,          "il2cpp_image_get_name");
    R(fp_image_classes,       "il2cpp_image_get_classes");
    R(fp_class_name,          "il2cpp_class_get_name");
    R(fp_class_namespace,     "il2cpp_class_get_namespace");
    R(fp_class_get_methods,   "il2cpp_class_get_methods");
    R(fp_method_name,         "il2cpp_method_get_name");
    R(fp_method_param_count,  "il2cpp_method_get_param_count");
    R(fp_method_return_type,  "il2cpp_method_get_return_type");
    R(fp_type_name,           "il2cpp_type_get_name");
    R(fp_class_get_fields,    "il2cpp_class_get_fields");
    R(fp_field_name,          "il2cpp_field_get_name");
    R(fp_field_offset,        "il2cpp_field_get_offset");
    R(fp_field_type,          "il2cpp_field_get_type");
#undef R
    return fp_domain_get != NULL && fp_image_classes != NULL;
}

// ═══════════════════════════════════════════════════════════════════════════════
// дампер
// ═══════════════════════════════════════════════════════════════════════════════
static void FlushToFile(NSString *path, NSMutableString *buf) {
    if (!buf.length) return;
    NSFileHandle *fh = [NSFileHandle fileHandleForWritingAtPath:path];
    if (!fh) {
        [@"" writeToFile:path atomically:NO encoding:NSUTF8StringEncoding error:nil];
        fh = [NSFileHandle fileHandleForWritingAtPath:path];
    }
    [fh seekToEndOfFile];
    [fh writeData:[buf dataUsingEncoding:NSUTF8StringEncoding]];
    [fh closeFile];
    [buf setString:@""];
}

static void RunDump(void) {
    if (!LoadDumpAPI()) {
        NSLog(@"[DUMP] API not loaded");
        return;
    }

    NSString *docs = NSSearchPathForDirectoriesInDomains(
        NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
    NSString *path = [docs stringByAppendingPathComponent:@"dump.cs"];
    // очищаем старый файл
    [@"" writeToFile:path atomically:NO encoding:NSUTF8StringEncoding error:nil];

    NSMutableString *out = [NSMutableString stringWithCapacity:1024*512];

    void *domain = fp_domain_get();
    size_t asmCount = 0;
    void **asms = fp_domain_assemblies(domain, &asmCount);

    for (size_t ai = 0; ai < asmCount; ai++) {
        void *img = fp_assembly_image(asms[ai]);
        if (!img) continue;
        const char *imgName = fp_image_name(img);
        if (!imgName) continue;

        [out appendFormat:@"\n// Image: %s\n", imgName];

        size_t classCount = 0;
        void **classes = (void**)fp_image_classes(img, &classCount);
        if (!classes) continue;

        for (size_t ci = 0; ci < classCount; ci++) {
            void *klass = classes[ci];
            if (!klass) continue;

            const char *ns   = fp_class_namespace ? fp_class_namespace(klass) : "";
            const char *name = fp_class_name(klass);
            if (!name) continue;

            if (ns && strlen(ns) > 0)
                [out appendFormat:@"\n// Namespace: %s\nclass %s {\n", ns, name];
            else
                [out appendFormat:@"\nclass %s {\n", name];

            // поля
            if (fp_class_get_fields && fp_field_name && fp_field_offset && fp_field_type && fp_type_name) {
                void *it = NULL;
                void *f;
                while ((f = fp_class_get_fields(klass, &it)) != NULL) {
                    const char *fn = fp_field_name(f);
                    int offset     = fp_field_offset(f);
                    void *ft       = fp_field_type(f);
                    const char *tn = (ft && fp_type_name) ? fp_type_name(ft) : "?";
                    if (fn)
                        [out appendFormat:@"    // 0x%X\n    %s %s;\n",
                            offset, tn ? tn : "?", fn];
                }
            }

            // методы
            if (fp_class_get_methods && fp_method_name) {
                void *it = NULL;
                void *m;
                while ((m = fp_class_get_methods(klass, &it)) != NULL) {
                    const char *mn = fp_method_name(m);
                    int pc = fp_method_param_count ? fp_method_param_count(m) : -1;
                    const char *rt = "void";
                    if (fp_method_return_type && fp_type_name) {
                        void *rtype = fp_method_return_type(m);
                        if (rtype) rt = fp_type_name(rtype) ?: "void";
                    }
                    if (mn)
                        [out appendFormat:@"    %s %s(); // params: %d\n", rt, mn, pc];
                }
            }

            [out appendString:@"}\n"];

            if (ci % 300 == 0 && ci > 0)
                FlushToFile(path, out);
        }
    }

    FlushToFile(path, out);
    NSLog(@"[DUMP] saved to %@", path);

    dispatch_async(dispatch_get_main_queue(), ^{
        UIWindowScene *ws = nil;
        for (UIScene *s in [UIApplication sharedApplication].connectedScenes)
            if ([s isKindOfClass:[UIWindowScene class]]) { ws=(UIWindowScene*)s; break; }
        UIViewController *vc = ws.windows.firstObject.rootViewController;
        while (vc.presentedViewController) vc = vc.presentedViewController;
        UIAlertController *a = [UIAlertController
            alertControllerWithTitle:@"Dump готов"
            message:[NSString stringWithFormat:@"%@", path]
            preferredStyle:UIAlertControllerStyleAlert];
        [a addAction:[UIAlertAction actionWithTitle:@"OK"
            style:UIAlertActionStyleDefault handler:nil]];
        [vc presentViewController:a animated:YES completion:nil];
    });
}

// ═══════════════════════════════════════════════════════════════════════════════
// кнопка дампа
// ═══════════════════════════════════════════════════════════════════════════════
@interface DumpButton : UIView
@property (strong) UIWindow *keepWin;
@end
@implementation DumpButton { CGPoint _off; BOOL _moved; BOOL _dumping; }
-(instancetype)init {
    self=[super initWithFrame:CGRectMake(20,200,80,36)];
    self.backgroundColor=[UIColor colorWithRed:.1f green:.1f blue:.13f alpha:.95f];
    self.layer.cornerRadius=10;
    self.layer.borderColor=[UIColor colorWithRed:.9f green:.4f blue:.1f alpha:.8f].CGColor;
    self.layer.borderWidth=1.5f;
    UILabel *l=[[UILabel alloc] initWithFrame:self.bounds];
    l.tag=1;
    l.text=@"DUMP"; l.textAlignment=NSTextAlignmentCenter;
    l.font=[UIFont systemFontOfSize:13 weight:UIFontWeightBold];
    l.textColor=[UIColor colorWithRed:.9f green:.4f blue:.1f alpha:1];
    [self addSubview:l];
    [self addGestureRecognizer:[[UIPanGestureRecognizer alloc]
        initWithTarget:self action:@selector(pan:)]];
    return self;
}
-(void)pan:(UIPanGestureRecognizer*)g {
    CGPoint loc=[g locationInView:self.superview];
    if (g.state==UIGestureRecognizerStateBegan){
        _moved=NO;
        _off=CGPointMake(loc.x-self.frame.origin.x,loc.y-self.frame.origin.y);
    } else if (g.state==UIGestureRecognizerStateChanged){
        _moved=YES;
        CGRect f=self.frame; f.origin=CGPointMake(loc.x-_off.x,loc.y-_off.y); self.frame=f;
    }
}
-(void)touchesEnded:(NSSet*)t withEvent:(UIEvent*)e {
    if (_moved||_dumping) return;
    _dumping=YES;
    UILabel *l=(UILabel*)[self viewWithTag:1];
    l.text=@"...";
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT,0), ^{
        RunDump();
        dispatch_async(dispatch_get_main_queue(), ^{
            l.text=@"DUMP";
            self->_dumping=NO;
        });
    });
}
@end

// ═══════════════════════════════════════════════════════════════════════════════
// PassthroughWindow
// ═══════════════════════════════════════════════════════════════════════════════
@interface DumpWindow : UIWindow @end
@implementation DumpWindow
-(UIView*)hitTest:(CGPoint)p withEvent:(UIEvent*)e {
    UIView *v=[super hitTest:p withEvent:e];
    if (!v||v==self||v==self.rootViewController.view) return nil;
    return v;
}
@end

// ═══════════════════════════════════════════════════════════════════════════════
// Init
// ═══════════════════════════════════════════════════════════════════════════════
__attribute__((constructor))
static void Init(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(2.0*NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            UIWindowScene *scene=nil;
            for (UIScene *s in [UIApplication sharedApplication].connectedScenes)
                if ([s isKindOfClass:[UIWindowScene class]]){scene=(UIWindowScene*)s;break;}
            DumpWindow *win = scene
                ? [[DumpWindow alloc] initWithWindowScene:scene]
                : [[DumpWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
            win.windowLevel = UIWindowLevelAlert+300;
            win.backgroundColor = [UIColor clearColor];
            UIViewController *vc=[UIViewController new];
            vc.view=[[UIView alloc] initWithFrame:[UIScreen mainScreen].bounds];
            vc.view.backgroundColor=[UIColor clearColor];
            win.rootViewController=vc;
            win.hidden=NO;
            DumpButton *btn=[DumpButton new];
            btn.keepWin=win;
            [vc.view addSubview:btn];
        });
    });
}
