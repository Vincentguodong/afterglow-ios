#!/usr/bin/env python3
"""Check the publishable tree for common credentials and local-only artifacts.

This is a conservative guard, not a guarantee that all private data is detected.
Run before publishing; review image metadata and Git author identity separately.
Only relative file names and rule names are printed, never matching values.
"""
from pathlib import Path
import re
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
READ_INDEX = (ROOT / '.git').exists()
BLOCKED_SUFFIXES = {
    '.p12', '.p8', '.pem', '.key', '.cer', '.pfx', '.mobileprovision',
    '.provisionprofile', '.ipa', '.xcuserstate', '.log', '.zip',
}
BLOCKED_PARTS = {
    'xcuserdata', 'build', 'DerivedData', 'node_modules', '__pycache__',
}
RULES = {
    'private-key': r'-----BEGIN (?:RSA |EC |OPENSSH |DSA )?PRIVATE KEY-----',
    'github-token': r'\b(?:gh[pousr]_[A-Za-z0-9]{30,}|github_pat_[A-Za-z0-9_]{30,})\b',
    'aws-access-key': r'\b(?:AKIA|ASIA)[A-Z0-9]{16}\b',
    'private-hosting-link': r'https?://[^\s)<>]*\.chatgpt\.site\b',
    'library-link': r'https?://chatgpt\.com/library\?',
    'local-user-path': r'/(?:Users|home|workspace)/[A-Za-z0-9_.-]+/',
    'populated-team-id': r'\bDEVELOPMENT_TEAM\s*=\s*["\']?[A-Z0-9]{10}["\']?\s*[;\n]',
    'device-id': r'\b[0-9]{8}-[A-F0-9]{16}\b',
}

def files_to_check():
    if READ_INDEX:
        result = subprocess.run(
            ['git', 'ls-files', '-z'], cwd=ROOT, check=True, capture_output=True
        )
        return [ROOT / n.decode() for n in result.stdout.split(b'\0') if n]
    return [p for p in ROOT.rglob('*') if p.is_file()]

findings = []
paths = files_to_check()
if not paths:
    sys.exit('No files checked. Stage the intended publication with git add first.')
for path in paths:
    relative = path.relative_to(ROOT)
    if path.is_symlink():
        findings.append((str(relative), 'symbolic-link'))
        continue
    if (path.suffix.lower() in BLOCKED_SUFFIXES
            or any(part in BLOCKED_PARTS for part in relative.parts)
            or path.name == 'Signing.xcconfig'
            or path.name.startswith('.env')):
        findings.append((str(relative), 'local-only-file'))
    try:
        if READ_INDEX:
            staged = subprocess.run(
                ['git', 'show', ':' + relative.as_posix()], cwd=ROOT,
                capture_output=True, check=True,
            )
            content = staged.stdout.decode('utf-8')
        else:
            content = path.read_text(encoding='utf-8')
    except UnicodeDecodeError:
        continue
    except (OSError, subprocess.CalledProcessError):
        findings.append((str(relative), 'unreadable-file'))
        continue
    for rule, pattern in RULES.items():
        if re.search(pattern, content):
            findings.append((str(relative), rule))

if findings:
    for path, rule in findings:
        print(f'{path}: {rule}')
    sys.exit(1)
print(f'Passed common-credential and local-file checks for {len(paths)} files.')
print('This does not replace manual privacy review or a Git history audit.')
