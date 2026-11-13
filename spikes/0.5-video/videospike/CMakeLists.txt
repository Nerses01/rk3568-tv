# Step 0.5 video spike: throwaway measurement app (see main.cpp).
cmake_minimum_required(VERSION 3.16)
project(videospike LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_AUTOMOC ON)

find_package(Qt6 REQUIRED COMPONENTS Gui Quick Multimedia)
find_package(PkgConfig REQUIRED)
pkg_check_modules(GST REQUIRED IMPORTED_TARGET gstreamer-1.0 gstreamer-app-1.0 gstreamer-video-1.0 gstreamer-allocators-1.0)
pkg_check_modules(GFX REQUIRED IMPORTED_TARGET egl glesv2 libdrm)

qt_add_executable(videospike main.cpp)
qt_add_resources(videospike "qml" PREFIX "/" FILES main.qml)
target_link_libraries(videospike PRIVATE Qt6::Gui Qt6::GuiPrivate Qt6::Quick Qt6::Multimedia PkgConfig::GST PkgConfig::GFX)
