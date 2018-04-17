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

# say YAML::Dump([map { $_->essentials } Article->all($schema, $website_map)]);

sub ancestries_sitemap {
  my %ancestries;
  foreach my $article (Article->all($schema, $website_map)) {
    my $v = $article->get_main_vertex();
    next if (! $v);
    my @ancestry = $article->ancestry($v);
    my $ancestry_path = join(" ", map {
      $_ = $_->{label};
      s|^https://sti.epfl.ch||;
      $_
    } @ancestry);
    push @{$ancestries{$ancestry_path}}, ($article->get_main_url())[0];
  }
  return \%ancestries;
}
say YAML::Dump(ancestries_sitemap);

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

sub moniker {
  my ($self) = @_;
  return sprintf("<Article rss_id=%d lang=%s>", $self->rss_id, $self->lang);
}

sub essentials {
  my $self = shift;
  if (! $self->{essentials}) {
    $self->{essentials} = { %{$self->{dbic}->essentials($self->{lang})} };
    $self->{essentials}->{urls} = $self->get_all_urls();
  }

  return $self->{essentials};
}

sub get_main_vertex {
  my ($self) = @_;
  if (! exists $self->{vertex}) {
    my $url = $self->get_main_url();
    if (! $url) {
      $self->{vertex} = undef;
    } else {
      $self->{vertex} = $self->{website_map}->find_vertex($url);
    }
  }
  return $self->{vertex};
}

sub get_all_urls {
  my ($self) = @_;
  return $self->{website_map}->get_urls($self->rss_id, $self->lang);
}

sub get_main_url {
  my ($self) = @_;
  my @urls = $self->get_all_urls();
  return if (! @urls);
  my $lang = $self->lang;
  my @lang_qualified_urls = grep { m/-${lang}.html$/ } @urls;
  if (! @lang_qualified_urls) {
    warn $self->moniker . " has no language-qualified URLs; picking " . $urls[0] . " as main URL";
    return $urls[0];
  } elsif (scalar(@lang_qualified_urls) > 1) {
    warn sprintf("%s has multiple language-qualified URLs (%s); " .
                   "picking the first one as the main URL",
                 $self->moniker, join(" ", @lang_qualified_urls));
  }
  return $lang_qualified_urls[0];
}

sub ancestry {
  my ($self, $vertex) = @_;
  return $self->{website_map}->ancestry($vertex);
}

# DBIx::Class::_Util freaks out when DESTROY is called twice, which it would
# (through the delegate) if we didn't do this:
sub DESTROY {}
