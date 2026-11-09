// The Windows BLE central behind lib/ble/windows_ble_central.dart.
//
// Threading: method calls arrive on the platform thread. Every WinRT call
// that can block runs in a C++/WinRT coroutine after
// winrt::resume_background(), on a thread-pool (MTA) thread; WinRT events
// (advertisements, notifications, connection and radio changes) arrive on
// thread-pool threads too. Results and events go back to the platform
// thread through PlatformDispatcher, the only place that touches the
// Flutter channels. Device state is shared between threads under mutex_.
//
// A device is connected by Bluetooth address, without a scan:
// BluetoothLEDevice::FromBluetoothAddressAsync (only when Windows has
// forgotten the device does a short watcher run first), a GattSession with
// MaintainConnection, then an uncached service query, which is what makes
// Windows open the link. Windows closes the link once every service,
// session and device object is closed, which Close() does on a drop and on
// disconnect. Nothing reconnects here: the Dart side retries.

#include "ble_central_channel.h"

#include <flutter/encodable_value.h>
#include <flutter/event_channel.h>
#include <flutter/event_sink.h>
#include <flutter/event_stream_handler_functions.h>
#include <flutter/method_channel.h>
#include <flutter/method_result.h>
#include <flutter/standard_method_codec.h>

#include <winrt/Windows.Devices.Bluetooth.Advertisement.h>
#include <winrt/Windows.Devices.Bluetooth.GenericAttributeProfile.h>
#include <winrt/Windows.Devices.Bluetooth.h>
#include <winrt/Windows.Devices.Radios.h>
#include <winrt/Windows.Foundation.Collections.h>
#include <winrt/Windows.Foundation.h>
#include <winrt/Windows.Storage.Streams.h>

#include <chrono>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <atomic>
#include <map>
#include <mutex>
#include <string>
#include <utility>
#include <vector>

#include "platform_dispatcher.h"

