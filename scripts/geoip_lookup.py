#!/usr/bin/env python3
# CLI geolocation lookup for shell scripts.
# Prints: country|city|lat|lon

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from services.geolocation import get_location

if len(sys.argv) != 2:
    print('Unknown|Unknown|0|0')
    sys.exit(1)

loc = get_location(sys.argv[1])
print(f"{loc['country']}|{loc['city']}|{loc['lat']}|{loc['lon']}")
