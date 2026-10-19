#import <UIKit/UIKit.h>
#import <dobby.h>
#include <mach/mach.h>
#include <sys/mman.h>

// ═══════════════════════════════════════════════════════════════════════════════
// OFFSETS — CounterFlame / base: 0x112a70000
// ═══════════════════════════════════════════════════════════════════════════════
// PlayerController
#define OFF_PC_VIEW            0x80   // _view  -> PhotonView*
#define OFF_PC_IS_DEATH        0xA8   // bool
// PhotonView
#define OFF_PV_IS_MINE         0x60   // bool <IsMine>k__BackingField
// MonoBehaviour -> Component -> get_transform RVA
#define RVA_GET_TRANSFORM      0x2BAA1E8
// Transform -> get_position RVA
#define RVA_GET_POSITION       0x2BB4894
// Camera::WorldToScreenPoint(Vector3, Eye) RVA
#define RVA_W2S                0x2B73E5C
// Camera::get_main RVA
#define RVA_CAM_MAIN           0x2B741F0
// GameController Singleton _instance  (static field, 0x0 inside class obj)
#define RVA_GC_STATIC          0x1415FA4  // get_Player — не нужен; берём _alivePlayers через Instance
// GameController Instance — это static поле _instance внутри static object
// Singleton`1._instance offset = 0x0 внутри статик объекта класса
#define OFF_GC_ALIVE_PLAYERS   0x118  // List<PlayerController> _alivePlayers
// List<T> internals
#define OFF_LIST_ITEMS         0x10   // backing array _items
#define OFF_LIST_SIZE          0x18   // int _size
#define OFF_ARRAY_DATA         0x20   // first element

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
// Unity function typedefs (ARM64 IL2CPP calling convention)
// ═══════════════════════════════════════════════════════════════════════════════
typedef struct { float x, y, z; } Vec3;
typedef struct { float x, y, z, w; } Vec3s; // WorldToScreenPoint returns 3 floats via sret

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
// GameController Instance helper
// ═══════════════════════════════════════════════════════════════════════════════
// Singleton`1 хранит _instance как static поле (offset 0x0 в static storage).
// Класс GameController — il2cpp_class получаем через любой живой объект или
// через klass pointer (offset 0x0 от объекта). Проще: ищем живой GameController
// через _alivePlayers косвенно или через photonViewList.
// Самый надёжный путь без дополнительных API — пройти photonViewList и найти
// PlayerController по типу. Делаем проще: держим кэш из OnEnable-хука.

static NSMutableArray *gPlayerControllers; // кэш PlayerController*

// Идём через photonViewList (NetworkingClient._photonViewList) offset 0xB0
// NetworkingClient — статик в PhotonNetwork
// PhotonNetwork статика: RVA get_CurrentRoom = 0x24B9FA4 (не нужен)
// Проще и надёжнее — хукаем PlayerController Awake / OnDestroy

typedef void (*fn_pc_awake_t)(uint64_t self, void *method);
static fn_pc_awake_t orig_pc_awake;

typedef void (*fn_pc_destroy_t)(uint64_t self, void *method);
static fn_pc_destroy_t orig_pc_destroy;

static void hook_pc_awake(uint64_t self, void *method) {
    orig_pc_awake(self, method);
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
    orig_pc_destroy(self, method);
}

// ═══════════════════════════════════════════════════════════════════════════════
// w2s wrapper — возвращает CGPoint в screen coords (origin top-left)
// ═══════════════════════════════════════════════════════════════════════════════
static BOOL w2s(uint64_t cam, Vec3 worldPos, CGPoint *out) {
    if (!cam || !fn_w2s) return NO;
    Vec3 sp = fn_w2s(cam, worldPos, 0, nil);
    if (sp.z <= 0.f) return NO;   // за камерой
    CGSize screen = UIScreen.mainScreen.bounds.size;
    out->x = sp.x;
    out->y = screen.height - sp.y; // Unity Y — снизу, UIKit — сверху
    return YES;
}

