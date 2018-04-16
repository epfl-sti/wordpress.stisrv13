#!/usr/bin/perl

use v5.26;

use warnings;
use strict;
use autodie;

use Text::CSV_XS qw(csv);

use FindBin qw($Dir);
use String::Similarity qw(similarity);

my $csv_in = csv(in => "$Dir/rss.csv", detect_bom => 1);

my $csv_out = new CsvOut("$Dir/rss-out.csv");
$csv_out->header(qw(rss_id headline entete eng fra img simil));

foreach my $line (@$csv_in) {
  $line->{simil} = similarity($line->{eng}, $line->{fra});
  $csv_out->out($line);
}

####################################

package CsvOut;

sub new {
  my ($class, $outfile) = @_;
  my $self = bless {}, $class;
  open my $fh, ">:encoding(utf8)", $outfile;
  $self->{fh}  = $fh;
  $self->{csv} = Text::CSV_XS->new ({ binary => 1, auto_diag => 1 });
  return $self;
}

sub header {
  my ($self, @headers) = @_;
  $self->{headers} = [@headers];
  $self->{csv}->say($self->{fh}, [@headers]);
}

sub out {
  my ($self, $hashref) = @_;
  $self->{csv}->say($self->{fh}, [map {$hashref->{$_}} @{$self->{headers}}]);
}

sub close {
  my ($self) = @_;
  $self->{fh}->close();
}
