#!/usr/bin/env python3
"""Generate Kanata configurations from the canonical Shingeta YAML."""

import argparse
from pathlib import Path

import yaml

HERE = Path(__file__).resolve().parent
DEFAULT_SOURCE = HERE.parent / "xremap" / "shingeta.yml"

INPUT_NAMES = {
    "KEY_DOT": ".",
    "KEY_EQUAL": "=",
    "KEY_MINUS": "-",
    "KEY_COMMA": ",",
    "KEY_F24": "f24",
    "KEY_APOSTROPHE": "apos",
}
OUTPUT_NAMES = {
    "KEY_DOT": ".",
    "DOT": ".",
    "KEY_EQUAL": "=",
    "EQUAL": "=",
    "KEY_MINUS": "-",
    "MINUS": "-",
    "KEY_COMMA": ",",
    "COMMA": ",",
    "KEY_F24": "f24",
    "F24": "f24",
    "KEY_APOSTROPHE": "apos",
    "APOSTROPHE": "apos",
    "KEY_SLASH": "/",
    "SLASH": "/",
    "KEY_1": "1",
    "KEY_2": "2",
    "KEY_3": "3",
    "KEY_4": "4",
    "KEY_5": "5",
    "KEY_6": "6",
    "KEY_7": "7",
    "KEY_8": "8",
    "KEY_9": "9",
    "KEY_0": "0",
    "LEFTBRACE": "[",
    "RIGHTBRACE": "]",
    "BACKSLASH": "bksl",
    "GRAVE": "grv",
}

# Inverse of the active Goku JIS-to-custom base layout. Canonical Shingeta
# keys are logical keys; Kanata chords must name the physical macOS keys.
MAC_LOGICAL_TO_PHYSICAL = {
    "k": "q",
    "y": "w",
    "o": "e",
    ".": "r",
    "=": "t",
    "f": "y",
    "c": "u",
    "l": "i",
    "p": "o",
    "q": "p",
    "z": "[",
    "h": "a",
    "i": "s",
    "e": "d",
    "a": "f",
    "u": "g",
    "d": "h",
    "s": "j",
    "t": "k",
    "n": "l",
    "r": ";",
    "v": "apos",
    "j": "z",
    "-": "x",
    ",": "c",
    "f24": "v",
    "apos": "b",
    "w": "n",
    "g": "m",
    "m": ",",
    "b": ".",
    "x": "/",
}

# Physical key -> (unshifted action, shifted action). AquaSKK's ASCII input
# interprets Kanata's VirtualHID output usages with ANSI symbol semantics even
# though the device advertises JIS country code 33. These actions reproduce the
# characters documented by homes/darwin/karabiner.edn on the real watari JIS
# keyboard.
MAC_BASE_ACTIONS = {
    "1": ("S-1", "(unshift 9)"),
    "2": ("S-7", "(unshift 7)"),
    "3": ("S-,", "(unshift 5)"),
    "4": ("[", "(unshift 3)"),
    "5": ("S-[", "(unshift 1)"),
    "6": ("S-grv", "(unshift 8)"),
    "7": ("S-]", "(unshift 0)"),
    "8": ("]", "(unshift 2)"),
    "9": ("S-.", "(unshift 4)"),
    "0": ("S-4", "(unshift 6)"),
    # Lean's Unicode input leader is far more frequent than `#`. Reclaim the
    # duplicate shifted `!` path: physical number-row `- / =` now emits `\\`
    # on tap and `#` with Shift; `!` remains on physical `1 / !`.
    "-": ("(unshift bksl)", "S-3"),
    "=": ("S-2", "(unshift grv)"),
    "q": ("k", "k"),
    "w": ("y", "y"),
    "e": ("o", "o"),
    "r": (".", "(unshift ;)"),
    "t": ("=", "S-;"),
    "y": ("f", "f"),
    "u": ("c", "c"),
    "i": ("l", "l"),
    "o": ("p", "p"),
    "p": ("q", "q"),
    "[": ("z", "z"),
    "]": ("S-5", "S-6"),
    "a": ("h", "h"),
    "s": ("i", "i"),
    "d": ("e", "e"),
    "f": ("a", "a"),
    "g": ("u", "u"),
    "h": ("d", "d"),
    "j": ("s", "s"),
    "k": ("t", "t"),
    "l": ("n", "n"),
    ";": ("r", "r"),
    "apos": ("v", "v"),
    # A1 moved `\\` to the physical number-row `- / =` key. Reuse the former
    # shifted Yen-key leader path for the otherwise unreachable ASCII `?`.
    "¥": ("S-bksl", "S-/"),
    "z": ("j", "j"),
    "x": ("-", "S-8"),
    "c": (",", "S--"),
    "v": ("S-9", "S-="),
    "b": ("apos", "S-apos"),
    "n": ("w", "w"),
    "m": ("g", "g"),
    ",": ("m", "m"),
    ".": ("b", "b"),
    "/": ("x", "x"),
    "ro": ("S-0", "(unshift /)"),
}
MAC_DEVICE_PLACEHOLDER = "REPLACE_WITH_EXACT_DEVICE_NAME_FROM_KANATA_LIST"


