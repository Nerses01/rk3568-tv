import QtQuick
import QtTest
import Rk3568Tv

// The 10-foot rules on every page: no text smaller than Theme.textCaption (readable at 3 m), and all of it inside
// the title-safe area
TestCase {
    name: "TenFoot"
    when: windowShown

    Component {
        id: mainComponent

        Main {
        }
    }

    // Pages slide in; measure where they rest
    function initTestCase() {
        Theme.motion = false;
    }

    function cleanupTestCase() {
        Theme.motion = true;
    }

    function createMain() {
        const main = createTemporaryObject(mainComponent, null);
        verify(main, "Main.qml loads");
        main.requestActivate();
        tryVerify(function () {
                return main.active;
            }, 1000, "the window becomes active");
        return main;
    }

    // Every visible Text with something in it, under item
    function texts(item, found) {
        // a QML list isn't iterable in Qt 6.2, and qmlformat 6.2 breaks `for (let ...)`
        for (var i = 0; i < item.children.length; ++i) {
            const child = item.children[i];
            if (!child.visible)
                continue;
            if (child.font !== undefined && child.textFormat !== undefined && child.text !== "")
                found.push(child);
            texts(child, found);
        }
        return found;
    }

    function checkPage(main, name) {
        const page = main.pages.currentPage;
        const found = texts(page, []);
        verify(found.length > 1, name + ": has text");
        for (const text of found) {
            const where = name + ": \"" + text.text + "\"";
            verify(text.font.pixelSize >= Theme.textCaption, where + " is " + text.font.pixelSize + " px");
            // positions come back through the window's scale: allow for rounding (ARM rounds unlike x86)
            const p = text.mapToItem(main.pages, 0, 0);
            const e = 0.5;
            verify(p.x >= Theme.safeX - e && p.y >= Theme.safeY - e, where + " starts in the safe area: " + p.x + ", " + p.y);
            verify(p.x + text.width <= Theme.width - Theme.safeX + e, where + " ends in the safe area, horizontally");
            verify(p.y + text.height <= Theme.height - Theme.safeY + e, where + " ends in the safe area, vertically");
        }
    }

    function test_every_page() {
        const main = createMain();
        checkPage(main, "Home");
        keyClick(Qt.Key_Return);
        checkPage(main, "Videos");
        keyClick(Qt.Key_Escape);
        keyClick(Qt.Key_Right);
        keyClick(Qt.Key_Return);
        checkPage(main, "Settings");
        keyClick(Qt.Key_Return);
        checkPage(main, "Wi-Fi");
        keyClick(Qt.Key_Escape);
        keyClick(Qt.Key_Up);
        keyClick(Qt.Key_Down);
        keyClick(Qt.Key_Down);
        keyClick(Qt.Key_Down);
        keyClick(Qt.Key_Return);
        checkPage(main, "About");
    }
}
