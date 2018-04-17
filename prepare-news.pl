#!/usr/bin/perl

use v5.26;

use warnings;
use strict;
use autodie;

use YAML;
use IO::All;
use Text::CSV_XS qw(csv);

use FindBin qw($Dir);
use Memoize;

use FindBin qw($Dir); use lib $Dir;
use STISRV13;
use WebsiteMap;

my $secrets = YAML::LoadFile('./secrets.yaml');
my $website_map = WebsiteMap->new(
  scalar(io('newsatone-meta.json')->slurp),
  scalar(io('sti-website.gml')->slurp));
my $schema = STISRV13->connect(-password => $secrets->{mysql_password});

say YAML::Dump([map { $_->essentials } Article->all($schema, $website_map)]);

##############################################
package Article;

use base qw(Class::Delegate);

sub all {
  my ($class, $schema, $website_map) = @_;
  my @results;
  foreach my $dbic ($schema->resultset('Article')->all) {
    foreach my $lang ($dbic->languages) {
      my $elem = $class->new($dbic, $lang, $website_map);
      # TODO: Weed out articles that are published in only one language
      push @results, $elem;
    }
  }
  return @results;
}

sub new {
  my ($class, $dbic, $lang, $website_map) = @_;
  my $self = bless {
    dbic => $dbic,
    lang => $lang,
    website_map => $website_map
  }, $class;
  $self->add_delegate($dbic);
  return $self;
}

sub lang { shift->{lang} }

sub essentials {
  my $self = shift;
  if (! $self->{essentials}) {
    $self->{essentials} = { %{$self->{dbic}->essentials($self->{lang})} };
    my @vertices = $self->get_website_map_vertices();
    $self->{essentials}->{urls} = [ map { $_->{label} } @vertices ];
  }

  return $self->{essentials};
}

sub get_website_map_vertices {
  my ($self) = @_;
  if (! $self->{vertices}) {
    $self->{vertices} =
      [ map { $self->{website_map}->find_vertices($_) } ($self->get_urls()) ];
  }
  return @{$self->{vertices}}
}

sub get_urls {
  my ($self) = @_;
  return $self->{website_map}->get_urls($self->rss_id, $self->lang);
}

sub ancestry {
  my ($self) = @_;
  return $self->{website_map}->ancestry($self);
}

# DBIx::Class::_Util freaks out when DESTROY is called twice, which it would
# (through the delegate) if we didn't do this:
sub DESTROY {}
