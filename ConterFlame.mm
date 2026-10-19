#import <UIKit/UIKit.h>
#import <objc/runtime.h>

// ─── CONFIG ───────────────────────────────────────────────────────────
static BOOL  cf_esp_enabled = NO;
static BOOL  cf_esp_boxes   = NO;
static BOOL  cf_esp_health  = NO;
static BOOL  cf_esp_names   = NO;
static BOOL  cf_aimbot      = NO;
static float cf_aim_fov     = 5.0f;
static float cf_aim_smooth  = 2.5f;
static BOOL  cf_rcs         = NO;
static float cf_rcs_x       = 100.0f;
static float cf_rcs_y       = 100.0f;

// ─── СТИЛИ ────────────────────────────────────────────────────────────
#define BG_COLOR  [UIColor colorWithRed:.05 green:.05 blue:.07 alpha:.96]
#define HDR_COLOR [UIColor colorWithRed:.09 green:.09 blue:.13 alpha:1]
#define SEC_COLOR [UIColor colorWithRed:.13 green:.13 blue:.18 alpha:1]
#define ACC_COLOR [UIColor colorWithRed:.28 green:.44 blue:.90 alpha:1]

static const CGFloat ROW   = 40;
static const CGFloat SECH  = 26;
static const CGFloat HDRH  = 42;
static const CGFloat MENUW = 255;

// ─── МОДЕЛЬ СТРОКИ ────────────────────────────────────────────────────
typedef NS_ENUM(NSInteger, RowType) { RowSection, RowToggle, RowSlider };

@interface Row : NSObject
@property RowType   type;
@property NSString *label;
@property BOOL     *boolRef;
@property float    *floatRef;
@property float     fmin, fmax;
@end
@implementation Row
+ (instancetype)sec:(NSString *)t {
    Row *r = [Row new]; r.type = RowSection; r.label = t; return r;
}
+ (instancetype)tog:(NSString *)l ref:(BOOL *)b {
    Row *r = [Row new]; r.type = RowToggle; r.label = l; r.boolRef = b; return r;
}
+ (instancetype)sld:(NSString *)l ref:(float *)f min:(float)mn max:(float)mx {
    Row *r = [Row new]; r.type = RowSlider; r.label = l;
    r.floatRef = f; r.fmin = mn; r.fmax = mx; return r;
}
@end

// ─── МЕНЮ ─────────────────────────────────────────────────────────────
@interface CFMenu : UIView <UITableViewDataSource, UITableViewDelegate>
@property BOOL           visible;
@property UITableView   *table;
@property NSArray<Row*> *rows;
@property CGPoint        dragOffset;
- (void)toggleVisible;
@end

@implementation CFMenu

- (instancetype)init {
    self.rows = @[
        [Row sec:@"ESP"],
        [Row tog:@"Enabled"    ref:&cf_esp_enabled],
        [Row tog:@"Boxes"      ref:&cf_esp_boxes],
        [Row tog:@"Health Bar" ref:&cf_esp_health],
        [Row tog:@"Names"      ref:&cf_esp_names],
        [Row sec:@"AIMBOT"],
        [Row tog:@"Enabled"    ref:&cf_aimbot],
        [Row sld:@"FOV"        ref:&cf_aim_fov    min:1  max:30],
        [Row sld:@"Smooth"     ref:&cf_aim_smooth min:1  max:10],
        [Row sec:@"RCS"],
        [Row tog:@"Enabled"    ref:&cf_rcs],
        [Row sld:@"X Axis"     ref:&cf_rcs_x      min:0  max:100],
        [Row sld:@"Y Axis"     ref:&cf_rcs_y      min:0  max:100],
    ];

    CGFloat screenH  = UIScreen.mainScreen.bounds.size.height;
    CGFloat contentH = 0;
    for (Row *r in self.rows) contentH += (r.type == RowSection) ? SECH : ROW;
    CGFloat tableH = MIN(contentH, screenH * 0.68);
    CGFloat menuH  = HDRH + tableH;

    self = [super initWithFrame:CGRectMake(16, 60, MENUW, menuH)];
    if (!self) return nil;
    self.backgroundColor     = BG_COLOR;
    self.layer.cornerRadius  = 8;
    self.layer.masksToBounds = YES;
    self.visible = YES;

    // шапка
    UIView *hdr = [[UIView alloc] initWithFrame:CGRectMake(0, 0, MENUW, HDRH)];
    hdr.backgroundColor = HDR_COLOR;

    UILabel *title = [[UILabel alloc] initWithFrame:CGRectMake(0, 0, MENUW, HDRH)];
    title.text          = @"ConterFlame";
    title.textColor     = [UIColor whiteColor];
    title.textAlignment = NSTextAlignmentCenter;
    title.font          = [UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];
    [hdr addSubview:title];
    [self addSubview:hdr];

    // таблица
    self.table = [[UITableView alloc] initWithFrame:CGRectMake(0, HDRH, MENUW, tableH)
                                              style:UITableViewStylePlain];
    self.table.backgroundColor            = [UIColor clearColor];
    self.table.separatorStyle             = UITableViewCellSeparatorStyleNone;
    self.table.showsVerticalScrollIndicator = YES;
    self.table.dataSource = self;
    self.table.delegate   = self;
    [self addSubview:self.table];

    // перетаскивание
    UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc]
        initWithTarget:self action:@selector(pan:)];
    [hdr addGestureRecognizer:pan];

    return self;
}

