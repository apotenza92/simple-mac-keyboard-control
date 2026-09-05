#!/usr/bin/env python3
"""Prevent an older release or a concurrent publication from downgrading feeds."""
from pathlib import Path
import shutil
import sys
import xml.etree.ElementTree as ET


def version(path):
    value = ET.parse(path).findtext('./channel/item/{http://www.andymatuschak.org/xml-namespaces/sparkle}version')
    if not value or not value.isdecimal():
        raise ValueError('Invalid feed build number')
    return int(value)


def install(source, destination):
    paths = list(source.glob('*.xml'))
    advancing = []
    for path in paths:
        target = destination / path.name
        if target.exists() and version(target) >= version(path):
            if version(target) == version(path) and target.read_bytes() != path.read_bytes():
                raise ValueError('Refusing to replace an existing build: ' + path.name)
            continue
        advancing.append(path)
    for path in advancing: shutil.copyfile(path, destination / path.name)

if __name__ == '__main__':
    install(Path(sys.argv[1]), Path(sys.argv[2]))
