// CREZ Mod Menu — Tweak.mm
// Theos tweak, iOS 15+, arm64/arm64e
// Dear ImGui 1.90.x header-only assumed in $THEOS/vendor/include/imgui/
// Metal backend inlined below (imgui_impl_metal subset)
// No external assets — font fallback to ImGui default

#import <UIKit/UIKit.h>
#import <Metal/Metal.h>
#import <MetalKit/MetalKit.h>
#import <QuartzCore/QuartzCore.h>
#import <Foundation/Foundation.h>
#import <objc/runtime.h>

// ── ImGui ────────────────────────────────────────────────────────────────────
#define IMGUI_IMPL_METAL_CPP_EXTENSIONS
#include <imgui/imgui.h>
#include <imgui/imgui_internal.h>

// ── Constants ────────────────────────────────────────────────────────────────
static const char* kVersion       = "v1.0.0";
static const ImVec4 kAccent       = {0.424f, 0.361f, 0.906f, 1.f};   // #6C5CE7
static const ImVec4 kBg           = {0.055f, 0.055f, 0.071f, 0.97f}; // #0E0E12
static const ImVec4 kBgLight      = {0.090f, 0.090f, 0.110f, 1.f};
static const ImVec4 kBorder       = {0.165f, 0.165f, 0.208f, 1.f};   // #2A2A35
static const float  kCornerRadius = 18.f;
static const float  kTabWidth     = 120.f;
static const float  kTitleH       = 40.f;
static const float  kTabBarH      = 36.f;
static const float  kMinW         = 320.f;
static const float  kMinH         = 400.f;
static const float  kBtnRadius    = 26.f;

// ── Fake config struct ───────────────────────────────────────────────────────
struct FakeConfig {
    // Rage
    bool  rageEnable      = false;
    float aimbotFov       = 15.f;
    int   aimbotHitbox    = 0;
    bool  autoFire        = false;
    bool  triggerBot      = false;
    float triggerDelay    = 0.05f;
    bool  backtrack       = false;
    int   backtrackTicks  = 12;
    bool  resolver        = false;
    // Legit
    bool  legitEnable     = false;
    float legitSmooth     = 3.f;
    float legitFov        = 5.f;
    bool  rcs             = false;
    float rcsX            = 1.f;
    float rcsY            = 1.f;
    // Visuals
    bool  esp             = false;
    bool  espBox          = true;
    bool  espHealth       = true;
    bool  espName         = false;
    bool  espSkeleton     = false;
    float espColorR       = 0.424f;
    float espColorG       = 0.361f;
    float espColorB       = 0.906f;
    bool  chams           = false;
    bool  bloom           = false;
    float bloomIntensity  = 1.f;
    // Misc
    bool  bhop            = false;
    bool  autoStrafe      = false;
    bool  fakelag         = false;
    int   fakelagTicks    = 8;
    bool  antiAim         = false;
    int   antiAimPitch    = 0;
    // Config
    char  configName[64]  = "default";
    // Scripts
    bool  scriptA         = false;
    bool  scriptB         = false;
} g_cfg;

// ── Keybind state ────────────────────────────────────────────────────────────
struct Keybind { int key = -1; bool waiting = false; };
static Keybind g_keybindAimbot;
static Keybind g_keybindEsp;

// ── Menu state ───────────────────────────────────────────────────────────────
static bool   g_menuOpen      = false;
static bool   g_menuMinimized = false;
static ImVec2 g_menuPos       = {40.f, 80.f};
static ImVec2 g_menuSize      = {560.f, 480.f};
static int    g_activeTab     = 0;
static bool   g_sectionOpen[12] = {true};

// Float button
static ImVec2 g_btnPos        = {20.f, 200.f};
static bool   g_btnDragging   = false;
static ImVec2 g_btnDragOff    = {};

// Animations
static float  g_menuAlpha     = 0.f;
static float  g_menuScale     = 0.85f;
static float  g_tabIndicatorY = 0.f;
static float  g_tabIndicatorYTarget = 0.f;

// Resize handle
static bool   g_resizing      = false;
static ImVec2 g_resizeStart   = {};
static ImVec2 g_resizeSizeStart = {};

// Title drag
static bool   g_titleDragging = false;
static ImVec2 g_titleDragOff  = {};

// Combo open state
static int    g_openCombo     = -1;
static float  g_comboHeight[8]= {};

// Dropdown content (fake)
static const char* kHitboxes[] = {"Head","Neck","Body","Legs"};
static const char* kAntiPitch[] = {"Down","Zero","Up","Spin"};

// NSUserDefaults keys
static NSString* kKeyMenuOpen  = @"crez_menu_open";
static NSString* kKeyMenuX     = @"crez_menu_x";
static NSString* kKeyMenuY     = @"crez_menu_y";
static NSString* kKeyMenuW     = @"crez_menu_w";
static NSString* kKeyMenuH     = @"crez_menu_h";
static NSString* kKeyBtnX      = @"crez_btn_x";
static NSString* kKeyBtnY      = @"crez_btn_y";
static NSString* kKeyTab       = @"crez_tab";

// ── Metal / ImGui plumbing ───────────────────────────────────────────────────
// Minimal Metal ImGui backend — adapted from imgui_impl_metal.mm (MIT)
// We only need what's used here.

#include <simd/simd.h>

typedef struct {
    float position[2];
    float texcoord[2];
    uint8_t color[4];
} MetalVertex;

@interface CrezMetalRenderer : NSObject
@property (nonatomic, strong) id<MTLDevice>              device;
@property (nonatomic, strong) id<MTLCommandQueue>        commandQueue;
@property (nonatomic, strong) id<MTLRenderPipelineState> pipeline;
@property (nonatomic, strong) id<MTLDepthStencilState>   depthStencil;
@property (nonatomic, strong) id<MTLTexture>             fontTexture;
@property (nonatomic, strong) NSMutableArray*            bufferCache;
@property (nonatomic, assign) NSUInteger                 bufferCacheIdx;

- (instancetype)initWithDevice:(id<MTLDevice>)device pixelFormat:(MTLPixelFormat)pf;
- (void)renderDrawData:(ImDrawData*)drawData
         commandBuffer:(id<MTLCommandBuffer>)cb
        renderPassDesc:(MTLRenderPassDescriptor*)rpd;
- (void)createFontTexture;
@end

@implementation CrezMetalRenderer

- (instancetype)initWithDevice:(id<MTLDevice>)device pixelFormat:(MTLPixelFormat)pf {
    if (!(self = [super init])) return nil;
    _device       = device;
    _commandQueue = [device newCommandQueue];
    _bufferCache  = [NSMutableArray array];
    [self buildPipelineWithPixelFormat:pf];
    [self buildDepthStencil];
    return self;
}

- (void)buildDepthStencil {
    MTLDepthStencilDescriptor* d = [MTLDepthStencilDescriptor new];
    d.depthCompareFunction = MTLCompareFunctionAlways;
    d.depthWriteEnabled    = NO;
    _depthStencil = [_device newDepthStencilStateWithDescriptor:d];
}

