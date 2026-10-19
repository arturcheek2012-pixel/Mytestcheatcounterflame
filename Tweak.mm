#import <UIKit/UIKit.h>
#include <mach/mach.h>
#include <sys/mman.h>
#include <libkern/OSCacheControl.h>

// ═══════════════════════════════════════════════════════════════════════════════
// OFFSETS — CounterFlame / base: 0x112a70000
// ═══════════════════════════════════════════════════════════════════════════════
#define OFF_PC_VIEW            0x80
#define OFF_PC_IS_DEATH        0xA8
#define OFF_PV_IS_MINE         0x60
#define RVA_GET_TRANSFORM      0x2BAA1E8
#define RVA_GET_POSITION       0x2BB4894
#define RVA_W2S                0x2B73E5C
#define RVA_CAM_MAIN           0x2B741F0
#define OFF_GC_ALIVE_PLAYERS   0x118
#define OFF_LIST_ITEMS         0x10
#define OFF_LIST_SIZE          0x18
#define OFF_ARRAY_DATA         0x20
#define BASE                   0x112a70000ULL

// ═══════════════════════════════════════════════════════════════════════════════
// memory helpers
// ═══════════════════════════════════════════════════════════════════════════════
static inline uint64_t ReadU64(uint64_t addr) {
    if (addr < 0x1000) return 0;
    return *(volatile uint64_t *)addr;
}
static inline uint32_t ReadU32(uint64_t addr) {
    if (addr < 0x1000) return 0;
    return *(volatile uint32_t *)addr;
}
static inline bool ReadBool(uint64_t addr) {
    if (addr < 0x1000) return false;
    return *(volatile uint8_t *)addr != 0;
}

// ═══════════════════════════════════════════════════════════════════════════════
// inline hook — без dobby, с проверкой PC-relative инструкций
// ═══════════════════════════════════════════════════════════════════════════════
// ARM64: инструкции которые PC-relative и нельзя копировать в трамплин:
// ADRP  : top 8 bits = 0x90..0x97 (маска 0x9F000000)
// B/BL  : top 8 bits = 0x14..0x17 (B) / 0x94..0x97 (BL)
// CBZ/CBNZ, TBZ/TBNZ тоже PC-relative
// STP/SUB SP — безопасны, их копировать можно

static bool _is_pc_relative(uint32_t insn) {
    uint32_t op = insn & 0x9F000000;
    if (op == 0x90000000) return true; // ADRP
    op = insn & 0xFC000000;
    if (op == 0x14000000) return true; // B
    if (op == 0x94000000) return true; // BL
    op = insn & 0x7E000000;
    if (op == 0x34000000) return true; // CBZ/CBNZ
    op = insn & 0x7E000000;
    if (op == 0x36000000) return true; // TBZ/TBNZ
    return false;
}

