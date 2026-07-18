#include "include/vidra_player/vidra_player_plugin_c_api.h"

#include <flutter/plugin_registrar_windows.h>

#include "vidra_player_plugin.h"

void VidraPlayerPluginCApiRegisterWithRegistrar(
    FlutterDesktopPluginRegistrarRef registrar) {
  vidra_player::VidraPlayerPlugin::RegisterWithRegistrar(
      flutter::PluginRegistrarManager::GetInstance()
          ->GetRegistrar<flutter::PluginRegistrarWindows>(registrar));
}