namespace {

namespace wf = winrt::Windows::Foundation;
namespace bt = winrt::Windows::Devices::Bluetooth;
namespace adv = winrt::Windows::Devices::Bluetooth::Advertisement;
namespace gatt = winrt::Windows::Devices::Bluetooth::GenericAttributeProfile;
namespace radios = winrt::Windows::Devices::Radios;
namespace streams = winrt::Windows::Storage::Streams;

using flutter::EncodableList;
using flutter::EncodableMap;
using flutter::EncodableValue;
using MethodResultPtr = std::shared_ptr<flutter::MethodResult<EncodableValue>>;

constexpr char kMethodChannel[] = "nl.despaankamer.ccrlogger/ble";
constexpr char kEventChannel[] = "nl.despaankamer.ccrlogger/ble/events";

// The PlatformException codes; the same strings as the kBleError* codes in
// lib/ble/ble_central.dart.
constexpr char kErrUnavailable[] = "unavailable";
constexpr char kErrNotFound[] = "notFound";
constexpr char kErrUnreachable[] = "unreachable";
constexpr char kErrNotConnected[] = "notConnected";
constexpr char kErrGatt[] = "gatt";
constexpr char kErrWriteFailed[] = "writeFailed";
constexpr char kErrScanFailed[] = "scanFailed";
constexpr char kErrBadArgs[] = "badArgs";
constexpr char kErrUnknown[] = "unknown";

constexpr int32_t kDefaultMtu = 23;

// Lower case, 128-bit, as the Dart side's normalizeBleUuid.
std::string GuidToString(const winrt::guid& g) {
  char buf[40];
  std::snprintf(buf, sizeof(buf),
                "%08x-%04x-%04x-%02x%02x-%02x%02x%02x%02x%02x%02x",
                static_cast<unsigned int>(g.Data1),
                static_cast<unsigned int>(g.Data2),
                static_cast<unsigned int>(g.Data3),
                static_cast<unsigned int>(g.Data4[0]),
                static_cast<unsigned int>(g.Data4[1]),
                static_cast<unsigned int>(g.Data4[2]),
                static_cast<unsigned int>(g.Data4[3]),
                static_cast<unsigned int>(g.Data4[4]),
                static_cast<unsigned int>(g.Data4[5]),
                static_cast<unsigned int>(g.Data4[6]),
                static_cast<unsigned int>(g.Data4[7]));
  return buf;
}

// The device id: the 48-bit Bluetooth address as 12 upper-case hex digits.
std::string FormatAddress(uint64_t address) {
  char buf[24];
  std::snprintf(buf, sizeof(buf), "%012llX",
                static_cast<unsigned long long>(address));
  return buf;
}

bool ParseAddress(const std::string& id, uint64_t& address) {
  if (id.size() != 12) return false;
  for (char c : id) {
    const bool hex = (c >= '0' && c <= '9') || (c >= 'a' && c <= 'f') ||
                     (c >= 'A' && c <= 'F');
    if (!hex) return false;
  }
  address = std::strtoull(id.c_str(), nullptr, 16);
  return true;
}

const EncodableValue* Arg(const EncodableMap* args, const char* key) {
  if (!args) return nullptr;
  auto it = args->find(EncodableValue(key));
  return it == args->end() ? nullptr : &it->second;
}

std::string StringArg(const EncodableMap* args, const char* key) {
  const EncodableValue* v = Arg(args, key);
  if (!v) return {};
  if (const auto* s = std::get_if<std::string>(v)) return *s;
  return {};
}

bool BoolArg(const EncodableMap* args, const char* key) {
  const EncodableValue* v = Arg(args, key);
  if (!v) return false;
  if (const auto* b = std::get_if<bool>(v)) return *b;
  return false;
}

std::vector<uint8_t> BytesArg(const EncodableMap* args, const char* key) {
  const EncodableValue* v = Arg(args, key);
  if (!v) return {};
  if (const auto* b = std::get_if<std::vector<uint8_t>>(v)) return *b;
  return {};
}

bool HasProperty(gatt::GattCharacteristicProperties props,
                 gatt::GattCharacteristicProperties flag) {
  return (static_cast<uint32_t>(props) & static_cast<uint32_t>(flag)) != 0;
}

// The bit set the Dart side decodes: 1 read, 2 write, 4 write without
// response, 8 notify, 16 indicate.
int32_t PropertyBits(gatt::GattCharacteristicProperties p) {
  using P = gatt::GattCharacteristicProperties;
  int32_t bits = 0;
  if (HasProperty(p, P::Read)) bits |= 1;
  if (HasProperty(p, P::Write)) bits |= 2;
  if (HasProperty(p, P::WriteWithoutResponse)) bits |= 4;
  if (HasProperty(p, P::Notify)) bits |= 8;
  if (HasProperty(p, P::Indicate)) bits |= 16;
  return bits;
}

const char* RadioStateName(radios::RadioState s) {
  switch (s) {
    case radios::RadioState::On:
      return "on";
    case radios::RadioState::Off:
    case radios::RadioState::Disabled:
      return "off";
    default:
      return "unknown";
  }
}

std::string GattStatusName(gatt::GattCommunicationStatus s) {
  switch (s) {
    case gatt::GattCommunicationStatus::Success:
      return "success";
    case gatt::GattCommunicationStatus::Unreachable:
      return "unreachable";
    case gatt::GattCommunicationStatus::ProtocolError:
      return "protocol error";
    case gatt::GattCommunicationStatus::AccessDenied:
      return "access denied";
    default:
      return "status " + std::to_string(static_cast<int>(s));
  }
}

std::string BluetoothErrorName(bt::BluetoothError e) {
  switch (e) {
    case bt::BluetoothError::Success:
      return "success";
    case bt::BluetoothError::RadioNotAvailable:
      return "radio not available";
    case bt::BluetoothError::ResourceInUse:
      return "resource in use";
    case bt::BluetoothError::DeviceNotConnected:
      return "device not connected";
    case bt::BluetoothError::DisabledByPolicy:
      return "disabled by policy";
    case bt::BluetoothError::DisabledByUser:
      return "disabled by user";
    case bt::BluetoothError::NotSupported:
      return "not supported";
    case bt::BluetoothError::ConsentRequired:
      return "consent required";
    default:
      return "error " + std::to_string(static_cast<int>(e));
  }
}

std::string HresultMessage(const winrt::hresult_error& e) {
  char code[16];
  std::snprintf(code, sizeof(code), "0x%08X",
                static_cast<unsigned int>(e.code().value));
  std::string message = winrt::to_string(e.message());
  return message.empty() ? std::string(code) : message + " (" + code + ")";
}

std::string CharKey(const std::string& service, const std::string& chr) {
  return service + "|" + chr;
}

// Waits up to [timeout] for an advertisement from [address], with a watcher
// of its own, and returns the address type it advertised with (-1 when none
// came). FromBluetoothAddressAsync returns null for a device Windows has not
// seen lately (an unpaired device after a restart, say); seeing one
// advertisement is enough for it to find the device again.
wf::IAsyncOperation<int32_t> WaitForAdvertisement(uint64_t address,
                                                  wf::TimeSpan timeout) {
  // Shared with the handler, so a late callback never signals a closed
  // (and possibly reused) handle.
  auto seen = std::make_shared<winrt::handle>(
      CreateEventW(nullptr, TRUE, FALSE, nullptr));
  if (!*seen) co_return -1;
  auto type = std::make_shared<std::atomic<int32_t>>(-1);
  adv::BluetoothLEAdvertisementWatcher watcher;
  watcher.ScanningMode(adv::BluetoothLEScanningMode::Active);
  winrt::event_token token = watcher.Received(
      [seen, type, address](
          const adv::BluetoothLEAdvertisementWatcher&,
          const adv::BluetoothLEAdvertisementReceivedEventArgs& args) {
        if (args.BluetoothAddress() != address) return;
        type->store(static_cast<int32_t>(args.BluetoothAddressType()));
        SetEvent(seen->get());
      });
  watcher.Start();
  const bool found = co_await winrt::resume_on_signal(seen->get(), timeout);
  watcher.Received(token);
  watcher.Stop();
  co_return found ? type->load() : -1;
}

// One connected device and everything Windows holds open for it.
struct Device {
  std::string id;
  bt::BluetoothLEDevice device{nullptr};
  gatt::GattSession session{nullptr};
  std::vector<gatt::GattDeviceService> services;
  // Keyed by CharKey(service, characteristic). Guarded by Impl::mutex_.
  std::map<std::string, gatt::GattCharacteristic> chars;
  std::map<std::string, winrt::event_token> value_tokens;
  winrt::event_token status_token{};
  winrt::event_token mtu_token{};
};

}  // namespace

