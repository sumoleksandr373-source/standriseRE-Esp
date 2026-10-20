// StandRise Rework — ESP Tweak
// Unity il2cpp, Photon Multiplayer
// Inject: Dopamine / Unc0ver + CydiaSubstrate
// Build: make package FINALPACKAGE=1

#import <UIKit/UIKit.h>
#import <substrate.h>
#include <mach-o/dyld.h>
#include <stdint.h>
#include <string.h>
#include "Offsets.h"
#import "Overlay.h"

// ============================================================
// helpers
// ============================================================

static uintptr_t s_base = 0;

static uintptr_t GameBase(void) {
    if (s_base) return s_base;
    for (uint32_t i = 0; i < _dyld_image_count(); i++) {
        const char *name = _dyld_get_image_name(i);
        if (name && strstr(name, "GameAssembly")) {
            s_base = (uintptr_t)_dyld_get_image_vmaddr_slide(i) + 0x100000000ULL;
            return s_base;
        }
    }
    return 0;
}

// typed read helper — returns 0/nullptr on bad ptr
template<typename T>
static T Rd(uintptr_t addr) {
    if (!addr) return T{};
    return *reinterpret_cast<T *>(addr);
}

// ============================================================
// il2cpp method typedefs (grabbed via RVA hooks or direct call)
// ============================================================

typedef void *(*t_Transform_get_position)(void *transform, void *method);
typedef void *(*t_Camera_WorldToScreen)(void *cam, float x, float y, float z, void *method);

// We call these directly — no hook needed
static t_Transform_get_position  fn_Transform_get_position  = nullptr;
static t_Camera_WorldToScreen    fn_Camera_WorldToScreen    = nullptr;

// Unity Vector3 layout
struct Vec3 { float x, y, z; };

// il2cpp HashSet<T> — slots array at +0x10, count at +0x0C
// Each slot: Il2CppObject header (0x10) + T* at +0x10
// HashSet slot stride = 0x18 (header + key + hashcode)
//   key at slot+0x10 for reference types

// ============================================================
// safe il2cpp call wrappers
// ============================================================

static Vec3 GetPosition(void *transform) {
    if (!transform || !fn_Transform_get_position) return {};
    // il2cpp internal struct return — injected variant writes into ret by ref
    // use _Injected version signature: (transform, out Vec3 ret, method)
    // RVA_Transform_get_position is the plain getter which returns struct in x0:x1 on arm64
    // safe to call directly: first arg = this, method param = nullptr (cached)
    typedef Vec3 (*t_pos)(void *, void *);
    Vec3 v = reinterpret_cast<t_pos>(fn_Transform_get_position)(transform, nullptr);
    return v;
}

// Camera.WorldToScreenPoint — returns Vec3, z is depth
static Vec3 WorldToScreen(void *camera, Vec3 world) {
    if (!camera || !fn_Camera_WorldToScreen) return {};
    typedef Vec3 (*t_w2s)(void *, float, float, float, void *);
    return reinterpret_cast<t_w2s>(fn_Camera_WorldToScreen)(camera, world.x, world.y, world.z, nullptr);
}

// ============================================================
// PlayerManager singleton — via TypeInfo static_fields
// ============================================================

// Il2CppClass layout (simplified):
//   +0xB8  static_fields*
// LazySingleton<T> static_fields layout (standard Singleton pattern):
//   +0x00  T* _instance   (first static field)

static void *GetPlayerManager(void) {
    uintptr_t base = GameBase();
    if (!base) return nullptr;

    uintptr_t typeInfoPtr = Rd<uintptr_t>(base + TYPEINFO_PlayerManager);
    if (!typeInfoPtr) return nullptr;

    uintptr_t staticFields = Rd<uintptr_t>(typeInfoPtr + TYPEINFO_OFF_STATIC_FIELDS);
    if (!staticFields) return nullptr;

    // first static field of LazySingleton<PlayerManager> = instance
    void *pm = Rd<void *>(staticFields + 0x00);
    return pm;
}

// ============================================================
// PlayerMainCamera singleton
// ============================================================