static bool _install_hook(void *target, void *replacement, void **orig_out) {
    uintptr_t t    = (uintptr_t)target;
    uintptr_t page = t & ~(uintptr_t)(PAGE_SIZE - 1);

    // проверяем первые 4 инструкции (16 байт) на PC-relative
    uint32_t *insns = (uint32_t *)target;
    for (int i = 0; i < 4; i++) {
        if (_is_pc_relative(insns[i])) {
            // небезопасно копировать — orig будет вызывать target напрямую
            // (хук не устанавливаем, возвращаем false)
            return false;
        }
    }

    mprotect((void *)page, PAGE_SIZE * 2, PROT_READ | PROT_WRITE | PROT_EXEC);

    // трамплин для orig: 16 байт оригинала + абс прыжок обратно
    uint8_t *stub = (uint8_t *)mmap(NULL, PAGE_SIZE,
                                    PROT_READ | PROT_WRITE | PROT_EXEC,
                                    MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
    memcpy(stub, target, 16);
    uintptr_t resume = t + 16;
    *(uint32_t *)(stub + 16) = 0x58000050; // LDR X16, #8
    *(uint32_t *)(stub + 20) = 0xD61F0200; // BR X16
    *(uint64_t *)(stub + 24) = resume;
    sys_icache_invalidate(stub, 32);
    *orig_out = stub;

    // патч цели
    uint8_t patch[16];
    *(uint32_t *)(patch + 0) = 0x58000050; // LDR X16, #8
    *(uint32_t *)(patch + 4) = 0xD61F0200; // BR X16
    *(uint64_t *)(patch + 8) = (uint64_t)replacement;
    memcpy(target, patch, 16);
    sys_icache_invalidate(target, 16);
    mprotect((void *)page, PAGE_SIZE * 2, PROT_READ | PROT_EXEC);
    return true;
}

// ═══════════════════════════════════════════════════════════════════════════════
// Unity function typedefs
// ═══════════════════════════════════════════════════════════════════════════════
typedef struct { float x, y, z; } Vec3;

typedef uint64_t (*fn_get_transform_t)(uint64_t component, void *method);
typedef Vec3     (*fn_get_position_t) (uint64_t transform,  void *method);
typedef Vec3     (*fn_w2s_t)          (uint64_t camera, Vec3 worldPos, int32_t eye, void *method);
typedef uint64_t (*fn_cam_main_t)     (void *method);

static fn_get_transform_t  fn_get_transform;
static fn_get_position_t   fn_get_position;
static fn_w2s_t            fn_w2s;
static fn_cam_main_t       fn_cam_main;

static void _resolveRVAs(void) {
    fn_get_transform = (fn_get_transform_t)(BASE + RVA_GET_TRANSFORM);
    fn_get_position  = (fn_get_position_t) (BASE + RVA_GET_POSITION);
    fn_w2s           = (fn_w2s_t)          (BASE + RVA_W2S);
    fn_cam_main      = (fn_cam_main_t)     (BASE + RVA_CAM_MAIN);
}

// ═══════════════════════════════════════════════════════════════════════════════
// PlayerController cache via hooks
// ═══════════════════════════════════════════════════════════════════════════════
static NSMutableArray *gPlayerControllers;

typedef void (*fn_pc_awake_t)  (uint64_t self, void *method);
typedef void (*fn_pc_destroy_t)(uint64_t self, void *method);

static fn_pc_awake_t   orig_pc_awake   = NULL;
static fn_pc_destroy_t orig_pc_destroy = NULL;

// адреса оригиналов для прямого вызова если трамплин не встал
static void *raw_pc_awake   = NULL;
static void *raw_pc_destroy = NULL;

static void hook_pc_awake(uint64_t self, void *method) {
    // зовём оригинал: либо через трамплин, либо напрямую по RVA+16
    if (orig_pc_awake)
        orig_pc_awake(self, method);
    else if (raw_pc_awake)
        ((fn_pc_awake_t)((uintptr_t)raw_pc_awake + 16))(self, method);

    dispatch_async(dispatch_get_main_queue(), ^{
        NSValue *v = [NSValue valueWithBytes:&self objCType:@encode(uint64_t)];
        if (![gPlayerControllers containsObject:v])
            [gPlayerControllers addObject:v];
    });
}

static void hook_pc_destroy(uint64_t self, void *method) {
    dispatch_async(dispatch_get_main_queue(), ^{
        NSValue *v = [NSValue valueWithBytes:&self objCType:@encode(uint64_t)];
        [gPlayerControllers removeObject:v];
    });
    if (orig_pc_destroy)
        orig_pc_destroy(self, method);
    else if (raw_pc_destroy)
        ((fn_pc_destroy_t)((uintptr_t)raw_pc_destroy + 16))(self, method);
}

// ═══════════════════════════════════════════════════════════════════════════════
// w2s
// ═══════════════════════════════════════════════════════════════════════════════
static BOOL w2s(uint64_t cam, Vec3 worldPos, CGPoint *out) {
    if (!cam || !fn_w2s) return NO;
    Vec3 sp = fn_w2s(cam, worldPos, 0, nil);
    if (sp.z <= 0.f) return NO;
    CGSize screen = UIScreen.mainScreen.bounds.size;
    out->x = sp.x;
    out->y = screen.height - sp.y;
    return YES;
}

// ═══════════════════════════════════════════════════════════════════════════════
// ESP overlay
// ═══════════════════════════════════════════════════════════════════════════════
@interface CrezESPView : UIView
@end

@implementation CrezESPView

- (instancetype)initWithFrame:(CGRect)f {
    self = [super initWithFrame:f];
    self.backgroundColor        = [UIColor clearColor];
    self.userInteractionEnabled = NO;
    return self;
}

- (void)drawRect:(CGRect)r {
    CGContextRef ctx = UIGraphicsGetCurrentContext();
    if (!ctx) return;
    if (!fn_cam_main || !fn_get_transform || !fn_get_position || !fn_w2s) return;

    uint64_t cam = fn_cam_main(nil);
    if (!cam) return;

    CGContextSetLineWidth(ctx, 1.5f);
    CGContextSetStrokeColorWithColor(ctx,
        [UIColor colorWithRed:.2f green:.8f blue:.2f alpha:.9f].CGColor);

    for (NSValue *v in [gPlayerControllers copy]) {
        uint64_t pc = 0;
        [v getValue:&pc];
        if (!pc) continue;

        if (ReadBool(pc + OFF_PC_IS_DEATH)) continue;

        uint64_t pv = ReadU64(pc + OFF_PC_VIEW);
        if (pv && ReadBool(pv + OFF_PV_IS_MINE)) continue;

        uint64_t tfm = fn_get_transform(pc, nil);
        if (!tfm) continue;
        Vec3 pos = fn_get_position(tfm, nil);

        Vec3 top = { pos.x, pos.y + 1.8f, pos.z };

        CGPoint scBot, scTop;
        if (!w2s(cam, pos, &scBot)) continue;
        if (!w2s(cam, top, &scTop)) continue;

        CGFloat h = scBot.y - scTop.y;
        if (h < 4.f) continue;
        CGFloat w = h * 0.45f;
        CGFloat x = scBot.x - w * .5f;

        CGContextStrokeRect(ctx, CGRectMake(x, scTop.y, w, h));

        CGContextSetStrokeColorWithColor(ctx,
            [UIColor colorWithRed:.9f green:.2f blue:.1f alpha:.9f].CGColor);
        CGContextMoveToPoint(ctx, x, scTop.y);
        CGContextAddLineToPoint(ctx, x + w, scTop.y);
        CGContextStrokePath(ctx);

        CGContextSetStrokeColorWithColor(ctx,
            [UIColor colorWithRed:.2f green:.8f blue:.2f alpha:.9f].CGColor);
    }
}

@end

// ═══════════════════════════════════════════════════════════════════════════════
// UI constants & colors
// ═══════════════════════════════════════════════════════════════════════════════
static const CGFloat kMenuW    = 420.f;
static const CGFloat kMenuH    = 380.f;
static const CGFloat kSidebarW = 130.f;
static const CGFloat kHeaderH  = 44.f;
static const CGFloat kMarginUI = 12.f;

static UIColor *BG(void)       { return [UIColor colorWithRed:.10f green:.10f blue:.10f alpha:.97f]; }
static UIColor *Sidebar(void)  { return [UIColor colorWithRed:.07f green:.07f blue:.07f alpha:1.f ]; }
static UIColor *Accent(void)   { return [UIColor colorWithRed:.90f green:.20f blue:.10f alpha:1.f ]; }
static UIColor *ActiveBG(void) { return [UIColor colorWithRed:.15f green:.15f blue:.15f alpha:1.f ]; }
static UIColor *TextMain(void) { return [UIColor colorWithWhite:.92f alpha:1.f]; }
static UIColor *TextDim(void)  { return [UIColor colorWithWhite:.45f alpha:1.f]; }
static UIColor *Divider(void)  { return [UIColor colorWithWhite:.2f  alpha:1.f]; }

// ═══════════════════════════════════════════════════════════════════════════════
// ESP state
// ═══════════════════════════════════════════════════════════════════════════════
static BOOL           gESPEnabled = NO;
static CrezESPView   *gESPView;
static CADisplayLink *gDisplayLink;

// ═══════════════════════════════════════════════════════════════════════════════
// Toggle switch
// ═══════════════════════════════════════════════════════════════════════════════
@interface CrezToggleSwitch : UIControl
@property (nonatomic, assign) BOOL on;
@property (nonatomic, copy)   void (^onChange)(BOOL);
@end

@implementation CrezToggleSwitch {
    UIView *_track, *_thumb;
}
- (instancetype)init {
    self = [super initWithFrame:CGRectMake(0,0,44,24)];
    _track = [[UIView alloc] initWithFrame:self.bounds];
    _track.layer.cornerRadius = 12.f;
    _track.backgroundColor    = [UIColor colorWithWhite:.25f alpha:1.f];
    [self addSubview:_track];
    _thumb = [[UIView alloc] initWithFrame:CGRectMake(2,2,20,20)];
    _thumb.layer.cornerRadius = 10.f;
    _thumb.backgroundColor    = [UIColor whiteColor];
    [self addSubview:_thumb];
    [self addTarget:self action:@selector(_tap) forControlEvents:UIControlEventTouchUpInside];
    return self;
}
- (void)_tap {
    self.on = !self.on;
    [UIView animateWithDuration:.18f animations:^{
        self->_thumb.frame = self.on ? CGRectMake(22,2,20,20) : CGRectMake(2,2,20,20);
        self->_track.backgroundColor = self.on ? Accent() : [UIColor colorWithWhite:.25f alpha:1.f];
    }];
    if (self.onChange) self.onChange(self.on);
}
@end

// ═══════════════════════════════════════════════════════════════════════════════
// Sidebar item
// ═══════════════════════════════════════════════════════════════════════════════
@interface CrezSideItem : UIControl
@property (nonatomic, assign) BOOL   active;
@property (nonatomic, copy)   void  (^action)(void);
@end

@implementation CrezSideItem {
    UIView      *_activeBG, *_bar;
    UILabel     *_lbl;
    UIImageView *_ico;
}
- (instancetype)initWithTitle:(NSString *)t icon:(NSString *)sf {
    self = [super initWithFrame:CGRectZero];
    _activeBG = [[UIView alloc] init];
    _activeBG.backgroundColor = ActiveBG();
    _activeBG.hidden = YES;
    [self addSubview:_activeBG];
    _bar = [[UIView alloc] init];
    _bar.backgroundColor = Accent();
    _bar.hidden = YES;
    [self addSubview:_bar];
    _ico = [[UIImageView alloc] init];
    if (@available(iOS 13,*)) { _ico.image = [UIImage systemImageNamed:sf]; }
    _ico.tintColor    = TextDim();
    _ico.contentMode  = UIViewContentModeScaleAspectFit;
    [self addSubview:_ico];
    _lbl = [[UILabel alloc] init];
    _lbl.text      = t;
    _lbl.font      = [UIFont systemFontOfSize:13.f weight:UIFontWeightMedium];
    _lbl.textColor = TextDim();
    [self addSubview:_lbl];
    [self addTarget:self action:@selector(_tap) forControlEvents:UIControlEventTouchUpInside];
    return self;
}
- (void)_tap { if (self.action) self.action(); }
- (void)setActive:(BOOL)v {
    _active = v;
    _activeBG.hidden = !v; _bar.hidden = !v;
    _lbl.textColor = v ? TextMain() : TextDim();
    _ico.tintColor = v ? Accent()   : TextDim();
}
- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat w = self.bounds.size.width, h = self.bounds.size.height;
    _activeBG.frame = CGRectMake(0,0,w,h);
    _bar.frame      = CGRectMake(0,6.f,3.f,h-12.f);
    _ico.frame      = CGRectMake(14.f,(h-16.f)*.5f,16.f,16.f);
    _lbl.frame      = CGRectMake(36.f,0,w-40.f,h);
}
@end