class BleCentralChannel::Impl : public std::enable_shared_from_this<Impl> {
 public:
  explicit Impl(flutter::BinaryMessenger* messenger)
      : messenger_(messenger), dispatcher_(PlatformDispatcher::Create()) {}

  // Platform thread, right after construction (needs weak_from_this()).
  void Start() {
    std::weak_ptr<Impl> weak = weak_from_this();
    methods_ = std::make_unique<flutter::MethodChannel<EncodableValue>>(
        messenger_, kMethodChannel,
        &flutter::StandardMethodCodec::GetInstance());
    methods_->SetMethodCallHandler(
        [weak](const flutter::MethodCall<EncodableValue>& call,
               std::unique_ptr<flutter::MethodResult<EncodableValue>> result) {
          auto self = weak.lock();
          if (!self) {
            result->Error(kErrUnavailable, "BLE channel closed");
            return;
          }
          self->HandleMethodCall(call, MethodResultPtr(std::move(result)));
        });

    events_ = std::make_unique<flutter::EventChannel<EncodableValue>>(
        messenger_, kEventChannel,
        &flutter::StandardMethodCodec::GetInstance());
    events_->SetStreamHandler(
        std::make_unique<flutter::StreamHandlerFunctions<EncodableValue>>(
            [weak](const EncodableValue* arguments,
                   std::unique_ptr<flutter::EventSink<EncodableValue>>&&
                       events)
                -> std::unique_ptr<
                    flutter::StreamHandlerError<EncodableValue>> {
              if (auto self = weak.lock()) self->sink_ = std::move(events);
              return nullptr;
            },
            [weak](const EncodableValue* arguments)
                -> std::unique_ptr<
                    flutter::StreamHandlerError<EncodableValue>> {
              if (auto self = weak.lock()) self->sink_.reset();
              return nullptr;
            }));
  }

  // Platform thread. Stops the scan, closes every device and unhooks the
  // channels; results and events still in flight are dropped.
  void Shutdown() {
    StopScan();
    std::map<std::string, std::shared_ptr<Device>> devices;
    {
      std::lock_guard<std::mutex> lock(mutex_);
      devices.swap(devices_);
      if (radio_) {
        try {
          radio_.StateChanged(radio_token_);
        } catch (...) {
        }
        radio_ = nullptr;
      }
    }
    for (auto& entry : devices) Close(entry.second);
    if (methods_) methods_->SetMethodCallHandler(nullptr);
    if (events_) events_->SetStreamHandler(nullptr);
    sink_.reset();
    dispatcher_->Shutdown();
    methods_.reset();
    events_.reset();
  }

 private:
  // -------------------------------------------------------------------------
  // Dispatch (platform thread)
  // -------------------------------------------------------------------------

