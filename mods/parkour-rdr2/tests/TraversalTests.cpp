#include "../src/Traversal.hpp"
#include <cassert>
#include <iostream>
#include <limits>
#include <vector>
using namespace traversal;

// Synthetic map: player faces +Y; solid wall y=0.8; platform z=2.0.
struct Fixture : Queries {
    int rays=0, sweeps=0;
    int invalidAt=-1, calls=0;
    bool wall=true, top=true, fixed=true, narrow=false, blocked=false;
    float height=2.f, normalZ=1.f;
    std::vector<std::pair<Vec,Vec>> sweepSegments;
    std::optional<Hit> cast(Vec a, Vec b, float radius) override {
        if (calls++==invalidAt) return {};
        if (radius>0) {
            ++sweeps; sweepSegments.emplace_back(a,b);
            return Hit{blocked,{},{},true};
        }
        ++rays;
        if (std::abs(a.z-b.z)<0.01f) return Hit{wall,{0,.8f,1.05f},{0,-1,0},fixed};
        if (a.z>2.7f) return Hit{top,{0,1.45f,height},{0,0,normalZ},fixed};
        return Hit{!narrow,{a.x,a.y,height},{0,0,1},fixed};
    }
};
bool near(Vec a, Vec b) { return length(a-b)<.0001f; }
struct Box { Vec low, high; };
struct BoxWorld : Queries {
    std::vector<Box> boxes{{{-5,.8f,-5},{5,5,2}}};
    std::optional<Hit> cast(Vec a, Vec b, float radius) override {
        Hit closest{};
        float best=2;
        for (const auto& box: boxes) {
            float lo=0, hi=1;
            Vec normal{};
            const float av[]={a.x,a.y,a.z}, dv[]={b.x-a.x,b.y-a.y,b.z-a.z};
            const float mn[]={box.low.x-radius,box.low.y-radius,box.low.z-radius};
            const float mx[]={box.high.x+radius,box.high.y+radius,box.high.z+radius};
            bool intersects=true;
            for(int axis=0;axis<3;++axis) {
                if(std::abs(dv[axis])<1e-6f) {
                    if(av[axis]<mn[axis] || av[axis]>mx[axis]) { intersects=false; break; }
                } else {
                    float t1=(mn[axis]-av[axis])/dv[axis], t2=(mx[axis]-av[axis])/dv[axis];
                    float sign=-1;
                    if(t1>t2) { std::swap(t1,t2); sign=1; }
                    if(t1>lo) { lo=t1; normal={}; if(axis==0) normal.x=sign; if(axis==1) normal.y=sign; if(axis==2) normal.z=sign; }
                    hi=std::min(hi,t2);
                    if(lo>hi) { intersects=false; break; }
                }
            }
            if(intersects && lo<best) { best=lo; closest={true,lerp(a,b,lo),normal,true}; }
        }
        return closest;
    }
};
Plan validPlan() {
    Fixture f;
    auto plan=probe(f,{0,0,0},{0,1,0},.9f);
    assert(plan);
    assert(f.sweeps==15);
    assert(near(plan->hangFeet,{0,.25f,.2f}));
    assert(near(plan->raisedFeet,{0,.25f,2.07f}));
    assert(near(plan->endFeet,{0,1.45f,2.07f}));
    return *plan;
}
int main() {
    auto plan=validPlan();
    // Independent geometric collision oracle (expanded AABBs, conservative
    // swept-sphere approximation), not scripted "all clear" query answers.
    {
        BoxWorld world;
        auto physical=probe(world,{},{0,1,0},.9f);
        assert(physical);
        assert(!bodyPathClear(world,physical->hangFeet,physical->endFeet));
        assert(bodyPathClear(world,physical->hangFeet,physical->raisedFeet));
        assert(bodyPathClear(world,physical->raisedFeet,physical->endFeet));
        world.boxes.push_back({{-5,-1,3},{5,5,3.2f}}); // low ceiling
        assert(!probe(world,{},{0,1,0},.9f));
    }
    {
        BoxWorld world;
        world.boxes[0]={{-.1f,.8f,-5},{.1f,5,2}}; // too narrow to stand on
        assert(!probe(world,{},{0,1,0},.9f));
    }
    { Fixture f; f.wall=false; assert(!probe(f,{},{0,1,0},.9f)); }
    { Fixture f; f.top=false; assert(!probe(f,{},{0,1,0},.9f)); }
    { Fixture f; f.fixed=false; assert(!probe(f,{},{0,1,0},.9f)); }
    { Fixture f; f.narrow=true; assert(!probe(f,{},{0,1,0},.9f)); }
    { Fixture f; f.blocked=true; assert(!probe(f,{},{0,1,0},.9f)); }
    { Fixture f; f.normalZ=.5f; assert(!probe(f,{},{0,1,0},.9f)); }
    for (float height : {.5f,1.2f,2.8f,10.f}) {
        Fixture f; f.height=height; assert(!probe(f,{},{0,1,0},.9f));
    }
    for (int i=0;i<20;++i) {
        Fixture f; f.invalidAt=i; assert(!probe(f,{},{0,1,0},.9f));
    }
    { Fixture f; assert(!probe(f,{},{},.9f)); assert(f.calls==0); }
    const float nan=std::numeric_limits<float>::quiet_NaN();
    { Fixture f; assert(!probe(f,{nan,0,0},{0,1,0},.9f)); }
    { Fixture f; assert(!probe(f,{},{0,nan,0},.9f)); }
    { Fixture f; assert(!probe(f,{},{0,1,0},nan)); }
    for (float offset : {0.f,.19f,1.51f}) {
        Fixture f; assert(!probe(f,{},{0,1,0},offset));
    }
    for (float fps : {30.f,60.f,144.f}) {
        Motion m;
        assert(!m.pull()); assert(m.begin(plan)); assert(!m.begin(plan));
        for (int i=0;i<static_cast<int>(fps);++i) assert(m.tick(1.f/fps));
        assert(m.state==State::Hanging); assert(near(m.feet,plan.hangFeet));
        assert(m.pull());
        for (int i=0;m.state!=State::Idle && i<static_cast<int>(2*fps);++i) {
            assert(m.tick(1.f/fps));
            // Crossing the wall only once the feet are above the platform.
            if (m.feet.y>.55f) assert(m.feet.z>=2.06f);
        }
        assert(m.state==State::Idle); assert(near(m.feet,plan.endFeet));
    }
    for (float badDt : {-1.f,.3f,nan}) {
        Motion m; assert(m.begin(plan)); assert(!m.tick(badDt)); assert(m.state==State::Idle);
    }
    { Motion m; assert(m.begin(plan)); m.release(); assert(m.state==State::Idle); assert(!m.tick(.01f)); }
    { Motion m; assert(m.begin(plan)); for(int i=0;i<1600;++i) m.tick(.01f); assert(m.state==State::Idle); }
    { Motion m; auto bad=plan; bad.endFeet.x=nan; assert(!m.begin(bad)); }
    std::cout << "PASS: ledge geometry, blocked/missing/dynamic surfaces, 20 query failures,\n"
                 "invalid data, collision-safe path, 30/60/144Hz motion, cancellation and timeout\n";
}