- (void)buildPipelineWithPixelFormat:(MTLPixelFormat)pf {
    NSString* src = @
    "#include <metal_stdlib>\n"
    "using namespace metal;\n"
    "struct Vert { float2 pos [[attribute(0)]]; float2 uv [[attribute(1)]]; uchar4 col [[attribute(2)]]; };\n"
    "struct Frag { float4 pos [[position]]; float2 uv; float4 col; };\n"
    "vertex Frag vs(Vert in [[stage_in]], constant float4x4& proj [[buffer(1)]]) {\n"
    "    Frag out;\n"
    "    out.pos = proj * float4(in.pos, 0, 1);\n"
    "    out.uv  = in.uv;\n"
    "    out.col = float4(in.col) / 255.0;\n"
    "    return out;\n"
    "}\n"
    "fragment float4 fs(Frag in [[stage_in]], texture2d<float> tex [[texture(0)]]) {\n"
    "    constexpr sampler s(filter::linear);\n"
    "    return in.col * tex.sample(s, in.uv);\n"
    "}\n";

    NSError* err = nil;
    id<MTLLibrary> lib = [_device newLibraryWithSource:src options:nil error:&err];
    if (!lib) { NSLog(@"[CREZ] shader error: %@", err); return; }

    MTLRenderPipelineDescriptor* pd = [MTLRenderPipelineDescriptor new];
    pd.vertexFunction   = [lib newFunctionWithName:@"vs"];
    pd.fragmentFunction = [lib newFunctionWithName:@"fs"];
    pd.colorAttachments[0].pixelFormat                 = pf;
    pd.colorAttachments[0].blendingEnabled             = YES;
    pd.colorAttachments[0].sourceRGBBlendFactor        = MTLBlendFactorSourceAlpha;
    pd.colorAttachments[0].destinationRGBBlendFactor   = MTLBlendFactorOneMinusSourceAlpha;
    pd.colorAttachments[0].sourceAlphaBlendFactor      = MTLBlendFactorOne;
    pd.colorAttachments[0].destinationAlphaBlendFactor = MTLBlendFactorOneMinusSourceAlpha;

    MTLVertexDescriptor* vd = [MTLVertexDescriptor new];
    vd.attributes[0].format      = MTLVertexFormatFloat2;
    vd.attributes[0].offset      = offsetof(MetalVertex, position);
    vd.attributes[0].bufferIndex = 0;
    vd.attributes[1].format      = MTLVertexFormatFloat2;
    vd.attributes[1].offset      = offsetof(MetalVertex, texcoord);
    vd.attributes[1].bufferIndex = 0;
    vd.attributes[2].format      = MTLVertexFormatUChar4;
    vd.attributes[2].offset      = offsetof(MetalVertex, color);
    vd.attributes[2].bufferIndex = 0;
    vd.layouts[0].stride         = sizeof(MetalVertex);
    pd.vertexDescriptor          = vd;

    _pipeline = [_device newRenderPipelineStateWithDescriptor:pd error:&err];
    if (!_pipeline) NSLog(@"[CREZ] pipeline error: %@", err);
}

- (void)createFontTexture {
    ImGuiIO& io = ImGui::GetIO();
    uint8_t* px; int w, h;
    io.Fonts->GetTexDataAsRGBA32(&px, &w, &h);
    MTLTextureDescriptor* td = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatRGBA8Unorm
                                                                                  width:w height:h mipmapped:NO];
    td.usage = MTLTextureUsageShaderRead;
    _fontTexture = [_device newTextureWithDescriptor:td];
    [_fontTexture replaceRegion:MTLRegionMake2D(0,0,w,h) mipmapLevel:0
                      withBytes:px bytesPerRow:(NSUInteger)(w*4)];
    io.Fonts->SetTexID((__bridge void*)_fontTexture);
}

- (id<MTLBuffer>)dequeueBufferWithLength:(NSUInteger)len {
    while (_bufferCacheIdx < _bufferCache.count) {
        id<MTLBuffer> b = _bufferCache[_bufferCacheIdx];
        if (b.length >= len) { _bufferCacheIdx++; return b; }
        _bufferCacheIdx++;
    }
    id<MTLBuffer> b = [_device newBufferWithLength:MAX(len, 4096u)
                                           options:MTLResourceStorageModeShared];
    [_bufferCache addObject:b];
    _bufferCacheIdx++;
    return b;
}

- (void)renderDrawData:(ImDrawData*)dd
         commandBuffer:(id<MTLCommandBuffer>)cb
        renderPassDesc:(MTLRenderPassDescriptor*)rpd {
    if (!dd || dd->CmdListsCount == 0) return;

    _bufferCacheIdx = 0;

    float L = dd->DisplayPos.x;
    float R = dd->DisplayPos.x + dd->DisplaySize.x;
    float T = dd->DisplayPos.y;
    float B = dd->DisplayPos.y + dd->DisplaySize.y;
    float proj[4][4] = {
        { 2.f/(R-L),   0,           0, 0 },
        { 0,           2.f/(T-B),   0, 0 },
        { 0,           0,          -1, 0 },
        { (R+L)/(L-R), (T+B)/(B-T), 0, 1 },
    };

    id<MTLRenderCommandEncoder> enc = [cb renderCommandEncoderWithDescriptor:rpd];
    [enc setRenderPipelineState:_pipeline];
    [enc setDepthStencilState:_depthStencil];
    [enc setVertexBytes:proj length:sizeof(proj) atIndex:1];
    [enc setFragmentTexture:_fontTexture atIndex:0];
    [enc setCullMode:MTLCullModeNone];

    for (int n = 0; n < dd->CmdListsCount; n++) {
        ImDrawList* cl = dd->CmdLists[n];
        NSUInteger vBytes = (NSUInteger)cl->VtxBuffer.Size * sizeof(ImDrawVert);
        NSUInteger iBytes = (NSUInteger)cl->IdxBuffer.Size * sizeof(ImDrawIdx);
        id<MTLBuffer> vb = [self dequeueBufferWithLength:vBytes];
        id<MTLBuffer> ib = [self dequeueBufferWithLength:iBytes];
        memcpy(vb.contents, cl->VtxBuffer.Data, vBytes);
        memcpy(ib.contents, cl->IdxBuffer.Data, iBytes);

        // convert vtx to MetalVertex (ImDrawVert has same layout for pos/uv/col)
        [enc setVertexBuffer:vb offset:0 atIndex:0];

        int idxOffset = 0;
        for (int c = 0; c < cl->CmdBuffer.Size; c++) {
            const ImDrawCmd& cmd = cl->CmdBuffer[c];
            if (cmd.UserCallback) { cmd.UserCallback(cl, &cmd); idxOffset += cmd.ElemCount; continue; }
            MTLScissorRect sr;
            sr.x      = MAX((NSUInteger)cmd.ClipRect.x, 0);
            sr.y      = MAX((NSUInteger)cmd.ClipRect.y, 0);
            sr.width  = (NSUInteger)(cmd.ClipRect.z - cmd.ClipRect.x);
            sr.height = (NSUInteger)(cmd.ClipRect.w - cmd.ClipRect.y);
            [enc setScissorRect:sr];
            if (cmd.TextureId)
                [enc setFragmentTexture:(__bridge id<MTLTexture>)cmd.TextureId atIndex:0];
            else
                [enc setFragmentTexture:_fontTexture atIndex:0];
            [enc drawIndexedPrimitives:MTLPrimitiveTypeTriangle
                            indexCount:cmd.ElemCount
                             indexType:(sizeof(ImDrawIdx)==2?MTLIndexTypeUInt16:MTLIndexTypeUInt32)
                           indexBuffer:ib
                     indexBufferOffset:(NSUInteger)(idxOffset * sizeof(ImDrawIdx))];
            idxOffset += cmd.ElemCount;
        }
    }
    [enc endEncoding];
}
@end

// ── Touch overlay ────────────────────────────────────────────────────────────
@interface CrezTouchView : UIView
@end

@implementation CrezTouchView {
    UITouch* _primaryTouch;
    UITouch* _secondTouch;
    CFTimeInterval _touchStartTime;
    CGPoint        _touchStartPos;
    bool           _longPressFired;
    // Button drag
    bool           _btnTouchActive;
    // snap-anim
    bool           _snapping;
    CGPoint        _snapTarget;
    CGPoint        _snapCurrent;
}

- (instancetype)initWithFrame:(CGRect)f {
    if (!(self = [super initWithFrame:f])) return nil;
    self.multipleTouchEnabled    = YES;
    self.userInteractionEnabled  = YES;
    self.backgroundColor         = [UIColor clearColor];
    return self;
}

- (BOOL)pointInside:(CGPoint)p withEvent:(UIEvent*)e {
    // Eat touches only inside the menu window or the float button
    if (!g_menuOpen || g_menuMinimized) {
        // button only
        float dx = p.x - (g_btnPos.x + kBtnRadius);
        float dy = p.y - (g_btnPos.y + kBtnRadius);
        return sqrtf(dx*dx+dy*dy) <= kBtnRadius + 8.f;
    }
    // menu rect
    CGRect menu = CGRectMake(g_menuPos.x, g_menuPos.y, g_menuSize.x, g_menuSize.y);
    // button
    float dx = p.x - (g_btnPos.x + kBtnRadius);
    float dy = p.y - (g_btnPos.y + kBtnRadius);
    bool inBtn = sqrtf(dx*dx+dy*dy) <= kBtnRadius + 8.f;
    return CGRectContainsPoint(menu, p) || inBtn;
}

