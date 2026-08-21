var DEFAULT_BINDINGS = {
    "enter": "copy-password",
    "shift+enter": "copy-username",
    "ctrl+u": "copy-username",
    "ctrl+p": "copy-password",
    "ctrl+t": "copy-totp",
    "ctrl+r": "refresh",
    "ctrl+l": "lock",
    "ctrl+shift+x": "clear-clipboard"
};

var DEFAULT_PREFERRED = {
    "copy-username": "ctrl+u",
    "copy-password": "ctrl+p",
    "copy-totp": "ctrl+t",
    "refresh": "ctrl+r",
    "lock": "ctrl+l",
    "clear-clipboard": "ctrl+shift+x"
};

var ACTIONS = [
    "copy-username",
    "copy-password",
    "copy-totp",
    "clear-clipboard",
    "lock",
    "logout",
    "refresh"
];

function copyObject(source) {
    var result = {};
    var keys = Object.keys(source);
    for (var i = 0; i < keys.length; i++)
        result[keys[i]] = source[keys[i]];
    return result;
}

function firstChordForAction(bindings, action) {
    var chords = Object.keys(bindings);
    for (var i = 0; i < chords.length; i++) {
        if (bindings[chords[i]] === action)
            return chords[i];
    }
    return "";
}

function parse(raw, warn) {
    var bindings = copyObject(DEFAULT_BINDINGS);
    var preferred = copyObject(DEFAULT_PREFERRED);
    var customPreferred = {};
    var text = String(raw === undefined || raw === null ? "" : raw);
    if (text.trim() !== "") {
        var entries = text.split(",");
        for (var i = 0; i < entries.length; i++) {
            var namedEntry = entries[i].trim();
            var parts = namedEntry.split(":");
            var chord = parts.length === 2 ? parts[0].trim().toLowerCase() : "";
            var action = parts.length === 2 ? parts[1].trim().toLowerCase() : "";
            var validChord = /^(ctrl\+)?(shift\+)?(alt\+)?(enter|f[1-9]|[a-z])$/.test(chord);
            if (!validChord || ACTIONS.indexOf(action) === -1) {
                if (typeof warn === "function")
                    warn(namedEntry);
                continue;
            }
            bindings[chord] = action;
            customPreferred[action] = chord;
        }
    }

    for (var actionIndex = 0; actionIndex < ACTIONS.length; actionIndex++) {
        var actionName = ACTIONS[actionIndex];
        var customChord = customPreferred[actionName] || "";
        var defaultChord = preferred[actionName] || "";
        if (customChord !== "" && bindings[customChord] === actionName)
            preferred[actionName] = customChord;
        else if (defaultChord === "" || bindings[defaultChord] !== actionName)
            preferred[actionName] = firstChordForAction(bindings, actionName);
    }

    return {bindings: bindings, preferred: preferred};
}

function display(chord) {
    if (!chord)
        return "";
    return String(chord).split("+").map(function(part) {
        if (part === "ctrl") return "Ctrl";
        if (part === "shift") return "Shift";
        if (part === "alt") return "Alt";
        if (part === "enter") return "Enter";
        return part.toUpperCase();
    }).join("+");
}
