#include "nearby_wifi.h"

#include <flutter/standard_method_codec.h>
#include <winrt/base.h>
#include <winrt/windows.devices.wifidirect.h>
#include <winrt/windows.foundation.h>
#include <winrt/windows.security.credentials.h>

#include <mutex>
#include <string>

using winrt::Windows::Devices::WiFiDirect::WiFiDirectAdvertisementPublisher;
using winrt::Windows::Devices::WiFiDirect::WiFiDirectAdvertisementPublisherStatus;
using winrt::Windows::Devices::WiFiDirect::WiFiDirectAdvertisementPublisherStatusChangedEventArgs;
using winrt::Windows::Devices::WiFiDirect::WiFiDirectError;
using winrt::Windows::Security::Credentials::PasswordCredential;

namespace {

constexpr char kChannelName[] = "org.glideapp.glide/nearby_wifi";

const char* StatusName(WiFiDirectAdvertisementPublisherStatus status) {
  switch (status) {
    case WiFiDirectAdvertisementPublisherStatus::Created:
      return "created";
    case WiFiDirectAdvertisementPublisherStatus::Started:
      return "started";
    case WiFiDirectAdvertisementPublisherStatus::Stopped:
      return "stopped";
    case WiFiDirectAdvertisementPublisherStatus::Aborted:
      return "aborted";
  }
  return "unknown";
}

std::string StringArgument(const flutter::EncodableMap& arguments, const char* key) {
  auto it = arguments.find(flutter::EncodableValue(key));
  if (it == arguments.end()) {
    return std::string();
  }
  const auto* value = std::get_if<std::string>(&it->second);
  return value ? *value : std::string();
}

}  // namespace

struct NearbyWifi::State {
  WiFiDirectAdvertisementPublisher publisher{nullptr};
  winrt::event_token status_token{};

  // Written from the publisher's event thread, read on the platform thread.
  std::mutex mutex;
  WiFiDirectAdvertisementPublisherStatus status = WiFiDirectAdvertisementPublisherStatus::Created;
  WiFiDirectError error = WiFiDirectError::Success;

  void Stop() {
    if (publisher == nullptr) {
      return;
    }
    try {
      publisher.StatusChanged(status_token);
      if (publisher.Status() == WiFiDirectAdvertisementPublisherStatus::Started) {
        publisher.Stop();
      }
    } catch (const winrt::hresult_error&) {
      // Already gone; nothing left to stop.
    }
    publisher = nullptr;
    std::lock_guard<std::mutex> lock(mutex);
    status = WiFiDirectAdvertisementPublisherStatus::Stopped;
    error = WiFiDirectError::Success;
  }
};

NearbyWifi::NearbyWifi(flutter::BinaryMessenger* messenger) : state_(std::make_unique<State>()) {
  channel_ = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      messenger, kChannelName, &flutter::StandardMethodCodec::GetInstance());
  channel_->SetMethodCallHandler([this](const auto& call, auto result) { HandleMethodCall(call, std::move(result)); });
}

NearbyWifi::~NearbyWifi() {
  channel_->SetMethodCallHandler(nullptr);
  // Never leave an access point behind.
  state_->Stop();
}

void NearbyWifi::HandleMethodCall(const flutter::MethodCall<flutter::EncodableValue>& call,
                                  std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  const std::string& method = call.method_name();

  if (method == "capabilities") {
    // Whether the adapter supports Wi-Fi Direct only shows when starting;
    // the Dart side then falls back to the other device hosting.
    result->Success(flutter::EncodableValue(flutter::EncodableMap{
        {flutter::EncodableValue("canHost"), flutter::EncodableValue(true)},
    }));
    return;
  }

  if (method == "startHosting") {
    const auto* arguments = std::get_if<flutter::EncodableMap>(call.arguments());
    const std::string ssid = arguments ? StringArgument(*arguments, "ssid") : std::string();
    const std::string passphrase = arguments ? StringArgument(*arguments, "passphrase") : std::string();
    if (ssid.empty() || passphrase.size() < 8) {
      result->Error("INVALID_ARGUMENT", "Missing ssid or passphrase");
      return;
    }
    state_->Stop();
    try {
      WiFiDirectAdvertisementPublisher publisher;
      auto advertisement = publisher.Advertisement();
      // Act as the group owner right away instead of waiting for a peer.
      advertisement.IsAutonomousGroupOwnerEnabled(true);
      auto legacy = advertisement.LegacySettings();
      legacy.IsEnabled(true);
      legacy.Ssid(winrt::to_hstring(ssid));
      PasswordCredential credential;
      credential.Password(winrt::to_hstring(passphrase));
      legacy.Passphrase(credential);

      State* state = state_.get();
      state->status_token = publisher.StatusChanged(
          [state](const WiFiDirectAdvertisementPublisher&, const WiFiDirectAdvertisementPublisherStatusChangedEventArgs& args) {
            std::lock_guard<std::mutex> lock(state->mutex);
            state->status = args.Status();
            state->error = args.Error();
          });
      {
        std::lock_guard<std::mutex> lock(state->mutex);
        state->status = WiFiDirectAdvertisementPublisherStatus::Created;
        state->error = WiFiDirectError::Success;
      }
      state->publisher = publisher;
      publisher.Start();
      result->Success();
    } catch (const winrt::hresult_error& e) {
      state_->Stop();
      result->Error("START_FAILED", winrt::to_string(e.message()));
    }
    return;
  }

  if (method == "hostingStatus") {
    std::lock_guard<std::mutex> lock(state_->mutex);
    result->Success(flutter::EncodableValue(flutter::EncodableMap{
        {flutter::EncodableValue("status"), flutter::EncodableValue(StatusName(state_->status))},
        {flutter::EncodableValue("error"), flutter::EncodableValue(static_cast<int32_t>(state_->error))},
    }));
    return;
  }

  if (method == "stopHosting") {
    state_->Stop();
    result->Success();
    return;
  }

  // join / leave are implemented in Dart.
  result->NotImplemented();
}