static void *GetMainCamera(void) {
    // PlayerMainCamera has static getter at RVA_PlayerMainCamera_get_HGGHFBCAGEEGBDH
    // but easier: grab via Camera.get_main which Unity exposes
    typedef void *(*t_get_main)(void *);
    uintptr_t base = GameBase();
    if (!base) return nullptr;
    void *cam = reinterpret_cast<t_get_main>(base + RVA_Camera_get_main)(nullptr);
    return cam;
}

// ============================================================
// iterate HashSet<PlayerController>
// il2cpp HashSet layout:
//   +0x00  Il2CppObject header (klass*, monitor)  = 0x10 bytes
//   +0x10  int[]  _buckets     (ptr)
//   +0x18  Slot[] _slots       (ptr)   <- each Slot: hashCode(int)+next(int)+value(T*)
//   +0x20  int    _count
//   ...
// Slot stride = 0x10 (4+4+8 on arm64)
// Slot layout: [0x00] int hashCode, [0x04] int next, [0x08] T* value
// ============================================================

static void IterateHashSet(void *set, void (*cb)(void *elem, void *ctx), void *ctx) {
    if (!set) return;

    uintptr_t s     = (uintptr_t)set;
    void     *slots = Rd<void *>(s + 0x18);
    int32_t   count = Rd<int32_t>(s + 0x20);
    if (!slots || count <= 0 || count > 512) return;  // sanity

    // Il2CppArrayBounds for the backing Array:
    // il2cpp Array layout: header(0x10) + bounds(0x08 for 1D, often skipped) + length(0x18 or 0x20) + data
    // safer: just walk count slots from array data ptr
    // The _slots field points to an Il2CppArray<Slot>
    // array data starts at offset 0x20 (header 0x10 + max_length 0x04 + bounds 0x04 (1D) = 0x20? varies)
    // common il2cpp array data offset = 0x20
    uintptr_t data  = (uintptr_t)slots + 0x20;
    const int SLOT_STRIDE = 0x10;

    for (int i = 0; i < count; i++) {
        uintptr_t slotPtr = data + (uintptr_t)i * SLOT_STRIDE;
        int32_t   hashCode = Rd<int32_t>(slotPtr + 0x00);
        if (hashCode <= 0) continue;  // empty/deleted slot
        void *value = Rd<void *>(slotPtr + 0x08);
        if (value) cb(value, ctx);
    }
}

// ============================================================
// Local player identification
// PlayerManager.DEEBDAFCBHCGFBA (internal) = local PlayerController
// getter RVA: 0x10F8AE0
// ============================================================

static void *GetLocalPlayer(void *pm) {
    if (!pm) return nullptr;
    typedef void *(*t_getter)(void *, void *);
    uintptr_t base = GameBase();
    if (!base) return nullptr;
    return reinterpret_cast<t_getter>(base + 0x10F8AE0)(pm, nullptr);
}

// ============================================================
// SRESPCollectEntities — called from Overlay each frame
// ============================================================

struct CollectCtx {
    void             *camera;
    void             *localPlayer;
    int               localTeam;
    NSMutableArray   *result;
    CGSize            screenSize;
};

