#ifndef RUNNER_NEARBY_WIFI_H_
#define RUNNER_NEARBY_WIFI_H_

#include <flutter/binary_messenger.h>
#include <flutter/encodable_value.h>
#include <flutter/method_channel.h>

#include <memory>

// Hosts the temporary network of a Nearby transfer (see the app's
// lib/provider/network/nearby/wifi_link.dart): a Wi-Fi Direct advertisement
// with legacy settings, i.e. a WPA2 access point that iPhones, Macs and other
// PCs join like any other network. Joining is done in Dart (wlanapi FFI).
//
// Channel "org.glideapp.glide/nearby_wifi":
// - capabilities -> {canHost: bool}
// - startHosting {ssid, passphrase} -> null; the access point comes up
//   asynchronously, poll hostingStatus (the Dart side waits for its address)
// - hostingStatus -> {status: "created"|"started"|"stopped"|"aborted", error: int}
// - stopHosting -> null
class NearbyWifi {
 public:
  explicit NearbyWifi(flutter::BinaryMessenger* messenger);
  ~NearbyWifi();

  NearbyWifi(const NearbyWifi&) = delete;
  NearbyWifi& operator=(const NearbyWifi&) = delete;

 private:
  struct State;

  void HandleMethodCall(const flutter::MethodCall<flutter::EncodableValue>& call,
                        std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);

  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel_;
  std::unique_ptr<State> state_;
};

#endif  // RUNNER_NEARBY_WIFI_H_