  void HandleMethodCall(const flutter::MethodCall<EncodableValue>& call,
                        MethodResultPtr result) {
    const std::string& method = call.method_name();
    const auto* args = std::get_if<EncodableMap>(call.arguments());
    auto self = shared_from_this();

    if (method == "adapterState") {
      AdapterState(self, result);
      return;
    }
    if (method == "startScan") {
      StartScan(result);
      return;
    }
    if (method == "stopScan") {
      StopScan();
      result->Success();
      return;
    }

    uint64_t address = 0;
    if (!ParseAddress(StringArg(args, "id"), address)) {
      result->Error(kErrBadArgs, "Bad device id");
      return;
    }
    const std::string id = FormatAddress(address);

    if (method == "connect") {
      Connect(self, id, address, result);
    } else if (method == "discover") {
      Discover(self, id, result);
    } else if (method == "setNotify") {
      SetNotify(self, id, StringArg(args, "service"),
                StringArg(args, "characteristic"), BoolArg(args, "enable"),
                result);
    } else if (method == "write") {
      Write(self, id, StringArg(args, "service"),
            StringArg(args, "characteristic"), BytesArg(args, "value"),
            BoolArg(args, "withoutResponse"), result);
    } else if (method == "disconnect") {
      Disconnect(id);
      result->Success();
    } else {
      result->NotImplemented();
    }
  }

  // Any thread.
  void Reply(MethodResultPtr result, EncodableValue value) {
    dispatcher_->Post([result, value]() { result->Success(value); });
  }

  void ReplyOk(MethodResultPtr result) {
    dispatcher_->Post([result]() { result->Success(); });
  }

  void ReplyError(MethodResultPtr result, std::string code,
                  std::string message) {
    dispatcher_->Post(
        [result, code, message]() { result->Error(code, message); });
  }

  void Emit(EncodableMap event) {
    std::weak_ptr<Impl> weak = weak_from_this();
    EncodableValue value(std::move(event));
    dispatcher_->Post([weak, value]() {
      auto self = weak.lock();
      if (self && self->sink_) self->sink_->Success(value);
    });
  }

  // -------------------------------------------------------------------------
  // Adapter
  // -------------------------------------------------------------------------

  winrt::fire_and_forget AdapterState(std::shared_ptr<Impl> self,
                                      MethodResultPtr result) {
    co_await winrt::resume_background();
    std::string state = "unknown";
    try {
      bt::BluetoothAdapter adapter =
          co_await bt::BluetoothAdapter::GetDefaultAsync();
      if (!adapter || !adapter.IsLowEnergySupported()) {
        state = "unavailable";
      } else {
        radios::Radio radio = co_await adapter.GetRadioAsync();
        if (radio) {
          state = RadioStateName(radio.State());
          self->WatchRadio(radio);
        }
      }
    } catch (const winrt::hresult_error& e) {
      OutputDebugStringA(("BLE: adapter query failed: " + HresultMessage(e) +
                          "\n")
                             .c_str());
      state = "unavailable";
    } catch (...) {
      state = "unavailable";
    }
    self->Reply(result, EncodableValue(state));
  }

  // Reports radio on/off changes as "adapter" events. Once.
  void WatchRadio(const radios::Radio& radio) {
    std::lock_guard<std::mutex> lock(mutex_);
    if (radio_) return;
    radio_ = radio;
    std::weak_ptr<Impl> weak = weak_from_this();
    radio_token_ = radio_.StateChanged(
        [weak](const radios::Radio& sender, const wf::IInspectable&) {
          auto self = weak.lock();
          if (!self) return;
          self->Emit(EncodableMap{
              {EncodableValue("event"), EncodableValue("adapter")},
              {EncodableValue("state"),
               EncodableValue(RadioStateName(sender.State()))},
          });
        });
  }

  // -------------------------------------------------------------------------
  // Scan (platform thread; the watcher calls are not blocking)
  // -------------------------------------------------------------------------

