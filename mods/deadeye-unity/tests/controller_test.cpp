#include "../DeadEyeController.hpp"
#include <cassert>
#include <iostream>
#include <limits>

using deadeye::Controller;
using deadeye::Frame;
struct Rig {
    Controller c;
    Frame f{1, 1.0 / 60, 1, true, false, true, false};
    std::optional<float> tick() {
        auto result = c.step(f);
        if (result) f.observedScale = *result;
        return result;
    }
    Rig() { tick(); tick(); }
    void start() { f.held = true; tick(); assert(c.active()); }
};

int main() {
    { Rig r; r.start(); assert(std::abs(r.f.observedScale - .18f) < .001f);
      r.f.held = false; assert(r.tick().value() == 1); assert(!r.c.active()); }
    for (int reason = 0; reason != 5; ++reason) {
        Rig r; r.start();
        if (reason == 0) r.f.enabled = false;
        if (reason == 1) r.f.foreground = false;
        if (reason == 2) r.f.uiCapture = true;
        if (reason == 3) r.f.elapsed = 0;
        if (reason == 4) r.f.elapsed = 2;
        assert(r.tick().value() == 1); assert(!r.c.active());
    }
    { Rig r; r.start(); r.f.world = 2; r.f.observedScale = .7f;
      assert(!r.tick()); assert(!r.c.active()); assert(r.f.observedScale == .7f); }
    { Rig r; r.start(); r.f.world = 0; assert(!r.tick()); assert(!r.c.active()); }
    { Rig r; r.start(); r.f.observedScale = .5f;
      assert(!r.tick()); assert(!r.c.active()); assert(r.f.observedScale == .5f); }
    { Rig r; r.f.observedScale = .5f; r.f.held = true; assert(!r.tick()); assert(!r.c.active()); }
    { Rig r; r.start(); for (int n = 0; n < 400; ++n) r.tick();
      assert(!r.c.active()); assert(r.c.charge() == 0); assert(r.f.observedScale == 1);
      for (int n = 0; n < 600; ++n) r.tick(); assert(r.c.charge() == 0);
      r.f.held = false; for (int n = 0; n < 650; ++n) r.tick();
      assert(r.c.charge() == Controller::capacity); r.start(); }
    for (double bad : { -1.0, std::numeric_limits<double>::infinity(), std::numeric_limits<double>::quiet_NaN() }) {
        Rig r; r.start(); r.f.elapsed = bad; assert(r.tick().value() == 1); assert(!r.c.active());
    }
    { Rig r; r.f.observedScale = std::numeric_limits<float>::quiet_NaN(); r.f.held = true;
      assert(!r.tick()); assert(!r.c.active()); }
    { Rig r; r.start(); r.f.enabled = false; r.tick(); r.f.enabled = true;
      assert(!r.tick()); r.f.held = false; r.tick(); r.start(); }
    for (double hz : {30., 60., 144.}) {
        Rig r; r.f.elapsed = 1. / hz; r.f.held = true;
        for (int n = 0; n < static_cast<int>(hz * 3); ++n) r.tick();
        assert(std::abs(r.c.charge() - 3.) < .001); assert(r.c.active());
    }
    std::cout << "PASS: activation, release, pause, focus, disable, UI, world loss/change, external ownership, budget, recharge, bad deltas, frame-rate independence\n";
}
