#import <UIKit/UIKit.h>

// ── config ────────────────────────────────────────────────────────────────────
static const CGFloat kMenuW      = 300.f;
static const CGFloat kMenuH      = 340.f;
static const CGFloat kSidebarW   = 110.f;
static const CGFloat kHeaderH    = 44.f;
static const CGFloat kMargin     = 12.f;

static UIColor *BG(void)         { return [UIColor colorWithRed:.10f green:.10f blue:.10f alpha:.97f]; }
static UIColor *Sidebar(void)    { return [UIColor colorWithRed:.07f green:.07f blue:.07f alpha:1.f ]; }
static UIColor *Accent(void)     { return [UIColor colorWithRed:.90f green:.20f blue:.10f alpha:1.f ]; }
static UIColor *ActiveItem(void) { return [UIColor colorWithRed:.15f green:.15f blue:.15f alpha:1.f ]; }
static UIColor *TextMain(void)   { return [UIColor colorWithWhite:.92f alpha:1.f]; }
static UIColor *TextDim(void)    { return [UIColor colorWithWhite:.45f alpha:1.f]; }
static UIColor *Divider(void)    { return [UIColor colorWithWhite:.2f  alpha:1.f]; }
// ─────────────────────────────────────────────────────────────────────────────

@interface CrezMenuWindow : UIWindow
@property (nonatomic, strong) UIView *menuView;
@end

// ── строка каталога ───────────────────────────────────────────────────────────
@interface CrezSideItem : UIControl
@property (nonatomic, assign) BOOL   active;
@property (nonatomic, copy)   NSString *title;
@property (nonatomic, copy)   void (^action)(void);
@end

@implementation CrezSideItem {
    UIView  *_activeLine;
    UILabel *_lbl;
}
- (instancetype)initWithTitle:(NSString *)t icon:(NSString *)icon {
    self = [super initWithFrame:CGRectZero];
    self.title = t;

    // фон активного
    _activeLine = [[UIView alloc] init];
    _activeLine.backgroundColor = ActiveItem();
    _activeLine.hidden = YES;
    [self addSubview:_activeLine];

    // иконка (SF Symbol или просто пустое место)
    UIImageView *ico = [[UIImageView alloc] init];
    if (@available(iOS 13, *)) {
        UIImage *img = [UIImage systemImageNamed:icon];
        ico.image = img;
        ico.tintColor = TextDim();
    }
    ico.contentMode = UIViewContentModeScaleAspectFit;
    ico.tag = 10;
    [self addSubview:ico];

    _lbl = [[UILabel alloc] init];
    _lbl.text      = t;
    _lbl.font      = [UIFont systemFontOfSize:13.f weight:UIFontWeightMedium];
    _lbl.textColor = TextDim();
    [self addSubview:_lbl];

    // красная левая черта активного
    UIView *bar = [[UIView alloc] init];
    bar.backgroundColor = Accent();
    bar.tag = 20;
    bar.hidden = YES;
    [self addSubview:bar];

    [self addTarget:self action:@selector(_tap) forControlEvents:UIControlEventTouchUpInside];
    return self;
}
- (void)_tap { if (self.action) self.action(); }
- (void)setActive:(BOOL)v {
    _active = v;
    _activeLine.hidden = !v;
    _lbl.textColor     = v ? TextMain() : TextDim();
    [self viewWithTag:10].tintColor = v ? Accent() : TextDim();
    [self viewWithTag:20].hidden    = !v;
}
- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat w = self.bounds.size.width, h = self.bounds.size.height;
    _activeLine.frame          = CGRectMake(0, 0, w, h);
    [self viewWithTag:20].frame = CGRectMake(0, 6.f, 3.f, h - 12.f);
    [self viewWithTag:10].frame = CGRectMake(14.f, (h-16.f)*.5f, 16.f, 16.f);
    _lbl.frame                 = CGRectMake(36.f, 0, w - 40.f, h);
}
@end

// ── основное меню ─────────────────────────────────────────────────────────────
@interface CrezMenu : UIView
- (instancetype)init;
@end