// ═══════════════════════════════════════════════════════════════════════════════
// Content view (tabs)
// ═══════════════════════════════════════════════════════════════════════════════
@interface CrezContentView : UIView
- (instancetype)initForTab:(NSInteger)tab;
@end

@implementation CrezContentView
- (instancetype)initForTab:(NSInteger)tab {
    self = [super initWithFrame:CGRectZero];
    self.backgroundColor = [UIColor clearColor];

    if (tab == 0) {
        UILabel *l  = [[UILabel alloc] init];
        l.tag       = 99;
        l.text      = @"— пусто —";
        l.textColor = [UIColor colorWithWhite:1.f alpha:.15f];
        l.font      = [UIFont monospacedSystemFontOfSize:11.f weight:UIFontWeightRegular];
        l.textAlignment = NSTextAlignmentCenter;
        [self addSubview:l];
    } else if (tab == 1) {
        UILabel *lbl  = [[UILabel alloc] init];
        lbl.text      = @"ESP";
        lbl.textColor = TextMain();
        lbl.font      = [UIFont systemFontOfSize:13.f weight:UIFontWeightMedium];
        lbl.tag       = 1;
        [self addSubview:lbl];

        CrezToggleSwitch *sw = [[CrezToggleSwitch alloc] init];
        sw.on  = gESPEnabled;
        sw.tag = 2;
        sw.onChange = ^(BOOL on) {
            gESPEnabled    = on;
            gESPView.hidden = !on;
            if (on) {
                [gDisplayLink invalidate];
                gDisplayLink = [CADisplayLink displayLinkWithTarget:gESPView
                                                           selector:@selector(setNeedsDisplay)];
                [gDisplayLink addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
            } else {
                [gDisplayLink invalidate];
                gDisplayLink = nil;
            }
        };
        [self addSubview:sw];
    }
    return self;
}
- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat w = self.bounds.size.width, h = self.bounds.size.height;
    UILabel *placeholder = [self viewWithTag:99];
    if (placeholder) { placeholder.frame = CGRectMake(0,0,w,h); return; }
    UILabel *lbl = [self viewWithTag:1];
    UIView  *sw  = [self viewWithTag:2];
    if (lbl && sw) {
        CGFloat cy = h * .5f;
        lbl.frame = CGRectMake(16.f, cy-12.f, 80.f, 24.f);
        sw.frame  = CGRectMake(16.f + 80.f + 12.f, cy-12.f, 44.f, 24.f);
    }
}
@end

