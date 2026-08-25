import QtQuick
import Quickshell
import Quickshell.Io

// Headless Proton Pass service. Only non-secret item metadata crosses this
// boundary; field values stay inside the helper and go directly to wl-copy.
Item {
    id: root

    property var settings: ({})
    property string state: "INIT"
    property string message: ""
    property var items: []
    property var vaults: []
    property var warnings: []
    property string query: ""
    property bool refreshing: false
    property bool copyBusy: false
    property bool clearClipboardBusy: false
    property int clipboardClearSeconds: 0
    property int clipboardSecondsRemaining: 0
    readonly property bool clipboardCountdownActive: clipboardClearSeconds > 0
        && clipboardSecondsRemaining > 0
    property double lastSuccessfulIndexAt: 0
    property bool logoutBusy: false
    property bool createBusy: false
    property bool staleWarning: false
    property bool panelOpen: false
    property double subtitleNow: Date.now()
    readonly property var filteredItems: filterItems(items, query)
    readonly property bool showRecents: boolSetting("showRecents", true)
    readonly property var recentItems: joinRecents(items, recents)
    readonly property int maxIndexItems: 10000
    readonly property int maxIndexVaults: 100
    readonly property bool displayingRecents: showRecents && query === "" && recentItems.length > 0
    // Rows are the item objects themselves. Nothing is precomputed into them:
    // the subtitle and the cursor index are derived in the delegate, so typing
    // only re-filters instead of rebuilding a parallel array of row objects and
    // re-running the date maths for every item on every keystroke.
    readonly property var recentRows: displayingRecents ? recentItems : []
    readonly property var allRows: filteredItems
    readonly property var displayItems: recentRows.concat(allRows)
    readonly property bool hasIndex: _hasIndex
    property var recents: []

    property bool _hasIndex: false
    property bool _doctorReady: false
    property bool _doctorContinueIndex: false
    property int _indexGeneration: 0
    property int _activeIndexGeneration: 0
    property bool _indexPending: false
    property string _recentsOperation: ""
    property string _pendingRecentsOperation: ""
    property string _createInput: ""

    signal toastRequested(string message)
    signal loginCreated(string shareId, string itemId)

    function setting(name, fallback) {
        var value = settings ? settings[name] : undefined;
        return value === undefined || value === null ? fallback : value;
    }

    function intSetting(name, fallback, minimum, maximum) {
        var value = parseInt(String(setting(name, fallback)), 10);
        if (!isFinite(value))
            value = fallback;
        return Math.max(minimum, Math.min(maximum, value));
    }

    function boolSetting(name, fallback) {
        var value = setting(name, fallback);
        if (value === true || value === false)
            return value;
        var text = String(value).toLowerCase();
        return text === "true" || text === "yes" || text === "on" || text === "1";
    }

    function helperPath() {
        var override = String(Quickshell.env("OMARCHY_PROTONPASS_HELPER") || "");
        if (override !== "")
            return override;
        return Qt.resolvedUrl("omarchy-protonpass").toString().replace(/^file:\/\//, "");
    }

    function filterItems(source, text) {
        var needle = String(text || "").toLocaleLowerCase();
        if (needle === "")
            return source;
        return source.filter(function(item) {
            return item.title.toLocaleLowerCase().indexOf(needle) !== -1
                || item.vaultName.toLocaleLowerCase().indexOf(needle) !== -1;
        });
    }

    function joinRecents(source, recentMetadata) {
        if (!showRecents || !Array.isArray(source) || !Array.isArray(recentMetadata))
            return [];
        var joined = [];
        for (var i = 0; i < recentMetadata.length && joined.length < 8; i++) {
            var recent = recentMetadata[i];
            for (var j = 0; j < source.length; j++) {
                if (source[j].shareId === recent.shareId && source[j].itemId === recent.itemId) {
                    joined.push({
                        itemId: source[j].itemId,
                        shareId: source[j].shareId,
                        vaultName: source[j].vaultName,
                        title: source[j].title,
                        createTime: source[j].createTime,
                        recentTs: recent.ts
                    });
                    break;
                }
            }
        }
        return joined;
    }

    function recentTimestamp(item) {
        if (!showRecents || !Array.isArray(recents))
            return null;
        for (var i = 0; i < recents.length; i++) {
            if (recents[i].shareId === item.shareId && recents[i].itemId === item.itemId)
                return recents[i].ts;
        }
        return null;
    }

    function relativeUsedText(timestamp) {
        var elapsedSeconds = Math.max(0, Math.floor((subtitleNow - timestamp * 1000) / 1000));
        var amount = Math.max(1, Math.floor(elapsedSeconds / 60));
        var unit = "minute";
        if (elapsedSeconds >= 31536000) {
            amount = Math.floor(elapsedSeconds / 31536000);
            unit = "year";
        } else if (elapsedSeconds >= 2592000) {
            amount = Math.floor(elapsedSeconds / 2592000);
            unit = "month";
        } else if (elapsedSeconds >= 86400) {
            amount = Math.floor(elapsedSeconds / 86400);
            unit = "day";
        } else if (elapsedSeconds >= 3600) {
            amount = Math.floor(elapsedSeconds / 3600);
            unit = "hour";
        }

        if (unit === "year")
            return amount === 1 ? qsTr("used 1 year ago") : qsTr("used %L1 years ago").arg(amount);
        if (unit === "month")
            return amount === 1 ? qsTr("used 1 month ago") : qsTr("used %L1 months ago").arg(amount);
        if (unit === "day")
            return amount === 1 ? qsTr("used 1 day ago") : qsTr("used %L1 days ago").arg(amount);
        if (unit === "hour")
            return amount === 1 ? qsTr("used 1 hour ago") : qsTr("used %L1 hours ago").arg(amount);
        return amount === 1 ? qsTr("used 1 minute ago") : qsTr("used %L1 minutes ago").arg(amount);
    }

    function subtitleFor(item) {
        var timestamp = item.recentTs !== undefined ? item.recentTs : recentTimestamp(item);
        if (timestamp !== null)
            return relativeUsedText(timestamp);
        var created = new Date(item.createTime);
        return qsTr("created %1").arg(created.toLocaleDateString(Qt.locale(), Locale.ShortFormat));
    }

    function refreshSubtitleNow() {
        subtitleNow = Date.now();
    }

    function _isObject(value) {
        return value !== null && typeof value === "object" && !Array.isArray(value);
    }

    function _isStringArray(value) {
        if (!Array.isArray(value))
            return false;
        for (var i = 0; i < value.length; i++) {
            if (typeof value[i] !== "string")
                return false;
        }
        return true;
    }

    function _knownState(commandName, responseState) {
        var states = {
            doctor: ["ok", "missing-deps"],
            index: ["ready", "cli-missing", "logged-out", "locked", "unreachable", "error"],
            copy: ["copied", "no-field", "cli-missing", "logged-out", "locked", "unreachable", "error"],
            lock: ["locked", "no-lock", "cli-missing", "logged-out", "unreachable", "error"],
            "clear-now": ["cleared", "not-owner", "error"],
            recents: ["ok", "error"],
            logout: ["logged-out-ok", "cli-missing", "unreachable", "error"],
            create: ["created", "invalid-input", "cli-missing", "logged-out", "locked", "unreachable", "error"]
        };
        return states[commandName] !== undefined && states[commandName].indexOf(responseState) !== -1;
    }

    // Returns a sanitized response or null. Never logs the response body:
    // malformed bodies may be attacker-controlled and must not reach shell logs.
    function _validatedResponse(raw, expectedCommand) {
        var data;
        try {
            data = JSON.parse(String(raw || ""));
        } catch (error) {
            console.warn("omarchy-protonpass: malformed helper response (command=" + expectedCommand + ")");
            return null;
        }

        if (!_isObject(data)
                || data.schemaVersion !== 1
                || data.command !== expectedCommand
                || typeof data.state !== "string"
                || !_knownState(expectedCommand, data.state)
                || typeof data.message !== "string") {
            console.warn("omarchy-protonpass: invalid helper envelope (command=" + expectedCommand + ")");
            return null;
        }

        if (expectedCommand === "doctor") {
            if (!_isObject(data.passCli)
                    || typeof data.passCli.present !== "boolean"
                    || typeof data.passCli.version !== "string"
                    || !_isObject(data.wlClipboard)
                    || typeof data.wlClipboard.present !== "boolean")
                return null;
        } else if (expectedCommand === "index") {
            if (!Array.isArray(data.items) || !Array.isArray(data.vaults) || !_isStringArray(data.warnings))
                return null;
            // The helper enforces these; the panel refuses them independently.
            // The helper is a separate process on PATH, so trusting its output
            // to be bounded would make the shared shell's memory depend on a
            // file we do not own.
            if (data.items.length > root.maxIndexItems || data.vaults.length > root.maxIndexVaults)
                return null;
            for (var i = 0; i < data.items.length; i++) {
                var item = data.items[i];
                if (!_isObject(item)
                        || typeof item.itemId !== "string"
                        || typeof item.shareId !== "string"
                        || typeof item.vaultName !== "string"
                        || typeof item.title !== "string"
                        || typeof item.createTime !== "string"
                        || !isFinite(Date.parse(item.createTime)))
                    return null;
            }
            for (var vaultIndex = 0; vaultIndex < data.vaults.length; vaultIndex++) {
                var vault = data.vaults[vaultIndex];
                if (!_isObject(vault)
                        || typeof vault.shareId !== "string"
                        || vault.shareId === ""
                        || typeof vault.name !== "string"
                        || vault.name === "")
                    return null;
            }
        } else if (expectedCommand === "copy") {
            if (["username", "password", "totp"].indexOf(data.field) === -1
                    || typeof data.fallbackUsed !== "boolean"
                    || typeof data.clearSeconds !== "number"
                    || !isFinite(data.clearSeconds)
                    || Math.floor(data.clearSeconds) !== data.clearSeconds
                    || data.clearSeconds < 0
                    || data.clearSeconds > 300)
                return null;
        } else if (expectedCommand === "create" && data.state === "created") {
            if (typeof data.itemId !== "string"
                    || typeof data.shareId !== "string"
                    || !/^[A-Za-z0-9+/=_-]{1,256}$/.test(data.itemId)
                    || !/^[A-Za-z0-9+/=_-]{1,256}$/.test(data.shareId))
                return null;
        } else if (expectedCommand === "recents" && data.recents !== undefined) {
            if (!Array.isArray(data.recents) || data.recents.length > 8)
                return null;
            for (var recentIndex = 0; recentIndex < data.recents.length; recentIndex++) {
                var recent = data.recents[recentIndex];
                if (!_isObject(recent)
                        || Object.keys(recent).sort().join(",") !== "itemId,shareId,ts"
                        || typeof recent.shareId !== "string"
                        || typeof recent.itemId !== "string"
                        || !/^[A-Za-z0-9+/=_-]{1,256}$/.test(recent.shareId)
                        || !/^[A-Za-z0-9+/=_-]{1,256}$/.test(recent.itemId)
                        || typeof recent.ts !== "number"
                        || !isFinite(recent.ts)
                        || Math.floor(recent.ts) !== recent.ts
                        || recent.ts < 0)
                    return null;
            }
        }

        return data;
    }

    // Shared epilogue for every helper command. Returns a validated response, or
    // null when the command is already finished -- it failed, or it was an
    // auth/dependency transition that owns the outcome by itself. Each onExited
    // keeps only its own tail.
    //
    // The index's generation fencing deliberately stays outside this: it has to
    // decide whether a response is relevant at all before anything here touches
    // shared state. Recents stays outside too, because it is fail-soft by
    // design and must not raise a program error.
    function _finish(exitCode, raw, commandName, failureToast) {
        var response = _validatedResponse(String(raw), commandName);
        if (exitCode !== 0 || response === null) {
            _programError();
            if (failureToast !== undefined && panelOpen)
                toastRequested(failureToast);
            return null;
        }
        if (response.state === "cli-missing") {
            _missingDependency(response.message);
            return null;
        }
        if (_authTransition(response.state, response.message))
            return null;
        return response;
    }

    function _programError() {
        state = "ERROR";
        message = "Something went wrong talking to pass-cli";
        refreshing = false;
        staleWarning = false;
    }

    function _clearIndex() {
        // An auth transition is authoritative. Invalidate any older index so
        // it cannot repopulate metadata after logout, lock, or session expiry.
        _indexGeneration++;
        _indexPending = false;
        if (indexProcess.running)
            indexProcess.running = false;
        items = [];
        vaults = [];
        recents = [];
        warnings = [];
        _hasIndex = false;
        refreshing = false;
        staleWarning = false;
    }

    function _authTransition(responseState, responseMessage) {
        if (responseState === "logged-out") {
            _clearIndex();
            state = "LOGGED_OUT";
            message = responseMessage;
            return true;
        }
        if (responseState === "locked") {
            _clearIndex();
            state = "LOCKED";
            message = responseMessage;
            return true;
        }
        return false;
    }

    function _missingDependency(responseMessage) {
        state = "MISSING_DEPS";
        message = responseMessage;
        refreshing = false;
        staleWarning = false;
        _doctorReady = false;
    }

    function runDoctor(continueWithIndex) {
        _doctorContinueIndex = _doctorContinueIndex || continueWithIndex;
        if (doctorProcess.running)
            return;
        doctorProcess.command = [helperPath(), "doctor"];
        doctorProcess.running = true;
    }

    function _launchIndex() {
        if (!panelOpen || indexProcess.running)
            return;
        _indexPending = false;
        _activeIndexGeneration = _indexGeneration;
        indexProcess.command = [helperPath(), "index", "--exclude-vaults", String(setting("excludeVaults", ""))];
        indexProcess.running = true;
    }

    function refresh() {
        if (!panelOpen)
            return;

        _indexGeneration++;
        staleWarning = false;
        if (_hasIndex) {
            state = "READY";
            refreshing = true;
        } else {
            state = "LOADING";
            refreshing = false;
        }

        if (indexProcess.running) {
            _indexPending = true;
            indexProcess.running = false;
            return;
        }
        _launchIndex();
    }

    function retry() {
        refresh();
    }

    function recheck() {
        runDoctor(true);
    }

    function onPanelOpened() {
        if (panelOpen)
            return;
        panelOpen = true;
        refreshSubtitleNow();
        if (showRecents)
            runRecents("load");

        if (state === "MISSING_DEPS") {
            runDoctor(true);
        } else if (!_doctorReady) {
            runDoctor(true);
        } else if (state === "LOADING" && indexProcess.running
                && _activeIndexGeneration !== _indexGeneration) {
            // The panel reopened while a close-triggered SIGTERM was still in
            // flight. Start the current generation as soon as it exits.
            _indexPending = true;
        } else if (state !== "LOADING" || !indexProcess.running) {
            refresh();
        }
    }

    function onPanelClosed() {
        panelOpen = false;
        _doctorContinueIndex = false;
        _indexPending = false;
        if (indexProcess.running) {
            // Invalidate before SIGTERM so onExited cannot publish stale data.
            _indexGeneration++;
            indexProcess.running = false;
        }
        refreshing = false;
        // Copy, create, clear-now, lock, recents, and logout processes intentionally continue to completion.
    }

    function copy(shareId, itemId, field) {
        var share = String(shareId || "");
        var item = String(itemId || "");
        var requestedField = String(field || "");
        if (copyBusy
                || !/^[A-Za-z0-9+/=_-]{1,256}$/.test(share)
                || !/^[A-Za-z0-9+/=_-]{1,256}$/.test(item)
                || ["username", "password", "totp"].indexOf(requestedField) === -1)
            return false;

        var commandLine = [helperPath(), "copy", "--share-id", share, "--item-id", item,
            "--field", requestedField, "--clear-seconds", String(intSetting("clipboardClearSeconds", 45, 0, 300))];
        if (boolSetting("pasteOnce", false))
            commandLine.push("--paste-once");

        copyProcess.command = commandLine;
        copyBusy = true;
        copyProcess.running = true;
        return true;
    }

    function _unicodeLength(value) {
        var text = String(value);
        var count = 0;
        for (var i = 0; i < text.length; i++) {
            var code = text.charCodeAt(i);
            if (code >= 0xD800 && code <= 0xDBFF && i + 1 < text.length) {
                var next = text.charCodeAt(i + 1);
                if (next >= 0xDC00 && next <= 0xDFFF)
                    i++;
            }
            count++;
        }
        return count;
    }

    function validCreateInput(shareId, title, identifierField, identifier) {
        return /^[A-Za-z0-9+/=_-]{1,256}$/.test(String(shareId || ""))
            && typeof title === "string"
            && _unicodeLength(title) > 0
            && _unicodeLength(title) <= 500
            && ["username", "email"].indexOf(identifierField) !== -1
            && typeof identifier === "string"
            && _unicodeLength(identifier) <= 500;
    }

    function create(shareId, title, identifierField, identifier) {
        var share = String(shareId || "");
        if (state !== "READY" || copyBusy || createBusy
                || !validCreateInput(share, title, identifierField, identifier))
            return false;

        var body = { title: title };
        body[identifierField] = identifier;
        _createInput = JSON.stringify(body);
        createProcess.command = [helperPath(), "create", "--share-id", share];
        createBusy = true;
        createProcess.running = true;
        return true;
    }

    function _hideClipboardCountdown() {
        clipboardCountdownTimer.stop();
        clipboardClearSeconds = 0;
        clipboardSecondsRemaining = 0;
    }

    function _startClipboardCountdown(clearSeconds) {
        clipboardCountdownTimer.stop();
        clipboardClearSeconds = clearSeconds;
        clipboardSecondsRemaining = clearSeconds;
        if (clearSeconds > 0)
            clipboardCountdownTimer.start();
    }

    function clearClipboard() {
        if (clearClipboardProcess.running)
            return false;
        clearClipboardProcess.command = [helperPath(), "clear-now"];
        clearClipboardBusy = true;
        clearClipboardProcess.running = true;
        return true;
    }

    function lock() {
        if (lockProcess.running)
            return false;
        lockProcess.command = [helperPath(), "lock"];
        lockProcess.running = true;
        return true;
    }

    function runRecents(operation) {
        if (["load", "clear"].indexOf(operation) === -1)
            return false;
        if (recentsProcess.running) {
            _pendingRecentsOperation = operation;
            return true;
        }
        _recentsOperation = operation;
        recentsProcess.command = [helperPath(), "recents", operation];
        recentsProcess.running = true;
        return true;
    }

    function syncRecentsSetting() {
        if (showRecents) {
            if (panelOpen)
                runRecents("load");
        } else {
            recents = [];
            runRecents("clear");
        }
    }

    function logout() {
        if (logoutProcess.running)
            return false;
        logoutProcess.command = [helperPath(), "logout"];
        logoutBusy = true;
        logoutProcess.running = true;
        return true;
    }

    function _copyToast(response) {
        if (response.state === "no-field") {
            return response.field === "totp"
                ? "No TOTP on this item"
                : "No username or email on this item";
        }
        if (response.state !== "copied")
            return "Copy failed — check connection and try again";

        var label = response.field === "password" ? "Password"
            : response.field === "totp" ? "TOTP"
            : response.fallbackUsed ? "Email" : "Username";
        return label + " copied" + (response.clearSeconds > 0 ? " — clears in " + response.clearSeconds + "s" : "");
    }

    visible: false

    onItemsChanged: refreshSubtitleNow()
    onRecentsChanged: refreshSubtitleNow()

    // The one clock in the plugin. Row subtitles and the panel header's
    // synced-age text both read subtitleNow, so they cannot drift apart, and
    // nothing ticks while the panel is closed.
    Timer {
        interval: 30000
        repeat: true
        running: root.panelOpen && root.state === "READY"
        onTriggered: root.refreshSubtitleNow()
    }

    Timer {
        id: clipboardCountdownTimer
        interval: 1000
        repeat: true
        onTriggered: {
            if (root.clipboardSecondsRemaining <= 1) {
                root._hideClipboardCountdown();
            } else {
                root.clipboardSecondsRemaining--;
            }
        }
    }

    Component.onCompleted: {
        root.runDoctor(false);
        root.syncRecentsSetting();
    }

    onShowRecentsChanged: root.syncRecentsSetting()

    Process {
        id: doctorProcess
        running: false
        command: []
        onExited: function(exitCode) {
            var shouldIndex = root._doctorContinueIndex;
            root._doctorContinueIndex = false;
            var response = root._finish(exitCode, doctorOutput.text, "doctor");
            if (response === null) {
                root._doctorReady = false;
                return;
            }
            if (response.state === "missing-deps") {
                root._doctorReady = false;
                root.state = "MISSING_DEPS";
                root.message = response.message;
                return;
            }
            root._doctorReady = true;
            root.state = "INIT";
            root.message = response.message;
            if (shouldIndex && root.panelOpen)
                Qt.callLater(root.refresh);
        }
        stdout: StdioCollector {
            id: doctorOutput
            waitForEnd: true
        }
        stderr: StdioCollector { waitForEnd: true }
    }

    Process {
        id: indexProcess
        running: false
        command: []
        onExited: function(exitCode) {
            var responseGeneration = root._activeIndexGeneration;
            var pending = root._indexPending;
            if (responseGeneration !== root._indexGeneration) {
                if (pending && root.panelOpen)
                    Qt.callLater(root._launchIndex);
                return;
            }

            root.refreshing = false;
            var response = root._finish(exitCode, indexOutput.text, "index");
            if (response === null) {
                // Failed, or an auth/cli-missing transition already handled it.
            } else if (response.state === "ready") {
                var cleanItems = [];
                var cleanVaults = [];
                for (var i = 0; i < response.items.length; i++) {
                    cleanItems.push({
                        itemId: response.items[i].itemId,
                        shareId: response.items[i].shareId,
                        vaultName: response.items[i].vaultName,
                        title: response.items[i].title,
                        createTime: response.items[i].createTime
                    });
                }
                for (var vaultIndex = 0; vaultIndex < response.vaults.length; vaultIndex++) {
                    cleanVaults.push({
                        shareId: response.vaults[vaultIndex].shareId,
                        name: response.vaults[vaultIndex].name
                    });
                }
                root.items = cleanItems;
                root.vaults = cleanVaults;
                root.warnings = response.warnings.slice();
                root._hasIndex = true;
                root.lastSuccessfulIndexAt = Date.now();
                root.state = "READY";
                root.message = response.message;
                root.staleWarning = false;
            } else if (root._hasIndex && (response.state === "unreachable" || response.state === "error")) {
                root.state = "READY";
                root.message = response.message;
                root.staleWarning = true;
            } else {
                root.state = response.state === "unreachable" ? "UNREACHABLE" : "ERROR";
                root.message = response.message;
                root.staleWarning = false;
            }
        }
        stdout: StdioCollector {
            id: indexOutput
            waitForEnd: true
        }
        stderr: StdioCollector { waitForEnd: true }
    }

    Process {
        id: copyProcess
        running: false
        command: []
        onExited: function(exitCode) {
            root.copyBusy = false;
            var response = root._finish(exitCode, copyOutput.text, "copy",
                "Copy failed — check connection and try again");
            if (response === null)
                return;
            if (response.state === "copied")
                root._startClipboardCountdown(response.clearSeconds);
            if (root.panelOpen)
                root.toastRequested(root._copyToast(response));
            if (response.state === "copied" && root.showRecents && root.panelOpen)
                root.runRecents("load");
        }
        stdout: StdioCollector {
            id: copyOutput
            waitForEnd: true
        }
        stderr: StdioCollector { waitForEnd: true }
    }

    Process {
        id: createProcess
        running: false
        command: []
        stdinEnabled: true
        onStarted: {
            write(root._createInput);
            root._createInput = "";
            // Closing stdin is required: the helper reads the template with
            // CREATE_INPUT=$(cat) and blocks forever without EOF.
            createProcess.stdinEnabled = false;
        }
        onExited: function(exitCode) {
            root.createBusy = false;
            root._createInput = "";
            var response = root._finish(exitCode, createOutput.text, "create",
                "Could not create login");
            if (response === null)
                return;
            if (response.state === "created") {
                if (root.panelOpen) {
                    root.loginCreated(response.shareId, response.itemId);
                    root.refresh();
                }
            } else if (root.panelOpen) {
                root.toastRequested(response.state === "invalid-input"
                    ? "Check the login details and try again"
                    : "Could not create login");
            }
        }
        stdout: StdioCollector {
            id: createOutput
            waitForEnd: true
        }
        stderr: StdioCollector { waitForEnd: true }
    }

    Process {
        id: clearClipboardProcess
        running: false
        command: []
        onExited: function(exitCode) {
            root.clearClipboardBusy = false;
            var response = root._finish(exitCode, clearClipboardOutput.text, "clear-now");
            if (response === null)
                return;
            if (response.state === "cleared" || response.state === "not-owner") {
                root._hideClipboardCountdown();
                if (response.state === "cleared" && root.panelOpen)
                    root.toastRequested("Clipboard cleared");
            } else if (root.panelOpen) {
                root.toastRequested("Could not clear clipboard");
            }
        }
        stdout: StdioCollector {
            id: clearClipboardOutput
            waitForEnd: true
        }
        stderr: StdioCollector { waitForEnd: true }
    }

    Process {
        id: lockProcess
        running: false
        command: []
        onExited: function(exitCode) {
            // "locked" is an auth transition, so _finish has already cleared the
            // index and entered LOCKED by the time this returns null.
            var response = root._finish(exitCode, lockOutput.text, "lock");
            if (response === null)
                return;
            if (response.state === "no-lock") {
                if (root.panelOpen)
                    root.toastRequested("No session lock configured — run pass-cli session create-lock");
            } else if (root.panelOpen) {
                root.toastRequested("Could not lock Proton Pass");
            }
        }
        stdout: StdioCollector {
            id: lockOutput
            waitForEnd: true
        }
        stderr: StdioCollector { waitForEnd: true }
    }

    Process {
        id: recentsProcess
        running: false
        command: []
        onExited: function(exitCode) {
            var operation = root._recentsOperation;
            // Deliberately not _finish: a failed recents read is ignored, never
            // escalated to a program error.
            var response = root._validatedResponse(String(recentsOutput.text), "recents");
            if (exitCode === 0 && response !== null && response.state === "ok") {
                if (operation === "load" && Array.isArray(response.recents) && root.showRecents)
                    root.recents = response.recents.slice(0, 8);
                else if (operation === "clear")
                    root.recents = [];
            }
            var pending = root._pendingRecentsOperation;
            root._pendingRecentsOperation = "";
            if (pending !== "")
                Qt.callLater(function() { root.runRecents(pending); });
        }
        stdout: StdioCollector {
            id: recentsOutput
            waitForEnd: true
        }
        stderr: StdioCollector { waitForEnd: true }
    }

    Process {
        id: logoutProcess
        running: false
        command: []
        onExited: function(exitCode) {
            root.logoutBusy = false;
            var response = root._finish(exitCode, logoutOutput.text, "logout");
            if (response === null)
                return;
            if (response.state === "logged-out-ok") {
                root._clearIndex();
                root.state = "LOGGED_OUT";
                root.message = response.message;
            } else if (root.panelOpen) {
                root.toastRequested("Could not log out — check connection and try again");
            }
        }
        stdout: StdioCollector {
            id: logoutOutput
            waitForEnd: true
        }
        stderr: StdioCollector { waitForEnd: true }
    }
}
