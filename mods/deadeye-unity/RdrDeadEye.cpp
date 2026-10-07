#include "pch.h"
#include "DeadEyeController.hpp"
#include "ACU/World.h"
#include "Common_Plugins/Common_PluginSide.h"

// Existing ACUFixes functions, linked from its original slow-motion source.
// No new retail addresses, signatures, injection or protection patches.
void ACUSetTimescaleInGameClock(float scale);

namespace {
deadeye::Controller controller;
bool enabled = false; // Explicit opt-in on EVERY launch. No online-mode detection.
World* previousWorld = nullptr;
std::uint64_t previousTime = 0;

bool IsGameForeground() {
    DWORD pid = 0;
    GetWindowThreadProcessId(GetForegroundWindow(), &pid);
    return pid == GetCurrentProcessId();
}

void Tick(bool forceStop) {
    World* world = World::GetSingleton();
    deadeye::Frame frame;
    frame.world = reinterpret_cast<std::uintptr_t>(world);
    if (world) {
        const auto now = world->clockUnpausedWithoutSlowmotion.currentTimestamp;
        if (world == previousWorld && now >= previousTime) {
            frame.elapsed = static_cast<double>(now - previousTime) / 30000.0;
        }
        previousTime = now;
        frame.observedScale = world->clockInWorldWithSlowmotion.overrideTimescale;
    }
    previousWorld = world;
    frame.foreground = IsGameForeground();
    if (frame.foreground && (GetAsyncKeyState(VK_F7) & 0x8000)) enabled = false;
    frame.enabled = enabled && !forceStop;
    frame.held = frame.foreground && (GetAsyncKeyState(VK_F6) & 0x8000);
    const auto& io = ImGui::GetIO();
    frame.uiCapture = io.WantCaptureKeyboard || io.WantCaptureMouse;
    if (auto scale = controller.step(frame)) {
        // Re-check identity before calling the established upstream setter.
        if (world && World::GetSingleton() == world) ACUSetTimescaleInGameClock(*scale);
    }
}
}

void RdrDeadEyeUpdate() {
    Tick(false);
    if (!enabled || !previousWorld) return;
    ImGui::SetNextWindowBgAlpha(0.7f);
    ImGui::SetNextWindowPos(ImVec2(24, 90), ImGuiCond_Always);
    constexpr auto flags = ImGuiWindowFlags_NoDecoration | ImGuiWindowFlags_AlwaysAutoResize
        | ImGuiWindowFlags_NoInputs | ImGuiWindowFlags_NoSavedSettings
        | ImGuiWindowFlags_NoFocusOnAppearing;
    ImGui::Begin("Dead Eye prototype status", nullptr, flags);
    ImGui::TextUnformatted(controller.active() ? "DEAD EYE - F6 held" : "DEAD EYE - hold F6 / F7 off");
    ImGui::ProgressBar(static_cast<float>(controller.charge() / deadeye::Controller::capacity), ImVec2(240, 16));
    ImGui::End();
}

void RdrDeadEyeDrawMenu() {
    ImGui::Separator();
    ImGui::TextUnformatted("RDR-inspired Dead Eye prototype (unverified in game)");
    ImGui::TextWrapped("Offline single-player ONLY. No automatic co-op detection. Disable before any online session.");
    if (ImGui::Checkbox("I am offline: enable Dead Eye (hold F6)", &enabled) && !enabled) Tick(true);
    ImGui::TextWrapped("Six seconds of 18%% speed; recharge while released. F7 disables. No targeting, Arthur model, or RDR2 assets.");
    if (ImGui::Button("Disable and restore owned timescale")) { enabled = false; Tick(true); }
}

void RdrDeadEyeRequestUnload() {
    enabled = false;
    Tick(true);
    RequestUnloadThisPlugin();
}