// ═══════════════════════════════════════════════════════════════════════════════
// ESP overlay view
// ═══════════════════════════════════════════════════════════════════════════════
@interface CrezESPView : UIView
@end

@implementation CrezESPView

- (instancetype)initWithFrame:(CGRect)f {
    self = [super initWithFrame:f];
    self.backgroundColor   = [UIColor clearColor];
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
    CGContextSetStrokeColorWithColor(ctx, [UIColor colorWithRed:.2f green:.8f blue:.2f alpha:.9f].CGColor);

    for (NSValue *v in [gPlayerControllers copy]) {
        uint64_t pc = 0;
        [v getValue:&pc];
        if (!pc) continue;

        // мёртвый игрок — пропуск
        if (ReadBool(pc + OFF_PC_IS_DEATH)) continue;

        // свой — пропуск (IsMine на PhotonView)
        uint64_t pv = ReadU64(pc + OFF_PC_VIEW);
        if (pv && ReadBool(pv + OFF_PV_IS_MINE)) continue;

        // позиция
        uint64_t tfm = fn_get_transform(pc, nil);
        if (!tfm) continue;
        Vec3 pos = fn_get_position(tfm, nil);

        // верх бокса: +1.8м
        Vec3 top = { pos.x, pos.y + 1.8f, pos.z };

        CGPoint scBot, scTop;
        if (!w2s(cam, pos, &scBot)) continue;
        if (!w2s(cam, top, &scTop)) continue;

        CGFloat h = scBot.y - scTop.y;
        if (h < 4.f) continue;
        CGFloat w = h * 0.45f;
        CGFloat x = scBot.x - w * .5f;

        // 2D box
        CGContextStrokeRect(ctx, CGRectMake(x, scTop.y, w, h));

        // маленький хедер-бар сверху (акцент)
        CGContextSetStrokeColorWithColor(ctx,
            [UIColor colorWithRed:.9f green:.2f blue:.1f alpha:.9f].CGColor);
        CGContextMoveToPoint(ctx, x, scTop.y);
        CGContextAddLineToPoint(ctx, x + w, scTop.y);
        CGContextStrokePath(ctx);

        // сброс цвета обратно
        CGContextSetStrokeColorWithColor(ctx,
            [UIColor colorWithRed:.2f green:.8f blue:.2f alpha:.9f].CGColor);
    }
}

@end

// ═══════════════════════════════════════════════════════════════════════════════
// UI — меню
// ═══════════════════════════════════════════════════════════════════════════════
static const CGFloat kMenuW      = 420.f;
static const CGFloat kMenuH      = 380.f;
static const CGFloat kSidebarW   = 130.f;
static const CGFloat kHeaderH    = 44.f;
static const CGFloat kMarginUI   = 12.f;

static UIColor *BG(void)       { return [UIColor colorWithRed:.10f green:.10f blue:.10f alpha:.97f]; }
static UIColor *Sidebar(void)  { return [UIColor colorWithRed:.07f green:.07f blue:.07f alpha:1.f ]; }
static UIColor *Accent(void)   { return [UIColor colorWithRed:.90f green:.20f blue:.10f alpha:1.f ]; }
static UIColor *ActiveBG(void) { return [UIColor colorWithRed:.15f green:.15f blue:.15f alpha:1.f ]; }
static UIColor *TextMain(void) { return [UIColor colorWithWhite:.92f alpha:1.f]; }
static UIColor *TextDim(void)  { return [UIColor colorWithWhite:.45f alpha:1.f]; }
static UIColor *Divider(void)  { return [UIColor colorWithWhite:.2f  alpha:1.f]; }

// ── ESP toggle state ──────────────────────────────────────────────────────────
static BOOL gESPEnabled = NO;
static CrezESPView *gESPView;
static CADisplayLink *gDisplayLink;

static void espTick(id sender) {
    [gESPView setNeedsDisplay];
}