  void StartScan(MethodResultPtr result) {
    try {
      std::lock_guard<std::mutex> lock(mutex_);
      if (!watcher_) {
        watcher_ = adv::BluetoothLEAdvertisementWatcher();
        watcher_.ScanningMode(adv::BluetoothLEScanningMode::Active);
        std::weak_ptr<Impl> weak = weak_from_this();
        received_token_ = watcher_.Received(
            [weak](const adv::BluetoothLEAdvertisementWatcher&,
                   const adv::BluetoothLEAdvertisementReceivedEventArgs&
                       args) {
              auto self = weak.lock();
              if (!self) return;
              {
                std::lock_guard<std::mutex> lock(self->mutex_);
                self->address_types_[args.BluetoothAddress()] =
                    args.BluetoothAddressType();
              }
              EncodableList services;
              for (const winrt::guid& g : args.Advertisement().ServiceUuids()) {
                services.push_back(EncodableValue(GuidToString(g)));
              }
              self->Emit(EncodableMap{
                  {EncodableValue("event"), EncodableValue("scan")},
                  {EncodableValue("id"),
                   EncodableValue(FormatAddress(args.BluetoothAddress()))},
                  {EncodableValue("name"),
                   EncodableValue(
                       winrt::to_string(args.Advertisement().LocalName()))},
                  {EncodableValue("rssi"),
                   EncodableValue(
                       static_cast<int32_t>(args.RawSignalStrengthInDBm()))},
                  {EncodableValue("services"), EncodableValue(services)},
              });
            });
        stopped_token_ = watcher_.Stopped(
            [weak](const adv::BluetoothLEAdvertisementWatcher&,
                   const adv::BluetoothLEAdvertisementWatcherStoppedEventArgs&
                       args) {
              // A stop we asked for needs no event; only a watcher that
              // stopped by itself (radio off, say) is reported.
              if (args.Error() == bt::BluetoothError::Success) return;
              auto self = weak.lock();
              if (!self) return;
              self->Emit(EncodableMap{
                  {EncodableValue("event"), EncodableValue("scanStopped")},
                  {EncodableValue("error"),
                   EncodableValue(BluetoothErrorName(args.Error()))},
              });
            });
      }
      if (watcher_.Status() != adv::BluetoothLEAdvertisementWatcherStatus::
                                   Started) {
        watcher_.Start();
      }
      if (watcher_.Status() ==
          adv::BluetoothLEAdvertisementWatcherStatus::Aborted) {
        result->Error(kErrScanFailed, "Scan aborted (is Bluetooth on?)");
        return;
      }
    } catch (const winrt::hresult_error& e) {
      result->Error(kErrScanFailed, HresultMessage(e));
      return;
    }
    result->Success();
  }

  void StopScan() {
    std::lock_guard<std::mutex> lock(mutex_);
    if (!watcher_) return;
    try {
      watcher_.Received(received_token_);
      watcher_.Stopped(stopped_token_);
      watcher_.Stop();
    } catch (...) {
    }
    watcher_ = nullptr;
  }

  // -------------------------------------------------------------------------
  // Connection
  // -------------------------------------------------------------------------

  std::shared_ptr<Device> Find(const std::string& id) {
    std::lock_guard<std::mutex> lock(mutex_);
    auto it = devices_.find(id);
    return it == devices_.end() ? nullptr : it->second;
  }