- (void)touchesBegan:(NSSet<UITouch*>*)touches withEvent:(UIEvent*)event {
    for (UITouch* t in touches) {
        if (!_primaryTouch) {
            _primaryTouch    = t;
            CGPoint p        = [t locationInView:self];
            _touchStartTime  = CACurrentMediaTime();
            _touchStartPos   = p;
            _longPressFired  = false;
            _btnTouchActive  = false;
            // check button
            float dx = p.x - (g_btnPos.x + kBtnRadius);
            float dy = p.y - (g_btnPos.y + kBtnRadius);
            if (sqrtf(dx*dx+dy*dy) <= kBtnRadius + 8.f) {
                _btnTouchActive = true;
                g_btnDragOff    = {(float)(p.x - g_btnPos.x), (float)(p.y - g_btnPos.y)};
            }
            ImGuiIO& io = ImGui::GetIO();
            io.AddMousePosEvent(p.x, p.y);
            io.AddMouseButtonEvent(0, true);
        } else if (!_secondTouch) {
            _secondTouch = t;
        }
    }
}

- (void)touchesMoved:(NSSet<UITouch*>*)touches withEvent:(UIEvent*)event {
    if ([touches containsObject:_primaryTouch]) {
        CGPoint p    = [_primaryTouch locationInView:self];
        CGPoint prev = [_primaryTouch previousLocationInView:self];
        float dist   = hypotf(p.x - _touchStartPos.x, p.y - _touchStartPos.y);

        if (_btnTouchActive) {
            // drag button
            g_btnPos.x = p.x - g_btnDragOff.x;
            g_btnPos.y = p.y - g_btnDragOff.y;
            // clamp
            CGSize scr = UIScreen.mainScreen.bounds.size;
            g_btnPos.x = MAX(0.f, MIN((float)scr.width  - kBtnRadius*2, g_btnPos.x));
            g_btnPos.y = MAX(0.f, MIN((float)scr.height - kBtnRadius*2, g_btnPos.y));
        } else {
            ImGuiIO& io = ImGui::GetIO();
            // scroll with two fingers
            if (_secondTouch) {
                CGPoint p2 = [_secondTouch locationInView:self];
                CGPoint pv = [_secondTouch previousLocationInView:self];
                io.AddMouseWheelEvent(0.f, (float)(p.y - prev.y + p2.y - pv.y) * 0.04f);
            } else {
                io.AddMousePosEvent(p.x, p.y);
            }
        }
        (void)dist;
    }
}

- (void)touchesEnded:(NSSet<UITouch*>*)touches withEvent:(UIEvent*)event {
    if ([touches containsObject:_primaryTouch]) {
        CGPoint p   = [_primaryTouch locationInView:self];
        CFTimeInterval dur = CACurrentMediaTime() - _touchStartTime;
        float dist  = hypotf(p.x - _touchStartPos.x, p.y - _touchStartPos.y);

        if (_btnTouchActive && dist < 8.f && dur < 0.3) {
            // tap on button
            if (g_menuOpen && !g_menuMinimized && dur > 0.4f) {
                g_menuOpen = false; // long press while open — hide
            } else {
                g_menuOpen      = !g_menuOpen;
                g_menuMinimized = false;
            }
            [self saveState];
        } else if (_btnTouchActive) {
            // snap to nearest edge
            [self snapButton];
        }

        ImGuiIO& io = ImGui::GetIO();
        io.AddMousePosEvent(p.x, p.y);
        io.AddMouseButtonEvent(0, false);
        _primaryTouch   = nil;
        _secondTouch    = nil;
        _btnTouchActive = false;
    }
    if ([touches containsObject:_secondTouch]) {
        _secondTouch = nil;
    }
}

- (void)touchesCancelled:(NSSet<UITouch*>*)touches withEvent:(UIEvent*)event {
    [self touchesEnded:touches withEvent:event];
}

- (void)snapButton {
    CGSize scr = UIScreen.mainScreen.bounds.size;
    float cx   = g_btnPos.x + kBtnRadius;
    float midX = scr.width / 2.f;
    float targetX = (cx < midX) ? 0.f : (scr.width - kBtnRadius*2);
    // animate via a display link tick is not trivial here — we do it in render loop
    // set snap flag
    _snapping   = true;
    _snapTarget = {(float)targetX, g_btnPos.y};
    _snapCurrent= g_btnPos;
    // persist
    [self saveState];
}

- (void)saveState {
    NSUserDefaults* ud = NSUserDefaults.standardUserDefaults;
    [ud setBool:g_menuOpen forKey:kKeyMenuOpen];
    [ud setFloat:g_menuPos.x  forKey:kKeyMenuX];
    [ud setFloat:g_menuPos.y  forKey:kKeyMenuY];
    [ud setFloat:g_menuSize.x forKey:kKeyMenuW];
    [ud setFloat:g_menuSize.y forKey:kKeyMenuH];
    [ud setFloat:g_btnPos.x   forKey:kKeyBtnX];
    [ud setFloat:g_btnPos.y   forKey:kKeyBtnY];
    [ud setInteger:g_activeTab forKey:kKeyTab];
    [ud synchronize];
}

- (BOOL)isSnapping { return _snapping; }
- (CGPoint)snapTarget { return _snapTarget; }
- (void)clearSnap { _snapping = false; }
@end

// ── Render controller ─────────────────────────────────────────────────────────
@interface CrezMenuController : NSObject
+ (instancetype)shared;
- (void)setup;
@end

static CrezMenuController* g_ctrl = nil;

@implementation CrezMenuController {
    UIWindow*            _window;
    CAMetalLayer*        _layer;
    CADisplayLink*       _displayLink;
    CrezMetalRenderer*   _renderer;
    CrezTouchView*       _touchView;
    id<MTLDevice>        _device;
    ImFont*              _fontTitle;
    ImFont*              _fontBody;
}

+ (instancetype)shared {
    static dispatch_once_t t;
    dispatch_once(&t, ^{ g_ctrl = [CrezMenuController new]; });
    return g_ctrl;
}

- (void)setup {
    _device = MTLCreateSystemDefaultDevice();

    // Fullscreen window above everything
    CGRect screen = UIScreen.mainScreen.bounds;
    _window = [[UIWindow alloc] initWithFrame:screen];
    _window.windowLevel      = UIWindowLevelStatusBar + 1000.f;
    _window.backgroundColor  = [UIColor clearColor];
    _window.userInteractionEnabled = YES;
    _window.hidden           = NO;

    UIViewController* vc = [UIViewController new];
    vc.view.backgroundColor  = [UIColor clearColor];
    _window.rootViewController = vc;

    // Metal layer
    _layer                  = [CAMetalLayer layer];
    _layer.device           = _device;
    _layer.pixelFormat      = MTLPixelFormatBGRA8Unorm;
    _layer.framebufferOnly  = NO;
    _layer.frame            = screen;
    _layer.opaque           = NO;
    _layer.backgroundColor  = [UIColor clearColor].CGColor;
    [vc.view.layer addSublayer:_layer];

    // Touch view
    _touchView = [[CrezTouchView alloc] initWithFrame:screen];
    [vc.view addSubview:_touchView];

    // ImGui
    IMGUI_CHECKVERSION();
    ImGui::CreateContext();
    ImGuiIO& io = ImGui::GetIO();
    io.DisplaySize = ImVec2(screen.size.width, screen.size.height);
    io.IniFilename = nullptr;
    io.ConfigFlags |= ImGuiConfigFlags_NoMouseCursorChange;

    // Fonts
    _fontTitle = io.Fonts->AddFontDefault();
    _fontBody  = io.Fonts->AddFontDefault();
    // attempt real fonts
    NSArray<NSString*>* paths = @[
        @"/System/Library/Fonts/HelveticaNeue.ttc",
        @"/System/Library/Fonts/SFNSDisplay.ttf",
        @"/System/Library/Fonts/AppleSystemUIFont.ttf"
    ];
    for (NSString* p in paths) {
        if ([[NSFileManager defaultManager] fileExistsAtPath:p]) {
            ImFont* f1 = io.Fonts->AddFontFromFileTTF(p.UTF8String, 17.f);
            ImFont* f2 = io.Fonts->AddFontFromFileTTF(p.UTF8String, 13.f);
            if (f1 && f2) { _fontTitle = f1; _fontBody = f2; break; }
        }
    }

    // Renderer
    _renderer = [[CrezMetalRenderer alloc] initWithDevice:_device
                                              pixelFormat:MTLPixelFormatBGRA8Unorm];
    [_renderer createFontTexture];

    // Restore state
    [self restoreState];

    // Init animations
    g_tabIndicatorY       = g_activeTab * 42.f;
    g_tabIndicatorYTarget = g_tabIndicatorY;

    // Display link
    _displayLink = [CADisplayLink displayLinkWithTarget:self selector:@selector(render)];
    _displayLink.preferredFramesPerSecond = 60;
    [_displayLink addToRunLoop:NSRunLoop.mainRunLoop forMode:NSRunLoopCommonModes];
}