// ═══════════════════════════════════════════════════════════════════════════════
// Main menu
// ═══════════════════════════════════════════════════════════════════════════════
@interface CrezMenu : UIView
@end

@implementation CrezMenu {
    NSMutableArray  *_sideItems;
    NSInteger        _activeIdx;
    CrezContentView *_contentView;
    UIButton        *_showBtn;
    BOOL             _menuHidden;
    CGPoint          _dragStart;
    CGPoint          _originStart;
}

- (instancetype)init {
    CGFloat sw = UIScreen.mainScreen.bounds.size.width;
    CGFloat mw = MIN(kMenuW, sw - kMarginUI * 2.f);
    self = [super initWithFrame:CGRectMake(kMarginUI, 80.f, mw, kMenuH)];
    self.backgroundColor    = BG();
    self.layer.cornerRadius = 4.f;
    self.layer.borderColor  = [UIColor colorWithWhite:.18f alpha:1.f].CGColor;
    self.layer.borderWidth  = 1.f;
    self.clipsToBounds      = YES;
    [self _buildHeader];
    [self _buildSidebar];
    [self _buildContent:0];
    UIPanGestureRecognizer *pan =
        [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(_pan:)];
    [self addGestureRecognizer:pan];
    return self;
}

- (void)_buildHeader {
    CGFloat fw  = self.bounds.size.width;
    UIView *hdr = [[UIView alloc] initWithFrame:CGRectMake(0,0,fw,kHeaderH)];
    hdr.backgroundColor    = [UIColor colorWithRed:.08f green:.08f blue:.08f alpha:1.f];
    hdr.autoresizingMask   = UIViewAutoresizingFlexibleWidth;
    [self addSubview:hdr];

    UILabel *t = [[UILabel alloc] initWithFrame:CGRectMake(14.f,0,fw-60.f,kHeaderH)];
    t.text            = @"⬡  CHEAT";
    t.font            = [UIFont systemFontOfSize:15.f weight:UIFontWeightBold];
    t.textColor       = TextMain();
    t.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    [hdr addSubview:t];

    UIButton *closeBtn = [[UIButton alloc] initWithFrame:CGRectMake(fw-36.f,0,36.f,kHeaderH)];
    closeBtn.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin;
    [closeBtn setTitle:@"✕" forState:UIControlStateNormal];
    [closeBtn setTitleColor:TextDim() forState:UIControlStateNormal];
    closeBtn.titleLabel.font = [UIFont systemFontOfSize:14.f];
    [closeBtn addTarget:self action:@selector(_toggleHide)
       forControlEvents:UIControlEventTouchUpInside];
    [hdr addSubview:closeBtn];

    UIView *div = [[UIView alloc] initWithFrame:CGRectMake(0,kHeaderH-1.f,fw,1.f)];
    div.backgroundColor  = Divider();
    div.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    [hdr addSubview:div];
}