// ── toggle switch ─────────────────────────────────────────────────────────────
@interface CrezToggleSwitch : UIControl
@property (nonatomic, assign) BOOL on;
@property (nonatomic, copy) void (^onChange)(BOOL);
@end
@implementation CrezToggleSwitch {
    UIView *_track, *_thumb;
}
- (instancetype)init {
    self = [super initWithFrame:CGRectMake(0,0,44,24)];
    _track = [[UIView alloc] initWithFrame:self.bounds];
    _track.layer.cornerRadius = 12.f;
    _track.backgroundColor = [UIColor colorWithWhite:.25f alpha:1.f];
    [self addSubview:_track];
    _thumb = [[UIView alloc] initWithFrame:CGRectMake(2,2,20,20)];
    _thumb.layer.cornerRadius = 10.f;
    _thumb.backgroundColor = [UIColor whiteColor];
    [self addSubview:_thumb];
    [self addTarget:self action:@selector(_tap) forControlEvents:UIControlEventTouchUpInside];
    return self;
}
- (void)_tap {
    self.on = !self.on;
    [UIView animateWithDuration:.18f animations:^{
        self->_thumb.frame = self.on
            ? CGRectMake(22,2,20,20)
            : CGRectMake(2,2,20,20);
        self->_track.backgroundColor = self.on ? Accent() : [UIColor colorWithWhite:.25f alpha:1.f];
    }];
    if (self.onChange) self.onChange(self.on);
}
@end

