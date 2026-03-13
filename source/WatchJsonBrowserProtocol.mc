import Toybox.Lang;

module WatchJsonBrowserProtocol {
    const PAYLOAD_UNWRAP_MAX_DEPTH = 8;

    function normalizeIncomingPayload(rawPayload) {
        var payloadDict = coerceToDictionary(rawPayload);
        var rootValue = payloadDict != null ? unwrapPayload(payloadDict) : rawPayload;
        if (isProbePayload(rootValue)) {
            return null;
        }
        return canonicalizeRenderableValue(rootValue);
    }

    function normalizeDisconnectedStatusPayload(rawPayload) {
        var payloadDict = coerceToDictionary(rawPayload);
        if (payloadDict == null) {
            return null;
        }

        var rootValue = coerceToDictionary(unwrapPayload(payloadDict));
        if (rootValue == null) {
            return null;
        }

        var schemaVersion = parseCounterValue(getProtocolFieldRawValue(rootValue, "schema_version"));
        var serverConnected = parseBooleanValue(getProtocolFieldRawValue(rootValue, "server_connected"));
        if ((schemaVersion == null) || (serverConnected != false)) {
            return null;
        }

        var result = {
            "server_connected" => false,
            "value" => {"server_connected" => false}
        };

        var snapshotTs = parseCounterValue(getProtocolFieldRawValue(rootValue, "snapshot_ts_ms"));
        if (snapshotTs != null) {
            result["snapshot_ts_ms"] = snapshotTs.toNumber();
        }
        if (schemaVersion != null) {
            result["schema_version"] = schemaVersion.toNumber();
        }
        return result;
    }

    function isServerStateCarrierPayload(payload) {
        var payloadDict = coerceToDictionary(payload);
        if (payloadDict == null) {
            return false;
        }
        if (getProtocolFieldRawValue(payloadDict, "schema_version") == null) {
            return false;
        }
        if (isProbePayload(payloadDict)) {
            return true;
        }
        return getProtocolFieldRawValue(payloadDict, "server_connected") != null;
    }

    function isProbePayload(payload) {
        return parseBooleanValue(getProtocolFieldRawValue(payload, "probe")) == true;
    }

    function getAcceptedSnapshotTimestamp(payload) {
        if (payload == null) {
            return null;
        }
        if (payload instanceof Lang.Dictionary) {
            return parseCounterValue(dictionaryGetByKey(payload, "snapshot_ts_ms"));
        }
        return null;
    }

    function getRenderableRoot(payload) {
        if (payload == null) {
            return null;
        }
        if (payload instanceof Lang.Dictionary) {
            var root = dictionaryGetByKey(payload, "value");
            var rootDict = coerceToDictionary(root);
            if (rootDict != null) {
                var menuNode = dictionaryGetByKey(rootDict, "menu");
                if (menuNode != null) {
                    return menuNode;
                }
            }
            return root;
        }
        return null;
    }

    function canonicalizeRenderableValue(rawValue) {
        var result = {
            "value" => canonicalizeValue(rawValue)
        };

        var rootDict = coerceToDictionary(rawValue);
        if (rootDict != null) {
            var schemaVersion = parseCounterValue(getProtocolFieldRawValue(rootDict, "schema_version"));
            if (schemaVersion != null) {
                result["schema_version"] = schemaVersion.toNumber();
            }

            var snapshotTs = parseCounterValue(getProtocolFieldRawValue(rootDict, "snapshot_ts_ms"));
            if (snapshotTs != null) {
                result["snapshot_ts_ms"] = snapshotTs.toNumber();
            }

            var serverConnected = parseBooleanValue(getProtocolFieldRawValue(rootDict, "server_connected"));
            if (serverConnected != null) {
                result["server_connected"] = serverConnected;
            }
        }

        return result;
    }

    function canonicalizeValue(rawValue) {
        if (rawValue == null) {
            return null;
        }

        var scalar = unwrapScalarValue(rawValue);
        if (scalar instanceof Lang.String || scalar instanceof Lang.Number || scalar instanceof Lang.Float || scalar instanceof Lang.Double || scalar instanceof Lang.Boolean) {
            return scalar;
        }

        var dict = coerceToDictionary(rawValue);
        if (dict != null) {
            var result = {};
            var keys = dict.keys();
            if ((keys != null) && (keys has :size)) {
                for (var i = 0; i < keys.size(); i += 1) {
                    var key = getSequentialItem(keys, i);
                    if (key == null) {
                        continue;
                    }
                    var keyText = key.toString();
                    result[keyText] = canonicalizeValue(dictionaryGetByKey(dict, keyText));
                }
            }
            return result;
        }

        var listValue = normalizeSequentialValue(rawValue);
        if (listValue != null) {
            var items = [];
            for (var j = 0; j < listValue.size(); j += 1) {
                items.add(canonicalizeValue(listValue[j]));
            }
            return items;
        }

        return rawValue.toString();
    }

    function unwrapPayload(payload) {
        var current = payload;
        var wrapperKeys = ["snapshot", "payload", "data", "body", "message", "overview"];

        for (var depth = 0; depth < PAYLOAD_UNWRAP_MAX_DEPTH; depth += 1) {
            var currentDict = coerceToDictionary(current);
            if (currentDict == null) {
                break;
            }

            var nextValue = null;
            for (var i = 0; i < wrapperKeys.size(); i += 1) {
                nextValue = getProtocolFieldRawValue(currentDict, wrapperKeys[i]);
                if (nextValue != null) {
                    break;
                }
            }

            if (nextValue == null) {
                break;
            }
            current = nextValue;
        }

        return current;
    }