- (void)restoreState {
    NSUserDefaults* ud = NSUserDefaults.standardUserDefaults;
    if ([ud objectForKey:kKeyMenuOpen]) g_menuOpen = [ud boolForKey:kKeyMenuOpen];
    if ([ud objectForKey:kKeyMenuX])    g_menuPos.x = [ud floatForKey:kKeyMenuX];
    if ([ud objectForKey:kKeyMenuY])    g_menuPos.y = [ud floatForKey:kKeyMenuY];
    if ([ud objectForKey:kKeyMenuW])    g_menuSize.x = [ud floatForKey:kKeyMenuW];
    if ([ud objectForKey:kKeyMenuH])    g_menuSize.y = [ud floatForKey:kKeyMenuH];
    if ([ud objectForKey:kKeyBtnX])     g_btnPos.x = [ud floatForKey:kKeyBtnX];
    if ([ud objectForKey:kKeyBtnY])     g_btnPos.y = [ud floatForKey:kKeyBtnY];
    if ([ud objectForKey:kKeyTab])      g_activeTab = (int)[ud integerForKey:kKeyTab];
}

- (void)render {
    id<CAMetalDrawable> drawable = [_layer nextDrawable];
    if (!drawable) return;

    float dt = (float)_displayLink.duration;

    ImGuiIO& io  = ImGui::GetIO();
    CGRect screen = UIScreen.mainScreen.bounds;
    io.DisplaySize = ImVec2(screen.size.width, screen.size.height);
    io.DeltaTime   = dt > 0.f ? dt : 1.f/60.f;

    // snap animation
    if ([_touchView isSnapping]) {
        CGPoint tgt = [_touchView snapTarget];
        float spd   = 1.f - powf(0.002f, dt);
        g_btnPos.x  += (tgt.x - g_btnPos.x) * spd;
        g_btnPos.y  += (tgt.y - g_btnPos.y) * spd;
        if (fabsf(g_btnPos.x - tgt.x) < 0.5f && fabsf(g_btnPos.y - tgt.y) < 0.5f) {
            g_btnPos.x = tgt.x; g_btnPos.y = tgt.y;
            [_touchView clearSnap];
        }
    }

    // Menu open/close animation
    float targetAlpha = (g_menuOpen && !g_menuMinimized) ? 1.f : 0.f;
    float targetScale = (g_menuOpen && !g_menuMinimized) ? 1.f : 0.85f;
    float spd         = 1.f - powf(0.005f, dt);
    g_menuAlpha += (targetAlpha - g_menuAlpha) * spd;
    g_menuScale += (targetScale - g_menuScale) * spd;

    // Tab indicator lerp
    g_tabIndicatorYTarget = g_activeTab * 42.f;
    g_tabIndicatorY += (g_tabIndicatorYTarget - g_tabIndicatorY) * spd;

    ImGui::NewFrame();
    [self drawUI];
    ImGui::EndFrame();
    ImGui::Render();

    MTLRenderPassDescriptor* rpd = [MTLRenderPassDescriptor new];
    rpd.colorAttachments[0].texture    = drawable.texture;
    rpd.colorAttachments[0].loadAction = MTLLoadActionClear;
    rpd.colorAttachments[0].clearColor = MTLClearColorMake(0,0,0,0);
    rpd.colorAttachments[0].storeAction= MTLStoreActionStore;

    id<MTLCommandBuffer> cb = [_renderer.commandQueue commandBuffer];
    [_renderer renderDrawData:ImGui::GetDrawData() commandBuffer:cb renderPassDesc:rpd];
    [cb presentDrawable:drawable];
    [cb commit];
}

// ─────────────────────────────────────────────────────────────────────────────
// Draw helpers
// ─────────────────────────────────────────────────────────────────────────────

static ImU32 Col(ImVec4 c, float aScale = 1.f) {
    return IM_COL32((int)(c.x*255),(int)(c.y*255),(int)(c.z*255),(int)(c.w*aScale*255));
}

static void DrawRoundedRect(ImDrawList* dl, ImVec2 a, ImVec2 b, ImU32 col,
                            float r, ImDrawFlags flags = ImDrawFlags_RoundCornersAll) {
    dl->AddRectFilled(a, b, col, r, flags);
}

static void DrawShadow(ImDrawList* dl, ImVec2 a, ImVec2 b, float r, float alpha) {
    for (int i = 4; i >= 0; i--) {
        float off = (float)(i * 3);
        ImU32 sc  = IM_COL32(0,0,0,(int)(alpha * (5-i)/5.f * 255.f));
        dl->AddRectFilled({a.x-off, a.y-off}, {b.x+off, b.y+off+off*0.5f}, sc, r+off);
    }
}

static void DrawGradientH(ImDrawList* dl, ImVec2 a, ImVec2 b,
                          ImU32 left, ImU32 right) {
    dl->AddRectFilledMultiColor(a, b, left, right, right, left);
}

// Checkbox
static bool CrezCheckbox(ImDrawList* dl, ImVec2 pos, bool& val, const char* label, float alpha) {
    float sz   = 16.f;
    ImVec2 a   = pos;
    ImVec2 b   = {pos.x+sz, pos.y+sz};
    ImVec2 mpos= ImGui::GetIO().MousePos;
    bool hover = mpos.x>=a.x && mpos.x<=b.x+120.f && mpos.y>=a.y && mpos.y<=b.y;
    bool clicked = hover && ImGui::IsMouseReleased(0);
    if (clicked) val = !val;

    ImU32 bgCol = val ? Col(kAccent, alpha) : IM_COL32(40,40,55,(int)(alpha*255));
    dl->AddRectFilled(a, b, bgCol, 4.f);
    dl->AddRect(a, b, val ? Col(kAccent,alpha) : IM_COL32(80,80,100,(int)(alpha*255)), 4.f);
    if (val) {
        // checkmark
        ImVec2 p1={a.x+3.f, a.y+8.f}, p2={a.x+6.f,a.y+12.f}, p3={a.x+13.f,a.y+4.f};
        dl->AddPolyline((ImVec2[]){p1,p2,p3}, 3, IM_COL32(255,255,255,(int)(alpha*255)), 0, 2.f);
    }
    // glow on active
    if (val)
        dl->AddRect({a.x-1,a.y-1},{b.x+1,b.y+1},
                    IM_COL32((int)(kAccent.x*255),(int)(kAccent.y*255),(int)(kAccent.z*255),
                             (int)(alpha*60)),5.f);

    ImVec2 textPos = {pos.x+sz+8.f, pos.y+1.f};
    dl->AddText(textPos, IM_COL32(200,200,210,(int)(alpha*255)), label);
    return clicked;
}

// Slider float
static void CrezSliderF(ImDrawList* dl, ImVec2 pos, float width, float& val,
                        float mn, float mx, const char* label, float alpha) {
    float h     = 4.f;
    float kh    = 10.f;
    float t     = (val - mn) / (mx - mn);
    float trackY= pos.y + 16.f;
    ImVec2 ta   = {pos.x, trackY};
    ImVec2 tb   = {pos.x+width, trackY+h};
    ImVec2 mpos = ImGui::GetIO().MousePos;
    bool hover  = mpos.x>=ta.x-2.f && mpos.x<=tb.x+2.f && mpos.y>=ta.y-8.f && mpos.y<=tb.y+8.f;
    if (hover && ImGui::IsMouseDown(0)) {
        float nt = (mpos.x - ta.x) / width;
        val = mn + IM_CLAMP(nt, 0.f, 1.f) * (mx - mn);
    }
    // track bg
    dl->AddRectFilled(ta, tb, IM_COL32(40,40,55,(int)(alpha*255)), 2.f);
    // fill
    dl->AddRectFilled(ta, {ta.x + t*(tb.x-ta.x), tb.y}, Col(kAccent, alpha*0.8f), 2.f);
    // knob
    float kx = ta.x + t * width;
    float ky  = trackY + h/2.f;
    dl->AddCircleFilled({kx, ky}, kh/2.f, Col(kAccent, alpha));
    dl->AddCircle({kx,ky}, kh/2.f, IM_COL32(255,255,255,(int)(alpha*80)), 12, 1.f);

    // label + value
    char buf[64]; snprintf(buf, sizeof(buf), "%s  %.2f", label, val);
    dl->AddText(pos, IM_COL32(180,180,195,(int)(alpha*255)), buf);
}

