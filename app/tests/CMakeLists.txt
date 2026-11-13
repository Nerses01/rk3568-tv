find_package(Qt6 6.2 REQUIRED COMPONENTS Test QuickTest)

# C++ tests (Qt Test), linked with the UI library
qt_add_executable(tst_remotekeys
    tst_remotekeys.cpp
)
target_link_libraries(tst_remotekeys PRIVATE
    rk3568tv_ui
    Qt6::Test
)
add_test(NAME tst_remotekeys COMMAND tst_remotekeys)

qt_add_executable(tst_unixsignals
    tst_unixsignals.cpp
)
target_link_libraries(tst_unixsignals PRIVATE
    rk3568tv_ui
    Qt6::Test
)
add_test(NAME tst_unixsignals COMMAND tst_unixsignals)

qt_add_executable(tst_systeminfo
    tst_systeminfo.cpp
)
target_link_libraries(tst_systeminfo PRIVATE
    rk3568tv_ui
    Qt6::Test
)
add_test(NAME tst_systeminfo COMMAND tst_systeminfo)

# QML tests (Qt Quick Test): every qml/tst_*.qml, with the app's QML module linked in
qt_add_executable(tst_qml
    tst_qml.cpp
)
target_compile_definitions(tst_qml PRIVATE
    QUICK_TEST_SOURCE_DIR="${CMAKE_CURRENT_SOURCE_DIR}/qml"
)
target_link_libraries(tst_qml PRIVATE
    rk3568tv_uiplugin
    Qt6::Qml
    Qt6::QuickTest
)
add_test(NAME tst_qml COMMAND tst_qml)

# No screen and no GPU needed: in CI, and on the board next to the running app
set_tests_properties(tst_remotekeys tst_unixsignals tst_systeminfo tst_qml PROPERTIES
    ENVIRONMENT "QT_QPA_PLATFORM=offscreen;QT_QUICK_BACKEND=software"
)