  winrt::fire_and_forget Connect(std::shared_ptr<Impl> self, std::string id,
                                 uint64_t address, MethodResultPtr result) {
    uint64_t generation = 0;
    {
      std::lock_guard<std::mutex> lock(self->mutex_);
      auto it = self->devices_.find(id);
      if (it != self->devices_.end()) {
        // Already connected: report the MTU in use.
        const auto& d = it->second;
        const int32_t mtu =
            d->session ? static_cast<int32_t>(d->session.MaxPduSize())
                       : kDefaultMtu;
        self->Reply(result, EncodableValue(EncodableMap{
                                {EncodableValue("mtu"), EncodableValue(mtu)},
                            }));
        co_return;
      }
      generation = ++self->generations_[id];
    }

    co_await winrt::resume_background();

    auto d = std::make_shared<Device>();
    d->id = id;
    std::string error_code;
    std::string error_message;
    try {
      // The type the scan saw, else public first and then random.
      bool known = false;
      bt::BluetoothAddressType type = bt::BluetoothAddressType::Public;
      {
        std::lock_guard<std::mutex> lock(self->mutex_);
        auto it = self->address_types_.find(address);
        if (it != self->address_types_.end()) {
          known = true;
          type = it->second;
        }
      }
      if (known) {
        d->device = co_await bt::BluetoothLEDevice::FromBluetoothAddressAsync(
            address, type);
      } else {
        d->device = co_await bt::BluetoothLEDevice::FromBluetoothAddressAsync(
            address, bt::BluetoothAddressType::Public);
        if (!d->device) {
          d->device =
              co_await bt::BluetoothLEDevice::FromBluetoothAddressAsync(
                  address, bt::BluetoothAddressType::Random);
        }
      }
      if (!d->device) {
        const int32_t seen =
            co_await WaitForAdvertisement(address, std::chrono::seconds(5));
        if (seen >= 0) {
          const auto seen_type = static_cast<bt::BluetoothAddressType>(seen);
          {
            std::lock_guard<std::mutex> lock(self->mutex_);
            self->address_types_[address] = seen_type;
          }
          d->device =
              co_await bt::BluetoothLEDevice::FromBluetoothAddressAsync(
                  address, seen_type);
        }
      }
      if (!d->device) {
        error_code = kErrNotFound;
        error_message = "Device not found";
      } else {
        d->session = co_await gatt::GattSession::FromDeviceIdAsync(
            d->device.BluetoothDeviceId());
        if (d->session) d->session.MaintainConnection(true);
        gatt::GattDeviceServicesResult services =
            co_await d->device.GetGattServicesAsync(
                bt::BluetoothCacheMode::Uncached);
        if (services.Status() != gatt::GattCommunicationStatus::Success) {
          error_code = kErrUnreachable;
          error_message =
              "Device unreachable (" + GattStatusName(services.Status()) + ")";
        } else {
          for (const auto& s : services.Services()) d->services.push_back(s);
        }
      }
    } catch (const winrt::hresult_error& e) {
      error_code = kErrUnreachable;
      error_message = HresultMessage(e);
    } catch (...) {
      error_code = kErrUnknown;
      error_message = "Connect failed";
    }
    if (!error_code.empty()) {
      Close(d);
      self->ReplyError(result, error_code, error_message);
      co_return;
    }

    std::weak_ptr<Impl> weak = self;
    try {
      d->status_token = d->device.ConnectionStatusChanged(
          [weak, id](const bt::BluetoothLEDevice& sender,
                     const wf::IInspectable&) {
            if (sender.ConnectionStatus() !=
                bt::BluetoothConnectionStatus::Disconnected) {
              return;
            }
            if (auto self = weak.lock()) self->OnDropped(id);
          });
      if (d->session) {
        d->mtu_token = d->session.MaxPduSizeChanged(
            [weak, id](const gatt::GattSession& sender,
                       const wf::IInspectable&) {
              auto self = weak.lock();
              if (!self) return;
              self->Emit(EncodableMap{
                  {EncodableValue("event"), EncodableValue("mtu")},
                  {EncodableValue("id"), EncodableValue(id)},
                  {EncodableValue("mtu"),
                   EncodableValue(static_cast<int32_t>(sender.MaxPduSize()))},
              });
            });
      }
    } catch (const winrt::hresult_error& e) {
      Close(d);
      self->ReplyError(result, kErrGatt, HresultMessage(e));
      co_return;
    }

    const int32_t mtu = d->session
                            ? static_cast<int32_t>(d->session.MaxPduSize())
                            : kDefaultMtu;
    bool stale = false;
    {
      std::lock_guard<std::mutex> lock(self->mutex_);
      // A disconnect (or a newer connect) came while this one ran.
      stale = self->generations_[id] != generation;
      if (!stale) self->devices_[id] = d;
    }
    if (stale) {
      Close(d);
      self->ReplyError(result, kErrNotConnected, "Connect cancelled");
      co_return;
    }
    self->Reply(result, EncodableValue(EncodableMap{
                            {EncodableValue("mtu"), EncodableValue(mtu)},
                        }));
  }

  // A thread-pool thread, from ConnectionStatusChanged.
  void OnDropped(const std::string& id) {
    std::shared_ptr<Device> d;
    {
      std::lock_guard<std::mutex> lock(mutex_);
      auto it = devices_.find(id);
      if (it == devices_.end()) return;
      d = it->second;
      devices_.erase(it);
    }
    Emit(EncodableMap{
        {EncodableValue("event"), EncodableValue("connection")},
        {EncodableValue("id"), EncodableValue(id)},
        {EncodableValue("connected"), EncodableValue(false)},
    });
    // Not from inside the device's own event handler.
    CloseLater(shared_from_this(), d);
  }

  // Platform thread.
  void Disconnect(const std::string& id) {
    std::shared_ptr<Device> d;
    {
      std::lock_guard<std::mutex> lock(mutex_);
      ++generations_[id];
      auto it = devices_.find(id);
      if (it != devices_.end()) {
        d = it->second;
        devices_.erase(it);
      }
    }
    if (d) CloseLater(shared_from_this(), d);
  }

  winrt::fire_and_forget CloseLater(std::shared_ptr<Impl> self,
                                    std::shared_ptr<Device> d) {
    co_await winrt::resume_background();
    self->Close(d);
  }

  // Revokes the handlers and closes every WinRT object of [d], which lets
  // Windows drop the link. Never throws.
  void Close(const std::shared_ptr<Device>& d) {
    if (!d) return;
    std::map<std::string, gatt::GattCharacteristic> chars;
    std::map<std::string, winrt::event_token> tokens;
    {
      std::lock_guard<std::mutex> lock(mutex_);
      chars.swap(d->chars);
      tokens.swap(d->value_tokens);
    }
    for (auto& entry : tokens) {
      auto it = chars.find(entry.first);
      if (it == chars.end()) continue;
      try {
        it->second.ValueChanged(entry.second);
      } catch (...) {
      }
    }
    try {
      if (d->device) d->device.ConnectionStatusChanged(d->status_token);
    } catch (...) {
    }
    try {
      if (d->session) d->session.MaxPduSizeChanged(d->mtu_token);
    } catch (...) {
    }
    for (auto& s : d->services) {
      try {
        s.Close();
      } catch (...) {
      }
    }
    d->services.clear();
    try {
      if (d->session) d->session.Close();
    } catch (...) {
    }
    d->session = nullptr;
    try {
      if (d->device) d->device.Close();
    } catch (...) {
    }
    d->device = nullptr;
  }

