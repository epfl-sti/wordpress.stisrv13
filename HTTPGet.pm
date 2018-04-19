#!/usr/bin/perl
#
# In this day and age, this is all just too complicated.

package HTTPGet;

use strict;

use IO::All;
use base qw(Exporter); our @EXPORT = qw(get);

sub get {
  my ($url) = @_;
  my $io = io->https($url);
  $io->get;
  throw HTTPGet::Error(-url => $url, -status => $io->response->status_line)
    unless $io->response->is_success;
  return scalar $io->slurp();
}

package HTTPGet::Error;

use base 'Error::Simple';

sub new {
  my $class = shift;
  my %opts = @_;
  $DB::single = 1;
  my $self = Error::Simple->new("HTTP Error " . $opts{-status});
  $self->{$_} = $opts{$_} for qw(-url -status);
  return $self;
}

sub throw {
  my $self = shift;
  if (! ref($self)) {
    $self = $self->new(@_);
  }
  $self->SUPER::throw();
}