def ikey(value):
    return INPUT_NAMES.get(value) or INPUT_NAMES.get(value.upper()) or value.lower()


def okey(value):
    if value.upper().startswith("SHIFT-"):
        return "S-" + okey(value[6:])
    return OUTPUT_NAMES.get(value) or OUTPUT_NAMES.get(value.upper()) or value.lower()


def seq(value):
    if isinstance(value, str):
        value = [value]
    return [okey(item) for item in value]


def macro(value):
    tokens = [
        ("Digit" + token) if token in "0123456789" and len(token) == 1 else token
        for token in seq(value)
    ]
    return "(macro " + " ".join(tokens) + ")"


def alias_name(key):
    return (
        "single-"
        + ikey(key)
        .replace("'", "apos")
        .replace(".", "dot")
        .replace("=", "equal")
        .replace("-", "minus")
        .replace(",", "comma")
    )


def load_maps(source):
    data = yaml.safe_load(source.read_text())
    keymaps = data["keymap"]
    default = next(item for item in keymaps if item.get("mode") == "default")["remap"]
    shinyou = next(item for item in keymaps if item.get("name") == "shinyou")["remap"]
    return default, shinyou


def unordered_chords(shinyou):
    chords = []
    seen = set()
    for first, rule in shinyou.items():
        timeout = rule["timeout_millis"]
        for second, output in rule.get("remap", {}).items():
            pair = tuple(sorted((ikey(first), ikey(second))))
            if pair in seen:
                continue
            seen.add(pair)
            chords.append((pair, output, timeout))
    return chords


def generate_linux(default, shinyou):
    primaries = list(shinyou)
    physical = ["lctl", "rctl", "lsft", "rsft", "spc"] + [
        ikey(key) for key in primaries
    ] + [f"th{i}" for i in range(1, 15)] + ["rpar"]
    physical = list(dict.fromkeys(physical))

    aliases = [
        "sp-default (switch ((or (input real lctl) (input real rctl))) (multi spc (layer-switch shingeta)) break () spc break)",
        "sp-shingeta (switch ((or (input real lctl) (input real rctl))) (multi spc (layer-switch default)) break () spc break)",
    ]
    for key, rule in shinyou.items():
        aliases.append(f'{alias_name(key)} {macro(rule["timeout_key"])}')

    special = {}
    for i in range(1, 15):
        base_key = f"BTN_TRIGGER_HAPPY{i}"
        plain = default[base_key]
        shifted = default[f"Shift-{base_key}"]
        shifted_action = macro(shifted)
        shifted_values = [shifted] if isinstance(shifted, str) else shifted
        if not any(value.upper().startswith("SHIFT-") for value in shifted_values):
            shifted_action = "(unmod " + " ".join(seq(shifted)) + ")"
        name = f"th{i}-default"
        aliases.append(
            f"{name} (switch (lsft rsft) {shifted_action} break () {macro(plain)} break)"
        )
        special[f"th{i}"] = "@" + name
    aliases.append(
        "rpar-default (switch (lsft rsft) (unmod /) break () rpar break)"
    )
    aliases.append(
        "f24-default (switch (lsft rsft) (macro S-=) break () (macro S-9) break)"
    )
    special["rpar"] = "@rpar-default"
    special["f24"] = "@f24-default"

    lines = ["(deflocalkeys-linux"] + [
        f"  th{i} {703 + i}" for i in range(1, 15)
    ] + [")", ""]
    lines += ["(defsrc", "  " + " ".join(physical), ")", ""]
    lines += ["(defalias"] + [f"  {alias}" for alias in aliases] + [")", ""]

    def layer_actions(name):
        actions = []
        logical_primaries = [ikey(key) for key in primaries]
        for key in physical:
            if key == "spc":
                actions.append("@sp-" + name)
            elif name == "shingeta" and key in logical_primaries:
                original = primaries[logical_primaries.index(key)]
                actions.append("@" + alias_name(original))
            elif name == "default" and key in special:
                actions.append(special[key])
            else:
                actions.append(key)
        return actions

    for name in ["default", "shingeta"]:
        lines += [f"(deflayer {name}", "  " + " ".join(layer_actions(name)), ")", ""]
    lines += ["(defchordsv2"]
    for pair, output, timeout in unordered_chords(shinyou):
        lines.append(
            f"  ({pair[0]} {pair[1]}) {macro(output)} {timeout} first-release (default)"
        )
    lines += [")", ""]
    return "\n".join(lines), len(primaries), len(unordered_chords(shinyou)), len(physical)


