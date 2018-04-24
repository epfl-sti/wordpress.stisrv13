#!/usr/bin/perl

use v5.26;

use warnings;
use strict;
use autodie;

use YAML;
use JSON;
use IO::All;

use FindBin qw($Dir);

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
YAML::Dump(ancestries_sitemap(@articles)) > io("news-sitemap.yaml")->utf8;
my $main_payload = {
  articles => [map { $_->essentials } @articles],
  videos   => [Video->all($schema)]
};
YAML::Dump($main_payload) > io("news.yaml")->utf8;
# Unlike encode_json, the OO version of JSON defaults to producing a
# string of characters (not bytes):
JSON->new->pretty->encode($main_payload) > io("news.json")->utf8;

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
    my ($categories_arrayref, $tags_arrayref) = $self->get_categories_and_tags();
    $self->{essentials}->{categories} = $categories_arrayref if $categories_arrayref;
    $self->{essentials}->{tags}       = $tags_arrayref       if $tags_arrayref;
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

sub get_categories_and_tags {
  my ($self) = @_;

  my $lang = $self->lang;
  my (@categories, @tags);

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

  my $cible = $self->cible;
  if ($cible =~ m/\bMICROMX\b/ or $self->headline =~ m/^What is this/i) {
    push @categories, "micromx-$lang";
  }
  if (my ($what, $where) = $cible =~ m/\b(?:(I|S)(EL|MX|GM||MT|BI))\b/) {
    my $where_lc = lc($where);
    push @categories, "i${where_lc}-news-${lang}";
    my $drill_down_category;
    if ($what eq "I") {
      $drill_down_category = ($lang eq "fr") ? "recherche" : "research";
    } else {
      $drill_down_category = "education-$lang";
    }
    push @categories, "i${where_lc}-${drill_down_category}";
    push @tags, "INST=$where";
  }
  if ($cible =~ m/microcity/) {
    push @categories, "imt-microcity-$lang";
  }

  if ($cible =~ m/PHD/) {
    push @tags, "LVL=PhD";
  }

  if ($cible =~ m/inthenews/) {
    push @categories, ($lang eq "fr") ? "dans-la-presse" : "in-the-media";
  }

  my $author_sciper = $self->academic_author;
  if ($author_sciper) {
    push @tags, "ATTRIBUTION=$author_sciper";
  }

  my %categories = map { $_ => 1 } @categories;
  return ([sort keys %categories], \@tags);
}

# DBIx::Class::_Util freaks out when DESTROY is called twice, which it would
# (through the delegate) if we didn't do this:
sub DESTROY {}

package Video;

sub all {
  my ($class, $schema) = @_;
  my @results;
  foreach my $profvideo (STISRV13::ProfVideo->all($schema)) {
    my $results_count_before = @results;
    if (my $youtube_id = $profvideo->videofra) {
      push @results, {
        lang       => "fr",
        youtube_id => $youtube_id,
        title      => scalar $profvideo->videotitlefr,
        content    => scalar $profvideo->videotextfr,
        categories => ["profs-videos-fr"],
        tags       => ["ATTRIBUTION=" . $profvideo->sciper]
      }
    }
    if (my $youtube_id = $profvideo->videoeng) {
      push @results, {
        lang       => "en",
        youtube_id => $youtube_id,
        title      => scalar $profvideo->videotitle,
        content    => scalar $profvideo->videotext,
        categories => ["profs-videos-en"],
        tags       => ["ATTRIBUTION=" . $profvideo->sciper]
      }
    }
    if (my $youtube_id = $profvideo->videoLH) {
      push @results, {
        youtube_id => $youtube_id,
        categories => ["events-lilh"],
        categories => ["profs-videos-en"],  # Just a guess, really
        tags       => ["ATTRIBUTION=" . $profvideo->sciper]
      }
    }
    if ($results_count_before == @results) {
      die("Couldn't find any video out of SELECT [...] FROM profs WHERE sciper=" . $profvideo->sciper);
    }
  }
  return @results;
}

