#pragma once
#include <stdint.h>

// ============================================================
// StandRise Rework — il2cpp offsets
// Source: dump.cs + script.json (filtered subset)
// Re-dump with Il2CppDumper when APK updates
// ============================================================

// ---- TypeInfo static pointers (absolute VA in GameAssembly) ----
// pattern: *(TypeInfo + 0xB8) = static_fields ptr
// static_fields + 0x00 = singleton instance for LazySingleton<T>
#define TYPEINFO_PlayerManager      0x4239B48ULL   // PlayerManager_TypeInfo
#define TYPEINFO_PlayerController   0x4239B40ULL
#define TYPEINFO_PlayerMainCamera   0x4239B40ULL   // same page, see below
#define TYPEINFO_Camera             0x4233330ULL

// ---- PlayerManager (LazySingleton<PlayerManager>) ----
// instance = *(*(TYPEINFO_PlayerManager + 0xB8) + 0x00)
#define PM_OFF_PLAYER_SET           0x28    // HashSet<PlayerController> FBHAHGDECHGBHEE
// iterate HashSet: slots ptr @ +0x10, count @ +0x0C

// ---- PlayerController fields ----
#define PC_OFF_TEAM                 0x59    // byte  (Team enum: None=0, Tr=1, Ct=2, Spectator=3)
#define PC_OFF_CHARACTER_BIPED      0x30    // BipedMap* _characterBiped
#define PC_OFF_NETWORK_CONTROLLER   0x98    // NetworkController* EHCDDHHEBDBEHEA
#define PC_OFF_PHOTON_PLAYER        0x130   // PhotonPlayer* HHCCEADDHBAFECD
// bool props (alive / dead flags) — read via getter hooks, not raw offset
// TODO(kindmops): grep NetworkController class in full dump.cs for int _health/_armor offsets
//   search: "private int.*// 0x" inside NetworkController class body

// ---- BipedMap bone Transform* offsets ----
#define BM_OFF_HEAD                 0x18
#define BM_OFF_NECK                 0x20
#define BM_OFF_SPINE1               0x28
#define BM_OFF_SPINE2               0x30
#define BM_OFF_LEFT_UPPERARM        0x40
#define BM_OFF_RIGHT_UPPERARM       0x60
#define BM_OFF_HIP                  0x78
#define BM_OFF_LEFT_THIGH           0x80
#define BM_OFF_RIGHT_THIGH          0x98
#define BM_OFF_LEFT_FOOT            0x90
#define BM_OFF_RIGHT_FOOT           0xA8

// ---- PlayerMainCamera ----
// static singleton getter RVA: 0x10F7EF4  (HGGHFBCAGEEGBDH)
// Camera* field inside PlayerMainCamera: offset 0x18  (HBDEBCBFEEGABFB)
#define PMC_OFF_CAMERA              0x18

// ---- Method RVAs (relative to GameAssembly base) ----
// Use MSHookFunction on (base + RVA)
#define RVA_Transform_get_position      0x2DDE140
#define RVA_Camera_WorldToScreenPoint   0x2DD1BFC   // Vector3 overload (no eye)
#define RVA_Camera_get_main             0x2DD22B8
#define RVA_PlayerController_DieViaServer   0x10F7B30
#define RVA_PlayerController_BEAGHGCHBCAGGDH_get  0x10F3BDC  // bool isAlive getter
#define RVA_PlayerManager_get_CEADFCHEEGGGDHC      0x10F8AD8  // HashSet<PlayerController> getter

// ---- Mono/il2cpp class TypeInfo layout ----
#define TYPEINFO_OFF_STATIC_FIELDS  0xB8   // Il2CppClass* -> static_fields*
