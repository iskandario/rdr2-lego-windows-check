#define WIN32_LEAN_AND_MEAN
#define NOMINMAX
#include <windows.h>
#include <main.h>
#include <natives.h>
#include <atomic>
#include <chrono>
#include <filesystem>
#include <fstream>
#include <string>
#include "Traversal.hpp"

using traversal::Vec;
namespace {
HMODULE moduleHandle{};
std::atomic<unsigned> keys{0};
constexpr unsigned Toggle=1, Grab=2, Pull=4, Drop=8, Emergency=16;
bool enabled=false, animate=true, ownsFreeze=false;
Ped ownedPed=0;
Hash ownedModel=0;
std::ofstream logFile;
traversal::Motion motion;
const char* status="F8 enable | EXPERIMENTAL - Story Mode only";
// Existing RDR2 clips, not AC assets. The suspended vault pose is a placeholder.
constexpr const char* AnimDict="mech_climb@base@vertical@stand@vault";
constexpr const char* AnimClip="vaultup_125_high";

void log(const std::string& message) {
    if (logFile) logFile << GetTickCount64() << " " << message << std::endl;
}
Vec vec(Vector3 v) { return {v.x,v.y,v.z}; }
bool focused() {
    DWORD pid=0;
    GetWindowThreadProcessId(GetForegroundWindow(),&pid);
    return pid==GetCurrentProcessId();
}
bool online() {
    return NETWORK::NETWORK_IS_SESSION_ACTIVE() || NETWORK::NETWORK_IS_IN_SESSION() ||
           NETWORK::NETWORK_IS_GAME_IN_PROGRESS();
}
bool eligible(Ped ped) {
    if (!focused() || online() || HUD::IS_PAUSE_MENU_ACTIVE() || !CAM::IS_SCREEN_FADED_IN()) return false;
    if (!ped || !ENTITY::DOES_ENTITY_EXIST(ped) || ped!=PLAYER::PLAYER_PED_ID() || ENTITY::IS_ENTITY_DEAD(ped)) return false;
    const Hash model=ENTITY::GET_ENTITY_MODEL(ped);
    if (model!=MISC::GET_HASH_KEY("player_zero") && model!=MISC::GET_HASH_KEY("player_three")) return false;
    return PLAYER::IS_PLAYER_CONTROL_ON(PLAYER::PLAYER_ID()) && !PED::IS_PED_ON_MOUNT(ped) &&
           !PED::IS_PED_IN_ANY_VEHICLE(ped,false) && !PED::IS_PED_SWIMMING(ped) &&
           !PED::IS_PED_RAGDOLL(ped) && !PED::IS_PED_IN_COMBAT(ped,0);
}
void suppressActions() {
    // Validated input identifiers from femga/rdr3_discoveries/controls.
    // Leave pause/look controls available; custom actions use the SDK key hook.
    PAD::DISABLE_CONTROL_ACTION(0,MISC::GET_HASH_KEY("INPUT_MOVE_LR"),true);
    PAD::DISABLE_CONTROL_ACTION(0,MISC::GET_HASH_KEY("INPUT_MOVE_UD"),true);
    PAD::DISABLE_CONTROL_ACTION(0,MISC::GET_HASH_KEY("INPUT_JUMP"),true);
    PAD::DISABLE_CONTROL_ACTION(0,MISC::GET_HASH_KEY("INPUT_ATTACK"),true);
    PAD::DISABLE_CONTROL_ACTION(0,MISC::GET_HASH_KEY("INPUT_AIM"),true);
    PAD::DISABLE_CONTROL_ACTION(0,MISC::GET_HASH_KEY("INPUT_ENTER"),true);
}
void release(const char* reason) {
    // Called only on the game script fiber, never from DllMain/keyboard handler.
    if (ownsFreeze && ENTITY::DOES_ENTITY_EXIST(ownedPed) && ENTITY::GET_ENTITY_MODEL(ownedPed)==ownedModel) {
        if (animate) TASK::STOP_ANIM_TASK(ownedPed,AnimDict,AnimClip,2.f);
        ENTITY::FREEZE_ENTITY_POSITION(ownedPed,false);
    }
    if (ownsFreeze) log(std::string("release: ")+reason);
    ownsFreeze=false; ownedPed=0; ownedModel=0;
    motion.release();
}
void place(Vec feet, float rootOffset) {
    ENTITY::SET_ENTITY_COORDS_NO_OFFSET(ownedPed,feet.x,feet.y,feet.z+rootOffset,false,false,false);
}
void startAnimation() {
    if (animate && STREAMING::HAS_ANIM_DICT_LOADED(AnimDict)) {
        TASK::TASK_PLAY_ANIM(ownedPed,AnimDict,AnimClip,4.f,-4.f,-1,2,0.f,false,0,false,nullptr,false);
    }
}
void pose() {
    if (!animate || !ENTITY::IS_ENTITY_PLAYING_ANIM(ownedPed,AnimDict,AnimClip,3)) return;
    float phase=0.35f;
    if (motion.state==traversal::State::Pulling)
        phase=0.35f+0.60f*std::clamp(motion.elapsed/1.4f,0.f,1.f);
    ENTITY::_SET_ENTITY_ANIM_CURRENT_TIME(ownedPed,AnimDict,AnimClip,phase);
    ENTITY::_SET_ENTITY_ANIM_SPEED(ownedPed,AnimDict,AnimClip,0.f);
}

class GameQueries final : public traversal::Queries {
    Ped ped;
    ULONGLONG deadline;
public:
    explicit GameQueries(Ped p) : ped(p), deadline(GetTickCount64()+2000) {}
    std::optional<traversal::Hit> cast(Vec a, Vec b, float radius) override {
        if (!traversal::finite(a) || !traversal::finite(b) || !eligible(ped) ||
            GetTickCount64()>deadline || (keys.load()&(Emergency|Drop|Toggle))) return {};
        // World + vehicles + peds + objects. A dynamic hit is an obstacle, but
        // never a valid anchor. Doors/wagons must not become a hanging platform.
        constexpr int flags=1|2|4|8|16;
        int handle=radius>0 ? SHAPETEST::START_SHAPE_TEST_CAPSULE(a.x,a.y,a.z,b.x,b.y,b.z,radius,flags,ped,7)
                            : SHAPETEST::START_SHAPE_TEST_LOS_PROBE(a.x,a.y,a.z,b.x,b.y,b.z,flags,ped,7);
        if (!handle) return {};
        for (int attempt=0;attempt<12;++attempt) {
            BOOL hit=false;
            Vector3 point{}, normal{};
            Entity entity=0;
            const int result=SHAPETEST::GET_SHAPE_TEST_RESULT(handle,&hit,&point,&normal,&entity);
            if (result==2) {
                bool fixed=true;
                if (hit && entity) {
                    fixed=ENTITY::DOES_ENTITY_EXIST(entity) && ENTITY::IS_ENTITY_STATIC(entity) &&
                          !ENTITY::IS_ENTITY_A_PED(entity) && !ENTITY::IS_ENTITY_A_VEHICLE(entity);
                }
                return traversal::Hit{hit!=FALSE,vec(point),vec(normal),fixed};
            }
            if (result!=1) return {};
            if (ownsFreeze) suppressActions();
            WAIT(0); // Yield to the game, do not spin/block the render thread.
            if (!eligible(ped) || GetTickCount64()>deadline || (keys.load()&(Emergency|Drop|Toggle))) return {};
        }
        return {}; // Timeout is not an unobstructed path.
    }
};

void display(const char* message) {
    HUD::SET_TEXT_SCALE(0.32f,0.32f);
    HUD::_SET_TEXT_COLOR(245,225,150,255);
    HUD::SET_TEXT_CENTRE(false);
    HUD::_DISPLAY_TEXT(MISC::_CREATE_VAR_STRING(10,"LITERAL_STRING",message),0.025f,0.08f);
}
void keyboard(DWORD key, WORD, BYTE, BOOL, BOOL alt, BOOL wasDown, BOOL up) {
    if (up || wasDown || alt) return;
    unsigned event=0;
    if (key==VK_F8) event=Toggle;
    if (key==VK_F9) event=Emergency;
    if (key=='G') event=Grab;
    if (key=='E') event=Pull;
    if (key=='Q') event=Drop;
    if (event) keys.fetch_or(event);
}

void scriptMain() {
    wchar_t path[MAX_PATH]{};
    GetModuleFileNameW(moduleHandle,path,MAX_PATH);
    const auto directory=std::filesystem::path(path).parent_path();
    logFile.open(directory/L"AssassinTraversal.log",std::ios::app);
    log("AssassinTraversal 0.1.0 experimental; no in-game verification; offline only");
    auto ini=directory/L"AssassinTraversal.ini";
    animate=GetPrivateProfileIntW(L"Traversal",L"Animate",1,ini.c_str())!=0;
    auto last=std::chrono::steady_clock::now();
    auto lastValidation=last;
    for (;;) {
        WAIT(0);
        auto now=std::chrono::steady_clock::now();
        float dt=std::chrono::duration<float>(now-last).count();
        last=now;
        const unsigned events=keys.exchange(0);
        const Ped ped=PLAYER::PLAYER_PED_ID();
        // The guard is a fallback, NOT permission to load mods in Red Dead Online.
        if (!eligible(ped)) {
            release("unsafe context / focus / loading / player change");
            enabled=false;
            status="F8 enable | EXPERIMENTAL - Story Mode only";
            continue;
        }
        if (ownsFreeze && (ped!=ownedPed || ENTITY::GET_ENTITY_MODEL(ped)!=ownedModel)) {
            release("player replaced"); enabled=false;
        }
        if (events&Emergency) {
            release("F9 emergency"); enabled=false;
            status="OFF - released. F8 enable";
        } else if (events&Toggle) {
            release("F8 toggle"); enabled=!enabled;
            status=enabled ? "ON - stand still facing a ledge; G grab | F9 off" : "OFF - F8 enable";
            log(enabled?"enabled":"disabled");
            if (enabled && animate) STREAMING::REQUEST_ANIM_DICT(AnimDict);
        }
        if (!enabled) { display(status); continue; }
        if (events&Drop) { release("Q drop"); status="Released. G grab | F9 off"; }
        if (ownsFreeze) {
            suppressActions();
            const Vec actual=vec(ENTITY::GET_ENTITY_COORDS(ped,true,false));
            const Vec expected=motion.feet+Vec{0,0,motion.plan.rootOffset};
            if (traversal::length(actual-expected)>0.5f || !ENTITY::_IS_ENTITY_FROZEN(ped)) {
                release("external movement/state change"); status="Cancelled: player moved externally";
                continue;
            }
            if ((events&Pull) && motion.state==traversal::State::Hanging) {
                GameQueries q(ped);
                if (traversal::bodyPathClear(q,motion.plan.hangFeet,motion.plan.raisedFeet) &&
                    traversal::bodyPathClear(q,motion.plan.raisedFeet,motion.plan.endFeet)) {
                    motion.pull(); log("pull requested");
                } else {
                    release("pull path blocked or cancelled"); status="Blocked pull path - released";
                    continue;
                }
                last=std::chrono::steady_clock::now(); dt=0;
            }
            // Revalidate body occupancy and support while holding a ledge.
            if (now-lastValidation>std::chrono::milliseconds(350)) {
                GameQueries q(ped);
                Vec end=motion.plan.endFeet;
                auto support=q.cast(end+Vec{0,0,0.20f},end-Vec{0,0,0.22f},0);
                if (!support || !support->hit || !support->fixed || support->normal.z<0.9f ||
                    !traversal::bodyPathClear(q,motion.feet,motion.feet+Vec{0,0,0.001f})) {
                    release("ledge/clearance lost"); status="Ledge changed - released"; continue;
                }
                last=std::chrono::steady_clock::now(); lastValidation=last; dt=0;
            }
            const Vec previous=motion.feet;
            if (!motion.tick(dt)) { release("timeout or frame stall"); status="Released (timeout/stall)"; continue; }
            if (traversal::length(motion.feet-previous)>0.001f) {
                GameQueries q(ped);
                if (!traversal::bodyPathClear(q,previous,motion.feet)) {
                    release("movement sweep blocked"); status="Obstacle - released"; continue;
                }
                // Validation yields frames. Account for that next tick rather
                // than resetting elapsed time and slowing movement indefinitely.
            }
            if (!eligible(ped) || (keys.load()&(Emergency|Drop|Toggle))) { release("cancel during query"); continue; }
            place(motion.feet,motion.plan.rootOffset);
            pose();
            if (motion.state==traversal::State::Idle) {
                release("pull completed"); status="On ledge. G grab | F9 off";
            } else status=motion.state==traversal::State::Hanging ? "HANGING - E pull up | Q drop | F9 off (15s limit)" : "MOVING - Q drop | F9 off";
        } else if ((events&Grab) && !(events&(Drop|Emergency|Toggle))) {
            if (ENTITY::_IS_ENTITY_FROZEN(ped) || PED::IS_PED_FALLING(ped) || PED::IS_PED_JUMPING(ped) ||
                PED::IS_PED_CLIMBING(ped) || ENTITY::GET_ENTITY_SPEED(ped)>0.3f) {
                status="Stand still on foot before pressing G"; continue;
            }
            if (animate && !STREAMING::HAS_ANIM_DICT_LOADED(AnimDict)) {
                STREAMING::REQUEST_ANIM_DICT(AnimDict);
                status="Loading climbing animation; press G again shortly"; continue;
            }
            const Vec root=vec(ENTITY::GET_ENTITY_COORDS(ped,true,false));
            // Calibrate entity origin against the two actual foot bones instead
            // of assuming GTA's origin convention. IDs from rdr3_discoveries.
            auto left=PED::GET_PED_BONE_COORDS(ped,45454,0,0,0);
            auto right=PED::GET_PED_BONE_COORDS(ped,33646,0,0,0);
            const float rootOffset=root.z-std::min(left.z,right.z)+0.06f;
            const Vec feet=root-Vec{0,0,rootOffset};
            GameQueries q(ped);
            auto plan=traversal::probe(q,feet,vec(ENTITY::GET_ENTITY_FORWARD_VECTOR(ped)),rootOffset);
            if (!plan || !eligible(ped) || (keys.load()&(Emergency|Drop|Toggle)) ||
                ENTITY::_IS_ENTITY_FROZEN(ped) ||
                traversal::length(vec(ENTITY::GET_ENTITY_COORDS(ped,true,false))-root)>0.12f) {
                log("grab rejected: no safe ledge / query cancelled / player moved");
                status="No safe ledge. Face a solid 1.3-2.6m wall with a wide flat top";
                continue;
            }
            if (motion.begin(*plan)) {
                ownedPed=ped; ownedModel=ENTITY::GET_ENTITY_MODEL(ped); ownsFreeze=true;
                ENTITY::FREEZE_ENTITY_POSITION(ped,true);
                ENTITY::SET_ENTITY_HEADING(ped,MISC::GET_HEADING_FROM_VECTOR_2D(-plan->outward.x,-plan->outward.y));
                startAnimation();
                last=std::chrono::steady_clock::now(); lastValidation=last;
                log("grab accepted: rootOffset="+std::to_string(rootOffset)+" ledgeZ="+std::to_string(plan->endFeet.z));
            }
        }
        display(status);
    }
}
} // namespace

BOOL APIENTRY DllMain(HMODULE module, DWORD reason, LPVOID) {
    if (reason==DLL_PROCESS_ATTACH) {
        moduleHandle=module;
        scriptRegister(module,scriptMain);
        keyboardHandlerRegister(keyboard);
    } else if (reason==DLL_PROCESS_DETACH) {
        // Native calls are unsafe under the loader lock. F9 MUST be used before
        // developer hot-unload; ordinary users should exit the game to uninstall.
        keyboardHandlerUnregister(keyboard);
        scriptUnregister(module);
    }
    return TRUE;
}
