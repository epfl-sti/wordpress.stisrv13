#!/usr/bin/env perl -w

use v5.26;
use strict;
use warnings;
use IO::All;
use Text::CSV_XS;
use YAML;
use JSON;
use URI;

my $stisrv13_assets = YAML::LoadFile('./news.yaml');
my %permalinks;

foreach my $wordpress_asset (@{decode_json(io('./imported-permalinks.json')->slurp)}) {
  my $lang = $wordpress_asset->{lang} || "__nolang__";
  $permalinks{$wordpress_asset->{import_id}}->{$lang} = $wordpress_asset->{permalink};
}

my $csv = Text::CSV_XS->new ({ binary => 1, auto_diag => 1 });

binmode(STDOUT, ":utf8");

# /wp-admin/tools.php?page=redirection.php&sub=io says:
# CSV file format: source URL, target URL - and can be optionally followed with regex, http code (regex - 0 for no, 1 for yes).

foreach my $article (@{$stisrv13_assets->{articles}}) {
  my $import_id = $article->{import_id};
  my $permalink;
  foreach my $lang (($article->{lang} || "__nolang__"), "__nolang__") {
    last if ($permalink = $permalinks{$import_id}->{$lang});
  }
  do { warn "$import_id not found in imported-permalinks.json\n"; next } unless $permalink;
  foreach my $url (@{$article->{urls}}) {
    $csv->say(*STDOUT, [URI->new($url)->path, URI->new($permalink)->path]);
  }
}