- (void)_buildSidebar {
    UIView *sb = [[UIView alloc] initWithFrame:
                  CGRectMake(0, kHeaderH, kSidebarW, kMenuH-kHeaderH)];
    sb.backgroundColor = Sidebar();
    [self addSubview:sb];

    UIView *div = [[UIView alloc] initWithFrame:
                   CGRectMake(kSidebarW-1.f, kHeaderH, 1.f, kMenuH-kHeaderH)];
    div.backgroundColor = Divider();
    [self addSubview:div];

    NSArray *cats = @[@[@"Aim",@"scope"], @[@"Visuals",@"eye"]];
    _sideItems = [NSMutableArray new];
    for (NSInteger i = 0; i < (NSInteger)cats.count; i++) {
        CrezSideItem *item = [[CrezSideItem alloc] initWithTitle:cats[i][0] icon:cats[i][1]];
        item.frame = CGRectMake(0, i*44.f, kSidebarW, 44.f);
        NSInteger idx = i;
        __weak CrezMenu *ws = self;
        item.action = ^{ [ws _selectCat:idx]; };
        [sb addSubview:item];
        [_sideItems addObject:item];
    }
    ((CrezSideItem *)_sideItems[0]).active = YES;
    _activeIdx = 0;
}

- (void)_buildContent:(NSInteger)idx {
    [_contentView removeFromSuperview];
    CGFloat fw   = self.bounds.size.width;
    _contentView = [[CrezContentView alloc] initForTab:idx];
    _contentView.frame = CGRectMake(kSidebarW, kHeaderH,
                                    fw - kSidebarW, kMenuH - kHeaderH);
    [self addSubview:_contentView];
}

