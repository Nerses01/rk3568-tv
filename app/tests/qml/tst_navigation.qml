import QtQuick
import QtTest
import Rk3568Tv

// The app's window driven by the remote's keys: Home, Videos, Settings, About, Back and Home
TestCase {
    name: "Navigation"
    when: windowShown

    Component {
        id: mainComponent

        Main {
        }
    }

    function createMain() {
        const main = createTemporaryObject(mainComponent, null);
        verify(main, "Main.qml loads");
        main.requestActivate(); // the test's keys go to the active window
        tryVerify(function () {
                return main.active;
            }, 1000, "the window becomes active");
        compare(main.pages.depth, 1);
        return main;
    }

    function tilesOf(main) {
        const tiles = findChild(main.pages.currentPage, "tiles");
        verify(tiles, "the home screen's tiles");
        return tiles;
    }

    function test_home_moves_between_tiles() {
        const main = createMain();
        const tiles = tilesOf(main);
        verify(tiles.activeFocus);
        compare(tiles.count, 2);
        compare(tiles.currentIndex, 0);
        verify(tiles.currentItem.highlighted, "the focus shows");
        keyClick(Qt.Key_Right);
        compare(tiles.currentIndex, 1);
        verify(tiles.currentItem.highlighted);
        verify(!tiles.itemAtIndex(0).highlighted, "one tile shows the focus");
        keyClick(Qt.Key_Right);
        compare(tiles.currentIndex, 1, "no wrap at the end");
        keyClick(Qt.Key_Left);
        compare(tiles.currentIndex, 0);
    }

    function test_ok_opens_back_returns() {
        const main = createMain();
        const tiles = tilesOf(main);
        keyClick(Qt.Key_Return);
        compare(main.pages.depth, 2);
        compare(main.pages.currentPage.title, "Videos");
        verify(!tiles.currentItem.highlighted, "a hidden page shows no focus");
        keyClick(Qt.Key_Escape);
        compare(main.pages.depth, 1);
        verify(tiles.activeFocus);
        compare(tiles.currentIndex, 0);
        keyClick(Qt.Key_Escape);
        compare(main.pages.depth, 1, "Back on the home screen stays there");
    }

    function test_settings_about_and_home() {
        const main = createMain();
        const tiles = tilesOf(main);
        keyClick(Qt.Key_Right);
        keyClick(Qt.Key_Enter);
        compare(main.pages.currentPage.title, "Settings");
        const rows = findChild(main.pages.currentPage, "rows");
        verify(rows.activeFocus);
        compare(rows.count, 4);
        verify(rows.currentItem.highlighted);
        keyClick(Qt.Key_Down);
        keyClick(Qt.Key_Down);
        keyClick(Qt.Key_Down);
        compare(rows.currentIndex, 3);
        keyClick(Qt.Key_Return);
        compare(main.pages.depth, 3);
        compare(main.pages.currentPage.title, "About");
        const version = findChild(main.pages.currentPage, "Version");
        verify(version, "About shows the version");
        compare(version.children[1].text, Qt.application.version);
        keyClick(Qt.Key_Back);
        compare(main.pages.depth, 2);
        compare(rows.currentIndex, 3, "Settings remembers its row");
        verify(rows.activeFocus);
        keyClick(Qt.Key_Return);
        compare(main.pages.depth, 3);
        keyClick(Qt.Key_HomePage);
        compare(main.pages.depth, 1, "Home goes home from anywhere");
        compare(tiles.currentIndex, 1, "home remembers its tile");
        verify(tiles.activeFocus);
    }
}