// Slider int
static void CrezSliderI(ImDrawList* dl, ImVec2 pos, float width, int& val,
                        int mn, int mx, const char* label, float alpha) {
    float fv = (float)val;
    CrezSliderF(dl, pos, width, fv, (float)mn, (float)mx, label, alpha);
    val = (int)roundf(fv);
}

// Combo
static bool CrezCombo(ImDrawList* dl, ImVec2 pos, float width, int& sel,
                      const char** items, int count, int id, float alpha) {
    float h    = 26.f;
    ImVec2 a   = pos;
    ImVec2 b   = {pos.x+width, pos.y+h};
    ImVec2 mp  = ImGui::GetIO().MousePos;
    bool hover = mp.x>=a.x && mp.x<=b.x && mp.y>=a.y && mp.y<=b.y;
    if (hover && ImGui::IsMouseReleased(0))
        g_openCombo = (g_openCombo==id) ? -1 : id;

    bool open = g_openCombo == id;
    DrawRoundedRect(dl, a, b, IM_COL32(30,30,42,(int)(alpha*255)), 5.f);
    dl->AddRect(a, b, open ? Col(kAccent,alpha) : IM_COL32(60,60,80,(int)(alpha*255)), 5.f);
    dl->AddText({pos.x+8.f, pos.y+5.f}, IM_COL32(200,200,210,(int)(alpha*255)), items[sel]);
    // arrow
    ImVec2 ac = {b.x-14.f, pos.y+13.f};
    float  aw  = open ? -1.f : 1.f;
    dl->AddTriangleFilled({ac.x-5.f, ac.y-3.f*aw},{ac.x+5.f,ac.y-3.f*aw},{ac.x,ac.y+3.f*aw},
                          IM_COL32(180,180,200,(int)(alpha*255)));

    // animate height
    float targetH = open ? count * 26.f : 0.f;
    float spd     = 1.f - powf(0.005f, ImGui::GetIO().DeltaTime);
    g_comboHeight[id<8?id:0] += (targetH - g_comboHeight[id<8?id:0]) * spd;

    float dh = g_comboHeight[id<8?id:0];
    if (dh > 0.5f) {
        ImVec2 da = {a.x, b.y+2.f};
        ImVec2 db = {b.x, da.y+dh};
        dl->PushClipRect(da, db, true);
        DrawRoundedRect(dl, da, db, IM_COL32(25,25,36,(int)(alpha*255)), 5.f);
        dl->AddRect(da, db, Col(kAccent, alpha*0.4f), 5.f);
        for (int i = 0; i < count; i++) {
            ImVec2 ia = {da.x, da.y + i*26.f};
            ImVec2 ib = {db.x, ia.y+26.f};
            bool iHov = mp.x>=ia.x && mp.x<=ib.x && mp.y>=ia.y && mp.y<=ib.y;
            if (iHov) DrawRoundedRect(dl, ia, ib, Col(kAccent, alpha*0.15f), 3.f);
            if (i == sel)
                dl->AddRectFilled({ia.x, ia.y}, {ia.x+3.f, ib.y}, Col(kAccent, alpha), 2.f);
            dl->AddText({ia.x+10.f, ia.y+5.f}, IM_COL32(200,200,210,(int)(alpha*255)), items[i]);
            if (iHov && ImGui::IsMouseReleased(0)) { sel = i; g_openCombo = -1; }
        }
        dl->PopClipRect();
        return open;
    }
    return open;
}

// Section header
static bool CrezSection(ImDrawList* dl, ImVec2& cursor, float width, const char* title,
                        bool& open, int idx, float alpha) {
    float h = 32.f;
    ImVec2 a = cursor;
    ImVec2 b = {cursor.x+width, cursor.y+h};
    ImVec2 mp = ImGui::GetIO().MousePos;
    bool hover = mp.x>=a.x && mp.x<=b.x && mp.y>=a.y && mp.y<=b.y;
    if (hover && ImGui::IsMouseReleased(0)) open = !open;

    DrawRoundedRect(dl, a, b, IM_COL32(20,20,30,(int)(alpha*255)), 4.f);
    if (hover)
        DrawRoundedRect(dl, a, b, IM_COL32(255,255,255,10), 4.f);

    // arrow (animated rotation via draw)
    float angle = open ? 0.f : -IM_PI/2.f;
    ImVec2 ac   = {a.x+12.f, a.y+h/2.f};
    // simple two-triangle chevron at angle — approximate
    float ax1 = ac.x + cosf(angle)*5.f, ay1 = ac.y + sinf(angle)*5.f;
    float ax2 = ac.x + cosf(angle+IM_PI*0.6f)*5.f, ay2 = ac.y + sinf(angle+IM_PI*0.6f)*5.f;
    float ax3 = ac.x + cosf(angle-IM_PI*0.6f)*5.f, ay3 = ac.y + sinf(angle-IM_PI*0.6f)*5.f;
    dl->AddTriangleFilled({ax1,ay1},{ax2,ay2},{ax3,ay3},
                          Col(kAccent, alpha * 0.8f));

    dl->AddText({a.x+26.f, a.y+8.f}, IM_COL32(220,220,230,(int)(alpha*255)), title);
    dl->AddLine({a.x, b.y-1.f},{b.x,b.y-1.f}, IM_COL32(50,50,65,(int)(alpha*255)));
    cursor.y += h + 4.f;
    return open;
}

// Keybind widget
static void CrezKeybind(ImDrawList* dl, ImVec2 pos, float width, Keybind& kb,
                        const char* label, float alpha) {
    float h   = 22.f;
    ImVec2 ba = {pos.x + width - 90.f, pos.y};
    ImVec2 bb = {pos.x + width, pos.y + h};
    ImVec2 mp = ImGui::GetIO().MousePos;
    bool hov  = mp.x>=ba.x && mp.x<=bb.x && mp.y>=ba.y && mp.y<=bb.y;
    if (hov && ImGui::IsMouseReleased(0)) kb.waiting = !kb.waiting;

    DrawRoundedRect(dl, ba, bb, kb.waiting ? Col(kAccent, alpha*0.3f) : IM_COL32(30,30,42,(int)(alpha*255)), 4.f);
    dl->AddRect(ba, bb, kb.waiting ? Col(kAccent,alpha) : IM_COL32(60,60,80,(int)(alpha*255)), 4.f);

    const char* display = kb.waiting ? "..." : (kb.key<0 ? "None" : "KEY");
    dl->AddText({ba.x+6.f, ba.y+4.f}, IM_COL32(200,200,210,(int)(alpha*255)), display);
    dl->AddText(pos, IM_COL32(180,180,195,(int)(alpha*255)), label);
}

// Color picker (compact row of sliders)
static void CrezColorPicker(ImDrawList* dl, ImVec2 pos, float width,
                            float& r, float& g, float& b, const char* label, float alpha) {
    dl->AddText(pos, IM_COL32(180,180,195,(int)(alpha*255)), label);
    float w3 = (width - 12.f) / 3.f;
    CrezSliderF(dl,{pos.x,          pos.y+16.f},w3,r,0.f,1.f,"R",alpha);
    CrezSliderF(dl,{pos.x+w3+6.f,   pos.y+16.f},w3,g,0.f,1.f,"G",alpha);
    CrezSliderF(dl,{pos.x+w3*2+12.f,pos.y+16.f},w3,b,0.f,1.f,"B",alpha);
    // preview swatch
    ImVec2 sa = {pos.x+width-28.f, pos.y-2.f};
    ImVec2 sb = {sa.x+24.f, sa.y+14.f};
    dl->AddRectFilled(sa, sb, IM_COL32((int)(r*255),(int)(g*255),(int)(b*255),(int)(alpha*255)), 3.f);
    dl->AddRect(sa, sb, IM_COL32(80,80,100,(int)(alpha*255)), 3.f);
}

// ─────────────────────────────────────────────────────────────────────────────
// Tab content renderers
// ─────────────────────────────────────────────────────────────────────────────