    function unwrapScalarValue(rawValue) {
        var current = rawValue;
        for (var depth = 0; depth < PAYLOAD_UNWRAP_MAX_DEPTH; depth += 1) {
            if (current == null) {
                return null;
            }

            if (current instanceof Lang.String || current instanceof Lang.Number || current instanceof Lang.Float || current instanceof Lang.Double || current instanceof Lang.Boolean) {
                return current;
            }

            var dict = coerceToDictionary(current);
            if (dict != null) {
                var wrapperKeys = ["value", "val", "data", "payload", "body", "message"];
                var moved = false;
                for (var i = 0; i < wrapperKeys.size(); i += 1) {
                    var nextValue = getProtocolFieldRawValue(dict, wrapperKeys[i]);
                    if (nextValue != null) {
                        current = nextValue;
                        moved = true;
                        break;
                    }
                }
                if (moved) {
                    continue;
                }
            }

            var listValue = normalizeSequentialValue(current);
            if ((listValue != null) && (listValue.size() > 0) && (listValue.size() <= 2)) {
                current = listValue[0];
                continue;
            }
            break;
        }
        return current;
    }

    function coerceToDictionary(rawValue) {
        if (rawValue == null) {
            return null;
        }
        if (rawValue instanceof Lang.Dictionary) {
            return rawValue;
        }
        if ((rawValue has :keys) && (rawValue has :get)) {
            var dict = {};
            var keys = rawValue.keys();
            if ((keys == null) || !(keys has :size)) {
                return null;
            }
            for (var i = 0; i < keys.size(); i += 1) {
                var key = getSequentialItem(keys, i);
                if (key == null) {
                    continue;
                }
                dict[key.toString()] = rawValue.get(key);
            }
            return dict;
        }
        return null;
    }

    function normalizeSequentialValue(rawValue) {
        if (rawValue == null) {
            return null;
        }
        if ((rawValue has :size) && (rawValue has :get)) {
            var result = [];
            var itemCount = rawValue.size();
            for (var i = 0; i < itemCount; i += 1) {
                result.add(rawValue.get(i));
            }
            return result;
        }
        return null;
    }

    function getSequentialItem(container, index) {
        if ((container == null) || !(container has :size) || !(container has :get)) {
            return null;
        }
        if ((index < 0) || (index >= container.size())) {
            return null;
        }
        return container.get(index);
    }

    function dictionaryGetByKey(dictionary, key) {
        if (dictionary == null) {
            return null;
        }
        if (dictionary.hasKey(key)) {
            return dictionary[key];
        }
        var keys = dictionary.keys();
        if ((keys == null) || !(keys has :size)) {
            return null;
        }
        for (var i = 0; i < keys.size(); i += 1) {
            var candidate = getSequentialItem(keys, i);
            if (candidate == null) {
                continue;
            }
            if (candidate.toString() == key) {
                return dictionary[candidate];
            }
        }
        return null;
    }

    function getProtocolFieldRawValue(container, key) {
        var dict = coerceToDictionary(container);
        if (dict == null) {
            return null;
        }
        return dictionaryGetByKey(dict, key);
    }

    function parseBooleanValue(rawValue) {
        var scalar = unwrapScalarValue(rawValue);
        if (scalar == true) {
            return true;
        }
        if (scalar == false) {
            return false;
        }
        if (scalar instanceof Lang.String) {
            var text = trimAsciiSpaces(scalar.toLower());
            if (text == "true") {
                return true;
            }
            if (text == "false") {
                return false;
            }
        }
        return null;
    }

    function parseCounterValue(rawValue) {
        var scalar = unwrapScalarValue(rawValue);
        if (scalar == null) {
            return null;
        }
        if (scalar instanceof Lang.Number || scalar instanceof Lang.Float || scalar instanceof Lang.Double) {
            return scalar.toNumber();
        }
        if (scalar instanceof Lang.String) {
            var text = trimAsciiSpaces(scalar);
            if (text.length() == 0) {
                return null;
            }
            return text.toNumber();
        }
        return null;
    }

    function trimAsciiSpaces(value) {
        var start = 0;
        var finish = value.length();
        while ((start < finish) && isAsciiWhitespace(value.substring(start, start + 1))) {
            start += 1;
        }
        while ((finish > start) && isAsciiWhitespace(value.substring(finish - 1, finish))) {
            finish -= 1;
        }
        return value.substring(start, finish);
    }

    function isAsciiWhitespace(character) {
        return (character == " ") || (character == "\t") || (character == "\n") || (character == "\r");
    }

    function previewValue(value) {
        if (value == null) {
            return "null";
        }
        if (value instanceof Lang.Dictionary) {
            var keys = value.keys();
            var count = ((keys != null) && (keys has :size)) ? keys.size() : 0;
            return "Object " + count.toString();
        }
        if (value instanceof Lang.Array) {
            return "Array " + value.size().toString();
        }
        var text = value.toString();
        return text.length() <= 24 ? text : text.substring(0, 21) + "...";
    }

    function splitTextForMenu(valueText, chunkLength) {
        var chunks = [];
        var text = valueText == null ? "null" : valueText;
        if (text.length() == 0) {
            chunks.add(" ");
            return chunks;
        }
        var start = 0;
        while (start < text.length()) {
            var finish = start + chunkLength;
            if (finish > text.length()) {
                finish = text.length();
            }
            chunks.add(text.substring(start, finish));
            start = finish;
        }
        return chunks;
    }
}
