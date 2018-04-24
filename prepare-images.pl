#!/usr/bin/perl -w

use v5.26;

use warnings;
use strict;
use autodie;

use JSON;
use IO::All;
use IO::String;
use Carp qw(croak);
use Error qw(:try);

use GD;

use FindBin; use lib $FindBin::Dir;
use HTTPGet;


my $covershots_meta = decode_json(scalar io("covershots-meta.json")->slurp);

sub progress;

my %covershots = map { $_ => 1 } (values %$covershots_meta);
foreach $_ (sort keys %covershots) {
  if (my ($url, $rss_id) = m/^<img src=(.*?left(\d+).png)>$/) {
    my $local_file = io_local_image($rss_id);
    next if $local_file->exists;
    progress "GETting $rss_id from $url";
    get($url) > $local_file;
  } elsif (my ($url_left, $rss_id_left, $url_right, $rss_id_right) =
             m|<table[^<>]*><td><img src=(.*?left(\d+).png)></td><td><img src=(.*?right(\d+).png)></td></table>|) {
    warn "Frankenstein image: $rss_id_left vs. $rss_id_right", next unless $rss_id_left eq $rss_id_right;
    my $local_file = io_local_image($rss_id_left);
    next if $local_file->exists;
    progress "Stitching $rss_id_left from $url_left and $url_right";
    next unless my $stitched = try {
      stitch_images(get($url_left), get($url_right));
    } catch Error::Simple with {
      warn "$rss_id_left: $@";
      undef;
    } except {
      warn "$rss_id_left: $@";
      undef;
    };
    $stitched > $local_file;
  } else {
    die "Unable to parse covershot HTML\n$_\n";
  }
}

sub io_local_image {
  my ($rss_id) = @_;
  return io->file("images/$rss_id.png");
}

sub progress {
  say @_
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

