#include "app_identity.h"
#include "smtc_plugin.h"

#include <unknwn.h>
#include <systemmediatransportcontrolsinterop.h>

#include <winrt/Windows.Foundation.h>
#include <winrt/Windows.Media.h>
#include <winrt/Windows.Storage.Streams.h>

#include <flutter/standard_method_codec.h>

#include <chrono>
#include <string>

namespace wm = winrt::Windows::Media;
namespace wf = winrt::Windows::Foundation;

namespace {

std::wstring ToWide(const std::string& utf8) {
  if (utf8.empty()) return std::wstring();
  int size = MultiByteToWideChar(CP_UTF8, 0, utf8.data(),
                                 static_cast<int>(utf8.size()), nullptr, 0);
  std::wstring out(size, L'\0');
  MultiByteToWideChar(CP_UTF8, 0, utf8.data(), static_cast<int>(utf8.size()),
                      out.data(), size);
  return out;
}

std::string GetString(const flutter::EncodableMap& map, const char* key) {
  auto it = map.find(flutter::EncodableValue(key));
  if (it == map.end()) return std::string();
  if (auto value = std::get_if<std::string>(&it->second)) return *value;
  return std::string();
}

int64_t GetInt(const flutter::EncodableMap& map, const char* key) {
  auto it = map.find(flutter::EncodableValue(key));
  if (it == map.end()) return 0;
  if (auto v = std::get_if<int32_t>(&it->second)) return *v;
  if (auto v = std::get_if<int64_t>(&it->second)) return *v;
  return 0;
}

const char* ButtonName(WPARAM code) {
  switch (code) {
    case 0: return "play";
    case 1: return "pause";
    case 2: return "next";
    case 3: return "previous";
    default: return "stop";
  }
}

}

struct SmtcPlugin::State {
  wm::SystemMediaTransportControls controls{nullptr};
  winrt::event_token button_token{};
  winrt::event_token seek_token{};
};

SmtcPlugin::SmtcPlugin(flutter::BinaryMessenger* messenger, HWND window)
    : window_(window), state_(std::make_unique<State>()) {
  channel_ = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      messenger, "scglow/smtc",
      &flutter::StandardMethodCodec::GetInstance());
  channel_->SetMethodCallHandler([this](const auto& call, auto result) {
    HandleMethodCall(call, std::move(result));
  });

  try {
    auto interop = winrt::get_activation_factory<
        wm::SystemMediaTransportControls,
        ISystemMediaTransportControlsInterop>();
    wm::SystemMediaTransportControls controls{nullptr};
    winrt::check_hresult(interop->GetForWindow(
        window_, winrt::guid_of<wm::SystemMediaTransportControls>(),
        winrt::put_abi(controls)));

    controls.IsEnabled(true);
    controls.IsPlayEnabled(true);
    controls.IsPauseEnabled(true);
    controls.IsNextEnabled(true);
    controls.IsPreviousEnabled(true);
    controls.IsStopEnabled(true);
    controls.PlaybackStatus(wm::MediaPlaybackStatus::Closed);

    HWND target = window_;
    state_->button_token = controls.ButtonPressed(
        [target](const wm::SystemMediaTransportControls&,
                 const wm::SystemMediaTransportControlsButtonPressedEventArgs&
                     args) {
          WPARAM code = 4;
          switch (args.Button()) {
            case wm::SystemMediaTransportControlsButton::Play: code = 0; break;
            case wm::SystemMediaTransportControlsButton::Pause: code = 1; break;
            case wm::SystemMediaTransportControlsButton::Next: code = 2; break;
            case wm::SystemMediaTransportControlsButton::Previous: code = 3; break;
            default: code = 4; break;
          }
          PostMessage(target, kButtonMessage, code, 0);
        });
    state_->seek_token = controls.PlaybackPositionChangeRequested(
        [target](const wm::SystemMediaTransportControls&,
                 const wm::PlaybackPositionChangeRequestedEventArgs& args) {
          auto ms = std::chrono::duration_cast<std::chrono::milliseconds>(
                        args.RequestedPlaybackPosition())
                        .count();
          PostMessage(target, kSeekMessage, 0, static_cast<LPARAM>(ms));
        });
    state_->controls = controls;
  } catch (const winrt::hresult_error& e) {
    OutputDebugStringW((L"SMTC init failed: " + e.message() + L"\n").c_str());
  }
}

SmtcPlugin::~SmtcPlugin() {
  if (state_ && state_->controls) {
    try {
      state_->controls.ButtonPressed(state_->button_token);
      state_->controls.PlaybackPositionChangeRequested(state_->seek_token);
      state_->controls.DisplayUpdater().ClearAll();
      state_->controls.IsEnabled(false);
    } catch (...) {
    }
  }
}

bool SmtcPlugin::HandleWindowMessage(UINT message, WPARAM wparam,
                                     LPARAM lparam) {
  if (message == kButtonMessage) {
    channel_->InvokeMethod(
        "button", std::make_unique<flutter::EncodableValue>(ButtonName(wparam)));
    return true;
  }
  if (message == kSeekMessage) {
    channel_->InvokeMethod("seek", std::make_unique<flutter::EncodableValue>(
                                       static_cast<int64_t>(lparam)));
    return true;
  }
  return false;
}

void SmtcPlugin::HandleMethodCall(
    const flutter::MethodCall<flutter::EncodableValue>& call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  auto controls = state_->controls;
  if (!controls) {
    result->Error("unavailable", "SMTC is not available");
    return;
  }
  const auto* args = std::get_if<flutter::EncodableMap>(call.arguments());
  if (!args) {
    result->Error("bad_args", "Expected a map");
    return;
  }
  try {
    const std::string& method = call.method_name();
    if (method == "setMetadata") {
      auto updater = controls.DisplayUpdater();
      updater.AppMediaId(kAppUserModelId);
      updater.Type(wm::MediaPlaybackType::Music);
      auto music = updater.MusicProperties();
      music.Title(winrt::hstring(ToWide(GetString(*args, "title"))));
      music.Artist(winrt::hstring(ToWide(GetString(*args, "artist"))));
      auto art = GetString(*args, "artUrl");
      if (!art.empty()) {
        updater.Thumbnail(
            winrt::Windows::Storage::Streams::RandomAccessStreamReference::
                CreateFromUri(wf::Uri(winrt::hstring(ToWide(art)))));
      } else {
        updater.Thumbnail(nullptr);
      }
      updater.Update();
    } else if (method == "setStatus") {
      auto status = GetString(*args, "status");
      controls.PlaybackStatus(
          status == "playing"   ? wm::MediaPlaybackStatus::Playing
          : status == "paused"  ? wm::MediaPlaybackStatus::Paused
                                : wm::MediaPlaybackStatus::Stopped);
    } else if (method == "setTimeline") {
      auto position = std::chrono::milliseconds(GetInt(*args, "positionMs"));
      auto duration = std::chrono::milliseconds(GetInt(*args, "durationMs"));
      wm::SystemMediaTransportControlsTimelineProperties timeline;
      timeline.StartTime(wf::TimeSpan(0));
      timeline.MinSeekTime(wf::TimeSpan(0));
      timeline.EndTime(duration);
      timeline.MaxSeekTime(duration);
      timeline.Position(position);
      controls.UpdateTimelineProperties(timeline);
    } else {
      result->NotImplemented();
      return;
    }
    result->Success();
  } catch (const winrt::hresult_error& e) {
    result->Error("smtc_error", winrt::to_string(e.message()));
  }
}
