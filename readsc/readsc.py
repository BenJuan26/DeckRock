#!/usr/bin/env python3
# -*- coding: utf-8 -*-
# Downloaded from https://www.unix-ag.uni-kl.de/~t_schmid/readsc/readsc.tar.zst

import sys
import json
#from pprint import pprint

import binvdf

sc = binvdf.parseshortcut(sys.argv[1])
#pprint(sc)
print(json.dumps(sc, indent=2))