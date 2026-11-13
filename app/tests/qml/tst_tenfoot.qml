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

    // Pages pushed directly: they need a network or a new screen mode to be reached otherwise
    Component {
        id: passwordPage

        PasswordPage {
        }
    }
    Component {
        id: choicesPage

        ChoicesPage {
        }
    }
    Component {
        id: confirmModePage

        ConfirmModePage {
        }
    }

    // Every visible Text with something in it, under item, each with the clipping item it shows through (a list)
    function texts(item, found, clipper) {
        // a QML list isn't iterable in Qt 6.2, and qmlformat 6.2 breaks `for (let ...)`
        for (var i = 0; i < item.children.length; ++i) {
            const child = item.children[i];
            if (!child.visible)
                continue;
            if (child.font !== undefined && child.textFormat !== undefined && child.text !== "")
                found.push({
                        "text": child,
                        "clipper": clipper
                    });
            texts(child, found, child.clip ? child : clipper);
        }
        return found;
    }

    function checkPage(main, name) {
        const page = main.pages.currentPage;
        const found = texts(page, [], null);
        verify(found.length > 1, name + ": has text");
        for (const entry of found) {
            const text = entry.text;
            const where = name + ": \"" + text.text + "\"";
            // positions come back through the window's scale: allow for rounding (ARM rounds unlike x86)
            const p = text.mapToItem(main.pages, 0, 0);
            var left = p.x, top = p.y, right = p.x + text.width, bottom = p.y + text.height;
            if (entry.clipper) {
                // what a list shows of it; a row scrolled out of the list isn't on the screen
                const c = entry.clipper.mapToItem(main.pages, 0, 0);
                left = Math.max(left, c.x);
                top = Math.max(top, c.y);
                right = Math.min(right, c.x + entry.clipper.width);
                bottom = Math.min(bottom, c.y + entry.clipper.height);
                if (right <= left || bottom <= top)
                    continue;
            }
            verify(text.font.pixelSize >= Theme.textCaption, where + " is " + text.font.pixelSize + " px");
            const e = 0.5;
            verify(left >= Theme.safeX - e && top >= Theme.safeY - e, where + " starts in the safe area: " + left + ", " + top);
            verify(right <= Theme.width - Theme.safeX + e, where + " ends in the safe area, horizontally");
            verify(bottom <= Theme.height - Theme.safeY + e, where + " ends in the safe area, vertically");
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
        keyClick(Qt.Key_Escape);
        keyClick(Qt.Key_Up);
        keyClick(Qt.Key_Up);
        keyClick(Qt.Key_Return);
        checkPage(main, "Bluetooth");
        keyClick(Qt.Key_Escape);
        keyClick(Qt.Key_Down);
        keyClick(Qt.Key_Return);
        checkPage(main, "Display");
        keyClick(Qt.Key_Escape);
        main.pages.push(passwordPage, {
                "title": "A network"
            });
        checkPage(main, "Password");
        main.pages.pop();
        main.pages.push(choicesPage, {
                "title": "A network",
                "choices": [{
                        "label": "Join",
                        "run": function () {}
                    }, {
                        "label": "Forget",
                        "run": function () {}
                    }],
                "text": "The box is on this network. Forgetting it leaves it."
            });
        checkPage(main, "Choices");
        main.pages.pop();
        main.pages.push(confirmModePage, {});
        checkPage(main, "Keep the screen mode");
    }
}
