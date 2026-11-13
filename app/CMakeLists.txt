cmake_minimum_required(VERSION 3.16)

project(rk3568-tv
    VERSION 0.1.0
    LANGUAGES CXX
)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

option(RK3568_TV_LINK_MALI "Link the Mali EGL, GLES and GBM libraries ahead of Qt (needed on the board)" ON)
option(BUILD_TESTING "Build the tests" ON)

find_package(Qt6 6.2 REQUIRED COMPONENTS Gui Network Qml Quick)
# Video: GStreamer (the board's is the vendor's 1.22, CI's Ubuntu's 1.20), and EGL and GL ES for drawing its DMA-BUFs
find_package(PkgConfig REQUIRED)
pkg_check_modules(GST REQUIRED IMPORTED_TARGET
    gstreamer-1.0
    gstreamer-allocators-1.0
    gstreamer-app-1.0
    gstreamer-tag-1.0
    gstreamer-video-1.0
)
pkg_check_modules(GFX REQUIRED IMPORTED_TARGET
    egl
    glesv2
    libdrm
)

# Qt 6.2 has no qt_standard_project_setup(); this is the part of it the app needs.
set(CMAKE_AUTOMOC ON)

add_compile_options(-Wall -Wextra)

# The UI: its QML and the C++ types that QML uses, as a static QML module, so that the app and the tests share it.
# Its resources go under /qt/qml, Qt 6.5's default; Qt 6.2 needs that import path added (src/main.cpp,
# tests/tst_qml.cpp).
qt_add_library(rk3568tv_ui STATIC)
set_source_files_properties(qml/Theme.qml PROPERTIES QT_QML_SINGLETON_TYPE TRUE)
qt_add_qml_module(rk3568tv_ui
    URI Rk3568Tv
    VERSION 1.0
    OUTPUT_DIRECTORY ${CMAKE_CURRENT_BINARY_DIR}/Rk3568Tv
    RESOURCE_PREFIX /qt/qml
    QML_FILES
        qml/AboutPage.qml
        qml/Clock.qml
        qml/HomePage.qml
        qml/Main.qml
        qml/MenuRow.qml
        qml/NotYetPage.qml
        qml/Page.qml
        qml/PageStack.qml
        qml/PlayerPage.qml
        qml/SettingsPage.qml
        qml/Theme.qml
        qml/Tile.qml
        qml/VideosPage.qml
    SOURCES
        src/remotekeys.cpp
        src/remotekeys.h
        src/systeminfo.cpp
        src/systeminfo.h
        src/videolibrary.cpp
        src/videolibrary.h
        src/videoplayer.cpp
        src/videoplayer.h
)
# C++ that QML doesn't see
target_sources(rk3568tv_ui PRIVATE
    src/resumepositions.cpp
    src/resumepositions.h
    src/unixsignals.cpp
    src/unixsignals.h
)
target_include_directories(rk3568tv_ui PUBLIC src)
target_link_libraries(rk3568tv_ui PUBLIC
    Qt6::Network
    Qt6::Qml
    Qt6::Quick
    PkgConfig::GST
    PkgConfig::GFX
)

qt_add_executable(rk3568-tv
    src/main.cpp
)

if(RK3568_TV_LINK_MALI)
    # Qt's KMS libraries have RUNPATH $ORIGIN and otherwise load Mesa's libgbm, which fails with the Mali driver
    # (docs/04-ui-spike.md, finding 1). Plain -l items, so that CMake neither merges nor moves them.
    target_link_libraries(rk3568-tv PRIVATE
        "-Wl,--push-state,--no-as-needed"
        EGL
        GLESv2
        gbm
        "-Wl,--pop-state"
    )
endif()

target_compile_definitions(rk3568-tv PRIVATE
    RK3568_TV_VERSION="${PROJECT_VERSION}"
)

target_link_libraries(rk3568-tv PRIVATE
    rk3568tv_uiplugin
    Qt6::Gui
    Qt6::Quick
)

if(BUILD_TESTING)
    enable_testing()
    add_subdirectory(tests)
endif()