- (void)pan:(UIPanGestureRecognizer *)g {
    CGPoint pt = [g locationInView:self.superview];
    if (g.state == UIGestureRecognizerStateBegan)
        self.dragOffset = [g locationInView:self];
    CGRect sb = UIScreen.mainScreen.bounds;
    CGFloat x = MAX(0, MIN(pt.x - self.dragOffset.x, sb.size.width  - MENUW));
    CGFloat y = MAX(0, MIN(pt.y - self.dragOffset.y, sb.size.height - self.bounds.size.height));
    self.frame = CGRectMake(x, y, self.bounds.size.width, self.bounds.size.height);
}

- (void)toggleVisible {
    self.visible = !self.visible;
    [UIView animateWithDuration:.18 animations:^{ self.alpha = self.visible ? 1 : 0; }];
    self.userInteractionEnabled = self.visible;
}

// ─── TableView ────────────────────────────────────────────────────────
- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)s {
    return (NSInteger)self.rows.count;
}
- (CGFloat)tableView:(UITableView *)tv heightForRowAtIndexPath:(NSIndexPath *)ip {
    return self.rows[ip.row].type == RowSection ? SECH : ROW;
}

- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip {
    Row *row = self.rows[ip.row];

    if (row.type == RowSection) {
        UITableViewCell *c = [UITableViewCell new];
        c.backgroundColor     = SEC_COLOR;
        c.selectionStyle      = UITableViewCellSelectionStyleNone;
        c.textLabel.text      = row.label;
        c.textLabel.textColor = [UIColor colorWithWhite:.65 alpha:1];
        c.textLabel.font      = [UIFont systemFontOfSize:11 weight:UIFontWeightSemibold];
        c.indentationLevel    = 0;
        return c;
    }

    if (row.type == RowToggle) {
        UITableViewCell *c = [UITableViewCell new];
        c.backgroundColor     = [UIColor clearColor];
        c.selectionStyle      = UITableViewCellSelectionStyleNone;
        c.textLabel.text      = row.label;
        c.textLabel.textColor = [UIColor whiteColor];
        c.textLabel.font      = [UIFont systemFontOfSize:13];

        UISwitch *sw = [UISwitch new];
        sw.onTintColor = ACC_COLOR;
        sw.transform   = CGAffineTransformMakeScale(.75, .75);
        sw.on          = *(row.boolRef);
        sw.tag         = ip.row;
        [sw addTarget:self action:@selector(toggled:) forControlEvents:UIControlEventValueChanged];
        c.accessoryView = sw;
        return c;
    }

    // RowSlider
    UITableViewCell *c = [UITableViewCell new];
    c.backgroundColor = [UIColor clearColor];
    c.selectionStyle  = UITableViewCellSelectionStyleNone;

    CGFloat cw = MENUW - 24;

    UILabel *lbl = [[UILabel alloc] initWithFrame:CGRectMake(12, 4, cw * .6, 16)];
    lbl.text      = row.label;
    lbl.textColor = [UIColor whiteColor];
    lbl.font      = [UIFont systemFontOfSize:13];

    UILabel *val = [[UILabel alloc] initWithFrame:CGRectMake(12 + cw * .6, 4, cw * .4, 16)];
    val.text          = [NSString stringWithFormat:@"%.2f", *(row.floatRef)];
    val.textColor     = ACC_COLOR;
    val.font          = [UIFont monospacedDigitSystemFontOfSize:11 weight:UIFontWeightRegular];
    val.textAlignment = NSTextAlignmentRight;
    val.tag           = 99;

    UISlider *sl = [[UISlider alloc] initWithFrame:CGRectMake(12, 22, cw, 14)];
    sl.minimumValue          = row.fmin;
    sl.maximumValue          = row.fmax;
    sl.value                 = *(row.floatRef);
    sl.minimumTrackTintColor = ACC_COLOR;
    sl.maximumTrackTintColor = [UIColor colorWithWhite:.3 alpha:1];
    sl.thumbTintColor        = [UIColor whiteColor];
    sl.tag                   = ip.row;
    [sl addTarget:self action:@selector(slid:) forControlEvents:UIControlEventValueChanged];

    [c.contentView addSubview:lbl];
    [c.contentView addSubview:val];
    [c.contentView addSubview:sl];
    return c;
}