@implementation CrezMenu {
    NSMutableArray *_sideItems;
    NSInteger       _activeIdx;
    UIView         *_contentArea;
    UILabel        *_contentLabel;
    // drag
    CGPoint         _dragStart;
    CGPoint         _originStart;
    BOOL            _hidden;
    UIButton        *_closeBtn;
    UIButton        *_showBtn;  // маленькая кнопка когда скрыто
}

- (instancetype)init {
    self = [super initWithFrame:CGRectMake(kMargin, 80.f, kMenuW, kMenuH)];
    if (!self) return nil;

    self.backgroundColor    = BG();
    self.layer.cornerRadius = 4.f;
    self.layer.borderColor  = [UIColor colorWithWhite:.18f alpha:1.f].CGColor;
    self.layer.borderWidth  = 1.f;
    self.clipsToBounds      = YES;

    [self _buildHeader];
    [self _buildSidebar];
    [self _buildContent];

    UIPanGestureRecognizer *pan =
        [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(_pan:)];
    [self addGestureRecognizer:pan];

    return self;
}

// ── header ────────────────────────────────────────────────────────────────────
- (void)_buildHeader {
    UIView *header = [[UIView alloc] initWithFrame:CGRectMake(0, 0, kMenuW, kHeaderH)];
    header.backgroundColor = [UIColor colorWithRed:.08f green:.08f blue:.08f alpha:1.f];
    [self addSubview:header];

    // логотип / название
    UILabel *title = [[UILabel alloc] initWithFrame:CGRectMake(14.f, 0, 180.f, kHeaderH)];
    title.text      = @"⬡  CHEAT";
    title.font      = [UIFont systemFontOfSize:15.f weight:UIFontWeightBold];
    title.textColor = TextMain();
    [header addSubview:title];

    // кнопка закрыть
    _closeBtn = [[UIButton alloc] initWithFrame:CGRectMake(kMenuW - 36.f, 0, 36.f, kHeaderH)];
    [_closeBtn setTitle:@"✕" forState:UIControlStateNormal];
    [_closeBtn setTitleColor:TextDim() forState:UIControlStateNormal];
    _closeBtn.titleLabel.font = [UIFont systemFontOfSize:14.f];
    [_closeBtn addTarget:self action:@selector(_toggleHide)
        forControlEvents:UIControlEventTouchUpInside];
    [header addSubview:_closeBtn];

    // разделитель под header
    UIView *div = [[UIView alloc] initWithFrame:CGRectMake(0, kHeaderH - 1.f, kMenuW, 1.f)];
    div.backgroundColor = Divider();
    [header addSubview:div];
}

// ── sidebar ───────────────────────────────────────────────────────────────────
static NSArray *kCats(void) {
    // {title, sfSymbol}
    return @[
        @[@"Aim",     @"scope"],
        @[@"Visuals", @"eye"],
    ];
}

- (void)_buildSidebar {
    UIView *sidebar = [[UIView alloc] initWithFrame:
                       CGRectMake(0, kHeaderH, kSidebarW, kMenuH - kHeaderH)];
    sidebar.backgroundColor = Sidebar();
    [self addSubview:sidebar];

    // вертикальный разделитель
    UIView *div = [[UIView alloc] initWithFrame:
                   CGRectMake(kSidebarW - 1.f, kHeaderH, 1.f, kMenuH - kHeaderH)];
    div.backgroundColor = Divider();
    [self addSubview:div];

    NSArray *cats = kCats();
    CGFloat itemH = 44.f;
    _sideItems = [NSMutableArray new];

    for (NSInteger i = 0; i < (NSInteger)cats.count; i++) {
        NSArray *cat = cats[i];
        CrezSideItem *item = [[CrezSideItem alloc] initWithTitle:cat[0] icon:cat[1]];
        item.frame = CGRectMake(0, i * itemH, kSidebarW, itemH);
        NSInteger idx = i;
        __weak CrezMenu *ws = self;
        item.action = ^{ [ws _selectCat:idx]; };
        [sidebar addSubview:item];
        [_sideItems addObject:item];
    }
    ((CrezSideItem *)_sideItems[0]).active = YES;
    _activeIdx = 0;
}

