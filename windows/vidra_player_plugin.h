#ifndef FLUTTER_PLUGIN_VIDRA_PLAYER_PLUGIN_H_
#define FLUTTER_PLUGIN_VIDRA_PLAYER_PLUGIN_H_

#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>

#include <memory>

namespace vidra_player {

class VidraPlayerPlugin : public flutter::Plugin {
 public:
  static void RegisterWithRegistrar(flutter::PluginRegistrarWindows *registrar);

  VidraPlayerPlugin();

  virtual ~VidraPlayerPlugin();

  // Disallow copy and assign.
  VidraPlayerPlugin(const VidraPlayerPlugin&) = delete;
  VidraPlayerPlugin& operator=(const VidraPlayerPlugin&) = delete;

  // Called when a method is called on this plugin's channel from Dart.
  void HandleMethodCall(
      const flutter::MethodCall<flutter::EncodableValue> &method_call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);
};

}  // namespace vidra_player

#endif  // FLUTTER_PLUGIN_VIDRA_PLAYER_PLUGIN_H_