- (void)toggled:(UISwitch *)sw {
    *(self.rows[sw.tag].boolRef) = sw.on;
}

- (void)slid:(UISlider *)sl {
    Row *row = self.rows[sl.tag];
    *(row.floatRef) = sl.value;
    UITableViewCell *c = [self.table cellForRowAtIndexPath:[NSIndexPath indexPathForRow:sl.tag inSection:0]];
    UILabel *val = (UILabel *)[c.contentView viewWithTag:99];
    val.text = [NSString stringWithFormat:@"%.2f", sl.value];
}

- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)ip {}

@end

// ─── КНОПКА CF ────────────────────────────────────────────────────────
@interface CFButton : UIButton @end
@implementation CFButton
- (instancetype)init {
    self = [super initWithFrame:CGRectMake(8, 80, 34, 34)];
    [self setTitle:@"CF" forState:UIControlStateNormal];
    [self setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    self.titleLabel.font     = [UIFont systemFontOfSize:12 weight:UIFontWeightBold];
    self.backgroundColor     = HDR_COLOR;
    self.layer.cornerRadius  = 6;
    self.layer.borderWidth   = 1;
    self.layer.borderColor   = ACC_COLOR.CGColor;
    return self;
}
@end

// ─── ИНЖЕКТ ───────────────────────────────────────────────────────────
static CFMenu   *gMenu   = nil;
static CFButton *gButton = nil;

static void InjectIntoWindow(UIWindow *w) {
    if (gMenu) return;
    gMenu   = [CFMenu new];
    gButton = [CFButton new];
    gMenu.layer.zPosition   = 9999;
    gButton.layer.zPosition = 9999;
    [gButton addTarget:gMenu action:@selector(toggleVisible)
      forControlEvents:UIControlEventTouchUpInside];
    [w addSubview:gMenu];
    [w addSubview:gButton];
}

// хук makeKeyAndVisible через objc runtime — без Theos
static IMP orig_makeKeyAndVisible = NULL;
static void hooked_makeKeyAndVisible(UIWindow *self, SEL _cmd) {
    ((void(*)(id,SEL))orig_makeKeyAndVisible)(self, _cmd);
    dispatch_async(dispatch_get_main_queue(), ^{ InjectIntoWindow(self); });
}

__attribute__((constructor))
static void cf_init(void) {
    Method m = class_getInstanceMethod([UIWindow class], @selector(makeKeyAndVisible));
    orig_makeKeyAndVisible = method_getImplementation(m);
    method_setImplementation(m, (IMP)hooked_makeKeyAndVisible);
}
