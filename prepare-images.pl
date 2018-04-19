#!/usr/bin/perl -w

use v5.26;

use warnings;
use strict;
use autodie;

use JSON;
use IO::All;

my $covershots_meta = decode_json(scalar io("covershots-meta.json")->slurp);

sub progress;

my %covershots = map { $_ => 1 } (values %$covershots_meta);
foreach $_ (sort keys %covershots) {
  if (my ($url, $rss_id) = m/^<img src=(.*?left(\d+).png)>$/) {
    my $local_file = io_local_image($rss_id);
    next if $local_file->exists;
    progress "GETting $rss_id from $url";
    io($url) > $local_file;
  } elsif (my ($url_left, $rss_id_left, $url_right, $rss_id_right) =
             m|<table[^<>]*><td><img src=(.*?left(\d+).png)></td><td><img src=(.*?right(\d+).png)></td></table>|) {
    warn "Frankenstein image: $rss_id_left vs. $rss_id_right", next unless $rss_id_left eq $rss_id_right;
    my $local_file = io_local_image($rss_id_left);
    next if $local_file->exists;
    progress "Stitching $rss_id_left from $url_left and $url_right";
    my $stitched = stitch_images(
      scalar(io($url_left)->get),
      scalar(io($url_right)->get));
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
  # TODO
  # Of interest:
  # https://stackoverflow.com/questions/9366158/merge-two-png-images-with-php-gd-library
  # http://www.perlmonks.org/?node_id=896244
  return "";
}