  // -------------------------------------------------------------------------
  // GATT
  // -------------------------------------------------------------------------

  winrt::fire_and_forget Discover(std::shared_ptr<Impl> self, std::string id,
                                  MethodResultPtr result) {
    auto d = self->Find(id);
    if (!d) {
      self->ReplyError(result, kErrNotConnected, "Not connected");
      co_return;
    }
    co_await winrt::resume_background();

    EncodableList out;
    std::string error;
    bool any_ok = false;
    try {
      for (const auto& s : d->services) {
        gatt::GattCharacteristicsResult r =
            co_await s.GetCharacteristicsAsync(
                bt::BluetoothCacheMode::Uncached);
        if (r.Status() != gatt::GattCommunicationStatus::Success) {
          // Some services (GAP, say) refuse access; skip them.
          if (error.empty()) error = GattStatusName(r.Status());
          continue;
        }
        any_ok = true;
        const std::string service = GuidToString(s.Uuid());
        for (const auto& c : r.Characteristics()) {
          const std::string chr = GuidToString(c.Uuid());
          {
            std::lock_guard<std::mutex> lock(self->mutex_);
            d->chars.insert_or_assign(CharKey(service, chr), c);
          }
          out.push_back(EncodableValue(EncodableMap{
              {EncodableValue("service"), EncodableValue(service)},
              {EncodableValue("characteristic"), EncodableValue(chr)},
              {EncodableValue("properties"),
               EncodableValue(PropertyBits(c.CharacteristicProperties()))},
          }));
        }
      }
    } catch (const winrt::hresult_error& e) {
      self->ReplyError(result, kErrGatt, HresultMessage(e));
      co_return;
    }
    if (!any_ok && !d->services.empty()) {
      self->ReplyError(result, kErrGatt, "Discovery failed (" + error + ")");
      co_return;
    }
    self->Reply(result, EncodableValue(out));
  }

  // The characteristic, or a null one.
  gatt::GattCharacteristic FindChar(const std::shared_ptr<Device>& d,
                                    const std::string& key) {
    std::lock_guard<std::mutex> lock(mutex_);
    auto it = d->chars.find(key);
    return it == d->chars.end() ? gatt::GattCharacteristic{nullptr}
                                : it->second;
  }

  winrt::fire_and_forget SetNotify(std::shared_ptr<Impl> self, std::string id,
                                   std::string service, std::string chr,
                                   bool enable, MethodResultPtr result) {
    auto d = self->Find(id);
    const std::string key = CharKey(service, chr);
    gatt::GattCharacteristic c =
        d ? self->FindChar(d, key) : gatt::GattCharacteristic{nullptr};
    if (!c) {
      self->ReplyError(result, kErrNotConnected,
                       "Not connected, or characteristic not discovered");
      co_return;
    }
    co_await winrt::resume_background();

    std::string error;
    try {
      using V = gatt::GattClientCharacteristicConfigurationDescriptorValue;
      const auto props = c.CharacteristicProperties();
      V value = V::None;
      if (enable) {
        value = HasProperty(props, gatt::GattCharacteristicProperties::Notify)
                    ? V::Notify
                    : V::Indicate;
        self->HookValueChanged(d, key, id, service, chr, c);
      }
      gatt::GattCommunicationStatus status =
          co_await c.WriteClientCharacteristicConfigurationDescriptorAsync(
              value);
      if (status != gatt::GattCommunicationStatus::Success) {
        error = "Subscribe failed (" + GattStatusName(status) + ")";
      }
      if (!enable) self->UnhookValueChanged(d, key, c);
    } catch (const winrt::hresult_error& e) {
      error = HresultMessage(e);
    }
    if (!error.empty()) {
      self->ReplyError(result, kErrGatt, error);
      co_return;
    }
    self->ReplyOk(result);
  }

