import Toybox.Lang;
import Toybox.Timer;
import Toybox.WatchUi;

class WatchJsonBrowserMainMenu extends WatchUi.Menu2 {
    const REFRESH_INTERVAL_MS = 1000;

    var _refreshTimer as Timer.Timer;
    var _itemCount = 0;
    var _lastTitle as String? = null;

    function initialize() {
        Menu2.initialize({:title => getMenuTitle()});
        _refreshTimer = new Timer.Timer();
    }

    function onShow() as Void {
        getApp().attachMainMenu(self);
        refreshMenu();
        _refreshTimer.start(method(:onRefreshTimer), REFRESH_INTERVAL_MS, true);
    }

    function onHide() as Void {
        _refreshTimer.stop();
        getApp().detachMainMenu(self);
    }

    function requestRefresh() as Void {
        refreshMenu();
    }

    function onRefreshTimer() as Void {
        refreshMenu();
    }

    function refreshMenu() as Void {
        var title = getMenuTitle();
        if ((_lastTitle == null) || (_lastTitle != title)) {
            setTitle(title);
            _lastTitle = title;
        }

        var model = getApp().buildMainMenuModel();
        getApp().applyRenderedMainMenuModel(model);
        rebuildMenu(getModelDescriptors(model));
        WatchUi.requestUpdate();
    }

    function rebuildMenu(descriptors as Lang.Array) as Void {
        for (var i = _itemCount - 1; i >= 0; i -= 1) {
            deleteItem(i);
        }

        _itemCount = 0;
        for (var j = 0; j < descriptors.size(); j += 1) {
            addItem(buildMenuItem(descriptors[j]));
            _itemCount += 1;
        }
    }

    function buildMenuItem(descriptor as Lang.Dictionary) as WatchUi.MenuItem {
        var label = getText(descriptor, "label");
        var subLabel = getNullableText(descriptor, "subLabel");
        return new WatchUi.MenuItem(label, subLabel, descriptor.get("id"), null);
    }

    function getText(descriptor as Lang.Dictionary, key as String) as String {
        var value = descriptor.get(key);
        return value == null ? "" : value.toString();
    }

    function getNullableText(descriptor as Lang.Dictionary, key as String) as String? {
        var value = descriptor.get(key);
        if (value == null) {
            return null;
        }
        var text = value.toString();
        return text.length() == 0 ? null : text;
    }

    function getMenuTitle() as String {
        return getApp().getSnapshotAgeTitleLabel() + " b" + getApp().getBuildVersion();
    }

    function getModelDescriptors(model as Lang.Dictionary) as Lang.Array {
        var descriptors = model.get("descriptors");
        if ((descriptors == null) || !(descriptors has :size)) {
            return [];
        }
        return descriptors as Lang.Array;
    }
}
