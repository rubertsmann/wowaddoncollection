"""Writes comment-ledger.csv: one row per comment (file, line, method that verified it) for every non-vendored code
file of the monorepo, and fails when a file that has comments is not covered by any method.
Run from the monorepo root:  python guildgames/features/021-comment-audit-and-reduction/evidence/ledger.py"""
import csv, fnmatch, os, re, subprocess, sys

HERE = os.path.dirname(os.path.abspath(__file__))
EXCLUDED = ('/Libs/', '/dist/', '/eval/', '/features/', '/review/')

# methods (see verify.md "How R3 was checked"); first matching pattern wins
WHOLE = 'whole file read'
CTX = 'comment + following code, documented functions read whole, builder comments checked against every widget use'
TEST = 'test comment checked against its helper / assertion / fixture'
METHODS = [
    ('*/tests/*', TEST),
    ('professionshare/Core/Data/Store.lua', WHOLE + ' to line 300; ' + CTX + ' after'),
    ('libguildsync/LibGuildSync/*', WHOLE),
    ('guildgames/Core/*', WHOLE),
    ('guildgames/UI/Animate.lua', WHOLE), ('guildgames/UI/Helpers.lua', WHOLE),
    ('guildgames/UI/AzeCaughtOptions.lua', WHOLE), ('guildgames/UI/DevProbe.lua', WHOLE),
    ('guildgames/UI/*', CTX),
    ('professionshare/Core/Base/*', WHOLE), ('professionshare/Core/Net/*', WHOLE),
    ('professionshare/Core/Debug/Trace.lua', WHOLE), ('professionshare/Core/Debug/*', CTX),
    ('professionshare/Core/Data/*', WHOLE),
    ('professionshare/Core/View/ItemText.lua', WHOLE), ('professionshare/Core/View/Names.lua', WHOLE),
    ('professionshare/Core/View/*', CTX), ('professionshare/Core/Game/*', CTX),
    ('professionshare/UI/*', CTX),
    ('professionshare/dev/*', WHOLE),
    ('fpvcigarette/Logic.lua', WHOLE), ('fpvcigarette/Geometry.lua', WHOLE), ('fpvcigarette/Displays.lua', WHOLE),
    ('fpvcigarette/*.lua', CTX),
    ('foreverbetteruiplus/*.lua', CTX),
    ('*/Locales/*', WHOLE),
    ('*/tools/*', WHOLE), ('tools/*', WHOLE), ('*.claude/skills/*', WHOLE),
]

def comment_lines(path, text):
    rows = []
    if path.endswith('.lua'):
        in_string = None
        for number, line in enumerate(text.split('\n'), 1):
            stripped = re.sub(r'"(\\.|[^"\\])*"|\'(\\.|[^\'\\])*\'', '""', line)   # drop string literals
            if '--' in stripped:
                rows.append((number, 'annotation' if stripped.lstrip().startswith('---@') else 'comment'))
    elif path.endswith(('.ps1', '.py')):
        for number, line in enumerate(text.split('\n'), 1):
            stripped = re.sub(r'"(\\.|[^"\\])*"|\'(\\.|[^\'\\])*\'', '""', line)
            if re.search(r'(^|\s)#(?!>)', stripped) and not stripped.lstrip().startswith('#!'):
                rows.append((number, 'comment'))
    return rows

files = subprocess.run(['git', 'ls-files'], capture_output=True, text=True).stdout.split()
files = [f for f in files if f.endswith(('.lua', '.ps1', '.py')) and not any(x in '/' + f for x in EXCLUDED)
         and not f.endswith('evidence/ledger.py')]
uncovered, total, rows_out = [], 0, []
for path in sorted(files):
    rows = comment_lines(path, open(path, encoding='utf-8').read())
    if not rows:
        continue
    method = next((m for pattern, m in METHODS if fnmatch.fnmatch(path, pattern)), None)
    if method is None:
        uncovered.append(path)
        continue
    for number, kind in rows:
        rows_out.append((path, number, kind, method))
        total += 1
with open(os.path.join(HERE, 'comment-ledger.csv'), 'w', newline='', encoding='utf-8') as handle:
    writer = csv.writer(handle)
    writer.writerow(['file', 'line', 'kind', 'verified by'])
    writer.writerows(rows_out)
files_covered = len({r[0] for r in rows_out})
print('ledger: %d comment lines in %d files, uncovered files: %d' % (total, files_covered, len(uncovered)))
for path in uncovered:
    print('  UNCOVERED ' + path)
sys.exit(1 if uncovered else 0)