  // Forwards notifications of [c] as "notify" events. Once per
  // characteristic.
  void HookValueChanged(const std::shared_ptr<Device>& d,
                        const std::string& key, const std::string& id,
                        const std::string& service, const std::string& chr,
                        const gatt::GattCharacteristic& c) {
    std::lock_guard<std::mutex> lock(mutex_);
    if (d->value_tokens.count(key)) return;
    std::weak_ptr<Impl> weak = weak_from_this();
    d->value_tokens[key] = c.ValueChanged(
        [weak, id, service, chr](const gatt::GattCharacteristic&,
                                 const gatt::GattValueChangedEventArgs& args) {
          auto self = weak.lock();
          if (!self) return;
          streams::IBuffer buffer = args.CharacteristicValue();
          std::vector<uint8_t> bytes(buffer.Length());
          if (!bytes.empty()) {
            streams::DataReader reader = streams::DataReader::FromBuffer(buffer);
            reader.ReadBytes(bytes);
          }
          self->Emit(EncodableMap{
              {EncodableValue("event"), EncodableValue("notify")},
              {EncodableValue("id"), EncodableValue(id)},
              {EncodableValue("service"), EncodableValue(service)},
              {EncodableValue("characteristic"), EncodableValue(chr)},
              {EncodableValue("value"), EncodableValue(bytes)},
          });
        });
  }

  void UnhookValueChanged(const std::shared_ptr<Device>& d,
                          const std::string& key,
                          const gatt::GattCharacteristic& c) {
    std::lock_guard<std::mutex> lock(mutex_);
    auto it = d->value_tokens.find(key);
    if (it == d->value_tokens.end()) return;
    try {
      c.ValueChanged(it->second);
    } catch (...) {
    }
    d->value_tokens.erase(it);
  }

  winrt::fire_and_forget Write(std::shared_ptr<Impl> self, std::string id,
                               std::string service, std::string chr,
                               std::vector<uint8_t> value,
                               bool without_response, MethodResultPtr result) {
    auto d = self->Find(id);
    gatt::GattCharacteristic c = d ? self->FindChar(d, CharKey(service, chr))
                                   : gatt::GattCharacteristic{nullptr};
    if (!c) {
      self->ReplyError(result, kErrNotConnected,
                       "Not connected, or characteristic not discovered");
      co_return;
    }
    co_await winrt::resume_background();

    std::string error;
    try {
      const auto props = c.CharacteristicProperties();
      // Follow what the characteristic supports when the caller's choice
      // isn't possible.
      bool without = without_response;
      if (without &&
          !HasProperty(props,
                       gatt::GattCharacteristicProperties::WriteWithoutResponse)) {
        without = false;
      } else if (!without &&
                 !HasProperty(props, gatt::GattCharacteristicProperties::Write)) {
        without = true;
      }
      streams::DataWriter writer;
      writer.WriteBytes(value);
      streams::IBuffer buffer = writer.DetachBuffer();
      gatt::GattWriteResult r = co_await c.WriteValueWithResultAsync(
          buffer, without ? gatt::GattWriteOption::WriteWithoutResponse
                          : gatt::GattWriteOption::WriteWithResponse);
      if (r.Status() != gatt::GattCommunicationStatus::Success) {
        error = "Write failed (" + GattStatusName(r.Status()) + ")";
      }
    } catch (const winrt::hresult_error& e) {
      error = HresultMessage(e);
    }
    if (!error.empty()) {
      self->ReplyError(result, kErrWriteFailed, error);
      co_return;
    }
    self->ReplyOk(result);
  }

  flutter::BinaryMessenger* messenger_;
  std::shared_ptr<PlatformDispatcher> dispatcher_;
  std::unique_ptr<flutter::MethodChannel<EncodableValue>> methods_;
  std::unique_ptr<flutter::EventChannel<EncodableValue>> events_;
  // Platform thread only.
  std::unique_ptr<flutter::EventSink<EncodableValue>> sink_;

  // Guards everything below.
  std::mutex mutex_;
  std::map<std::string, std::shared_ptr<Device>> devices_;
  // Bumped by every connect and disconnect, so a connect overtaken by a
  // disconnect closes what it opened instead of keeping it.
  std::map<std::string, uint64_t> generations_;
  // The address type each scanned device advertised with. Windows only
  // finds a device with a random address (the Phomemo printers use one)
  // when it is told the type.
  std::map<uint64_t, bt::BluetoothAddressType> address_types_;
  adv::BluetoothLEAdvertisementWatcher watcher_{nullptr};
  winrt::event_token received_token_{};
  winrt::event_token stopped_token_{};
  radios::Radio radio_{nullptr};
  winrt::event_token radio_token_{};
};

BleCentralChannel::BleCentralChannel(flutter::BinaryMessenger* messenger)
    : impl_(std::make_shared<Impl>(messenger)) {
  impl_->Start();
}

BleCentralChannel::~BleCentralChannel() { impl_->Shutdown(); }