// ── side item ─────────────────────────────────────────────────────────────────
@interface CrezSideItem : UIControl
@property (nonatomic, assign) BOOL   active;
@property (nonatomic, copy)   void  (^action)(void);
@end
@implementation CrezSideItem {
    UIView  *_activeBG, *_bar;
    UILabel *_lbl;
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
    _ico.tintColor = TextDim();
    _ico.contentMode = UIViewContentModeScaleAspectFit;
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

// ── контент вкладок ───────────────────────────────────────────────────────────
@interface CrezContentView : UIView
- (instancetype)initForTab:(NSInteger)tab;
@end
@implementation CrezContentView
- (instancetype)initForTab:(NSInteger)tab {
    self = [super initWithFrame:CGRectZero];
    self.backgroundColor = [UIColor clearColor];

    if (tab == 0) { // Aim — пусто
        UILabel *l = [[UILabel alloc] initWithFrame:CGRectMake(0,0,0,0)];
        l.tag = 99;
        l.text = @"— пусто —";
        l.textColor = [UIColor colorWithWhite:1.f alpha:.15f];
        l.font = [UIFont monospacedSystemFontOfSize:11.f weight:UIFontWeightRegular];
        l.textAlignment = NSTextAlignmentCenter;
        [self addSubview:l];
    } else if (tab == 1) { // Visuals — ESP toggle
        UILabel *lbl = [[UILabel alloc] init];
        lbl.text = @"ESP";
        lbl.textColor = TextMain();
        lbl.font = [UIFont systemFontOfSize:13.f weight:UIFontWeightMedium];
        [self addSubview:lbl];

        CrezToggleSwitch *sw = [[CrezToggleSwitch alloc] init];
        sw.on = gESPEnabled;
        sw.onChange = ^(BOOL on) {
            gESPEnabled = on;
            gESPView.hidden = !on;
            if (on) {
                [gDisplayLink invalidate];
                gDisplayLink = [CADisplayLink displayLinkWithTarget:[NSBlockOperation blockOperationWithBlock:^{}]
                                                           selector:@selector(invoke)];
                gDisplayLink = [CADisplayLink displayLinkWithTarget:gESPView
                                                           selector:@selector(setNeedsDisplay)];
                [gDisplayLink addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
            } else {
                [gDisplayLink invalidate];
                gDisplayLink = nil;
            }
        };
        [self addSubview:sw];

        lbl.tag = 1;
        sw.tag  = 2;
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

// ── основное меню ─────────────────────────────────────────────────────────────
@interface CrezMenu : UIView
@end
@implementation CrezMenu {
    NSMutableArray  *_sideItems;
    NSInteger        _activeIdx;
    CrezContentView *_contentView;
    UIButton        *_closeBtn;
    UIButton        *_showBtn;
    BOOL             _menuHidden;
    CGPoint          _dragStart;
    CGPoint          _originStart;
}

- (instancetype)init {
    CGFloat sw  = UIScreen.mainScreen.bounds.size.width;
    CGFloat mw  = MIN(kMenuW, sw - kMarginUI * 2.f);
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
    CGFloat fw = self.bounds.size.width;
    UIView *hdr = [[UIView alloc] initWithFrame:CGRectMake(0,0,fw,kHeaderH)];
    hdr.backgroundColor = [UIColor colorWithRed:.08f green:.08f blue:.08f alpha:1.f];
    hdr.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    [self addSubview:hdr];

    UILabel *t = [[UILabel alloc] initWithFrame:CGRectMake(14.f,0,fw-60.f,kHeaderH)];
    t.text = @"⬡  CHEAT";
    t.font = [UIFont systemFontOfSize:15.f weight:UIFontWeightBold];
    t.textColor = TextMain();
    t.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    [hdr addSubview:t];

    _closeBtn = [[UIButton alloc] initWithFrame:CGRectMake(fw-36.f,0,36.f,kHeaderH)];
    _closeBtn.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin;
    [_closeBtn setTitle:@"✕" forState:UIControlStateNormal];
    [_closeBtn setTitleColor:TextDim() forState:UIControlStateNormal];
    _closeBtn.titleLabel.font = [UIFont systemFontOfSize:14.f];
    [_closeBtn addTarget:self action:@selector(_toggleHide)
        forControlEvents:UIControlEventTouchUpInside];
    [hdr addSubview:_closeBtn];

    UIView *div = [[UIView alloc] initWithFrame:CGRectMake(0,kHeaderH-1.f,fw,1.f)];
    div.backgroundColor = Divider();
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
    CGFloat fw = self.bounds.size.width;
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
            _originStart = self.frame.origin; break;
        case UIGestureRecognizerStateChanged: {
            CGPoint c = [gr locationInView:sv];
            CGRect f  = self.frame;
            f.origin.x = _originStart.x + (c.x - _dragStart.x);
            f.origin.y = _originStart.y + (c.y - _dragStart.y);
            f.origin.x = MAX(kMarginUI, MIN(f.origin.x, sv.bounds.size.width  - f.size.width  - kMarginUI));
            f.origin.y = MAX(kMarginUI, MIN(f.origin.y, sv.bounds.size.height - f.size.height - kMarginUI));
            self.frame = f; break;
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
            _showBtn.backgroundColor = Accent();
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

    // ESP overlay — под меню
    gESPView = [[CrezESPView alloc] initWithFrame:UIScreen.mainScreen.bounds];
    gESPView.hidden = YES;
    [self.rootViewController.view addSubview:gESPView];

    CrezMenu *menu = [[CrezMenu alloc] init];
    [self.rootViewController.view addSubview:menu];

    [[NSNotificationCenter defaultCenter]
        addObserver:self selector:@selector(_rotate)
               name:UIApplicationDidChangeStatusBarOrientationNotification object:nil];
    return self;
}

- (void)_rotate {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(.15*NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        CGRect wb = UIScreen.mainScreen.bounds;
        self.frame = wb;
        self.rootViewController.view.frame = wb;
        self->gESPView.frame = wb;
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

    // хуки на PlayerController.Awake / OnDestroy
    // RVA: Awake = 0x157AB60, OnDestroy = 0x157C050
    void *awake_ptr   = (void *)(BASE + 0x157AB60);
    void *destroy_ptr = (void *)(BASE + 0x157C050);
    DobbyHook(awake_ptr,   (void *)hook_pc_awake,   (void **)&orig_pc_awake);
    DobbyHook(destroy_ptr, (void *)hook_pc_destroy, (void **)&orig_pc_destroy);

    dispatch_async(dispatch_get_main_queue(), ^{
        gWin = [[CrezMenuWindow alloc] init];
    });
}
