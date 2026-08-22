var DEFAULT_BINDINGS = {
    "enter": "copy-password",
    "shift+enter": "copy-username",
    "ctrl+u": "copy-username",
    "ctrl+p": "copy-password",
    "ctrl+t": "copy-totp",
    "ctrl+r": "refresh",
    "ctrl+l": "lock",
    "ctrl+shift+x": "clear-clipboard",

    // List-focus bindings. The chord grammar always allowed bare letters; these
    // lived hard-coded in the panel's key catcher instead, which is why binding
    // one in settings silently shadowed it. They fire only when the search
    // field does not have focus -- see isTypingChord in Panel.qml.
    "u": "copy-username",
    "p": "copy-password",
    "t": "copy-totp",
    "r": "refresh",
    "shift+l": "lock",
    "j": "cursor-down",
    "k": "cursor-up"
};

// Actions a user may bind. Cursor movement is deliberately absent: it is bound
// by default but is not part of the documented remap vocabulary, so binding it
// by name stays an error rather than silently growing the public surface.
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

function parse(raw, warn) {
    var bindings = copyObject(DEFAULT_BINDINGS);
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
        }
    }

    return {bindings: bindings};
}
