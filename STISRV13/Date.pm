#!/usr/bin/perl -w

=head1 NAME

STISRV13::Date — Parsing the wunderbares C<pubdate> field in C<rss> table

=cut

package STISRV13::Date;

use strict;
use DateTime;

use warnings;
no warnings "experimental::re_strict";
use re 'strict';

sub parse {
  my ($class, $date_str) = @_;
  return if (! $date_str);
  my @blacklist = ("14:37, vendredi le 13 f&eacute;vrie");
  return if grep { $_ eq $date_str } @blacklist;

  return $class->parse_strict($date_str);
}

sub parse_strict {
  my ($class, $date_str) = @_;
  my ($hour, $minute, $weekday, $day, $month, $year) =
      $date_str =~ m/^
                  (\d+) [h:] (\d+)  ,\                                 # $hour, $minute
                  (lundi|mardi|mercredi|jeudi|vendredi|samedi|dimanche|
                   Monday|Tuesday|Wednesday|Thursday|Friday|Saturday|Sunday)
                  (?: \ le \   | \ the \ )
                  (\d+) (?: \ )?  (?: st | nd | rd | th )? (?: \ )?
                  (janvier|fevrier|février|(?: f&eacute;vrie r?)|mars|avril|
                    mai|juin|juillet|aout|août|ao&ucirc;t|
                    septembre|octobre|novembre|
                    decembre|décembre|d&eacute;cembre|
                   January|February|March|April|May|June|July|August|September|
                   October|November|December)
                  ,\                                                   # Final separator
                  (\d+)
                /xx
                  or die "Unparseable date: $date_str";
  # warn "$year $month=>" . _month_num($month) . " $day $hour:$minute";
  my $retval = new DateTime(
    year   => $year,
    month  => _month_num($month),
    day    => $day,
    hour   => $hour,
    minute => $minute
   );
  my $expected_weekday = _weekday_num($weekday);
  if ($expected_weekday != $retval->day_of_week) {
    die sprintf(
      "Bad weekday: %d ( expected %d) when parsing $date_str",
      $retval->day_of_week,
      $expected_weekday);
  }
  return $retval;
}

sub _weekday_num {
  local $_ = shift;
  m/lundi|Monday/i       && return 1;   # See L<DateTime/SYNOPSIS>
  m/mardi|Tuesday/i      && return 2;
  m/mercredi|Wednesday/i && return 3;
  m/jeudi|Thursday/i     && return 4;
  m/vendredi|Friday/i    && return 5;
  m/samedi|Saturday/i    && return 6;
  m/dimanche|Sunday/i    && return 7;
  die "Unparsable weekday: $_";
}

sub _month_num {
  local $_ = shift;
  m/^jan/i                          && return 1;
  m/^(?:feb|fév|fev|f&eacute;v)/i   && return 2;
  m/^mar/i                          && return 3;
  m/^(?:apr|avr)/i                  && return 4;
  m/^(?:mai|may)/i                  && return 5;
  m/^(?:jun|juin)/i                 && return 6;
  m/^(?:jul|juil)/i                 && return 7;
  m/^(?:aug|ao)/i                   && return 8;
  m/^sep/i                          && return 9;
  m/^oct/i                          && return 10;
  m/^nov/i                          && return 11;
  m/^d\S+cem/i                      && return 12;
}

1;
