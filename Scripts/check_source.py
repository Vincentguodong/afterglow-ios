#!/usr/bin/env python3
"""Validate source structure only; this does not compile or run iOS code."""
import json
import plistlib
import re
import subprocess
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

root = Path(__file__).resolve().parents[1]
checks = []
for path in (root / 'Afterglow').glob('*.plist'):
    plistlib.loads(path.read_bytes())
    checks.append(str(path.relative_to(root)))
plistlib.loads((root / 'Afterglow/PrivacyInfo.xcprivacy').read_bytes())
checks.append('Afterglow/PrivacyInfo.xcprivacy')
for path in (root / 'Afterglow/Assets.xcassets').rglob('*.json'):
    json.loads(path.read_text())
    checks.append(str(path.relative_to(root)))
for path in root.glob('Afterglow.xcodeproj/**/*.xcscheme'):
    ET.parse(path)
    checks.append(str(path.relative_to(root)))
project = (root / 'Afterglow.xcodeproj/project.pbxproj').read_text()
objects = re.findall(r'^\s*([A-F0-9]{24}) =', project, re.M)
assert len(objects) == len(set(objects)), 'Duplicate project object ID'
references = set(re.findall(r'\b[A-F0-9]{24}\b', project))
assert references <= set(objects), 'Unresolved project reference'
sources = sorted(root.glob('Afterglow*/*.swift'))
for path in sources:
    assert f'path = "{path.name}";' in project, f'Missing source: {path.name}'
for path in [*root.glob('Scripts/*.sh'), *root.glob('*.command')]:
    subprocess.run(['bash', '-n', str(path)], check=True)
    checks.append(str(path.relative_to(root)))
syntax = 'not_checked_parser_not_installed'
try:
    from tree_sitter import Language, Parser
    import tree_sitter_swift
except ImportError:
    pass
else:
    parser = Parser(Language(tree_sitter_swift.language()))
    errors = []
    for path in sources:
        tree = parser.parse(path.read_bytes())
        if tree.root_node.has_error:
            pending = [tree.root_node]
            while pending:
                node = pending.pop()
                if node.type == 'ERROR' or node.is_missing:
                    errors.append({'file':str(path.relative_to(root)), 'line':node.start_point.row+1, 'type':node.type})
                pending.extend(node.children)
    assert not errors, errors
    syntax = 'passed_tree_sitter_swift_0.7.4'
result = {
    'source_structure':'passed', 'swift_files':len(sources), 'swift_syntax':syntax,
    'configuration_files_checked':checks, 'xcode_sdk_typecheck':'not_run',
    'xctest':'not_run', 'device_install':'not_run', 'signed_ipa':'not_created'
}
if '--write-report' in sys.argv:
    (root / 'Docs/native-static-checks.json').write_text(json.dumps(result, ensure_ascii=False, indent=2)+'\n')
print(json.dumps(result, ensure_ascii=False, indent=2))
