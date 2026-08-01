#!/usr/bin/env python3
import argparse
from pathlib import Path
import yaml

HERE = Path(__file__).resolve().parent
parser = argparse.ArgumentParser(description='Generate the Kanata module body from canonical xremap Shingeta YAML')
parser.add_argument('--source', type=Path, default=HERE.parent / 'xremap' / 'shingeta.yml')
parser.add_argument('--output', type=Path, default=HERE / 'shingeta.kbd')
args = parser.parse_args()
SRC = args.source
OUT = args.output
data = yaml.safe_load(SRC.read_text())
keymaps = data['keymap']
default = next(k for k in keymaps if k.get('mode') == 'default')['remap']
shinyou = next(k for k in keymaps if k.get('name') == 'shinyou')['remap']

input_names = {
    'KEY_DOT': '.', 'KEY_EQUAL': '=', 'KEY_MINUS': '-', 'KEY_COMMA': ',',
    'KEY_F24': 'f24', 'KEY_APOSTROPHE': 'apos',
}
output_names = {
    'KEY_DOT': '.', 'DOT': '.', 'KEY_EQUAL': '=', 'EQUAL': '=',
    'KEY_MINUS': '-', 'MINUS': '-', 'KEY_COMMA': ',', 'COMMA': ',',
    'KEY_F24': 'f24', 'F24': 'f24', 'KEY_APOSTROPHE': 'apos', 'APOSTROPHE': 'apos',
    'KEY_SLASH': '/', 'SLASH': '/', 'KEY_1': '1', 'KEY_2': '2', 'KEY_3': '3',
    'KEY_4': '4', 'KEY_5': '5', 'KEY_6': '6', 'KEY_7': '7', 'KEY_8': '8',
    'KEY_9': '9', 'KEY_0': '0', 'LEFTBRACE': '[', 'RIGHTBRACE': ']',
    'BACKSLASH': 'bksl', 'GRAVE': 'grv',
}

def ikey(x): return input_names.get(x, input_names.get(x.upper(), x.lower()))
def okey(x):
    if x.upper().startswith('SHIFT-'):
        return 'S-' + okey(x[6:])
    return output_names.get(x, output_names.get(x.upper(), x.lower()))
def seq(v):
    if isinstance(v, str): v = [v]
    return [okey(x) for x in v]
def macro(v):
    tokens = [('Digit' + x) if x in '0123456789' and len(x) == 1 else x for x in seq(v)]
    return '(macro ' + ' '.join(tokens) + ')'
def alias_name(k):
    return 'single-' + ikey(k).replace("'", 'apos').replace('.', 'dot').replace('=', 'equal').replace('-', 'minus').replace(',', 'comma')

primaries = list(shinyou)
physical = ['lctl', 'rctl', 'lsft', 'rsft', 'spc'] + [ikey(k) for k in primaries] + [f'th{i}' for i in range(1,15)] + ['rpar']
# stable de-dup
physical = list(dict.fromkeys(physical))

aliases = []
aliases += [
    'sp-default (switch ((or (input real lctl) (input real rctl))) (multi spc (layer-switch shingeta)) break () spc break)',
    'sp-shingeta (switch ((or (input real lctl) (input real rctl))) (multi spc (layer-switch default)) break () spc break)',
]
for k, rule in shinyou.items():
    aliases.append(f'{alias_name(k)} {macro(rule["timeout_key"])}')

# Default-layer special mappings, including shifted variants.
special = {}
for i in range(1, 15):
    base_key = f'BTN_TRIGGER_HAPPY{i}'
    plain = default[base_key]
    shifted = default[f'Shift-{base_key}']
    shifted_action = macro(shifted)
    # Remove held Shift whenever desired output itself is unshifted.
    if not any(x.upper().startswith('SHIFT-') for x in ([shifted] if isinstance(shifted, str) else shifted)):
        shifted_action = '(unmod ' + ' '.join(seq(shifted)) + ')'
    name = f'th{i}-default'
    aliases.append(f'{name} (switch (lsft rsft) {shifted_action} break () {macro(plain)} break)')
    special[f'th{i}'] = '@' + name
aliases.append('rpar-default (switch (lsft rsft) (unmod /) break () rpar break)')
aliases.append('f24-default (switch (lsft rsft) (macro S-=) break () (macro S-9) break)')
special['rpar'] = '@rpar-default'
special['f24'] = '@f24-default'

lines = []
lines += ['(deflocalkeys-linux'] + [f'  th{i} {703+i}' for i in range(1,15)] + [')', '']
lines += ['(defsrc', '  ' + ' '.join(physical), ')', '']
lines += ['(defalias'] + [f'  {a}' for a in aliases] + [')', '']

def layer_actions(name):
    out=[]
    for p in physical:
        if p == 'spc': out.append('@sp-' + name)
        elif name == 'shingeta' and p in [ikey(k) for k in primaries]:
            orig = primaries[[ikey(k) for k in primaries].index(p)]
            out.append('@' + alias_name(orig))
        elif name == 'default' and p in special: out.append(special[p])
        else: out.append(p)
    return out
for name in ['default','shingeta']:
    lines += [f'(deflayer {name}', '  ' + ' '.join(layer_actions(name)), ')', '']
lines += ['(defchordsv2']
seen=set()
for first, rule in shinyou.items():
    for second, output in rule.get('remap', {}).items():
        pair=tuple(sorted((ikey(first), ikey(second))))
        if pair in seen: continue
        seen.add(pair)
        lines.append(f'  ({pair[0]} {pair[1]}) {macro(output)} 40 first-release (default)')
lines += [')', '']
OUT.write_text('\n'.join(lines))
print(f'wrote {OUT}: {len(primaries)} singles, {len(seen)} unordered chords, {len(physical)} defsrc keys')