- (void)_selectCat:(NSInteger)idx {
    _activeIdx = idx;
    for (NSInteger i = 0; i < (NSInteger)_sideItems.count; i++)
        ((CrezSideItem *)_sideItems[i]).active = (i == idx);
    [self _buildContent:idx];
}

- (void)_pan:(UIPanGestureRecognizer *)gr {
    UIView *sv = self.superview; if (!sv) return;
    switch (gr.state) {
        case UIGestureRecognizerStateBegan:
            _dragStart   = [gr locationInView:sv];
            _originStart = self.frame.origin;
            break;
        case UIGestureRecognizerStateChanged: {
            CGPoint c = [gr locationInView:sv];
            CGRect  f = self.frame;
            f.origin.x = _originStart.x + (c.x - _dragStart.x);
            f.origin.y = _originStart.y + (c.y - _dragStart.y);
            f.origin.x = MAX(kMarginUI, MIN(f.origin.x, sv.bounds.size.width  - f.size.width  - kMarginUI));
            f.origin.y = MAX(kMarginUI, MIN(f.origin.y, sv.bounds.size.height - f.size.height - kMarginUI));
            self.frame = f;
            break;
        }
        default: break;
    }
}

- (void)_toggleHide {
    _menuHidden = !_menuHidden;
    [UIView animateWithDuration:.2f animations:^{
        self.alpha     = self->_menuHidden ? 0.f : 1.f;
        self.transform = self->_menuHidden
            ? CGAffineTransformMakeScale(.85f,.85f) : CGAffineTransformIdentity;
    }];
    UIView *sv = self.superview;
    if (_menuHidden) {
        if (!_showBtn) {
            _showBtn = [[UIButton alloc] initWithFrame:CGRectMake(0,0,36.f,36.f)];
            _showBtn.backgroundColor    = Accent();
            _showBtn.layer.cornerRadius = 4.f;
            [_showBtn setTitle:@"⬡" forState:UIControlStateNormal];
            [_showBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
            _showBtn.titleLabel.font = [UIFont systemFontOfSize:16.f];
            __weak CrezMenu *ws = self;
            [_showBtn addTarget:ws action:@selector(_toggleHide)
                forControlEvents:UIControlEventTouchUpInside];
        }
        _showBtn.frame = CGRectMake(self.frame.origin.x, self.frame.origin.y, 36.f, 36.f);
        [sv addSubview:_showBtn];
    } else {
        [_showBtn removeFromSuperview];
    }
}
@end

// ═══════════════════════════════════════════════════════════════════════════════
// Window
// ═══════════════════════════════════════════════════════════════════════════════
@interface CrezMenuWindow : UIWindow
@end

@implementation CrezMenuWindow

- (instancetype)init {
    self = [super initWithFrame:UIScreen.mainScreen.bounds];
    self.windowLevel        = UIWindowLevelAlert + 100;
    self.backgroundColor    = [UIColor clearColor];
    self.rootViewController = [UIViewController new];
    self.rootViewController.view.backgroundColor = [UIColor clearColor];
    self.hidden = NO;

    gESPView = [[CrezESPView alloc] initWithFrame:UIScreen.mainScreen.bounds];
    gESPView.hidden = YES;
    [self.rootViewController.view addSubview:gESPView];

    CrezMenu *menu = [[CrezMenu alloc] init];
    [self.rootViewController.view addSubview:menu];

    [[NSNotificationCenter defaultCenter]
        addObserver:self selector:@selector(_rotate)
               name:UIWindowDidBecomeVisibleNotification object:nil];
    return self;
}

- (void)_rotate {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(.15*NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        CGRect wb = UIScreen.mainScreen.bounds;
        self.frame = wb;
        self.rootViewController.view.frame = wb;
        gESPView.frame = wb;
    });
}

- (UIView *)hitTest:(CGPoint)p withEvent:(UIEvent *)e {
    UIView *hit = [super hitTest:p withEvent:e];
    return (hit == self || hit == self.rootViewController.view || hit == gESPView) ? nil : hit;
}
@end

// ═══════════════════════════════════════════════════════════════════════════════
// Init
// ═══════════════════════════════════════════════════════════════════════════════
static CrezMenuWindow *gWin;

__attribute__((constructor)) static void _init(void) {
    gPlayerControllers = [NSMutableArray new];
    _resolveRVAs();

    raw_pc_awake   = (void *)(BASE + 0x157AB60);
    raw_pc_destroy = (void *)(BASE + 0x157C050);
    _install_hook(raw_pc_awake,   (void *)hook_pc_awake,   (void **)&orig_pc_awake);
    _install_hook(raw_pc_destroy, (void *)hook_pc_destroy, (void **)&orig_pc_destroy);

    dispatch_async(dispatch_get_main_queue(), ^{
        gWin = [[CrezMenuWindow alloc] init];
    });
}
