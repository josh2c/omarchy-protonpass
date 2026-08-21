const fs = require("fs");
const vm = require("vm");

const source = fs.readFileSync(process.argv[2], "utf8");
const context = {};
vm.createContext(context);
vm.runInContext(source, context, {filename: process.argv[2]});

function assert(condition, message) {
    if (!condition) {
        process.stderr.write(`FAIL: ${message}\n`);
        process.exit(1);
    }
}

let warnings = [];
let parsed = context.parse("", entry => warnings.push(entry));
assert(parsed.bindings["ctrl+u"] === "copy-username", "Ctrl+U default");
assert(parsed.bindings["ctrl+p"] === "copy-password", "Ctrl+P default");
assert(parsed.bindings["ctrl+t"] === "copy-totp", "Ctrl+T default");
assert(parsed.bindings["ctrl+r"] === "refresh", "Ctrl+R default");
assert(parsed.bindings["ctrl+l"] === "lock", "Ctrl+L default");
assert(parsed.bindings["ctrl+shift+x"] === "clear-clipboard", "Ctrl+Shift+X default");
assert(parsed.bindings.enter === "copy-password", "Enter default");
assert(parsed.bindings["shift+enter"] === "copy-username", "Shift+Enter default");
assert(warnings.length === 0, "empty settings do not warn");

warnings = [];
parsed = context.parse("ctrl+;:copy-password,meta+x:logout", entry => warnings.push(entry));
assert(warnings.length === 2, "invalid entries warn exactly once each");
assert(warnings[0] === "ctrl+;:copy-password", "invalid punctuation entry is named");
assert(warnings[1] === "meta+x:logout", "invalid Meta entry is named");
assert(parsed.bindings["ctrl+p"] === "copy-password", "invalid entries leave defaults intact");

warnings = [];
parsed = context.parse("CTRL+O:logout,ctrl+o:refresh", entry => warnings.push(entry));
assert(parsed.bindings["ctrl+o"] === "refresh", "duplicate chords keep the last valid entry");
assert(parsed.bindings["ctrl+p"] === "copy-password", "unlisted defaults remain");
assert(parsed.preferred.refresh === "ctrl+o", "last custom binding becomes the displayed shortcut");
assert(parsed.preferred.logout === "", "overridden duplicate is not displayed for its old action");
assert(warnings.length === 0, "case-insensitive valid entries do not warn");

parsed = context.parse("ctrl+shift+c:copy-password", () => {});
assert(parsed.bindings["ctrl+shift+c"] === "copy-password", "valid custom chord is added");
assert(parsed.preferred["copy-password"] === "ctrl+shift+c", "custom chord is preferred in labels");
assert(context.display("ctrl+shift+c") === "Ctrl+Shift+C", "shortcut display is readable");

process.stdout.write("keybind parser tests passed\n");