- (void)drawTabRage:(ImDrawList*)dl cursor:(ImVec2&)cur w:(float)w alpha:(float)a {
    int si = 0;
    if (CrezSection(dl, cur, w, "Aimbot", g_sectionOpen[si], si, a)) {
        CrezCheckbox(dl, cur, g_cfg.rageEnable, "Enable Rage Aimbot", a); cur.y += 24.f;
        CrezSliderF (dl, cur, w, g_cfg.aimbotFov, 0.f, 180.f, "FOV", a); cur.y += 40.f;
        dl->AddText(cur, IM_COL32(160,160,175,(int)(a*255)), "Hitbox");
        cur.y += 18.f;
        CrezCombo(dl, cur, w, g_cfg.aimbotHitbox, kHitboxes, 4, 0, a);
        cur.y += 32.f;
        CrezCheckbox(dl, cur, g_cfg.autoFire, "Auto Fire", a);     cur.y += 24.f;
        CrezKeybind (dl, cur, w, g_keybindAimbot, "Aimbot Key", a);cur.y += 28.f;
        cur.y += 8.f;
    }
    si++;
    if (CrezSection(dl, cur, w, "Trigger Bot", g_sectionOpen[si], si, a)) {
        CrezCheckbox(dl, cur, g_cfg.triggerBot, "Enable Trigger Bot", a); cur.y += 24.f;
        CrezSliderF (dl, cur, w, g_cfg.triggerDelay, 0.f, 0.5f, "Delay (s)", a); cur.y += 40.f;
        cur.y += 8.f;
    }
    si++;
    if (CrezSection(dl, cur, w, "Anti-Aim", g_sectionOpen[si], si, a)) {
        CrezCheckbox(dl, cur, g_cfg.antiAim, "Enable Anti-Aim", a); cur.y += 24.f;
        dl->AddText(cur, IM_COL32(160,160,175,(int)(a*255)), "Pitch");
        cur.y += 18.f;
        CrezCombo(dl, cur, w, g_cfg.antiAimPitch, kAntiPitch, 4, 1, a);
        cur.y += 32.f;
        CrezCheckbox(dl, cur, g_cfg.resolver, "Resolver", a); cur.y += 24.f;
        cur.y += 8.f;
    }
    si++;
    if (CrezSection(dl, cur, w, "Backtrack", g_sectionOpen[si], si, a)) {
        CrezCheckbox(dl, cur, g_cfg.backtrack, "Enable Backtrack", a); cur.y += 24.f;
        CrezSliderI (dl, cur, w, g_cfg.backtrackTicks, 1, 16, "Ticks", a); cur.y += 40.f;
        cur.y += 8.f;
    }
}

- (void)drawTabLegit:(ImDrawList*)dl cursor:(ImVec2&)cur w:(float)w alpha:(float)a {
    int si = 4;
    if (CrezSection(dl, cur, w, "Legit Aimbot", g_sectionOpen[si], si, a)) {
        CrezCheckbox(dl, cur, g_cfg.legitEnable, "Enable Legit Aimbot", a); cur.y += 24.f;
        CrezSliderF(dl, cur, w, g_cfg.legitFov, 0.f, 30.f, "FOV", a);       cur.y += 40.f;
        CrezSliderF(dl, cur, w, g_cfg.legitSmooth, 1.f, 20.f, "Smooth", a); cur.y += 40.f;
        cur.y += 8.f;
    }
    si++;
    if (CrezSection(dl, cur, w, "RCS", g_sectionOpen[si], si, a)) {
        CrezCheckbox(dl, cur, g_cfg.rcs, "Enable RCS", a); cur.y += 24.f;
        CrezSliderF(dl, cur, w, g_cfg.rcsX, 0.f, 2.f, "X Scale", a); cur.y += 40.f;
        CrezSliderF(dl, cur, w, g_cfg.rcsY, 0.f, 2.f, "Y Scale", a); cur.y += 40.f;
        cur.y += 8.f;
    }
}

- (void)drawTabVisuals:(ImDrawList*)dl cursor:(ImVec2&)cur w:(float)w alpha:(float)a {
    int si = 6;
    if (CrezSection(dl, cur, w, "ESP", g_sectionOpen[si], si, a)) {
        CrezCheckbox(dl, cur, g_cfg.esp, "Enable ESP", a);       cur.y += 24.f;
        CrezCheckbox(dl, cur, g_cfg.espBox, "Box", a);           cur.y += 24.f;
        CrezCheckbox(dl, cur, g_cfg.espHealth, "Health Bar", a); cur.y += 24.f;
        CrezCheckbox(dl, cur, g_cfg.espName, "Names", a);        cur.y += 24.f;
        CrezCheckbox(dl, cur, g_cfg.espSkeleton, "Skeleton", a); cur.y += 24.f;
        CrezColorPicker(dl, cur, w, g_cfg.espColorR, g_cfg.espColorG, g_cfg.espColorB,
                        "ESP Color", a);                         cur.y += 46.f;
        CrezKeybind(dl, cur, w, g_keybindEsp, "ESP Key", a);    cur.y += 28.f;
        cur.y += 8.f;
    }
    si++;
    if (CrezSection(dl, cur, w, "Chams & Bloom", g_sectionOpen[si], si, a)) {
        CrezCheckbox(dl, cur, g_cfg.chams, "Chams", a);              cur.y += 24.f;
        CrezCheckbox(dl, cur, g_cfg.bloom, "Bloom", a);              cur.y += 24.f;
        CrezSliderF(dl, cur, w, g_cfg.bloomIntensity, 0.f, 3.f,
                    "Bloom Intensity", a);                            cur.y += 40.f;
        cur.y += 8.f;
    }
}

- (void)drawTabMisc:(ImDrawList*)dl cursor:(ImVec2&)cur w:(float)w alpha:(float)a {
    int si = 8;
    if (CrezSection(dl, cur, w, "Movement", g_sectionOpen[si], si, a)) {
        CrezCheckbox(dl, cur, g_cfg.bhop, "Bunny Hop", a);           cur.y += 24.f;
        CrezCheckbox(dl, cur, g_cfg.autoStrafe, "Auto Strafe", a);   cur.y += 24.f;
        cur.y += 8.f;
    }
    si++;
    if (CrezSection(dl, cur, w, "Fakelag", g_sectionOpen[si], si, a)) {
        CrezCheckbox(dl, cur, g_cfg.fakelag, "Enable Fakelag", a);   cur.y += 24.f;
        CrezSliderI(dl, cur, w, g_cfg.fakelagTicks, 1, 16, "Ticks", a); cur.y += 40.f;
        cur.y += 8.f;
    }
}

- (void)drawTabConfig:(ImDrawList*)dl cursor:(ImVec2&)cur w:(float)w alpha:(float)a {
    dl->AddText(cur, IM_COL32(160,160,175,(int)(a*255)), "Config Name");
    cur.y += 18.f;
    // Simple text field representation
    ImVec2 fa = cur; ImVec2 fb = {cur.x+w, cur.y+24.f};
    DrawRoundedRect(dl, fa, fb, IM_COL32(25,25,36,(int)(a*255)), 4.f);
    dl->AddRect(fa, fb, IM_COL32(60,60,80,(int)(a*255)), 4.f);
    dl->AddText({fa.x+6.f,fa.y+5.f}, IM_COL32(200,200,210,(int)(a*255)), g_cfg.configName);
    cur.y += 32.f;
    // Save / Load buttons
    float bw = (w-8.f)/2.f;
    auto drawBtn = [&](ImVec2 p, float bw, const char* lbl) {
        ImVec2 a2={p.x,p.y}, b2={p.x+bw,p.y+28.f};
        ImVec2 mp=ImGui::GetIO().MousePos;
        bool hov=mp.x>=a2.x&&mp.x<=b2.x&&mp.y>=a2.y&&mp.y<=b2.y;
        DrawRoundedRect(dl,a2,b2,hov?Col(kAccent,a):IM_COL32(35,35,50,(int)(a*255)),5.f);
        dl->AddRect(a2,b2,Col(kAccent,a*0.6f),5.f);
        // center text
        ImVec2 ts=ImGui::CalcTextSize(lbl);
        dl->AddText({a2.x+(bw-ts.x)/2.f,a2.y+(28.f-ts.y)/2.f},
                    IM_COL32(220,220,235,(int)(a*255)),lbl);
    };
    drawBtn(cur, bw, "Save"); drawBtn({cur.x+bw+8.f,cur.y}, bw, "Load");
    cur.y += 36.f;
    drawBtn(cur, bw, "Reset"); drawBtn({cur.x+bw+8.f,cur.y}, bw, "Delete");
    cur.y += 36.f;
}

