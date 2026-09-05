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
    for path in paths:
        target = destination / path.name
        if target.exists() and version(target) >= version(path):
            raise ValueError('Refusing to downgrade or replace existing feed: ' + path.name)
    for path in paths: shutil.copyfile(path, destination / path.name)

if __name__ == '__main__':
    install(Path(sys.argv[1]), Path(sys.argv[2]))
