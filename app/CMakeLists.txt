cmake_minimum_required(VERSION 3.16)

project(rk3568-tv
    VERSION 0.1.0
    LANGUAGES CXX
)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

find_package(Qt6 6.2 REQUIRED COMPONENTS Gui Quick)

# Qt 6.2 has no qt_standard_project_setup(); this is the part of it the app needs.
set(CMAKE_AUTOMOC ON)

qt_add_executable(rk3568-tv
    src/main.cpp
)

option(RK3568_TV_LINK_MALI "Link the Mali EGL, GLES and GBM libraries ahead of Qt (needed on the board)" ON)
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

qt_add_qml_module(rk3568-tv
    URI Rk3568Tv
    VERSION 1.0
    QML_FILES
        qml/Main.qml
)

target_compile_definitions(rk3568-tv PRIVATE
    RK3568_TV_VERSION="${PROJECT_VERSION}"
)

target_link_libraries(rk3568-tv PRIVATE
    Qt6::Gui
    Qt6::Quick
)
