#!/usr/bin/env perl -w

use v5.26;

use warnings;
use strict;
use autodie;

use IO::All;
use File::Basename qw(basename);
use URI;
use Carp qw(croak);
use Error qw(:try);
use Docopt;
use GD;

use FindBin; use lib $FindBin::Dir;
use File::Type;
use YAML;
use STISRV13;
use STISRV13::IO qw(load_secrets io_local_image load_json save_json);


=head1 NAME

prepare-images.pl

=head1 SYNOPSIS

  prepare-images.pl [ --offline ]

=cut

our $opts = do { local $^W; docopt(); };

my $covershots_meta = load_json("covershots-meta.json");

sub progress;

my %covershots = map { $_ => 1 } (values %$covershots_meta);
my %found;
foreach my $html_excerpt (sort keys %covershots) {
  my $found = scrape_covershot($html_excerpt);
  $found{$found} = 1 if $found;
}
my @stock_images;

my $secrets = load_secrets;
my $schema = STISRV13->connect(-password => $secrets->{mysql_password});
foreach my $rss (STISRV13::Article->almost_all($schema)) {
  my $rss_id = $rss->rss_id;
  next if $found{$rss_id};

  my $url = "http://stisrv13.epfl.ch/cgi-bin/newsatone.pl?id=$rss_id&lang=eng";
  progress "Looking up $url";
  my $html = io->https($url)->slurp;
  next if scrape_covershot($html);

  # Fall back on a "stock" image i.e. one that stisrv13.php will *not*
  # automatically pick up from the sideloaded material (instead it
  # will need to be told to do so, via stock-images.json)
  if (($url = $rss->img) && (my $shortname = scrape_stock_image($url))) {
    push @stock_images, {
      import_id => "rss-$rss_id",
      filename  => $shortname
    };
    next;
  }

  warn "No image could be found for $rss_id\n";
}

save_json("stock-images.json", {stock_images => \@stock_images});

sub progress {
  say @_
}

sub scrape_covershot {
  local $_ = shift;
  if (my ($url, $rss_id) = m/<img src=([^>]*?left(\d+).png)>/) {
    my $local_file = io_local_image("${rss_id}.png");
    return $rss_id if $local_file->exists;
    progress "GETting $rss_id from $url";
    get($url) > $local_file;
  } elsif (my ($url_left, $rss_id_left, $url_right, $rss_id_right) =
             m|<table[^<>]*><td><img src=([^>]*?left(\d+).png)></td><td><img src=([^>]*?right(\d+).png)></td></table>|) {
    warn "Frankenstein image: $rss_id_left vs. $rss_id_right", next unless $rss_id_left eq $rss_id_right;
    my $local_file = io_local_image("${rss_id_left}.png");
    return $rss_id_left if $local_file->exists;
    progress "Stitching $rss_id_left from $url_left and $url_right";
    return unless my $stitched = try {
      stitch_images(get($url_left), get($url_right));
    } catch Error::Simple with {
      warn "$rss_id_left: $@";
      undef;
    } except {
      warn "$rss_id_left: $@";
      undef;
    };
    $stitched > $local_file;
    return $rss_id_left;
  } else {
    warn sprintf("Unable to parse covershot HTML (%d characters)\n", length($_));
    return;
  }
}

sub stitch_images {
  my ($left, $right) = map { new GD::Image($_) } @_;

  # See http://www.perlmonks.org/?node_id=896244
  my( $x_l, $y_l ) = $left->getBounds();
  my( $x_r, $y_r ) = $right->getBounds();

  croak "Frankenstein stitching attempted ($y_l vs. $y_r)" if ($y_l != $y_r);

  my $stitched = new GD::Image($x_l + $x_r, $y_l);
  $stitched->copy($left,
                  0, 0,
                  0, 0,
                  $x_l, $y_l);
  $stitched->copy($right,
                  $x_l, 0,
                  0, 0,
                  $x_r, $y_r);
  return $stitched->png;
}

sub scrape_stock_image {
  my ($url) = @_;
  my $basename = basename(URI->new($url)->path);
  return $basename if ($opts->{'--offline'});
  my $contents; $contents < io->https($url);
  unless($basename =~ m/\.(jpeg|jpg|png)$/i) {
    my $sniffed_type = File::Type->new()->checktype_contents($contents);
    if ($sniffed_type eq "image/jpeg") {
      $basename .= "_.jpg";   # Use the underscore to be sure to avoid any like-named file
    } elsif ($sniffed_type eq "image/png") {
      $basename .= "_.png";   # Ditto
    } else {
      die "Sniffed an unknown MIME type at $url: $sniffed_type\n";
    }
  };
  my $stock_image = io_local_image($basename);
  unless ($stock_image->exists) {
    $contents > $stock_image;
  }
  return $basename;
}
