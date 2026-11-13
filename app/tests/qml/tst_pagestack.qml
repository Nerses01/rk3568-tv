import QtQuick
import QtTest
import Rk3568Tv

// PageStack: push, pop and popToFirst; only the top page shows and has the focus, which comes back where it was
TestCase {
    id: testCase

    height: 300
    name: "PageStack"
    when: windowShown
    width: 400

    Component {
        id: stackComponent

        PageStack {
            anchors.fill: parent
        }
    }
    Component {
        id: pageComponent

        Page {
            readonly property alias first: first
            readonly property alias second: second

            Item {
                id: first

                focus: true
                height: 10
                width: 10
            }
            Item {
                id: second

                height: 10
                width: 10
            }
        }
    }

    function createStack() {
        // other tests' windows may have taken the activation, and only an active window has active focus
        testCase.Window.window.requestActivate();
        tryVerify(function () {
                return testCase.Window.window.active;
            }, 1000, "the test's window becomes active");
        // in the window's visible content: a TestCase is itself invisible, and so would be everything in it
        const stack = createTemporaryObject(stackComponent, testCase.Window.window.contentItem);
        verify(stack);
        return stack;
    }

    function test_push() {
        const stack = createStack();
        compare(stack.depth, 0);
        compare(stack.currentPage, null);
        const home = stack.push(pageComponent, {
                "title": "Home"
            });
        compare(stack.depth, 1);
        compare(stack.currentPage, home);
        compare(home.stack, stack);
        compare(home.title, "Home");
        verify(home.first.activeFocus);
        const next = stack.push(pageComponent);
        compare(stack.depth, 2);
        compare(stack.currentPage, next);
        verify(!home.visible);
        verify(next.visible);
        verify(next.first.activeFocus);
    }

    function test_pop_gives_the_focus_back() {
        const stack = createStack();
        const home = stack.push(pageComponent);
        home.second.forceActiveFocus();
        stack.push(pageComponent);
        verify(!home.second.activeFocus);
        verify(stack.pop());
        compare(stack.depth, 1);
        compare(stack.currentPage, home);
        verify(home.visible);
        verify(home.second.activeFocus, "the focus is back where it was");
    }

    function test_pop_keeps_the_first_page() {
        const stack = createStack();
        const home = stack.push(pageComponent);
        verify(!stack.pop());
        compare(stack.depth, 1);
        verify(home.visible);
        verify(home.first.activeFocus);
    }

    function test_popToFirst() {
        const stack = createStack();
        const home = stack.push(pageComponent);
        const second = stack.push(pageComponent);
        stack.push(pageComponent);
        verify(stack.popToFirst());
        compare(stack.depth, 1);
        compare(stack.currentPage, home);
        verify(home.visible);
        verify(!second.visible);
        verify(home.first.activeFocus);
        verify(!stack.popToFirst());
    }
}
