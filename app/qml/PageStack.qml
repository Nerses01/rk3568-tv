import QtQuick
import Rk3568Tv

// The app's screens, one above the other. push() opens a page, pop() goes back one, popToFirst() goes home. Only the
// top page is visible and has the focus; a page that comes back to the top gets its focus back where it left it.
// A new page slides in from the right, a page that comes back from the left.
Item {
    id: stack

    property var pages: []
    readonly property int depth: stack.pages.length
    readonly property Item currentPage: stack.depth > 0 ? stack.pages[stack.depth - 1] : null

    // Opens a page made from component (a Page), with properties set on it; returns the page, or null
    function push(component, properties) {
        const page = component.createObject(stack, Object.assign({
                    "stack": stack
                }, properties || {}));
        if (!page) {
            console.warn("PageStack: cannot create the page: " + component.errorString());
            return null;
        }
        if (stack.currentPage)
            stack.currentPage.visible = false;
        stack.pages = stack.pages.concat([page]);
        stack.show(page, Theme.gap * 2);
        return page;
    }

    // Closes the top page; false when only the first page is left
    function pop() {
        return stack.popTo(stack.depth - 2);
    }

    // Closes every page but the first; false when only the first page is left
    function popToFirst() {
        return stack.popTo(0);
    }

    function popTo(index) {
        if (index < 0 || index >= stack.depth - 1)
            return false;
        const closing = stack.pages.slice(index + 1);
        stack.pages = stack.pages.slice(0, index + 1);
        for (const page of closing) {
            page.visible = false;
            page.destroy();
        }
        stack.currentPage.visible = true;
        stack.show(stack.currentPage, -Theme.gap * 2);
        return true;
    }

    function show(page, fromX) {
        page.forceActiveFocus();
        enter.stop();
        enterOpacity.target = page;
        enterX.target = page;
        enterX.from = fromX;
        enter.start();
    }

    ParallelAnimation {
        id: enter

        OpacityAnimator {
            id: enterOpacity

            duration: Theme.pageDuration
            easing.type: Easing.OutCubic
            from: 0
            to: 1
        }
        XAnimator {
            id: enterX

            duration: Theme.pageDuration
            easing.type: Easing.OutCubic
            to: 0
        }
    }
}
