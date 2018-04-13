#!/usr/bin/perl

use v5.26;

use warnings;
use strict;
use autodie;

use Text::CSV;
use FindBin qw($Dir);


sub read_csv {
  my ($filename) = @_;
  my @rows;
  my $csv = Text::CSV->new ( { binary => 1 } )  # should set binary attribute.
    or die "Cannot use CSV: ".Text::CSV->error_diag ();

  open my $fh, "<", $filename;
  my @hdr = $csv->header ($fh);
  while ( my $row = $csv->getline( $fh ) ) {
    push @rows, $row;
  }
  $csv->eof or die $csv->error_diag();
  close $fh;
  return { header => \@hdr, rows => \@rows };
}

use Data::Dumper; say Dumper([read_csv("$Dir/rss-test.csv")]);
