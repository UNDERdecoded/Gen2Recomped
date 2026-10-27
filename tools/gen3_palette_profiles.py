"""Curated, source-pinned terrain palette profiles, keyed by exact ROM SHA1.

Unlike the structural table discovery, these audited callback classifications
are specific to a matching build. No palette bytes or executable code here.
"""
import copy
import json
from pathlib import Path


def profile_for_sha1(sha1):
    path = Path(__file__).with_name("gen3_palette_program_profiles.json")
    profiles = json.loads(path.read_text())
    return copy.deepcopy(profiles.get(sha1))
