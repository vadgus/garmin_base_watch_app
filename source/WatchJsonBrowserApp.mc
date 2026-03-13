import Toybox.Application;
import Toybox.Communications;
import Toybox.Lang;
import Toybox.System;
import Toybox.WatchUi;

class WatchJsonBrowserApp extends Application.AppBase {
    const CONNECTION_TIMEOUT_MS = 12000;
    const SNAPSHOT_STALE_TIMEOUT_MS = 5000;
    const DETAIL_CHUNK_LENGTH = 18;

    const UI_MODE_PHONE_DISCONNECTED = :phone_disconnected;
    const UI_MODE_STALE_DATA = :stale_data;
    const UI_MODE_NORMAL = :normal;

    var _phoneMessageMethod;
    var _supportsMessaging = false;
    var _snapshot = null;
    var _hasSnapshot = false;
    var _lastInboundTick = null;
    var _lastPhoneActivityTick = null;
    var _lastSnapshotTsMs = null;
    var _mainMenuView = null;
    var _renderedEntryMap as Dictionary? = null;
    var _currentPath as Array;

    function initialize() {
        AppBase.initialize();
        _phoneMessageMethod = method(:onPhoneMessage);
        _supportsMessaging = (Communications has :registerForPhoneAppMessages);
        _currentPath = [];
    }

    function onStart(state as Dictionary?) as Void {
        resetSessionState();
        if (_supportsMessaging) {
            Communications.registerForPhoneAppMessages(_phoneMessageMethod);
        }
    }

    function onStop(state as Dictionary?) as Void {
        resetSessionState();
        if (Communications has :registerForPhoneAppMessages) {
            Communications.registerForPhoneAppMessages(null);
        }
    }

    function getInitialView() as [Views] or [Views, InputDelegates] {
        var mainMenu = new WatchJsonBrowserMainMenu();
        return [mainMenu, new WatchJsonBrowserMainMenuDelegate()];
    }

    function getBuildVersion() as String {
        return BuildInfo.VERSION;
    }

    function attachMainMenu(menuView) as Void {
        _mainMenuView = menuView;
    }

    function detachMainMenu(menuView) as Void {
        if (_mainMenuView == menuView) {
            _mainMenuView = null;
        }
    }

    function notifyUiChanged() as Void {
        if ((_mainMenuView != null) && (_mainMenuView has :requestRefresh)) {
            _mainMenuView.requestRefresh();
        }
        WatchUi.requestUpdate();
    }

    function isConnected() as Boolean {
        if (!_supportsMessaging || (_lastPhoneActivityTick == null)) {
            return false;
        }
        return (System.getTimer() - _lastPhoneActivityTick) <= CONNECTION_TIMEOUT_MS;
    }

    function hasFreshSnapshot() as Boolean {
        if (!_hasSnapshot || (_lastInboundTick == null)) {
            return false;
        }
        return (System.getTimer() - _lastInboundTick) <= SNAPSHOT_STALE_TIMEOUT_MS;
    }

    function getSnapshotAgeMs() as Number? {
        if (!hasFreshSnapshot()) {
            return null;
        }
        return System.getTimer() - _lastInboundTick;
    }

    function getSnapshotAgeTitleLabel() as String {
        var ageMs = getSnapshotAgeMs();
        if (ageMs == null) {
            return "-";
        }
        var seconds = (ageMs / 1000).toNumber();
        return seconds > 60 ? "60+" : seconds.toString();
    }

    function getUiMode() as Symbol {
        if (!isConnected()) {
            return UI_MODE_PHONE_DISCONNECTED;
        }
        if (!hasFreshSnapshot()) {
            return UI_MODE_STALE_DATA;
        }
        return UI_MODE_NORMAL;
    }

    function getUiStatusText() as String? {
        var mode = getUiMode();
        if (mode == UI_MODE_PHONE_DISCONNECTED) {
            return "Phone disconnected";
        }
        if (mode == UI_MODE_STALE_DATA) {
            return "Waiting for data";
        }
        return null;
    }

    function buildMainMenuModel() as Dictionary {
        var items = [];
        var entryMap = {};

        var statusText = getUiStatusText();
        if (statusText != null) {
            items.add(buildMenuItemDescriptor(:status_item, statusText, null));
            return {
                "descriptors" => items,
                "entryMap" => entryMap
            };
        }

        var currentNode = getCurrentNode();
        if (_currentPath.size() > 0) {
            items.add(buildMenuItemDescriptor(:nav_back, "..", getCurrentPathSummary()));
        }

        if (currentNode instanceof Lang.Dictionary) {
            appendDictionaryEntries(items, entryMap, currentNode);
        } else if (currentNode instanceof Lang.Array) {
            appendArrayEntries(items, entryMap, currentNode);
        } else {
            items.add(buildMenuItemDescriptor(:scalar_root, "value", WatchJsonBrowserProtocol.previewValue(currentNode)));
        }

        return {
            "descriptors" => items,
            "entryMap" => entryMap
        };
    }

