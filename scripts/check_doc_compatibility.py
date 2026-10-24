"""Resolve dependencies and generate docs from a clean export with an isolated toolchain."""
import argparse
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import zipfile

ROOT = Path(__file__).resolve().parent.parent
OUTPUT = ROOT / '_build/docs-compatibility'


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--moon', type=Path, help='Isolated moon executable')
    parser.add_argument('--source', type=Path, help='Already prepared clean source directory')
    args = parser.parse_args()
    OUTPUT.mkdir(parents=True, exist_ok=True)
    summary = dict(status='running', commands=[])
    summary_path = OUTPUT / 'summary.json'
    summary_path.write_text(json.dumps(summary), encoding='utf-8')
    env = dict(os.environ)
    moon = str(args.moon.resolve()) if args.moon else shutil.which('moon')
    if args.moon:
        env['MOON_HOME'] = str(args.moon.resolve().parent.parent)
        env['PATH'] = str(args.moon.resolve().parent) + os.pathsep + env.get('PATH', '')

    def run(name, command, cwd):
        process = subprocess.run(command, cwd=cwd, env=env, capture_output=True, timeout=420)
        (OUTPUT / (name + '.stdout')).write_bytes(process.stdout)
        (OUTPUT / (name + '.stderr')).write_bytes(process.stderr)
        summary['commands'].append(dict(name=name, command=command, exit_code=process.returncode))
        print(name + ': ' + str(process.returncode), flush=True)
        if process.returncode:
            raise RuntimeError(f'{name} failed; see {OUTPUT}')
        return process.stdout.decode('utf-8')

    try:
        if args.source:
            source = args.source.resolve()
            summary['source_kind'] = 'prepared clean source'
        else:
            source = Path(tempfile.mkdtemp(prefix='moonjson-docs-'))
            archive = OUTPUT / 'source.zip'
            summary['code_sha'] = run('code-sha', ['git', 'rev-parse', 'HEAD'], ROOT).strip()
            run('export', ['git', 'archive', '--format=zip', '-o', str(archive), 'HEAD'], ROOT)
            with zipfile.ZipFile(archive) as package:
                package.extractall(source)
            # git archive represents the tracked README symlink as its target text on Windows.
            (source / 'README.md').write_bytes((source / 'README.mbt.md').read_bytes())
            summary['source_kind'] = 'git archive HEAD'
        summary['source'] = str(source)
        if (source / '.mooncakes').exists() or (source / '_build').exists():
            raise RuntimeError('source is not clean: dependency or build directory already exists')
        if any((p / 'moon.work').exists() for p in [source, *source.parents]):
            raise RuntimeError('source has a workspace override')
        summary['toolchain'] = run('toolchain', [moon, 'version', '--all'], source)
        run('update', [moon, 'update'], source)
        # Resolve the full graph before checking that legacy modules are absent.
        run('check-native', [moon, 'check', '--target', 'native'], source)
        tree = run('dependencies', [moon, 'tree'], source)
        for obsolete in ['oboard/mio', 'bikallem/compress', 'bikallem/blit']:
            if obsolete in tree:
                raise RuntimeError('obsolete dependency remains: ' + obsolete)
        legacy = list((source / '.mooncakes').rglob('moon.mod.json'))
        if legacy:
            raise RuntimeError('legacy dependency manifests: ' + repr(legacy))
        summary['legacy_manifests'] = []
        summary['doc_help'] = run('doc-help', [moon, 'doc', '--help'], source)
        run('doc', [moon, 'doc'], source)
        # This pinned moondoc emits module/package JSON and Markdown assets;
        # it does not emit a standalone index.html.
        docs = source / '_build/doc/BigSaltyMan/moonjson-toolkit'
        for name in ['module_index.json', 'package_data.json']:
            data = json.loads((docs / name).read_text(encoding='utf-8'))
            if not data:
                raise RuntimeError('empty documentation asset: ' + name)
        readme = (docs / 'README.md').read_text(encoding='utf-8')
        for required in ['--check-schema', '--schema-output', 'batchValidation', 'jsonlValidation']:
            if required not in readme:
                raise RuntimeError('generated README is missing: ' + required)
        if not (docs / 'ai.mbt.html').stat().st_size:
            raise RuntimeError('HTTP source documentation is empty')
        summary.update(status='passed', documentation_directory=str(docs),
                       documentation_assets=['module_index.json', 'package_data.json', 'README.md', 'ai.mbt.html'])
    except (OSError, ValueError, RuntimeError, subprocess.TimeoutExpired) as error:
        summary.update(status='failed', error=str(error))
        print('FAIL ' + str(error), flush=True)
    summary_path.write_text(json.dumps(summary, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    print('Documentation compatibility: ' + summary['status'])
    return 0 if summary['status'] == 'passed' else 1


if __name__ == '__main__':
    raise SystemExit(main())
