#!/usr/bin/env python3
"""Bundle a validated delivery without replacing any existing app assets."""
import argparse
import json
from pathlib import Path

from export_eagle import check_license
from validate_glb import validate


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('delivery', type=Path)
    parser.add_argument('--destination', type=Path, default=Path(__file__).resolve().parents[2] /
                        'apps/eagle-study-android/assets/3d')
    args = parser.parse_args()
    check_license(args.delivery / 'license.json')
    report = validate(args.delivery / 'eagle_mascot.glb')
    names = ('eagle_mascot.glb', 'CREDITS.md', 'license.json')
    for name in names:
        if not (args.delivery / name).is_file():
            parser.error(f'Missing delivery file: {name}')
        if (args.destination / name).exists():
            parser.error(f'Refusing to overwrite {args.destination / name}')
    args.destination.mkdir(parents=True, exist_ok=True)
    for name in names:
        with (args.destination / name).open('xb') as target:
            target.write((args.delivery / name).read_bytes())
    print(json.dumps(report, indent=2))
    print('Bundled. Rebuild the app to preprocess the scene; device QA is still required.')


if __name__ == '__main__':
    main()
