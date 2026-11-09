cmake_minimum_required(VERSION 3.14)
project(runner LANGUAGES CXX)

# Define the application target. To change its name, change BINARY_NAME in the
# top-level CMakeLists.txt, not the value here, or `flutter run` will no longer
# work.
#
# Any new source files that you add to the application should be added here.
add_executable(${BINARY_NAME} WIN32
  "flutter_window.cpp"
  "main.cpp"
  "utils.cpp"
  "win32_window.cpp"
  "${FLUTTER_MANAGED_DIR}/generated_plugin_registrant.cc"
  "Runner.rc"
  "runner.exe.manifest"
)

# Apply the standard set of build settings. This can be removed for applications
# that need different build settings.
apply_standard_settings(${BINARY_NAME})

# Add preprocessor definitions for the build version.
target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION=\"${FLUTTER_VERSION}\"")
target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION_MAJOR=${FLUTTER_VERSION_MAJOR}")
target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION_MINOR=${FLUTTER_VERSION_MINOR}")
target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION_PATCH=${FLUTTER_VERSION_PATCH}")
target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION_BUILD=${FLUTTER_VERSION_BUILD}")

# Add the preprocessor flag for the nightly identity (see windows/CMakeLists.txt
# and app_identity.h). It has no value, so it passes cleanly to the C++ compiler
# and the resource compiler alike.
if(ANCHORLINE_NIGHTLY)
  target_compile_definitions(${BINARY_NAME} PRIVATE "ANCHORLINE_NIGHTLY")
endif()

# Disable Windows macros that collide with C++ standard library functions.
target_compile_definitions(${BINARY_NAME} PRIVATE "NOMINMAX")

# The Bluetooth LE central for the SOLO bridge and the label printer
# (ble_central_channel.cpp, see lib/ble/windows_ble_central.dart). A library of
# its own because C++/WinRT wants what apply_standard_settings takes away:
# C++20 (for its coroutines) and exceptions (_HAS_EXCEPTIONS=0 is set on the
# runner). The C++/WinRT headers ship with the Windows SDK; windowsapp.lib
# carries the WinRT imports. Warnings stay on (/W4) but are not errors, so a
# Windows SDK header warning can't break the build.
add_library(ble_central STATIC
  "ble_central_channel.cpp"
  "platform_dispatcher.cpp"
)
target_compile_features(ble_central PRIVATE cxx_std_20)
target_compile_options(ble_central PRIVATE /W4 /wd4100 /EHsc /bigobj /utf-8)
target_compile_definitions(ble_central PRIVATE "NOMINMAX"
  "$<$<CONFIG:Debug>:_DEBUG>")
target_link_libraries(ble_central PRIVATE flutter flutter_wrapper_app
  "windowsapp.lib")
target_include_directories(ble_central PRIVATE "${CMAKE_SOURCE_DIR}")
# Keep the .lib out of runner/<config>, which is the app folder the installer
# packs.
set_target_properties(ble_central PROPERTIES
  ARCHIVE_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/ble_central")

# Add dependency libraries and include directories. Add any application-specific
# dependencies here.
target_link_libraries(${BINARY_NAME} PRIVATE flutter flutter_wrapper_app)
target_link_libraries(${BINARY_NAME} PRIVATE ble_central "windowsapp.lib")
target_link_libraries(${BINARY_NAME} PRIVATE "dwmapi.lib")
target_include_directories(${BINARY_NAME} PRIVATE "${CMAKE_SOURCE_DIR}")

# Run the Flutter tool portions of the build. This must not be removed.
add_dependencies(${BINARY_NAME} flutter_assemble)
