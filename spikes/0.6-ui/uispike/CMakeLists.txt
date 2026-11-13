# Step 0.6 UI spike: throwaway measurement app (see main.cpp).
cmake_minimum_required(VERSION 3.16)
project(uispike LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

find_package(Qt6 REQUIRED COMPONENTS Gui Quick)

qt_add_executable(uispike main.cpp)
qt_add_resources(uispike "qml" PREFIX "/" FILES main.qml)
# Qt's KMS libraries have RUNPATH $ORIGIN, so on their own they load Mesa's libgbm from their folder, which fails
# with the Mali driver. Needed by the executable itself, ahead of Qt and although unused, the EGL, GLES and GBM
# sonames are looked up through ld.so.cache, which puts the Mali folder first; a library already loaded under a
# soname is the one Qt then gets. Plain -l items, so that CMake neither merges nor moves them.
target_link_libraries(uispike PRIVATE "-Wl,--push-state,--no-as-needed" EGL GLESv2 gbm "-Wl,--pop-state"
                      Qt6::Gui Qt6::Quick)
