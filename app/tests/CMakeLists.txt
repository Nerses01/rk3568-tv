find_package(Qt6 6.2 REQUIRED COMPONENTS Test QuickTest)

# C++ tests (Qt Test): tst_NAME.cpp each, linked with the UI library
foreach(name
        tst_bluetooth
        tst_displaysettings
        tst_remotekeys
        tst_resumepositions
        tst_systeminfo
        tst_unixsignals
        tst_videolibrary
        tst_videoplayer
        tst_wifi
)
    qt_add_executable(${name}
        ${name}.cpp
    )
    target_link_libraries(${name} PRIVATE
        rk3568tv_ui
        Qt6::Test
    )
    add_test(NAME ${name} COMMAND ${name})
endforeach()

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

# No screen, no GPU and no sound needed: in CI, and on the board next to the running app. No media folder either,
# and neither the board's Wi-Fi and Bluetooth nor its screen mode: the tests that need nmcli and bluetoothctl bring
# stubs, and without QT_QPA_EGLFS_KMS_CONFIG the screen mode can't change.
get_property(tests DIRECTORY PROPERTY TESTS)
set_tests_properties(${tests} PROPERTIES
    ENVIRONMENT "QT_QPA_PLATFORM=offscreen;QT_QUICK_BACKEND=software;RK3568_TV_AUDIO_SINK=fakesink sync=true;RK3568_TV_MEDIA=/nonexistent-media;RK3568_TV_NMCLI=/nonexistent/nmcli;RK3568_TV_BLUETOOTHCTL=/nonexistent/bluetoothctl;QT_QPA_EGLFS_KMS_CONFIG="
)
