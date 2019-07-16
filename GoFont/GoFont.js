
/**
 * This method will switch to the specified page of results.
 */
function loadPage(page) {
    window.webkit.messageHandlers.loadPage.postMessage(page);
}

/**
 * This method will send an event to the application to let it know
 * when a font has been select or unselected.
 */
function updateFont(id, checked) {
    if (checked) {
        window.webkit.messageHandlers.selectFont.postMessage(id);
    } else {
        window.webkit.messageHandlers.unselectFont.postMessage(id);
    }
}

/**
 * This method is used by select/unselect all links to apply
 * the change to all fonts within the family.
 */
function updateAllFonts(familyId, checked) {
    document.querySelectorAll("section[id=\"" + familyId + "\"] input").forEach(function(elem) {
        elem.checked = checked;
        elem.onchange();
    });
}
