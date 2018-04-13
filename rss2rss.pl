#!/usr/bin/perl

use v5.26;

use warnings;
use strict;
use autodie;

use Text::CSV_XS qw(csv);
use FindBin qw($Dir);

my $csv = csv(in => "$Dir/rss.csv", detect_bom => 1);

use Data::Dumper; say ref($csv->[0]);
