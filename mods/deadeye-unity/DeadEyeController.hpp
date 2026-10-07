#pragma once
#include <algorithm>
#include <cmath>
#include <cstdint>
#include <optional>

// Original standalone mechanic, not extracted RDR2 code or an exact Dead Eye port.
namespace deadeye {
struct Frame {
    std::uintptr_t world = 0;
    double elapsed = 0; // Host's unpaused, unscaled time delta.
    float observedScale = 1;
    bool enabled = false;
    bool held = false;
    bool foreground = false;
    bool uiCapture = false;
};

class Controller {
public:
    static constexpr double capacity = 6.0;
    static constexpr double rechargePerSecond = 0.6;
    static constexpr float slowScale = 0.18f;

    // No memory writes here. The game adapter alone applies returned commands.
    std::optional<float> step(const Frame& f) {
        if (f.world != world_) {
            world_ = f.world;
            active_ = false; // Never restore through a stale world pointer.
            releaseRequired_ = true;
            return {};
        }
        if (!f.world || !std::isfinite(f.observedScale)) {
            active_ = false;
            releaseRequired_ = true;
            return {};
        }
        if (active_ && std::abs(f.observedScale - lastWritten_) > 0.015f) {
            // A cutscene/another mod took ownership: do not fight its timescale.
            active_ = false;
            releaseRequired_ = true;
            return {};
        }
        const bool timeIsAdvancing = std::isfinite(f.elapsed) && f.elapsed > 0 && f.elapsed <= 0.5;
        const bool allowed = f.enabled && f.foreground && !f.uiCapture && timeIsAdvancing;
        if (!f.held) releaseRequired_ = false;
        if (!allowed || !f.held) {
            if (!allowed) releaseRequired_ = true;
            if (active_) {
                active_ = false;
                return originalScale_;
            }
            if (allowed) charge_ = std::min(capacity, charge_ + f.elapsed * rechargePerSecond);
            return {};
        }
        if (!active_) {
            if (releaseRequired_ || charge_ < 0.5 || std::abs(f.observedScale - 1.0f) > 0.015f) return {};
            originalScale_ = f.observedScale;
            lastWritten_ = originalScale_ * slowScale;
            active_ = true;
        }
        charge_ = std::max(0.0, charge_ - f.elapsed);
        if (charge_ <= 0) {
            active_ = false;
            releaseRequired_ = true;
            return originalScale_;
        }
        return lastWritten_;
    }
    bool active() const { return active_; }
    double charge() const { return charge_; }

private:
    std::uintptr_t world_ = 0;
    double charge_ = capacity;
    float originalScale_ = 1;
    float lastWritten_ = 1;
    bool active_ = false;
    bool releaseRequired_ = true;
};
} // namespace deadeye