def mac_alias_for_base(key, plain, shifted):
    if plain == shifted and plain not in {"S-1"}:
        return plain
    suffix = {
        "[": "lbrc",
        "]": "rbrc",
        ";": "scln",
        ",": "comma",
        ".": "dot",
        "/": "slash",
        "-": "minus",
        "=": "equal",
        "¥": "yen",
    }.get(key) or key
    name = "base-" + suffix
    return name, f"{name} (switch (lsft rsft) {shifted} break () {plain} break)"


def generate_macos(_default, shinyou):
    primaries = list(shinyou)
    if len(primaries) != 32 or set(map(ikey, primaries)) != set(MAC_LOGICAL_TO_PHYSICAL):
        raise ValueError("canonical 32-key Shingeta set no longer matches the macOS base map")
    timeouts = {rule["timeout_millis"] for rule in shinyou.values()}
    if timeouts != {40}:
        raise ValueError(f"macOS tranche requires one 40ms timeout, got {sorted(timeouts)}")

    physical = [
        "eisu",
        "kana",
        "lctl",
        "rctl",
        "lsft",
        "rsft",
        "spc",
        *MAC_BASE_ACTIONS.keys(),
    ]
    aliases = [
        "to-shingeta (multi (macro kana) (layer-switch shingeta))",
        "to-ascii (multi (macro l) (layer-switch ascii))",
    ]
    base_actions = {}
    for key, actions in MAC_BASE_ACTIONS.items():
        result = mac_alias_for_base(key, *actions)
        if isinstance(result, tuple):
            name, definition = result
            aliases.append(definition)
            base_actions[key] = "@" + name
        else:
            base_actions[key] = result

    logical_by_physical = {
        physical_key: logical for logical, physical_key in MAC_LOGICAL_TO_PHYSICAL.items()
    }
    for key, rule in shinyou.items():
        timeout_key = rule.get("macos_timeout_key", rule["timeout_key"])
        aliases.append(f"{alias_name(key)} {macro(timeout_key)}")

    lines = [
        ";; Generated from systems/nixos/services/xremap/shingeta.yml; do not edit.",
        ";; The Linux-only alias lets the same Kanata 1.12 parser validate this macOS file.",
        "(deflocalkeys-linux eisu 123)",
        "",
        "(defcfg",
        "  process-unmapped-keys yes",
        "  concurrent-tap-hold yes",
        "  log-layer-changes yes",
        "  macos-dev-names-include (",
        f'    "{MAC_DEVICE_PLACEHOLDER}"',
        "  )",
        ")",
        "",
        "(defsrc",
        "  " + " ".join(physical),
        ")",
        "",
        "(defalias",
        *[f"  {alias}" for alias in aliases],
        ")",
        "",
    ]

    def layer_actions(name):
        actions = []
        for key in physical:
            if key == "eisu":
                actions.append("rctl")
            elif key == "kana":
                actions.append("lsft")
            elif key == "lctl":
                actions.append("@to-shingeta" if name == "ascii" else "@to-ascii")
            elif name == "shingeta" and key in logical_by_physical:
                logical = logical_by_physical[key]
                original = primaries[[ikey(item) for item in primaries].index(logical)]
                actions.append("@" + alias_name(original))
            elif key in base_actions:
                actions.append(base_actions[key])
            else:
                actions.append(key)
        return actions

    for name in ["ascii", "shingeta"]:
        lines += [f"(deflayer {name}", "  " + " ".join(layer_actions(name)), ")", ""]

    lines.append("(defchordsv2")
    for pair, output, timeout in unordered_chords(shinyou):
        mac_pair = tuple(sorted(MAC_LOGICAL_TO_PHYSICAL[key] for key in pair))
        lines.append(
            f"  ({mac_pair[0]} {mac_pair[1]}) {macro(output)} {timeout} first-release (ascii)"
        )
    lines += [")", ""]
    return "\n".join(lines), len(primaries), len(unordered_chords(shinyou)), len(physical)


def main():
    parser = argparse.ArgumentParser(
        description="Generate Kanata configuration from canonical xremap Shingeta YAML"
    )
    parser.add_argument("--source", type=Path, default=DEFAULT_SOURCE)
    parser.add_argument("--platform", choices=("linux", "macos"), default="linux")
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    output = args.output or HERE / "shingeta.kbd"

    default, shinyou = load_maps(args.source)
    generator = generate_linux if args.platform == "linux" else generate_macos
    text, singles, chords, source_keys = generator(default, shinyou)
    output.write_text(text)
    print(
        f"wrote {output}: {singles} singles, {chords} unordered chords, "
        f"{source_keys} defsrc keys ({args.platform})"
    )


if __name__ == "__main__":
    main()
