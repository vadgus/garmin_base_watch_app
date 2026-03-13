import Toybox.WatchUi;

class WatchJsonBrowserMainMenuDelegate extends WatchUi.Menu2InputDelegate {
    function initialize() {
        Menu2InputDelegate.initialize();
    }

    function onSelect(item as WatchUi.MenuItem) as Void {
        getApp().handleMainMenuSelection(item.getId());
    }
}