    function applyRenderedMainMenuModel(model as Dictionary?) as Void {
        _renderedEntryMap = {};
        if (model == null) {
            return;
        }
        var entryMap = WatchJsonBrowserProtocol.coerceToDictionary(WatchJsonBrowserProtocol.dictionaryGetByKey(model, "entryMap"));
        if (entryMap != null) {
            _renderedEntryMap = entryMap;
        }
    }

    function handleMainMenuSelection(itemId) as Boolean {
        if (itemId == :nav_back) {
            navigateBack();
            return true;
        }

        var entry = getRenderedEntry(itemId);
        if (entry == null) {
            return false;
        }

        var entryKind = WatchJsonBrowserProtocol.dictionaryGetByKey(entry, "kind");
        var entryPath = WatchJsonBrowserProtocol.dictionaryGetByKey(entry, "path");
        if (!(entryPath instanceof Lang.Array)) {
            return false;
        }

        if (entryKind == "container") {
            _currentPath = clonePath(entryPath);
            notifyUiChanged();
            return true;
        }

        if (entryKind == "scalar") {
            openValueDetail(entry);
            return true;
        }

        return false;
    }

    function onPhoneMessage(msg as Communications.PhoneAppMessage) as Void {
        var payload = ((msg != null) && (msg has :data)) ? msg.data : msg;
        if (payload != null) {
            _lastPhoneActivityTick = System.getTimer();
        }

        var normalizedPayload = WatchJsonBrowserProtocol.normalizeIncomingPayload(payload);
        if (normalizedPayload == null) {
            normalizedPayload = WatchJsonBrowserProtocol.normalizeDisconnectedStatusPayload(payload);
        }
        if (normalizedPayload == null) {
            return;
        }
        if (!shouldAcceptSnapshotByTimestamp(normalizedPayload)) {
            return;
        }

        _snapshot = normalizedPayload;
        _hasSnapshot = true;
        _lastSnapshotTsMs = WatchJsonBrowserProtocol.getAcceptedSnapshotTimestamp(normalizedPayload);
        _lastInboundTick = System.getTimer();
        normalizeCurrentPath();
        notifyUiChanged();
    }

    function shouldAcceptSnapshotByTimestamp(payload as Dictionary?) as Boolean {
        var incomingTs = WatchJsonBrowserProtocol.getAcceptedSnapshotTimestamp(payload);
        if ((incomingTs == null) || (_lastSnapshotTsMs == null)) {
            return true;
        }
        return incomingTs >= _lastSnapshotTsMs;
    }

    function getCurrentNode() {
        var root = getRootNode();
        if (root == null) {
            return null;
        }

        var current = root;
        for (var i = 0; i < _currentPath.size(); i += 1) {
            var segment = _currentPath[i];
            if (current instanceof Lang.Dictionary) {
                current = WatchJsonBrowserProtocol.dictionaryGetByKey(current, segment.toString());
            } else if ((current instanceof Lang.Array) && (segment instanceof Lang.Number)) {
                if ((segment < 0) || (segment >= current.size())) {
                    return null;
                }
                current = current[segment];
            } else {
                return null;
            }
        }

        return current;
    }

    function getRootNode() {
        if (!_hasSnapshot || (_snapshot == null)) {
            return null;
        }
        var root = WatchJsonBrowserProtocol.getRenderableRoot(_snapshot);
        if (root instanceof Lang.Dictionary || root instanceof Lang.Array) {
            return root;
        }
        return {"value" => root};
    }

    function appendDictionaryEntries(items as Array, entryMap as Dictionary, dictionary as Lang.Dictionary) as Void {
        var keys = dictionary.keys();
        if ((keys == null) || !(keys has :size)) {
            return;
        }

        var keyTexts = [];
        for (var i = 0; i < keys.size(); i += 1) {
            var key = WatchJsonBrowserProtocol.getSequentialItem(keys, i);
            if (key != null) {
                keyTexts.add(key.toString());
            }
        }
        sortTextValuesAsc(keyTexts);

        for (var j = 0; j < keyTexts.size(); j += 1) {
            var keyText = keyTexts[j];
            var value = WatchJsonBrowserProtocol.dictionaryGetByKey(dictionary, keyText);
            appendEntryDescriptor(items, entryMap, keyText, value, extendPath(_currentPath, keyText), false, j);
        }
    }

