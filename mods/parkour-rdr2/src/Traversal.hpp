#pragma once
#include <algorithm>
#include <cmath>
#include <optional>

namespace traversal {
struct Vec {
    float x{}, y{}, z{};
    Vec operator+(Vec b) const { return {x+b.x, y+b.y, z+b.z}; }
    Vec operator-(Vec b) const { return {x-b.x, y-b.y, z-b.z}; }
    Vec operator*(float s) const { return {x*s, y*s, z*s}; }
};
inline bool finite(Vec a) { return std::isfinite(a.x) && std::isfinite(a.y) && std::isfinite(a.z); }
inline float dot(Vec a, Vec b) { return a.x*b.x+a.y*b.y+a.z*b.z; }
inline float length(Vec a) { return std::sqrt(dot(a,a)); }
inline Vec lerp(Vec a, Vec b, float t) { return a+(b-a)*t; }
inline float smooth(float t) { t=std::clamp(t,0.f,1.f); return t*t*(3.f-2.f*t); }

struct Hit { bool hit{}; Vec point{}, normal{}; bool fixed{true}; };
// nullopt means unavailable, cancelled, invalid or timed out: never "clear".
struct Queries {
    virtual ~Queries() = default;
    virtual std::optional<Hit> cast(Vec from, Vec to, float radius) = 0;
};
struct Plan { Vec startFeet, hangFeet, raisedFeet, endFeet, outward; float rootOffset{}; };

inline bool clear(Queries& q, Vec a, Vec b, float radius) {
    auto h=q.cast(a,b,radius);
    return h && !h->hit;
}
inline bool bodyPathClear(Queries& q, Vec feetA, Vec feetB) {
    if (!finite(feetA) || !finite(feetB)) return false;
    // Overlapping swept spheres approximate a standing capsule, including the
    // whole path, not just its destination. Keep a little space above the floor.
    for (float z : {0.32f,0.65f,0.98f,1.31f,1.60f}) {
        Vec offset{0,0,z};
        if (!clear(q,feetA+offset,feetB+offset,0.26f)) return false;
    }
    return true;
}
inline std::optional<Plan> probe(Queries& q, Vec feet, Vec forward, float rootOffset) {
    if (!finite(feet) || !finite(forward) || !std::isfinite(rootOffset) ||
        rootOffset<0.2f || rootOffset>1.5f) return {};
    forward.z=0;
    const float n=length(forward);
    if (n<0.01f) return {};
    forward=forward*(1.f/n);
    const Vec chest=feet+Vec{0,0,1.05f};
    auto wall=q.cast(chest,chest+forward*1.45f,0);
    if (!wall || !wall->hit || !wall->fixed || !finite(wall->normal) || !finite(wall->point)) return {};
    if (std::abs(wall->normal.z)>0.25f) return {};
    Vec outward{wall->normal.x,wall->normal.y,0};
    const float normalLength=length(outward);
    if (normalLength<0.8f || normalLength>1.2f) return {};
    outward=outward*(1.f/normalLength);
    if (dot(outward,forward)>-0.7f || length(wall->point-chest)>1.5f) return {};
    Vec inside=wall->point-outward*0.65f;
    auto top=q.cast({inside.x,inside.y,feet.z+2.85f},
                    {inside.x,inside.y,feet.z+1.20f},0);
    if (!top || !top->hit || !top->fixed || !finite(top->point) || !finite(top->normal)) return {};
    const float rise=top->point.z-feet.z;
    if (top->normal.z<0.90f || rise<1.30f || rise>2.65f) return {};
    Plan p;
    p.startFeet=feet; p.outward=outward; p.rootOffset=rootOffset;
    p.hangFeet={wall->point.x+outward.x*0.55f,wall->point.y+outward.y*0.55f,top->point.z-1.80f};
    p.endFeet={top->point.x,top->point.y,top->point.z+0.07f};
    p.raisedFeet={p.hangFeet.x,p.hangFeet.y,p.endFeet.z};
    // Limit snap distance; first version only begins while standing still.
    if (length(p.hangFeet-feet)>1.5f) return {};
    // Confirm a platform, not a single narrow beam or the edge of a thin fence.
    const Vec side{-outward.y,outward.x,0};
    for (Vec offset : {side*0.30f,side*(-0.30f),outward*(-0.25f)}) {
        Vec s=p.endFeet+offset;
        auto support=q.cast(s+Vec{0,0,0.2f},s-Vec{0,0,0.22f},0);
        if (!support || !support->hit || !support->fixed || !finite(support->point) ||
            !finite(support->normal) || support->normal.z<0.9f ||
            std::abs(support->point.z-top->point.z)>0.12f) return {};
    }
    if (!bodyPathClear(q,feet,p.hangFeet) ||
        !bodyPathClear(q,p.hangFeet,p.raisedFeet) ||
        !bodyPathClear(q,p.raisedFeet,p.endFeet)) return {};
    return p;
}

enum class State { Idle, Grabbing, Hanging, Pulling };
class Motion {
public:
    State state{State::Idle};
    Plan plan{};
    Vec feet{};
    float elapsed{}, hangingSeconds{};
    bool begin(const Plan& p) {
        if (state!=State::Idle || !finite(p.startFeet) || !finite(p.hangFeet) ||
            !finite(p.raisedFeet) || !finite(p.endFeet)) return false;
        plan=p; feet=p.startFeet; elapsed=0; hangingSeconds=0; state=State::Grabbing;
        return true;
    }
    void release() { state=State::Idle; elapsed=0; hangingSeconds=0; }
    bool pull() {
        if (state!=State::Hanging) return false;
        elapsed=0; state=State::Pulling; return true;
    }
    // false requests cleanup, including on invalid/stalled time or hang timeout.
    bool tick(float dt) {
        if (state==State::Idle) return false;
        if (!std::isfinite(dt) || dt<0 || dt>0.25f) { release(); return false; }
        elapsed+=dt;
        if (state==State::Grabbing) {
            feet=lerp(plan.startFeet,plan.hangFeet,smooth(elapsed/0.35f));
            if (elapsed>=0.35f) { state=State::Hanging; elapsed=0; }
        } else if (state==State::Hanging) {
            hangingSeconds+=dt;
            if (hangingSeconds>=15.f) { release(); return false; }
        } else if (state==State::Pulling) {
            // Lift outside the wall, then move over the top; never a diagonal
            // interpolation through the solid face of the building.
            if (elapsed<=0.85f) feet=lerp(plan.hangFeet,plan.raisedFeet,smooth(elapsed/0.85f));
            else feet=lerp(plan.raisedFeet,plan.endFeet,smooth((elapsed-0.85f)/0.55f));
            if (elapsed>=1.40f) { feet=plan.endFeet; state=State::Idle; }
        }
        return true;
    }
};
} // namespace traversal
