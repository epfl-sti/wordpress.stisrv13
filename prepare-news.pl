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
use Memoize;

use FindBin qw($Dir); use lib $Dir;
use STISRV13;
use GML;

my $newsatone_meta = decode_json(scalar io('newsatone-meta.json')->slurp);
my $site_graph; # = decode_gml(scalar io('sti-website.gml')->slurp);  # Takes ~10 secs
warn "Data loaded.";

my $secrets = YAML::LoadFile('./secrets.yaml');
my $schema = STISRV13->connect(-password => $secrets->{mysql_password});

say YAML::Dump([map { $_->essentials } Article->all($schema, $newsatone_meta, $site_graph)]);

##############################################
package Article;

use base qw(Class::Delegate);

sub all {
  my ($class, $schema, $newsatone_meta, $site_graph) = @_;
  my @results;
  foreach my $dbic ($schema->resultset('Article')->all) {
    foreach my $lang ($dbic->languages) {
      my $elem = $class->new($dbic, $lang);
      # TODO: Weed out articles that are published in only one language
      push @results, $elem;
    }
  }
  return @results;
}

sub new {
  my ($class, $dbic, $lang) = @_;
  my $self = bless { dbic => $dbic, lang => $lang }, $class;
  $self->add_delegate($dbic);
  return $self;
}

sub essentials {
  my $self = shift;
  return $self->{dbic}->essentials($self->{lang})
}

sub path_to_root {
}

# DBIx::Class::_Util freaks out when DESTROY is called twice, which it would
# (through the delegate) if we didn't do this:
sub DESTROY {}