    function appendArrayEntries(items as Array, entryMap as Dictionary, values as Lang.Array) as Void {
        for (var i = 0; i < values.size(); i += 1) {
            appendEntryDescriptor(items, entryMap, "[" + i.toString() + "]", values[i], extendPath(_currentPath, i), true, i);
        }
    }

    function appendEntryDescriptor(items as Array, entryMap as Dictionary, label as String, value, path as Array, isArrayEntry as Boolean, ordinal as Number) as Void {
        var identifier = buildEntryIdentifier(isArrayEntry, ordinal, label);
        var isContainer = (value instanceof Lang.Dictionary) || (value instanceof Lang.Array);
        var descriptor = buildMenuItemDescriptor(identifier, label, WatchJsonBrowserProtocol.previewValue(value));
        items.add(descriptor);
        entryMap[normalizeMenuIdentifierText(identifier)] = {
            "kind" => isContainer ? "container" : "scalar",
            "path" => path,
            "label" => label,
            "value" => value
        };
    }

    function buildEntryIdentifier(isArrayEntry as Boolean, ordinal as Number, label as String) {
        return (isArrayEntry ? "idx:" : "key:") + ordinal.toString() + ":" + label;
    }

    function sortTextValuesAsc(values as Array) as Void {
        for (var i = 1; i < values.size(); i += 1) {
            var current = values[i].toString();
            var j = i - 1;
            while (j >= 0) {
                var previous = values[j].toString();
                if (previous.compareTo(current) <= 0) {
                    break;
                }
                values[j + 1] = values[j];
                j -= 1;
            }
            values[j + 1] = current;
        }
    }

    function buildMenuItemDescriptor(identifier, label as String, subLabel as String?) as Dictionary {
        return {
            "id" => identifier,
            "label" => label,
            "subLabel" => subLabel
        };
    }

    function getRenderedEntry(itemId) {
        if (_renderedEntryMap == null) {
            return null;
        }
        var key = normalizeMenuIdentifierText(itemId);
        return _renderedEntryMap.hasKey(key) ? _renderedEntryMap[key] : null;
    }

    function openValueDetail(entry as Dictionary) as Void {
        var menu = new WatchUi.Menu();
        var label = WatchJsonBrowserProtocol.dictionaryGetByKey(entry, "label");
        var value = WatchJsonBrowserProtocol.dictionaryGetByKey(entry, "value");
        menu.setTitle(label == null ? "Value" : label.toString());

        var chunks = WatchJsonBrowserProtocol.splitTextForMenu(value == null ? "null" : value.toString(), DETAIL_CHUNK_LENGTH);
        for (var i = 0; i < chunks.size(); i += 1) {
            menu.addItem(chunks[i].toString(), :detail_line);
        }

        WatchUi.pushView(menu, new WatchJsonBrowserMenuDelegate(), WatchUi.SLIDE_UP);
    }

    function navigateBack() as Void {
        if (_currentPath.size() == 0) {
            return;
        }
        _currentPath.remove(_currentPath.size() - 1);
        notifyUiChanged();
    }

    function normalizeCurrentPath() as Void {
        var current = getCurrentNode();
        if (current != null) {
            return;
        }
        _currentPath = [];
    }

    function getCurrentPathSummary() as String {
        if (_currentPath.size() == 0) {
            return "root";
        }
        var parts = [];
        for (var i = 0; i < _currentPath.size(); i += 1) {
            parts.add(_currentPath[i].toString());
        }
        var text = "root/";
        for (var j = 0; j < parts.size(); j += 1) {
            if (j > 0) {
                text += "/";
            }
            text += parts[j];
        }
        return text;
    }

    function extendPath(basePath as Array, segment) as Array {
        var result = clonePath(basePath);
        result.add(segment);
        return result;
    }

    function clonePath(source as Array) as Array {
        var result = [];
        for (var i = 0; i < source.size(); i += 1) {
            result.add(source[i]);
        }
        return result;
    }

    function normalizeMenuIdentifierText(value) as String {
        if (value == null) {
            return "";
        }
        var text = value.toString();
        if ((text.length() > 0) && (text.substring(0, 1) == ":")) {
            text = text.substring(1, text.length());
        }
        return text;
    }

    function resetSessionState() as Void {
        _snapshot = null;
        _hasSnapshot = false;
        _lastInboundTick = null;
        _lastPhoneActivityTick = null;
        _lastSnapshotTsMs = null;
        _renderedEntryMap = {};
        _currentPath = [];
    }
}

function getApp() as WatchJsonBrowserApp {
    return Application.getApp() as WatchJsonBrowserApp;
}