// ── content ───────────────────────────────────────────────────────────────────
- (void)_buildContent {
    CGFloat cx = kSidebarW, cw = kMenuW - kSidebarW, ch = kMenuH - kHeaderH;
    _contentArea = [[UIView alloc] initWithFrame:CGRectMake(cx, kHeaderH, cw, ch)];
    _contentArea.backgroundColor = [UIColor clearColor];
    [self addSubview:_contentArea];

    _contentLabel = [[UILabel alloc] initWithFrame:_contentArea.bounds];
    _contentLabel.text          = @"— пусто —";
    _contentLabel.textAlignment = NSTextAlignmentCenter;
    _contentLabel.font          = [UIFont monospacedSystemFontOfSize:12.f weight:UIFontWeightRegular];
    _contentLabel.textColor     = [UIColor colorWithWhite:1.f alpha:.15f];
    [_contentArea addSubview:_contentLabel];
}

- (void)_selectCat:(NSInteger)idx {
    _activeIdx = idx;
    for (NSInteger i = 0; i < (NSInteger)_sideItems.count; i++)
        ((CrezSideItem *)_sideItems[i]).active = (i == idx);
    // здесь будет подгрузка контента под каталог
}

// ── drag ──────────────────────────────────────────────────────────────────────
- (void)_pan:(UIPanGestureRecognizer *)gr {
    UIView *sv = self.superview;
    if (!sv) return;
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
            CGFloat maxX = sv.bounds.size.width  - f.size.width  - kMargin;
            CGFloat maxY = sv.bounds.size.height - f.size.height - kMargin;
            f.origin.x = MAX(kMargin, MIN(f.origin.x, maxX));
            f.origin.y = MAX(kMargin, MIN(f.origin.y, maxY));
            self.frame = f;
            break;
        }
        default: break;
    }
}

// ── hide / show ───────────────────────────────────────────────────────────────
- (void)_toggleHide {
    _hidden = !_hidden;
    [UIView animateWithDuration:.2f animations:^{
        self.alpha  = self->_hidden ? 0.f : 1.f;
        self.transform = self->_hidden
            ? CGAffineTransformMakeScale(.85f, .85f)
            : CGAffineTransformIdentity;
    }];
    if (self.superview) {
        UIView *sv = self.superview;
        if (_hidden) {
            // показываем маленькую кнопку открыть
            if (!_showBtn) {
                _showBtn = [[UIButton alloc] initWithFrame:CGRectMake(kMargin, 80.f, 36.f, 36.f)];
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
}

@end

// ── window ────────────────────────────────────────────────────────────────────
@implementation CrezMenuWindow

- (instancetype)init {
    self = [super initWithFrame:UIScreen.mainScreen.bounds];
    if (!self) return nil;
    self.windowLevel        = UIWindowLevelAlert + 100;
    self.backgroundColor    = [UIColor clearColor];
    self.rootViewController = [UIViewController new];
    self.rootViewController.view.backgroundColor = [UIColor clearColor];
    self.hidden = NO;

    _menuView = [[CrezMenu alloc] init];
    [self.rootViewController.view addSubview:_menuView];

    [[NSNotificationCenter defaultCenter]
        addObserver:self
           selector:@selector(_rotate)
               name:UIApplicationDidChangeStatusBarOrientationNotification
             object:nil];
    return self;
}

- (void)_rotate {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(.15f * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        CGRect wb = UIScreen.mainScreen.bounds;
        self.frame = wb;
        self.rootViewController.view.frame = wb;
        // clamp позицию
        CGRect mf = self->_menuView.frame;
        mf.origin.x = MAX(kMargin, MIN(mf.origin.x, wb.size.width  - mf.size.width  - kMargin));
        mf.origin.y = MAX(kMargin, MIN(mf.origin.y, wb.size.height - mf.size.height - kMargin));
        self->_menuView.frame = mf;
    });
}

- (UIView *)hitTest:(CGPoint)p withEvent:(UIEvent *)e {
    UIView *hit = [super hitTest:p withEvent:e];
    return (hit == self || hit == self.rootViewController.view) ? nil : hit;
}

@end

// ── init ──────────────────────────────────────────────────────────────────────
static CrezMenuWindow *gWin;

__attribute__((constructor)) static void _init(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        gWin = [[CrezMenuWindow alloc] init];
    });
}
