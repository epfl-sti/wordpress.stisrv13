#!/usr/bin/env python3

import numpy as np
import pandas as pd
from sklearn.cluster import MeanShift, estimate_bandwidth
import matplotlib.pyplot as plt

df=pd.read_csv('rss-out.csv', sep=',').set_index('rss_id')

X = df.simil.values.reshape(-1,1)
## To plot an histogram:
plt.hist(X, bins=50); plt.hist(X, bins=500); plt.show()

# https://stackoverflow.com/a/18364570/435004
bw = estimate_bandwidth(X)
ms = MeanShift(bandwidth=bw, bin_seeding=True)
ms.fit(X)
cluster_centers = ms.cluster_centers_

# Using the Perl-computed "simil" rule:
almost_same = df.loc[df.simil > 0.995].loc[df.simil < 1]
