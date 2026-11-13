cmake_minimum_required(VERSION 3.16)

project(rk3568-tv
    VERSION 0.1.0
    LANGUAGES CXX
)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

option(RK3568_TV_LINK_MALI "Link the Mali EGL, GLES and GBM libraries ahead of Qt (needed on the board)" ON)
option(BUILD_TESTING "Build the tests" ON)

find_package(Qt6 6.2 REQUIRED COMPONENTS Gui Qml Quick)

# Qt 6.2 has no qt_standard_project_setup(); this is the part of it the app needs.
set(CMAKE_AUTOMOC ON)

add_compile_options(-Wall -Wextra)

# The UI: its QML and the C++ types that QML uses, as a static QML module, so that the app and the tests share it.
# Its resources go under /qt/qml, Qt 6.5's default; Qt 6.2 needs that import path added (src/main.cpp,
# tests/tst_qml.cpp).
qt_add_library(rk3568tv_ui STATIC)
qt_add_qml_module(rk3568tv_ui
    URI Rk3568Tv
    VERSION 1.0
    RESOURCE_PREFIX /qt/qml
    QML_FILES
        qml/Main.qml
    SOURCES
        src/remotekeys.cpp
        src/remotekeys.h
)
target_include_directories(rk3568tv_ui PUBLIC src)
target_link_libraries(rk3568tv_ui PUBLIC
    Qt6::Qml
    Qt6::Quick
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