- (void)drawTabScripts:(ImDrawList*)dl cursor:(ImVec2&)cur w:(float)w alpha:(float)a {
    int si = 10;
    if (CrezSection(dl, cur, w, "Loaded Scripts", g_sectionOpen[si], si, a)) {
        CrezCheckbox(dl, cur, g_cfg.scriptA, "aim_correction.lua", a);  cur.y += 24.f;
        CrezCheckbox(dl, cur, g_cfg.scriptB, "auto_peek.lua", a);       cur.y += 24.f;
        cur.y += 8.f;
    }
    si++;
    if (CrezSection(dl, cur, w, "Script Log", g_sectionOpen[si], si, a)) {
        const char* lines[] = {
            "[12:41:02] Scripts initialized",
            "[12:41:02] aim_correction loaded",
            "[12:41:03] auto_peek loaded",
        };
        for (auto* l : lines) {
            dl->AddText(cur, IM_COL32(140,140,160,(int)(a*255)), l);
            cur.y += 16.f;
        }
        cur.y += 8.f;
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// Main UI draw
// ─────────────────────────────────────────────────────────────────────────────
- (void)drawUI {
    ImDrawList* bgDL = ImGui::GetBackgroundDrawList();
    float alpha = g_menuAlpha;

    // ── Float button ─────────────────────────────────────────────────────────
    {
        ImVec2 bc = {g_btnPos.x + kBtnRadius, g_btnPos.y + kBtnRadius};
        // glow
        for (int i = 3; i >= 0; i--) {
            float off = (float)(i*4);
            bgDL->AddCircleFilled(bc, kBtnRadius+off,
                IM_COL32((int)(kAccent.x*255),(int)(kAccent.y*255),(int)(kAccent.z*255),
                         (int)(15.f/(i+1))));
        }
        // circle bg gradient
        bgDL->AddCircleFilled(bc, kBtnRadius, IM_COL32(18,18,26,240));
        bgDL->AddCircleFilled(bc, kBtnRadius, Col(kAccent, 0.18f));
        bgDL->AddCircle(bc, kBtnRadius, Col(kAccent, 0.9f), 48, 1.5f);

        // CREZ label
        const char* lbl = g_menuOpen ? "−" : "C";
        ImVec2 ts = ImGui::CalcTextSize(lbl);
        bgDL->AddText({bc.x-ts.x/2.f, bc.y-ts.y/2.f},
                       IM_COL32(220,220,235,240), lbl);
    }

    if (alpha < 0.01f) return;

    // ── Menu shadow ───────────────────────────────────────────────────────────
    // Scale pivot = center of menu
    ImVec2 pivot = {g_menuPos.x + g_menuSize.x/2.f, g_menuPos.y + g_menuSize.y/2.f};
    float sc     = g_menuScale;
    auto  xf     = [&](ImVec2 p) -> ImVec2 {
        return {pivot.x + (p.x - pivot.x)*sc, pivot.y + (p.y - pivot.y)*sc};
    };
    ImVec2 mA = xf(g_menuPos);
    ImVec2 mB = xf({g_menuPos.x+g_menuSize.x, g_menuPos.y+g_menuSize.y});

    DrawShadow(bgDL, mA, mB, kCornerRadius, alpha*0.6f);

    // ── Menu background ───────────────────────────────────────────────────────
    DrawRoundedRect(bgDL, mA, mB, Col(kBg, alpha), kCornerRadius);
    // subtle gradient overlay
    DrawGradientH(bgDL, mA, {mB.x, mA.y + (mB.y-mA.y)*0.4f},
                  IM_COL32(255,255,255,(int)(alpha*8)), IM_COL32(255,255,255,0));
    // border
    bgDL->AddRect(mA, mB, Col(kBorder, alpha*0.8f), kCornerRadius, 0, 1.f);

    // ── Title bar ─────────────────────────────────────────────────────────────
    ImVec2 tbA = mA;
    ImVec2 tbB = {mB.x, mA.y + kTitleH};
    DrawRoundedRect(bgDL, tbA, {tbB.x, tbB.y+kCornerRadius},
                    IM_COL32(16,16,22,(int)(alpha*255)), kCornerRadius,
                    ImDrawFlags_RoundCornersTop);
    bgDL->AddLine({tbA.x+kCornerRadius, tbB.y}, {tbB.x-kCornerRadius, tbB.y},
                  Col(kBorder, alpha*0.6f));

    // "CREZ" gradient letters
    {
        const char* letters = "CREZ";
        float lx = tbA.x + 16.f;
        float ly  = tbA.y + (kTitleH - 18.f)/2.f;
        ImVec4 gradColors[] = {
            {0.7f,0.5f,1.0f,1.f},
            {0.4f,0.6f,1.0f,1.f},
            {0.424f,0.361f,0.906f,1.f},
            {0.3f,0.8f,1.0f,1.f},
        };
        for (int i = 0; i < 4; i++) {
            char c[2] = {letters[i], 0};
            ImVec4 gc = gradColors[i];
            bgDL->AddText({lx, ly},
                IM_COL32((int)(gc.x*255),(int)(gc.y*255),(int)(gc.z*255),(int)(alpha*255)), c);
            lx += ImGui::CalcTextSize(c).x + 1.f;
        }
    }

    // version
    ImVec2 vs = ImGui::CalcTextSize(kVersion);
    bgDL->AddText({tbA.x + (tbB.x-tbA.x)/2.f - vs.x/2.f, tbA.y + (kTitleH-vs.y)/2.f},
                  IM_COL32(100,100,120,(int)(alpha*255)), kVersion);

    // Close button
    float btnSz = 16.f;
    ImVec2 closeC = {tbB.x - 14.f, tbA.y + kTitleH/2.f};
    ImVec2 miniC  = {closeC.x - 24.f, closeC.y};
    ImVec2 mp     = ImGui::GetIO().MousePos;

    auto circleBtn = [&](ImVec2 c, ImVec4 col, float r) -> bool {
        float dist = hypotf(mp.x-c.x, mp.y-c.y);
        bool hov   = dist <= r+2.f;
        bgDL->AddCircleFilled(c, r, IM_COL32((int)(col.x*255),(int)(col.y*255),(int)(col.z*255),
                                              (int)(alpha*(hov?255:200))));
        bgDL->AddCircle(c, r, IM_COL32(255,255,255,(int)(alpha*(hov?60:20))), 16, 1.f);
        return hov && ImGui::IsMouseReleased(0);
    };

    if (circleBtn(closeC, {0.85f,0.2f,0.2f,1.f}, 7.f)) {
        g_menuOpen = false;
        [_touchView saveState];
    }
    // close X
    float d=4.f;
    bgDL->AddLine({closeC.x-d,closeC.y-d},{closeC.x+d,closeC.y+d}, IM_COL32(255,255,255,(int)(alpha*180)),1.5f);
    bgDL->AddLine({closeC.x+d,closeC.y-d},{closeC.x-d,closeC.y+d}, IM_COL32(255,255,255,(int)(alpha*180)),1.5f);

    if (circleBtn(miniC, {0.2f,0.7f,0.2f,1.f}, 7.f)) {
        g_menuMinimized = true;
        [_touchView saveState];
    }
    // minimize line
    bgDL->AddLine({miniC.x-4.f,miniC.y},{miniC.x+4.f,miniC.y}, IM_COL32(255,255,255,(int)(alpha*180)),1.5f);

    // Title drag detection
    {
        bool inTitle = mp.x>=tbA.x && mp.x<=tbB.x && mp.y>=tbA.y && mp.y<=tbB.y;
        if (inTitle && ImGui::IsMouseClicked(0)) {
            g_titleDragging = true;
            g_titleDragOff  = {mp.x - g_menuPos.x, mp.y - g_menuPos.y};
        }
        if (g_titleDragging && ImGui::IsMouseDown(0)) {
            g_menuPos.x = mp.x - g_titleDragOff.x;
            g_menuPos.y = mp.y - g_titleDragOff.y;
            CGSize scr = UIScreen.mainScreen.bounds.size;
            g_menuPos.x = IM_CLAMP(g_menuPos.x, 0.f, (float)scr.width  - g_menuSize.x);
            g_menuPos.y = IM_CLAMP(g_menuPos.y, 0.f, (float)scr.height - g_menuSize.y);
        }
        if (!ImGui::IsMouseDown(0)) {
            if (g_titleDragging) [_touchView saveState];
            g_titleDragging = false;
        }
    }

    // Swipe down on title to minimize
    {
        static float titleSwipeStart = -1.f;
        if (ImGui::IsMouseClicked(0)) {
            bool inT = mp.x>=tbA.x && mp.x<=tbB.x && mp.y>=tbA.y && mp.y<=tbB.y;
            if (inT) titleSwipeStart = mp.y;
        }
        if (!ImGui::IsMouseDown(0) && titleSwipeStart >= 0.f) {
            if (mp.y - titleSwipeStart > 40.f) {
                g_menuMinimized = true;
                [_touchView saveState];
            }
            titleSwipeStart = -1.f;
        }
    }

    // ── Tab bar (left) ────────────────────────────────────────────────────────
    const char* tabNames[] = {"Rage","Legit","Visuals","Misc","Config","Scripts"};
    const int   tabCount   = 6;

    ImVec2 tabA = {mA.x, tbB.y};
    ImVec2 tabB = {mA.x + kTabWidth * sc, mB.y};

    DrawRoundedRect(bgDL, tabA, tabB, IM_COL32(12,12,18,(int)(alpha*255)), kCornerRadius,
                    ImDrawFlags_RoundCornersBottomLeft);

    // Tab indicator sliding pill
    float tabItemH = 42.f * sc;
    float indicX   = tabA.x;
    float indicY   = tabA.y + g_tabIndicatorY * sc;
    bgDL->AddRectFilled({indicX, indicY}, {indicX + kTabWidth*sc, indicY + tabItemH},
                        IM_COL32(255,255,255,(int)(alpha*10)));
    // accent bar
    bgDL->AddRectFilled({indicX, indicY}, {indicX + 3.f, indicY + tabItemH},
                        Col(kAccent, alpha));

    for (int i = 0; i < tabCount; i++) {
        float ty   = tabA.y + i * tabItemH;
        ImVec2 ia  = {tabA.x, ty};
        ImVec2 ib  = {tabB.x, ty + tabItemH};
        bool hov   = mp.x>=ia.x && mp.x<=ib.x && mp.y>=ia.y && mp.y<=ib.y;
        bool active= (i == g_activeTab);

        if (hov && !active)
            bgDL->AddRectFilled(ia, ib, IM_COL32(255,255,255,(int)(alpha*6)));

        // icon placeholder (simple geometric)
        float ix = ia.x + 14.f;
        float iy = ia.y + tabItemH/2.f;
        ImU32 iconCol = active ? Col(kAccent, alpha) : IM_COL32(100,100,120,(int)(alpha*255));
        bgDL->AddCircle({ix, iy}, 5.f, iconCol, 8, 1.2f);

        // label
        ImU32 textCol = active ? IM_COL32(220,220,235,(int)(alpha*255))
                                : IM_COL32(120,120,140,(int)(alpha*255));
        bgDL->AddText({ia.x+26.f, ia.y+(tabItemH-ImGui::CalcTextSize(tabNames[i]).y)/2.f},
                       textCol, tabNames[i]);

        if (hov && ImGui::IsMouseReleased(0) && !active) {
            g_activeTab = i;
            g_tabIndicatorYTarget = i * 42.f;
            [_touchView saveState];
        }
    }

    // tab divider line
    bgDL->AddLine({tabB.x, tabA.y+4.f}, {tabB.x, tabB.y-4.f},
                  Col(kBorder, alpha*0.5f));

    // ── Content area ──────────────────────────────────────────────────────────
    ImVec2 contentA = {tabB.x + 2.f, tbB.y};
    ImVec2 contentB = mB;
    float contentW  = (contentB.x - contentA.x - 16.f);
    float contentH  = contentB.y - contentA.y;

    // Clip to content
    bgDL->PushClipRect({contentA.x, contentA.y+2.f}, {contentB.x-2.f, contentB.y-2.f}, true);

    // Tab title + gradient separator
    ImVec2 cur = {contentA.x + 10.f, contentA.y + 10.f};
    {
        ImVec2 ts = ImGui::CalcTextSize(tabNames[g_activeTab]);
        bgDL->AddText(cur, IM_COL32(230,230,240,(int)(alpha*255)), tabNames[g_activeTab]);
        cur.y += ts.y + 2.f;
        // gradient separator
        DrawGradientH(bgDL, cur, {cur.x + contentW, cur.y + 2.f},
                      Col(kAccent, alpha), IM_COL32(0,0,0,0));
        cur.y += 10.f;
    }

    // Scrollable content
    static float scrollOffset[6] = {};
    cur.y -= scrollOffset[g_activeTab];
    float startY = cur.y;

    switch (g_activeTab) {
        case 0: [self drawTabRage:bgDL    cursor:cur w:contentW alpha:alpha]; break;
        case 1: [self drawTabLegit:bgDL   cursor:cur w:contentW alpha:alpha]; break;
        case 2: [self drawTabVisuals:bgDL cursor:cur w:contentW alpha:alpha]; break;
        case 3: [self drawTabMisc:bgDL    cursor:cur w:contentW alpha:alpha]; break;
        case 4: [self drawTabConfig:bgDL  cursor:cur w:contentW alpha:alpha]; break;
        case 5: [self drawTabScripts:bgDL cursor:cur w:contentW alpha:alpha]; break;
    }

    // Scroll wheel
    float contentTotalH = (cur.y + scrollOffset[g_activeTab]) - startY - scrollOffset[g_activeTab];
    float& sc2 = scrollOffset[g_activeTab];
    float wheel = ImGui::GetIO().MouseWheel;
    if (wheel != 0.f) {
        sc2 -= wheel * 20.f;
        sc2  = IM_CLAMP(sc2, 0.f, MAX(0.f, contentTotalH - contentH + 40.f));
    }

    // Scrollbar
    if (contentTotalH > contentH) {
        float ratio  = contentH / contentTotalH;
        float sbH    = contentH * ratio;
        float sbOffY = sc2 / contentTotalH * contentH;
        ImVec2 sbA = {contentB.x - 5.f, contentA.y + sbOffY};
        ImVec2 sbB = {contentB.x - 2.f, sbA.y + sbH};
        bgDL->AddRectFilled(sbA, sbB, Col(kAccent, alpha*0.5f), 2.f);
    }

    bgDL->PopClipRect();

    // ── Resize handle ─────────────────────────────────────────────────────────
    {
        ImVec2 rhA = {mB.x-16.f, mB.y-16.f};
        ImVec2 rhB = mB;
        bool hov   = mp.x>=rhA.x && mp.x<=rhB.x && mp.y>=rhA.y && mp.y<=rhB.y;
        bgDL->AddRectFilled(rhA, rhB, IM_COL32(0,0,0,0)); // invisible hit area

        // 3 diagonal dots visual
        for (int d = 0; d < 3; d++) {
            float f = (float)(d+1) * 4.f;
            bgDL->AddLine({mB.x-f, mB.y-2.f}, {mB.x-2.f, mB.y-f},
                          Col(kBorder, alpha * (hov ? 1.f : 0.5f)), 1.5f);
        }

        if (hov && ImGui::IsMouseClicked(0)) {
            g_resizing       = true;
            g_resizeStart    = mp;
            g_resizeSizeStart= g_menuSize;
        }
        if (g_resizing) {
            if (ImGui::IsMouseDown(0)) {
                g_menuSize.x = g_resizeSizeStart.x + (mp.x - g_resizeStart.x) / sc;
                g_menuSize.y = g_resizeSizeStart.y + (mp.y - g_resizeStart.y) / sc;
                CGSize scr = UIScreen.mainScreen.bounds.size;
                g_menuSize.x = IM_CLAMP(g_menuSize.x, kMinW, (float)scr.width  - g_menuPos.x);
                g_menuSize.y = IM_CLAMP(g_menuSize.y, kMinH, (float)scr.height - g_menuPos.y);
            } else {
                g_resizing = false;
                [_touchView saveState];
            }
        }
    }

    // ── FPS counter ───────────────────────────────────────────────────────────
    {
        static float fpsSmooth = 60.f;
        float fps = ImGui::GetIO().Framerate;
        fpsSmooth += (fps - fpsSmooth) * 0.05f;
        char fpsStr[24]; snprintf(fpsStr, sizeof(fpsStr), "%.0f fps", fpsSmooth);
        ImVec2 fs = ImGui::CalcTextSize(fpsStr);
        bgDL->AddText({mB.x - fs.x - 8.f, mB.y - fs.y - 5.f},
                       IM_COL32(80,80,100,(int)(alpha*200)), fpsStr);
    }
}

@end

// ── Logos inject ─────────────────────────────────────────────────────────────
%ctor {
    NSLog(@"[CREZ] loading");
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        [[CrezMenuController shared] setup];
        NSLog(@"[CREZ] menu initialized");
    });
}
