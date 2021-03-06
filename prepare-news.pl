#!/usr/bin/env perl

use v5.26;

use warnings;
use strict;
use autodie;

use YAML;
use JSON;

use FindBin qw($Dir);

use FindBin qw($Dir); use lib $Dir;
use STISRV13;
use STISRV13::IO qw(load_text load_secrets load_json save_yaml save_json);
use WebsiteMap;

use Docopt;

=head1 NAME

prepare-news.pl

=head1 SYNOPSIS

  prepare-news.pl [--videos-only]

=cut

our $opts = docopt();
my $opt_videos_only = $opts->{"--videos-only"};

my $website_map = WebsiteMap->new(
  load_json('newsatone-meta.json'),
  load_text('sti-website.gml'));
my $secrets = load_secrets();
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
unless ($opt_videos_only) {
  save_yaml("news-sitemap.yaml", ancestries_sitemap(@articles));
}
my $main_payload = {};

$main_payload->{articles} = [map { $_->essentials } @articles] unless ($opt_videos_only);
$main_payload->{videos}   = [map { $_->essentials } Video->all($schema)];

my $outprefix = $opt_videos_only ? "news-videos-only" : "news";
save_yaml("$outprefix.yaml", $main_payload);
save_json("$outprefix.json", $main_payload);

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
    $self->{essentials}->{import_id} = "rss-" . $self->{essentials}->{rss_id};
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
  if ($cible =~m/centre/) {
    push @categories, "centres-news-$lang";
  }
  if ($cible =~ m/PHD/) {
    push @tags, "LVL=PhD";
  }

  if ($cible =~ m/inthenews/) {
    push @categories, ($lang eq "fr") ? "dans-la-presse" : "in-the-media";
  }

  my $author_sciper = $self->academic_author;
  if ($author_sciper) {
    push @tags, "ATTRIBUTION=SCIPER:$author_sciper";
  }

  my %categories = map { $_ => 1 } @categories;
  return ([sort keys %categories], \@tags);
}

# DBIx::Class::_Util freaks out when DESTROY is called twice, which it would
# (through the delegate) if we didn't do this:
sub DESTROY {}

package Video;   #############################################################

use URI::Escape qw(uri_escape);
use IO::All;
use IO::All::HTTP;
use JSON qw(decode_json);
use DateTime::Format::ISO8601;
use warnings;

use STISRV13::IO qw(load_yaml save_yaml);

use utf8;  # For "Leçon d'honneur" in the source code, below

sub all {
  my ($class, $schema) = @_;

  my @results;
  foreach my $profvideo (STISRV13::ProfVideo->all($schema)) {
    my $sciper = $profvideo->sciper;
    my $results_count_before = @results;
    if (my $youtube_id = $profvideo->videofra) {
      $profvideo->check_sciper();
      push @results, $class->new(
        lang       => "fr",
        import_id  => "videofra-$sciper",
        youtube_id => $youtube_id,
        title      => scalar $profvideo->videotitlefr,
        body       => scalar $profvideo->videotextfr || " ",
        categories => ["lab-videos-fr"],
        tags       => ["ATTRIBUTION=SCIPER:$sciper"]
      );
    }
    if (my $youtube_id = $profvideo->videoeng) {
      $profvideo->check_sciper();
      push @results, $class->new(
        lang       => "en",
        import_id  => "videoen-$sciper",
        youtube_id => $youtube_id,
        title      => scalar $profvideo->videotitle,
        body       => scalar $profvideo->videotext || " ",
        categories => ["lab-videos-en"],
        tags       => ["ATTRIBUTION=SCIPER:$sciper"]
      );
    }
    if (my $youtube_id = $profvideo->videoLH) {
      $profvideo->check_sciper();
      push @results, $class->new(
        import_id  => "videolh-$sciper",
        youtube_id => $youtube_id,
        title      => sprintf("Leçon d'honneur — %s", $profvideo->fullName),
        categories => ["events-lilh", "memento-lilh"],      # Nondistinguished language
        tags       => ["ATTRIBUTION=SCIPER:$sciper"]
      )
    }
    if ($results_count_before == @results) {
      die("Couldn't find any video out of SELECT [...] FROM profs WHERE sciper=" . $profvideo->sciper);
    }
  }
  return @results;
}

my %seen_ids;

sub new {
  my $class = shift;
  my $self = bless {@_}, $class;
  die unless my $id = $self->{youtube_id};
  $seen_ids{$id}++;

  if (10 <= keys %seen_ids) {
    _do_load_api();
    %seen_ids = ();
  }
  return $self;
}

my %youtube_snippets;
use constant CACHE_FILE => "youtube-api-cache.yaml";
our $loaded_from_cache;

END {
  unless ($loaded_from_cache || $?) {
    save_yaml(CACHE_FILE, \%youtube_snippets);
    warn sprintf("YouTube API results saved to %s\n", CACHE_FILE);
  }
}

sub _do_load_api {
  if ((! %youtube_snippets) && (-f CACHE_FILE)) {
    warn sprintf("Loading YouTube API results from %s\n", CACHE_FILE);
    %youtube_snippets = %{load_yaml(CACHE_FILE)};
    $loaded_from_cache = 1;
  }
  return if (! %seen_ids);
  my $snippets_json;
  io->http(sprintf(
    'https://www.googleapis.com/youtube/v3/videos?part=snippet&id=%s&key=%s',
    uri_escape(join(',', keys %seen_ids)),
    $secrets->{youtube_api_key})) > $snippets_json;

  my $youtube_response = decode_json($snippets_json);
  die "Wrong number of results" unless (
    $youtube_response->{pageInfo}->{totalResults} == scalar keys %seen_ids);

  foreach my $item (@{$youtube_response->{items}}) {
    $youtube_snippets{$item->{id}} = $item;
  }
}

sub youtube_snippet {
  my ($self) = @_;
  my $id = $self->{youtube_id};
  _do_load_api() unless $youtube_snippets{$id};
  return $youtube_snippets{$id}->{snippet};
}

sub essentials {
  my ($self) = @_;
  return {
    %$self,
    pubdate => scalar _zulu2epoch($self->youtube_snippet->{publishedAt})
  };
}

sub _zulu2epoch {
  my ($zulu) = @_;
  return DateTime::Format::ISO8601->parse_datetime($zulu)->epoch;
}