static void CollectOne(void *pc, void *ctx_) {
    if (!pc) return;
    auto *ctx = (CollectCtx *)ctx_;

    // skip local player
    if (pc == ctx->localPlayer) return;

    uintptr_t pcAddr = (uintptr_t)pc;

    // alive check via getter
    typedef bool (*t_bool_getter)(void *, void *);
    uintptr_t base = GameBase();
    bool isAlive = reinterpret_cast<t_bool_getter>(base + RVA_PlayerController_BEAGHGCHBCAGGDH_get)(pc, nullptr);
    if (!isAlive) return;

    // team
    int8_t team = Rd<int8_t>(pcAddr + PC_OFF_TEAM);

    // BipedMap
    void *biped = Rd<void *>(pcAddr + PC_OFF_CHARACTER_BIPED);
    if (!biped) return;

    uintptr_t bipedAddr = (uintptr_t)biped;
    void *headTransform = Rd<void *>(bipedAddr + BM_OFF_HEAD);
    void *hipTransform  = Rd<void *>(bipedAddr + BM_OFF_HIP);
    if (!headTransform || !hipTransform) return;

    Vec3 headWorld = GetPosition(headTransform);
    Vec3 hipWorld  = GetPosition(hipTransform);

    // world → screen
    Vec3 headScr = WorldToScreen(ctx->camera, headWorld);
    Vec3 hipScr  = WorldToScreen(ctx->camera, hipWorld);

    // behind camera (z <= 0 in Unity screen space means behind)
    if (headScr.z <= 0.0f || hipScr.z <= 0.0f) return;

    // Unity screen: origin bottom-left, y-up → flip for UIKit (top-left, y-down)
    CGFloat sh = ctx->screenSize.height;
    CGPoint headPt = CGPointMake(headScr.x, sh - headScr.y);
    CGPoint hipPt  = CGPointMake(hipScr.x,  sh - hipScr.y);

    // basic sanity — at least partially on screen
    CGFloat sw = ctx->screenSize.width;
    if (headPt.x < -200 || headPt.x > sw + 200) return;
    if (headPt.y < -200 || headPt.y > sh + 200) return;

    // hp — TODO(kindmops): read int _health from NetworkController at PC_OFF_NETWORK_CONTROLLER
    //   pattern: NetworkController* nc = *(pc + 0x98); then grep full dump for health field offset
    //   set healthPct accordingly; for now defaulting to 1.0
    float healthPct = 1.0f;

    ESPEntity ent;
    ent.head      = headPt;
    ent.hip       = hipPt;
    ent.healthPct = healthPct;
    ent.team      = (int)team;
    ent.isAlive   = YES;

    NSValue *v = [NSValue valueWithBytes:&ent objCType:@encode(ESPEntity)];
    [ctx->result addObject:v];
}

NSArray<NSValue *> *SRESPCollectEntities(void) {
    uintptr_t base = GameBase();
    if (!base) return @[];

    void *pm = GetPlayerManager();
    if (!pm) return @[];

    // get HashSet<PlayerController> via getter
    typedef void *(*t_getter)(void *, void *);
    void *playerSet = reinterpret_cast<t_getter>(base + RVA_PlayerManager_get_CEADFCHEEGGGDHC)(pm, nullptr);
    if (!playerSet) return @[];

    void *camera = GetMainCamera();
    if (!camera) return @[];

    void *localPlayer = GetLocalPlayer(pm);
    int8_t localTeam  = localPlayer ? Rd<int8_t>((uintptr_t)localPlayer + PC_OFF_TEAM) : 0;

    CGSize screenSize = [UIScreen mainScreen].bounds.size;

    CollectCtx ctx;
    ctx.camera      = camera;
    ctx.localPlayer = localPlayer;
    ctx.localTeam   = (int)localTeam;
    ctx.result      = [NSMutableArray array];
    ctx.screenSize  = screenSize;

    IterateHashSet(playerSet, CollectOne, &ctx);
    return ctx.result;
}

// ============================================================
// Toggle — shake gesture wires ESP on/off
// ============================================================

static BOOL s_espEnabled = NO;

%hook UIApplication
- (void)motionEnded:(UIEventSubtype)motion withEvent:(UIEvent *)event {
    %orig;
    if (motion == UIEventSubtypeMotionShake) {
        s_espEnabled = !s_espEnabled;
        dispatch_async(dispatch_get_main_queue(), ^{
            [[ESPOverlayWindow sharedWindow] setESPEnabled:s_espEnabled];
        });
    }
}
%end

// ============================================================
// Init — resolve function pointers
// ============================================================

%ctor {
    dispatch_after(
        dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3.0 * NSEC_PER_SEC)),
        dispatch_get_main_queue(),
        ^{
            uintptr_t base = GameBase();
            if (!base) return;

            fn_Transform_get_position =
                (t_Transform_get_position)(base + RVA_Transform_get_position);
            fn_Camera_WorldToScreen   =
                (t_Camera_WorldToScreen)(base + RVA_Camera_WorldToScreenPoint);

            // Warm up overlay window (lazy init)
            [ESPOverlayWindow sharedWindow];

            NSLog(@"[StandRiseESP] loaded. base=0x%llx shake to toggle", (unsigned long long)base);
        }
    );
}
