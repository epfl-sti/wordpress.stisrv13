#!/usr/bin/perl

use v5.26;

use warnings;
use strict;
use autodie;

use YAML;
use JSON;
use IO::All;
use Text::CSV_XS qw(csv);

use FindBin qw($Dir);
use String::Similarity qw(similarity);

use FindBin qw($Dir); use lib $Dir;
use STISRV13;
use GML;

my $newsatone_meta = decode_json(scalar io('newsatone-meta.json')->slurp);
my $site_graph = decode_gml(scalar io('sti-website.gml')->slurp);  # Takes ~10 secs
my $secrets = YAML::LoadFile('./secrets.yaml');
my $schema = STISRV13->connect(-password => $secrets->{mysql_password});




######################################################

