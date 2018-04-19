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
use WebsiteMap;

my $secrets = YAML::LoadFile('./secrets.yaml');
my $website_map = WebsiteMap->new(
  scalar(io('newsatone-meta.json')->slurp),
  scalar(io('sti-website.gml')->slurp));
my $schema = STISRV13->connect(-password => $secrets->{mysql_password});

sub ancestries_sitemap {
  my (@articles) = @_;
  my %ancestries;
  foreach my $article (@articles) {
    my @urls_and_ancestry_paths = $article->urls_and_ancestry_paths();
    while(my ($url, $path) = splice(@urls_and_ancestry_paths, 0, 2)) {
      push @{$ancestries{$path}}, $url;
    }
  }
  return \%ancestries;
}

my @articles = Article->all($schema, $website_map);
io("news-sitemap.yaml")->utf8->print(YAML::Dump(ancestries_sitemap(@articles)));
my $main_payload = { articles => [map { $_->essentials } @articles]};
io("news.yaml")->utf8->print(YAML::Dump($main_payload));
io("news.json")->binmode->print(encode_json($main_payload));

##############################################
package Article;

use base qw(Class::Delegate);

sub all {
  my ($class, $schema, $website_map) = @_;
  my @results;
  foreach my $dbic (STISRV13::Article->almost_all($schema)) {
    foreach my $lang ($dbic->languages) {
      my $elem = $class->new($dbic, $lang, $website_map);
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
    $self->{essentials}->{urls} = [$self->get_all_urls()];
    if (my @categories = $self->get_categories()) {
      $self->{essentials}->{categories} = \@categories;
    }
  }

  return $self->{essentials};
}

sub get_main_vertex {
  my ($self) = @_;
  if (! exists $self->{vertex}) {
    my $url = $self->get_url();
    if (! $url) {
      $self->{vertex} = undef;
    } else {
      $self->{vertex} = $self->{website_map}->find_vertex($url);
    }
  }
  return $self->{vertex};
}

sub get_vertices {
  my ($self) = @_;
  return map { $self->{website_map}->find_vertex($_) }
    $self->get_url();  # Plural ('coz wantarray)
}

sub get_all_urls {
  my ($self) = @_;
  return $self->{website_map}->get_urls($self->rss_id, $self->lang);
}

sub get_url {
  my ($self) = @_;

  my @urls = $self->get_all_urls();
  return if (! @urls);

  my $lang = $self->lang;
  my @lang_qualified_urls = grep { m/-${lang}.html$/ } @urls;

  if (! @lang_qualified_urls) {
    warn $self->moniker . " has no language-qualified URLs; picking " . $urls[0] . " as main URL";
    return $urls[0];
  } elsif ((! wantarray)  &&  scalar(@lang_qualified_urls) > 1) {
    warn sprintf("%s has multiple language-qualified URLs (%s); " .
                   "picking the first one as the main URL",
                 $self->moniker, join(" ", @lang_qualified_urls));
  }
  return wantarray? @lang_qualified_urls : $lang_qualified_urls[0];
}

sub urls_and_ancestry_paths {
  my ($self) = @_;

  my @retval;
  foreach my $vertex ($self->get_vertices()) {
    my $url = $vertex->{label};
    my $ancestry_path = join(" ", map {
      $_ = $_->{label};
      s|^https://sti.epfl.ch||;
      $_
    } $self->{website_map}->ancestry($vertex));
    push @retval, ($url, $ancestry_path);
  }
  return @retval;
}

sub get_categories {
  my ($self) = @_;

  my $lang = $self->lang;
  my @categories;

  my @urls_and_ancestry_paths = $self->urls_and_ancestry_paths();
  while(my (undef, $path) = splice(@urls_and_ancestry_paths, 0, 2)) {
      local $_ = $path;
      if (m/Materials-News|Materiaux-News/) {
        push(@categories, "imt-news-$lang");
      } elsif (m|/igm/news|) {
        push(@categories, "igm-news-$lang");
      } elsif (m{/IMTRe(?:search|cherche)}) {
        push(@categories, "imt-news-$lang");
      } elsif (m{/electrical-engineering|/genie-electrique}) {
        push(@categories, "iel-news-$lang");
      } elsif (m{(?:^| )(?:/actu|/news)}) {
        push(@categories, "news");
      } elsif (m{(/cent(?:er|re)s)}) {
        push(@categories, "centres-news-$lang");
      } elsif (m{(?:^| )(?:/it)} or m{/page-1767[.-]}) {
        warn "Not keeping " . $self->moniker() . " as it appears under sti.epfl.ch/it";
      } else {
        die "Don't know how to categorize this ancestry path: $path for " . $self->get_url();
      }
  }

  my %categories = map { $_ => 1 } @categories;
  return sort keys %categories;
}

# DBIx::Class::_Util freaks out when DESTROY is called twice, which it would
# (through the delegate) if we didn't do this:
sub DESTROY {}
